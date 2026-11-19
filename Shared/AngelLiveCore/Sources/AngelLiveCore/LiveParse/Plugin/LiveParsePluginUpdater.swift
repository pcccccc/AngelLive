import CryptoKit
import Foundation

struct LiveParsePluginIndexResponseDiagnostics: Sendable {
    let url: URL
    let statusCode: Int?
    let contentType: String?
    let bodyPreview: String
    /// 正文是 m3u 播放列表（按内容判断）；用于把播放列表地址与插件索引区分开。
    var isPlaylist: Bool = false

    var logDescription: String {
        let statusText = statusCode.map(String.init) ?? "n/a"
        let contentTypeText = contentType ?? "unknown"
        return "URL=\(url.absoluteString), HTTP=\(statusText), Content-Type=\(contentTypeText), bodyPreview=\(bodyPreview)"
    }
}

enum LiveParsePluginIndexFetchError: Error, Sendable {
    case nonJSONResponse(LiveParsePluginIndexResponseDiagnostics)
    case decodingFailed(LiveParsePluginIndexResponseDiagnostics, DecodingError)
}

public struct LiveParsePluginUpdateInfo: Equatable, Sendable {
    public let pluginId: String
    public let currentVersion: String?
    public let latestVersion: String
    public let hasUpdate: Bool
    public let changelog: [String]

    public init(
        pluginId: String,
        currentVersion: String?,
        latestVersion: String,
        hasUpdate: Bool,
        changelog: [String]
    ) {
        self.pluginId = pluginId
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.hasUpdate = hasUpdate
        self.changelog = changelog
    }
}

public final class LiveParsePluginUpdater: @unchecked Sendable {
    static let httpStatusCodeUserInfoKey = "LiveParsePluginUpdater.HTTPStatusCode"

    public let storage: LiveParsePluginStorage
    public let session: URLSession

    public init(storage: LiveParsePluginStorage, session: URLSession = .shared) {
        self.storage = storage
        self.session = session
    }

