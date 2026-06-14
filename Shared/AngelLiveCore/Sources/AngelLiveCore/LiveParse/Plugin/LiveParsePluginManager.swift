import Foundation

public final class LiveParsePluginManager: @unchecked Sendable {
    public typealias LogHandler = JSRuntime.LogHandler

    public let storage: LiveParsePluginStorage
    public let bundle: Bundle
    public let session: URLSession

    private let logHandler: LogHandler?
    private let lock = NSLock()
    private var loadedPlugins: [String: LiveParseLoadedPlugin] = [:]
    private var state: LiveParsePluginState

    public convenience init(bundle: Bundle? = nil, session: URLSession = .shared, logHandler: LogHandler? = nil) throws {
        try self.init(storage: LiveParsePluginStorage(), bundle: bundle, session: session, logHandler: logHandler)
    }

    public init(storage: LiveParsePluginStorage, bundle: Bundle? = nil, session: URLSession = .shared, logHandler: LogHandler? = nil) {
        self.storage = storage
        self.bundle = bundle ?? .main
        self.session = session
        self.logHandler = logHandler
        self.state = storage.loadState()
    }

    public func reload() throws {
        try storage.ensureDirectories()
        state = storage.loadState()
        lock.lock()
        loadedPlugins.removeAll()
        lock.unlock()
    }

    public func pin(pluginId: String, version: String) throws {
        var record = state.plugins[pluginId] ?? .init()
        record.pinnedVersion = version
        state.plugins[pluginId] = record
        try storage.saveState(state)
        try reload()
    }

    public func unpin(pluginId: String) throws {
        var record = state.plugins[pluginId] ?? .init()
        record.pinnedVersion = nil
        state.plugins[pluginId] = record
        try storage.saveState(state)
        try reload()
    }

    public func setLastGoodVersion(pluginId: String, version: String?) throws {
        var record = state.plugins[pluginId] ?? .init()
        record.lastGoodVersion = version
        state.plugins[pluginId] = record
        try storage.saveState(state)
    }

    public func evict(pluginId: String) {
        lock.lock()
        loadedPlugins.removeValue(forKey: pluginId)
        lock.unlock()
    }

    public func resolve(pluginId: String) throws -> LiveParseLoadedPlugin {
        lock.lock()
        if let existing = loadedPlugins[pluginId] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let record = state.plugins[pluginId]
        if record?.enabled == false {
            throw LiveParsePluginError.pluginNotFound("\(pluginId) (disabled)")
        }

        let pinned = record?.pinnedVersion
        let selected = try selectBestCandidate(pluginId: pluginId, pinnedVersion: pinned, lastGood: record?.lastGoodVersion)
        let plugin = LiveParseLoadedPlugin(
            manifest: selected.manifest,
            rootDirectory: selected.rootDirectory,
            location: selected.location,
            runtime: JSRuntime(
                pluginId: selected.manifest.pluginId,
                session: session,
                nativeStream: selected.manifest.nativeStream,
                logHandler: logHandler
            )
        )

        lock.lock()
        loadedPlugins[pluginId] = plugin
        lock.unlock()
        return plugin
    }

    public func load(pluginId: String) async throws {
        let plugin = try resolve(pluginId: pluginId)
        try await plugin.load()
    }

    public func call(pluginId: String, function: String, payload: [String: Any] = [:]) async throws -> Any {
        if function == "setCookie" {
            let cookie = (payload["cookie"] as? String) ?? ""
            let uid = payload["uid"] as? String
            LiveParsePlatformSessionVault.update(platformId: pluginId, cookie: cookie, uid: uid)
            return ["ok": true, "managedByHost": true, "hasCookie": !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty]
        }
        if function == "clearCookie" {
            LiveParsePlatformSessionVault.clear(platformId: pluginId)
            return ["ok": true, "managedByHost": true, "hasCookie": false]
        }
        // 新 credential 入口：写入 vault 后继续 forward 到插件，让插件初始化 runtime 并返回 status。
        // 若插件未实现 setCredential/clearCredential，则在 forward 时会抛错；host 端的 Bridge 负责 fallback 到 setCookie/clearCookie。
        if function == "setCredential" {
            let (cookie, uid) = extractCredentialCookie(from: payload)
            LiveParsePlatformSessionVault.update(platformId: pluginId, cookie: cookie, uid: uid)
            // 不 return；继续走下方常规 forward 逻辑，让插件自身 runtime 处理。
        }
        if function == "clearCredential" {
            LiveParsePlatformSessionVault.clear(platformId: pluginId)
            // 同上，继续 forward。
        }

        // 开发者控制台日志 —— 跟宿主域(Favorite/Danmaku/Player 等)对齐,无条件写入。
        // 缓冲区有 500 条上限,代价可忽略;运行时 UI 是否显示由 GeneralSettingModel.developerModeEnabled 控制。
        let console = PluginConsoleService.shared
        let payloadStr = (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? "{}"
        let entryId = await console.log(tag: pluginId, method: function)
        await console.updateRequest(id: entryId, body: payloadStr)
        // 标记活跃调用，让 Host.http 能关联 HTTP 子请求
        console.setActiveCall(pluginId: pluginId, entryId: entryId)
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let plugin = try resolve(pluginId: pluginId)
            try await plugin.load()
            let result = try await plugin.runtime.callPluginFunction(name: function, payload: payload)

            console.clearActiveCall(pluginId: pluginId)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let responseStr = (try? String(data: JSONSerialization.data(withJSONObject: result), encoding: .utf8))
                .map { String($0.prefix(2000)) }
            await console.updateStatus(id: entryId, status: .success, duration: elapsed, responseBody: responseStr)
            return result
        } catch {
            console.clearActiveCall(pluginId: pluginId)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            await console.updateStatus(id: entryId, status: .error, duration: elapsed, errorMessage: error.localizedDescription)
            throw error
        }
    }

    public func callDecodable<T: Decodable>(
        pluginId: String,
        function: String,
        payload: [String: Any] = [:],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        do {
            let value = try await call(pluginId: pluginId, function: function, payload: payload)
            let data = try JSONSerialization.data(withJSONObject: value)
            if let jsonStr = String(data: data, encoding: .utf8) {
                Logger.debug("[PluginManager] callDecodable: pluginId=\(pluginId) function=\(function) rawJSON=\(jsonStr.prefix(1000))", category: .plugin)
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as LiveParsePluginError {
            throw error
        } catch {
            throw LiveParsePluginError.invalidReturnValue(
                "Decoding \(String(describing: T.self)) failed in \(pluginId).\(function): \(error.localizedDescription)"
            )
        }
    }

    private func extractCredentialCookie(from payload: [String: Any]) -> (String, String?) {
        // 支持 payload = { credential: { cookie, uid } } 或扁平 { cookie, uid }
        if let credential = payload["credential"] as? [String: Any] {
            let cookie = (credential["cookie"] as? String)
                ?? (credential["Cookie"] as? String)
                ?? ""
            let uid = credential["uid"] as? String
            return (cookie, uid)
        }
        if let cookie = payload["cookie"] as? String {
            return (cookie, payload["uid"] as? String)
        }
        return ("", nil)
    }
}

private extension LiveParsePluginManager {
    struct Candidate {
        let manifest: LiveParsePluginManifest
        let rootDirectory: URL
        let location: LiveParseLoadedPlugin.Location
    }

    func selectBestCandidate(pluginId: String, pinnedVersion: String?, lastGood: String?) throws -> Candidate {
        let sandboxCandidates = try discoverSandboxCandidates(pluginId: pluginId)
        let builtInCandidates = try discoverBuiltInCandidates(pluginId: pluginId)
        let allCandidates = sandboxCandidates + builtInCandidates

        func preferredCandidate(in candidates: [Candidate]) -> Candidate? {
            candidates.max { lhs, rhs in
                let versionCompare = semverCompare(lhs.manifest.version, rhs.manifest.version)
                if versionCompare != 0 {
                    return versionCompare < 0
                }
                if lhs.location != rhs.location {
                    return lhs.location == .builtIn && rhs.location == .sandbox
                }
                return lhs.rootDirectory.path < rhs.rootDirectory.path
            }
        }

        if let pinnedVersion {
            if let hit = preferredCandidate(in: allCandidates.filter({ $0.manifest.version == pinnedVersion })) {
                return hit
            }
            throw LiveParsePluginError.pluginNotFound("\(pluginId)@\(pinnedVersion)")
        }

        guard let best = preferredCandidate(in: allCandidates) else {
            throw LiveParsePluginError.pluginNotFound(pluginId)
        }

        if let lastGood,
           semverCompare(lastGood, best.manifest.version) >= 0,
           let hit = preferredCandidate(in: allCandidates.filter({ $0.manifest.version == lastGood })) {
            return hit
        }

        return best
    }

    func discoverSandboxCandidates(pluginId: String) throws -> [Candidate] {
        let versionDirs = storage.listInstalledVersions(pluginId: pluginId)
        return try versionDirs.compactMap { dir in
            let manifestURL = dir.appendingPathComponent("manifest.json", isDirectory: false)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
            let manifest = try LiveParsePluginManifest.load(from: manifestURL)
            guard manifest.pluginId == pluginId else { return nil }
            return Candidate(manifest: manifest, rootDirectory: dir, location: .sandbox)
        }
    }

    func discoverBuiltInCandidates(pluginId: String) throws -> [Candidate] {
        guard let resourceURL = bundle.resourceURL else {
            return []
        }

        // 兼容两种内置资源布局：
        // 1) 目录结构：Plugins/<pluginId>/manifest.json (理想情况)
        // 2) 资源被“扁平化”拷贝到 bundle 根目录：lp_plugin_<id>_<ver>_manifest.json（当前 SwiftPM 构建常见）

        let pluginsRoot = resourceURL.appendingPathComponent("Plugins", isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginsRoot.path) {
            return try discoverBuiltInCandidatesFolderMode(pluginId: pluginId, pluginsRoot: pluginsRoot)
        }
        return try discoverBuiltInCandidatesFlatMode(pluginId: pluginId, resourceURL: resourceURL)
    }

    func discoverBuiltInCandidatesFolderMode(pluginId: String, pluginsRoot: URL) throws -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: pluginsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [Candidate] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "manifest.json" else { continue }
            let manifest = try LiveParsePluginManifest.load(from: url)
            guard manifest.pluginId == pluginId else { continue }
            results.append(Candidate(manifest: manifest, rootDirectory: url.deletingLastPathComponent(), location: .builtIn))
        }
        return results
    }

    func discoverBuiltInCandidatesFlatMode(pluginId: String, resourceURL: URL) throws -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [Candidate] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("lp_plugin_") && name.hasSuffix("_manifest.json") else { continue }
            let manifest = try LiveParsePluginManifest.load(from: url)
            guard manifest.pluginId == pluginId else { continue }
            results.append(Candidate(manifest: manifest, rootDirectory: url.deletingLastPathComponent(), location: .builtIn))
        }
        return results
    }

    func semverCompare(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }
        let a = parts(lhs)
        let b = parts(rhs)
        for i in 0..<3 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        }
        return 0
    }
}