    public func fetchIndex(url: URL) async throws -> LiveParseRemotePluginIndex {
        let (data, response) = try await session.data(from: url)
        let httpResponse = response as? HTTPURLResponse
        if let httpResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)",
                Self.httpStatusCodeUserInfoKey: httpResponse.statusCode
            ])
        }

        let diagnostics = responseDiagnostics(url: url, response: response, data: data)
        guard Self.looksLikeJSONObject(data) else {
            Logger.error("Plugin index response is not JSON. \(diagnostics.logDescription)", category: .plugin)
            throw LiveParsePluginIndexFetchError.nonJSONResponse(diagnostics)
        }

        do {
            return try JSONDecoder().decode(LiveParseRemotePluginIndex.self, from: data)
        } catch let decodingError as DecodingError {
            let codingPath = Self.codingPathDescription(for: decodingError)
            let detail = Self.decodingDebugDescription(for: decodingError)
            let codingPathDescription = codingPath.isEmpty ? "<root>" : codingPath
            Logger.error(
                "Plugin index decode failed. \(diagnostics.logDescription), codingPath=\(codingPathDescription), detail=\(detail)",
                category: .plugin
            )
            throw LiveParsePluginIndexFetchError.decodingFailed(diagnostics, decodingError)
        }
    }

    public func downloadZip(url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    private func downloadZip(url: URL, progress: PluginInstallationProgressHandler) async throws -> Data {
        let (events, continuation) = AsyncThrowingStream<PluginZipDownloadDelegate.Event, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        let download = session.downloadTask(with: url)
        download.delegate = PluginZipDownloadDelegate(continuation: continuation)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            download.resume()
            for try await event in events {
                try Task.checkCancellation()
                switch event {
                case .bytes(let received, let expected):
                    guard expected > 0 else { continue }
                    let fraction = min(1, Double(received) / Double(expected))
                    await progress(.downloading(fraction))
                case .archive(let data):
                    return data
                }
            }
            try Task.checkCancellation()
            throw URLError(.cannotDecodeContentData)
        } onCancel: {
            download.cancel()
        }
    }

    /// Check whether the specified plugin has a newer version in remote index.
    /// - Returns: nil when plugin does not exist in the index.
    public func checkUpdate(
        pluginId: String,
        currentVersion: String?,
        index: LiveParseRemotePluginIndex
    ) -> LiveParsePluginUpdateInfo? {
        let candidates = index.plugins.filter { $0.pluginId == pluginId }
        guard let latest = candidates.max(by: { semverCompare($0.version, $1.version) < 0 }) else {
            return nil
        }

        let normalizedCurrent = currentVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUpdate: Bool
        if let current = normalizedCurrent, !current.isEmpty {
            hasUpdate = semverCompare(latest.version, current) > 0
        } else {
            hasUpdate = true
        }

        return LiveParsePluginUpdateInfo(
            pluginId: pluginId,
            currentVersion: normalizedCurrent,
            latestVersion: latest.version,
            hasUpdate: hasUpdate,
            changelog: latest.changelog ?? []
        )
    }

    public func install(item: LiveParseRemotePluginItem) async throws -> LiveParsePluginManifest {
        try await install(item: item, stagingDirectory: nil)
    }

    func install(
        item: LiveParseRemotePluginItem,
        stagingDirectory: URL?,
        progress: PluginInstallationProgressHandler? = nil
    ) async throws -> LiveParsePluginManifest {
        let entryId = await Self.consoleBegin(
            method: "install",
            request: Self.consoleRequestBody(for: item)
        )
        let start = Date()
        do {
            let zipData = try await downloadVerifiedZip(item: item, progress: progress)
            try Task.checkCancellation()
            let manifest: LiveParsePluginManifest
            if let stagingDirectory {
                manifest = try LiveParsePluginInstaller.extractPlugin(zipData: zipData, to: stagingDirectory)
                guard manifest.pluginId == item.pluginId, manifest.version == item.version else {
                    throw LiveParsePluginError.installFailed("Archive manifest does not match the catalog entry")
                }
            } else {
                manifest = try LiveParsePluginInstaller.install(zipData: zipData, storage: storage)
            }
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .success,
                responseBody: Self.consoleSuccessBody(manifest: manifest, zipBytes: zipData.count)
            )
            return manifest
        } catch {
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .error,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    /// Install plugin from remote item, run smoke test, and persist `lastGoodVersion`.
    /// If smoke test fails, the newly installed version is removed.
    ///
    /// - Parameter afterInstallConsent: 文件落地、smoke test 之前调用的确认钩子。
    ///   返回 `false` 时立即抛 `PluginInstallConsentError.userDeclined`,已写盘的版本会被回滚。
    @discardableResult
    public func installAndActivate(
        item: LiveParseRemotePluginItem,
        smokeFunction: String = "",
        smokePayload: [String: Any] = [:],
        manager: LiveParsePluginManager? = nil,
        afterInstallConsent: (@Sendable (LiveParsePluginManifest) async -> Bool)? = nil
    ) async throws -> LiveParsePluginManifest {
        let entryId = await Self.consoleBegin(
            method: "installAndActivate",
            request: Self.consoleRequestBody(for: item)
        )
        let start = Date()

        var installedManifest: LiveParsePluginManifest?
        do {
            let manifest = try await install(item: item)
            installedManifest = manifest
            try Task.checkCancellation()

            if let afterInstallConsent {
                let approved = await afterInstallConsent(manifest)
                if !approved {
                    throw PluginInstallConsentError.userDeclined
                }
            }

            try await activateInstalled(
                manifest: manifest,
                smokeFunction: smokeFunction,
                smokePayload: smokePayload,
                manager: manager
            )
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .success,
                responseBody: Self.consoleSuccessBody(manifest: manifest, smokeFunction: smokeFunction)
            )
            return manifest
        } catch {
            if let manifest = installedManifest {
                rollbackInstalled(manifest: manifest, manager: manager)
            } else {
                manager?.evict(pluginId: item.pluginId)
            }
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .error,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    func activateStaged(
        manifest: LiveParsePluginManifest,
        directory: URL,
        manager: LiveParsePluginManager,
        progress: PluginInstallationProgressHandler?
    ) async throws {
        await progress?(.activating)
        try Task.checkCancellation()
        let plugin = makePluginForSmokeTest(manifest: manifest, directory: directory, session: manager.session)
        defer { plugin.runtime.invalidateOwnedResources() }
        try await plugin.load()
        try Task.checkCancellation()
        try LiveParsePluginInstaller.placeExtractedPlugin(
            at: directory, manifest: manifest, storage: storage, replacingExisting: false
        )
        try await activateInstalled(manifest: manifest, manager: manager)
    }

    /// 完成已落盘插件的 smoke test 并写入 `lastGoodVersion`。
    /// 用于"先批量下载、再统一确认、最后激活"的两阶段安装流程。
    /// smoke test 失败时会自动回滚该版本并抛出错误。
    public func activateInstalled(
        manifest: LiveParsePluginManifest,
        smokeFunction: String = "",
        smokePayload: [String: Any] = [:],
        manager: LiveParsePluginManager? = nil
    ) async throws {
        let entryId = await Self.consoleBegin(
            method: "activate",
            request: """
            pluginId: \(manifest.pluginId)
            version: \(manifest.version)
            smokeFunction: \(smokeFunction.isEmpty ? "-" : smokeFunction)
            """
        )
        let start = Date()
        do {
            try Task.checkCancellation()
            try await smokeTestInstalledPlugin(
                manifest: manifest,
                function: smokeFunction,
                payload: smokePayload,
                session: manager?.session ?? session
            )
            // Cancellation before the last-good commit rolls back the staged
            // version. After the commit, the operation has succeeded.
            try Task.checkCancellation()

            if let manager {
                try manager.setLastGoodVersion(pluginId: manifest.pluginId, version: manifest.version)
                manager.evict(pluginId: manifest.pluginId)
            } else {
                try persistLastGoodVersion(pluginId: manifest.pluginId, version: manifest.version)
            }

            // 新版本激活成功后,清理同 pluginId 的旧版本目录(保留 pinned + lastGood + 最新版)
            let prunedVersions = CacheMaintenanceService.prunePluginOldVersions(pluginId: manifest.pluginId, storage: storage)
            let prunedDescription = prunedVersions.isEmpty
                ? "lastGood 已写入"
                : "lastGood 已写入,已清理旧版本: \(prunedVersions.joined(separator: ", "))"
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .success,
                responseBody: "已激活 \(manifest.pluginId)@\(manifest.version) (\(prunedDescription))"
            )
        } catch {
            rollbackInstalled(manifest: manifest, manager: manager)
            await Self.consoleFinish(
                id: entryId,
                start: start,
                status: .error,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    /// 回滚已落盘但尚未激活的插件版本(删除版本目录并清除运行时缓存)。
    public func rollbackInstalled(
        manifest: LiveParsePluginManifest,
        manager: LiveParsePluginManager? = nil
    ) {
        try? removeInstalledVersion(pluginId: manifest.pluginId, version: manifest.version)
        manager?.evict(pluginId: manifest.pluginId)
    }

    func downloadVerifiedZip(
        item: LiveParseRemotePluginItem,
        progress: PluginInstallationProgressHandler? = nil
    ) async throws -> Data {
        let expected = item.sha256.lowercased()
        let candidates = item.downloadURLs
        guard !candidates.isEmpty else {
            throw LiveParsePluginError.installFailed("No zip download URL for \(item.pluginId)@\(item.version)")
        }

        var diagnostics: [String] = []

        for (index, raw) in candidates.enumerated() {
            try Task.checkCancellation()
            guard let url = URL(string: raw) else {
                diagnostics.append("invalid-url(\(raw))")
                continue
            }

            do {
                // A mirror retry has a different byte count. Show activity
                // until a valid archive arrives without rewinding a known ring.
                await progress?(.downloading(nil))
                try Task.checkCancellation()
                let zipData: Data
                if index == 0, let progress {
                    zipData = try await downloadZip(url: url, progress: progress)
                } else {
                    zipData = try await downloadZip(url: url)
                }
                try Task.checkCancellation()
                await progress?(.verifyingAndExtracting)
                try Task.checkCancellation()
                let actual = sha256Hex(zipData)
                guard actual == expected else {
                    diagnostics.append("checksum-mismatch(\(url.absoluteString))")
                    continue
                }
                return zipData
            } catch {
                try Task.checkCancellation()
                diagnostics.append("download-failed(\(url.absoluteString)): \(error.localizedDescription)")
            }
        }

        throw LiveParsePluginError.installFailed(
            "All sources failed for \(item.pluginId)@\(item.version): \(diagnostics.joined(separator: "; "))"
        )
    }

    public func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func persistLastGoodVersion(pluginId: String, version: String) throws {
        var state = storage.loadState()
        var record = state.plugins[pluginId] ?? .init()
        record.lastGoodVersion = version
        state.plugins[pluginId] = record
        try storage.saveState(state)
    }

    func removeInstalledVersion(pluginId: String, version: String) throws {
        let target = storage.pluginVersionDirectory(pluginId: pluginId, version: version)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    func smokeTestInstalledPlugin(
        manifest: LiveParsePluginManifest,
        function: String,
        payload: [String: Any] = [:],
        session: URLSession
    ) async throws {
        let smoke = function.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !smoke.isEmpty else { return }

        let directory = storage.pluginVersionDirectory(pluginId: manifest.pluginId, version: manifest.version)
        let plugin = makePluginForSmokeTest(manifest: manifest, directory: directory, session: session)
        try await plugin.load()
        _ = try await plugin.runtime.callPluginFunction(name: smoke, payload: payload)
    }

    private func makePluginForSmokeTest(
        manifest: LiveParsePluginManifest,
        directory: URL,
        session: URLSession
    ) -> LiveParseLoadedPlugin {
        LiveParseLoadedPlugin(
            manifest: manifest,
            rootDirectory: directory,
            location: .sandbox,
            runtime: JSRuntime(
                pluginId: manifest.pluginId,
                session: session,
                nativeStream: manifest.nativeStream,
                credentialDomains: manifest.hostManagedCredentialDomains
            )
        )
    }

    func semverCompare(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ value: String) -> [Int] {
            value.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }

        let left = parts(lhs)
        let right = parts(rhs)
        for idx in 0..<3 {
            if left[idx] != right[idx] {
                return left[idx] < right[idx] ? -1 : 1
            }
        }
        return 0
    }

    private func responseDiagnostics(url: URL, response: URLResponse, data: Data) -> LiveParsePluginIndexResponseDiagnostics {
        let httpResponse = response as? HTTPURLResponse
        return LiveParsePluginIndexResponseDiagnostics(
            url: url,
            statusCode: httpResponse?.statusCode,
            contentType: httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType,
            bodyPreview: Self.bodyPreview(from: data),
            isPlaylist: M3UPlaylistParser.looksLikePlaylist(data)
        )
    }

    private static func looksLikeJSONObject(_ data: Data) -> Bool {
        firstMeaningfulByte(in: data) == UInt8(ascii: "{")
    }

    private static func firstMeaningfulByte(in data: Data) -> UInt8? {
        var index = data.startIndex
        if data.count >= 3,
           data[index] == 0xEF,
           data[data.index(after: index)] == 0xBB,
           data[data.index(index, offsetBy: 2)] == 0xBF {
            index = data.index(index, offsetBy: 3)
        }

        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index = data.index(after: index)
                continue
            }
            return byte
        }
        return nil
    }

    private static func bodyPreview(from data: Data, limit: Int = 200) -> String {
        guard !data.isEmpty else { return "<empty>" }

        let raw = String(decoding: data.prefix(limit), as: UTF8.self)
        let collapsed = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "<empty>" }
        return data.count > limit ? collapsed + "..." : collapsed
    }

    private static func codingPathDescription(for error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.map(\.stringValue).joined(separator: ".")
        @unknown default:
            return ""
        }
    }

    private static func decodingDebugDescription(for error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// Forwards native download events in delegate order. Only the stream consumer
/// publishes progress, so byte callbacks cannot arrive after the install moves
/// on to verification or cancellation cleanup.
private final class PluginZipDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    enum Event: Sendable {
        case bytes(received: Int64, expected: Int64)
        case archive(Data)
    }

    let continuation: AsyncThrowingStream<Event, Error>.Continuation

    init(continuation: AsyncThrowingStream<Event, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        continuation.yield(.bytes(received: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let response = downloadTask.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                throw URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(response.statusCode)",
                    LiveParsePluginUpdater.httpStatusCodeUserInfoKey: response.statusCode
                ])
            }
            // The temporary URL is only valid for the duration of this callback.
            continuation.yield(.archive(try Data(contentsOf: location)))
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.finish(throwing: error)
    }
}

// MARK: - DevConsole 钩子

private extension LiveParsePluginUpdater {
    @MainActor
    private static func makeConsoleEntry(method: String) -> UUID {
        PluginConsoleService.shared.log(tag: "Plugin", method: method, status: .loading)
    }

    @MainActor
    private static func attachRequest(id: UUID, body: String) {
        PluginConsoleService.shared.updateRequest(id: id, body: body)
    }

    @MainActor
    private static func finishEntry(
        id: UUID,
        duration: TimeInterval,
        status: PluginConsoleEntryStatus,
        responseBody: String?,
        errorMessage: String?
    ) {
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: status,
            duration: duration,
            responseBody: responseBody,
            errorMessage: errorMessage
        )
    }

    static func consoleBegin(method: String, request: String) async -> UUID {
        await MainActor.run {
            let id = makeConsoleEntry(method: method)
            attachRequest(id: id, body: request)
            return id
        }
    }

    static func consoleFinish(
        id: UUID,
        start: Date,
        status: PluginConsoleEntryStatus,
        responseBody: String? = nil,
        errorMessage: String? = nil
    ) async {
        let duration = Date().timeIntervalSince(start)
        await MainActor.run {
            finishEntry(
                id: id,
                duration: duration,
                status: status,
                responseBody: responseBody,
                errorMessage: errorMessage
            )
        }
    }

    static func consoleRequestBody(for item: LiveParseRemotePluginItem) -> String {
        let urls = item.downloadURLs.joined(separator: "\n  ")
        return """
        pluginId: \(item.pluginId)
        version: \(item.version)
        platform: \(item.platform ?? "-")
        platformName: \(item.platformName ?? "-")
        sha256: \(item.sha256)
        downloadURLs:
          \(urls.isEmpty ? "-" : urls)
        """
    }

    static func consoleSuccessBody(manifest: LiveParsePluginManifest, zipBytes: Int? = nil, smokeFunction: String = "") -> String {
        var lines: [String] = [
            "pluginId: \(manifest.pluginId)",
            "version: \(manifest.version)",
            "displayName: \(manifest.displayName ?? "-")"
        ]
        if let zipBytes {
            lines.append("zipBytes: \(zipBytes)")
        }
        if !smokeFunction.isEmpty {
            lines.append("smokeFunction: \(smokeFunction)")
        }
        return lines.joined(separator: "\n")
    }
}
