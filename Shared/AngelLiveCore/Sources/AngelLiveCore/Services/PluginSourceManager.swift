//
//  PluginSourceManager.swift
//  AngelLiveCore
//
//  管理用户添加的插件源 URL，拉取远程索引，安装插件。
//

import Foundation
import Observation

/// 单个插件的安装状态
public enum PluginInstallState: Equatable, Sendable {
    case notInstalled
    case installing
    case installed
    case failed(String)
}

/// 单个订阅源的健康状态
public enum PluginSourceHealth: Equatable, Sendable {
    /// 刚添加,还没拉取过索引
    case unknown
    /// 正在拉取索引
    case checking
    /// 拉取成功,带插件数量
    case healthy(pluginCount: Int)
    /// 拉取失败,带原因(可重试)
    case failed(String)

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// 带安装状态的远程插件条目
@Observable
public final class RemotePluginDisplayItem: Identifiable, @unchecked Sendable {
    public let item: LiveParseRemotePluginItem
    public var installState: PluginInstallState = .notInstalled

    public var id: String { item.pluginId }
    public var displayName: String { item.platformName ?? item.pluginId }

    public init(item: LiveParseRemotePluginItem) {
        self.item = item
    }
}

@Observable
public final class PluginSourceManager: @unchecked Sendable {

    /// 用户保存的插件源 URL 列表
    public private(set) var sourceURLs: [String] = []

    /// 各订阅源的健康状态(按 URL 索引,仅内存,启动后由拉取索引重新填充)
    public private(set) var sourceHealth: [String: PluginSourceHealth] = [:]

    /// 当前拉取的远程插件列表
    public private(set) var remotePlugins: [RemotePluginDisplayItem] = []

    /// 各插件在订阅源中的最新版本（按 pluginId 索引）
    public private(set) var latestRemoteItemsByPluginId: [String: LiveParseRemotePluginItem] = [:]

    /// 是否正在拉取索引
    public private(set) var isFetchingIndex: Bool = false

    /// 是否正在检查更新
    public private(set) var isCheckingUpdates: Bool = false

    /// 正在更新中的插件 ID
    public private(set) var updatingPluginIds: Set<String> = []

    /// 批量安装进度：已完成数量
    public private(set) var installCompletedCount: Int = 0

    /// 批量安装进度：总数量
    public private(set) var installTotalCount: Int = 0

    /// 错误信息
    public var errorMessage: String?

    /// 每个订阅源对应的插件 ID 集合（用于删除订阅源时联动删除插件）
    private var sourcePluginIds: [String: Set<String>] = [:]

    /// 是否有插件正在安装
    public var isInstalling: Bool {
        remotePlugins.contains { $0.installState == .installing }
    }

    @ObservationIgnored
    private let sourceURLsKey = "AngelLive.PluginSource.URLs"

    @ObservationIgnored
    private let sourcePluginIdsKey = "AngelLive.PluginSource.PluginIds"

    @ObservationIgnored
    private let updater: LiveParsePluginUpdater

    /// 网络请求超时时间（秒）
    @ObservationIgnored
    private let fetchTimeoutSeconds: UInt64 = 30

    /// 安装确认请求器:由各端在 app 启动时注入。
    /// nil 时所有确认默认通过(便于单元测试或纯命令行调用)。
    @ObservationIgnored
    public var consentRequester: (any PluginInstallConsentRequesting)?

    public init() {
        self.updater = LiveParsePluginUpdater(
            storage: LiveParsePlugins.shared.storage,
            session: LiveParsePlugins.shared.session
        )
        loadSourceURLs()
        loadSourcePluginIds()
    }

    // MARK: - 插件源管理

    private func loadSourceURLs() {
        sourceURLs = UserDefaults.standard.stringArray(forKey: sourceURLsKey) ?? []
    }

    private func saveSourceURLs() {
        UserDefaults.standard.set(sourceURLs, forKey: sourceURLsKey)
        // 同步到 CloudKit
        let urls = sourceURLs
        Task {
            await PluginSourceSyncService.syncToCloudStatic(sourceURLs: urls)
        }
    }

    /// 从 UserDefaults 恢复 source→pluginId 映射,用于源不可达时仍能联动卸载插件。
    private func loadSourcePluginIds() {
        let raw = UserDefaults.standard.dictionary(forKey: sourcePluginIdsKey) as? [String: [String]] ?? [:]
        sourcePluginIds = raw.mapValues { Set($0) }
    }

    private func saveSourcePluginIds() {
        let serialized = sourcePluginIds.mapValues { Array($0) }
        UserDefaults.standard.set(serialized, forKey: sourcePluginIdsKey)
    }

    public func addSource(_ urlString: String) {
        persistSourceIfNeeded(urlString)
    }

    /// 读取某个订阅源的健康状态(未知时返回 .unknown)
    public func health(for urlString: String) -> PluginSourceHealth {
        sourceHealth[urlString.trimmingCharacters(in: .whitespacesAndNewlines)] ?? .unknown
    }

    /// 添加用户输入的订阅源：支持 key 解析和直接 URL，只有校验成功后才会持久化并同步到 CloudKit。
    /// 返回实际添加或重新加载成功的 URL 列表。
    public func addSourceFromInput(_ input: String) async -> [String] {
        await validateAndLoadSource(input, allowDirectInput: true)
    }

    /// 仅处理 key 形式的订阅源输入。
    /// 若输入不是 key，则返回空数组，交由调用方按普通视频链接处理。
    public func addSourceWithKeyResolution(_ input: String) async -> [String] {
        await validateAndLoadSource(input, allowDirectInput: false)
    }

    /// 乐观添加订阅源:
    /// - key / 显式 .json 订阅一旦确定为订阅意图,就先把源持久化下来(即使当前拉取失败),
    ///   失败时把该源标记为 `.failed`,用户可在列表里重试或删除 —— 临时不可达的源也能先存上。
    /// - 当 `allowDirectInput == false` 且输入不是 key 时仍返回空,保留"普通视频链接走书签兜底"的判定。
    private func validateAndLoadSource(_ input: String, allowDirectInput: Bool) async -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        errorMessage = nil
        await PluginSourceKeyService.shared.fetchKeys()

        let resolvedCandidates = await PluginSourceKeyService.shared.resolveKey(trimmed)
        // 非 key 且不允许直接输入(用于区分订阅源 vs 视频书签):交回调用方按视频处理。
        if resolvedCandidates == nil, !allowDirectInput {
            return []
        }

        // key 解析出的多个候选是同一索引的镜像源,只持久化其中一个;直接输入则就是这一个 URL。
        let candidates = (resolvedCandidates ?? [trimmed]).filter { URL(string: $0) != nil }
        guard let primary = candidates.first else {
            errorMessage = "无效的 URL"
            return []
        }

        isFetchingIndex = true
        defer { isFetchingIndex = false }

        // 依次尝试候选(镜像),第一个成功的成为持久化的源。
        // 添加订阅源本身不下载 JS、不触发安装,无需 consent;
        // 凭证泄露风险的批量确认下沉到 installAll Phase 1,届时列出具体登录平台一次性拍板。
        var lastError: Error?
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            do {
                let index = try await fetchIndexWithTimeout(url: url)
                persistSourceIfNeeded(candidate)
                applyFetchedIndex(index, sourceURL: candidate)
                return [candidate]
            } catch {
                lastError = error
                Logger.warning("Source validation failed for \(candidate): \(Self.detailedErrorDescription(error))", category: .plugin)
            }
        }

        // 所有候选都拉取失败:乐观地把主候选存下来并标记异常,源不丢,用户可重试/删除。
        persistSourceIfNeeded(primary)
        if let lastError {
            sourceHealth[primary] = .failed(Self.detailedErrorDescription(lastError))
        } else {
            sourceHealth[primary] = .failed("暂时无法拉取插件索引")
        }
        return [primary]
    }

    private func persistSourceIfNeeded(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sourceURLs.contains(trimmed) else { return }
        sourceURLs.append(trimmed)
        sourcePluginIds[trimmed] = sourcePluginIds[trimmed] ?? Set<String>()
        if sourceHealth[trimmed] == nil {
            sourceHealth[trimmed] = .unknown
        }
        saveSourceURLs()
        saveSourcePluginIds()
    }

    private func applyFetchedIndex(_ index: LiveParseRemotePluginIndex, sourceURL: String) {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        sourcePluginIds[trimmed] = Set(index.plugins.map(\.pluginId))
        saveSourcePluginIds()
        sourceHealth[trimmed] = .healthy(pluginCount: index.plugins.count)
        remotePlugins = index.plugins.map(makeRemoteDisplayItem)
        mergeLatestRemoteItems(index.plugins)
    }

    private func makeRemoteDisplayItem(from item: LiveParseRemotePluginItem) -> RemotePluginDisplayItem {
        let displayItem = RemotePluginDisplayItem(item: item)
        if installedVersion(for: item.pluginId) != nil {
            displayItem.installState = .installed
        }
        return displayItem
    }

    public func removeSource(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceURLs.removeAll { $0 == trimmed }
        sourcePluginIds.removeValue(forKey: trimmed)
        sourceHealth.removeValue(forKey: trimmed)
        saveSourceURLs()
        saveSourcePluginIds()
    }

    /// 删除订阅源并移除该源对应的已安装插件。
    ///
    /// 删除永远即时:先同步把 URL 从列表里摘掉(UI 立刻更新),再用本地缓存 + 孤儿兜底
    /// 决定卸载哪些插件 —— 全程不发任何网络请求。这样失效/不可达的源也能秒删,
    /// 不会再被 30s 的索引拉取超时卡住(这正是之前"删不掉"的根因)。
    public func removeSourceAndAssociatedPlugins(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 仅用本地缓存解析该源声明过的插件;缓存为空时走下面的孤儿兜底,不再做远程拉取。
        var pluginIds = sourcePluginIds[trimmed] ?? Set<String>()
        let resolvedFromCache = !pluginIds.isEmpty

        // 先摘除 URL,UI 立即去掉这一行。removeSource 已把本源从 sourcePluginIds 移除,
        // 所以下面的 coveredByOtherSources 天然只剩"其它源"。
        removeSource(trimmed)

        // 其它源也声明过同一个 pluginId 时,这些插件不应被卸载。
        let coveredByOtherSources = sourcePluginIds
            .values
            .reduce(into: Set<String>()) { $0.formUnion($1) }

        // 缓存空(常见于:CloudKit 同步后只占位未拉过索引、老版本升级没写过 sourcePluginIds、
        // 添加即失败的失效源)时的兜底:沙盒里实际安装、又没有任何其它源声明的插件,
        // 视为该源的孤儿一并卸载。builtIn 插件不落地到 pluginsRootDirectory,不会被误删。
        if !resolvedFromCache {
            let orphans = installedSandboxPluginIds().subtracting(coveredByOtherSources)
            if !orphans.isEmpty {
                Logger.info(
                    "Removing orphan plugins for source \(trimmed): \(orphans.sorted())",
                    category: .plugin
                )
                pluginIds = orphans
            }
        }

        let pluginsToUninstall = pluginIds.subtracting(coveredByOtherSources)
        for pluginId in pluginsToUninstall {
            _ = uninstallPlugin(pluginId: pluginId)
        }
    }

    /// 列出 Application Support/LiveParse/plugins/ 下的实际安装目录。
    /// builtIn(随 bundle 分发)不在这里,所以这个集合天然只包含沙盒安装的插件。
    private func installedSandboxPluginIds() -> Set<String> {
        let root = LiveParsePlugins.shared.storage.pluginsRootDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(
            urls
                .filter { $0.hasDirectoryPath }
                .map { $0.lastPathComponent }
                .filter { !$0.isEmpty }
        )
    }

    // MARK: - 拉取远程索引

    public func fetchIndex(from urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMessage = "无效的 URL"
            return
        }

        isFetchingIndex = true
        errorMessage = nil
        defer { isFetchingIndex = false }

        do {
            let index = try await fetchIndexWithTimeout(url: url)
            applyFetchedIndex(index, sourceURL: trimmed)
        } catch {
            errorMessage = "拉取插件索引失败: \(Self.detailedErrorDescription(error))"
        }
    }

    /// 从所有订阅源检查可更新版本
    public func refreshAvailableUpdates() async {
        guard !sourceURLs.isEmpty else {
            latestRemoteItemsByPluginId = [:]
            sourcePluginIds = [:]
            sourceHealth = [:]
            saveSourcePluginIds()
            return
        }

        errorMessage = nil
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        var latest: [String: LiveParseRemotePluginItem] = [:]
        var pluginIdsBySource = sourcePluginIds.filter { sourceURLs.contains($0.key) }

        for source in sourceURLs {
            guard let url = URL(string: source) else {
                sourceHealth[source] = .failed("无效的 URL")
                continue
            }
            do {
                let index = try await fetchIndexWithTimeout(url: url)
                pluginIdsBySource[source] = Set(index.plugins.map(\.pluginId))
                sourceHealth[source] = .healthy(pluginCount: index.plugins.count)
                for item in index.plugins {
                    guard let existing = latest[item.pluginId] else {
                        latest[item.pluginId] = item
                        continue
                    }
                    if semverCompare(item.version, existing.version) > 0 {
                        latest[item.pluginId] = item
                    }
                }
            } catch {
                // 单个源失败不影响其它源,失败状态记到该源的 health 上(列表行显示并可重试),
                // 不再写全局 errorMessage,避免一个失效源把整页都罩上红色异常卡片。
                sourceHealth[source] = .failed(Self.detailedErrorDescription(error))
            }
        }

        latestRemoteItemsByPluginId = latest
        sourcePluginIds = pluginIdsBySource
        saveSourcePluginIds()
    }

    // MARK: - 安装插件

    /// 从所有已添加的订阅源拉取索引并合并到 remotePlugins（不覆盖，按 pluginId 去重）
    public func fetchAllSourceIndexes() async {
        isFetchingIndex = true
        errorMessage = nil
        defer { isFetchingIndex = false }

        var allItems: [LiveParseRemotePluginItem] = []
        var seenPluginIds = Set<String>()

        for source in sourceURLs {
            guard let url = URL(string: source) else {
                sourceHealth[source] = .failed("无效的 URL")
                continue
            }
            sourceHealth[source] = .checking
            do {
                let index = try await fetchIndexWithTimeout(url: url)
                sourcePluginIds[source] = Set(index.plugins.map(\.pluginId))
                sourceHealth[source] = .healthy(pluginCount: index.plugins.count)
                for item in index.plugins {
                    if !seenPluginIds.contains(item.pluginId) {
                        seenPluginIds.insert(item.pluginId)
                        allItems.append(item)
                    }
                }
                mergeLatestRemoteItems(index.plugins)
            } catch {
                // 失败状态记到该源的 health(列表行可重试),不再写全局 errorMessage。
                sourceHealth[source] = .failed(Self.detailedErrorDescription(error))
            }
        }

        saveSourcePluginIds()
        remotePlugins = allItems.map(makeRemoteDisplayItem)
    }

    /// 重新拉取单个订阅源(列表行"重试"用)。
    /// 成功后更新该源 health 与缓存,并把它的插件并入 remotePlugins(已存在的按 pluginId 跳过);
    /// 失败只更新该源 health,不影响其它源已加载的内容。
    @discardableResult
    public func refreshSource(_ urlString: String) async -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceURLs.contains(trimmed) else { return false }
        guard let url = URL(string: trimmed) else {
            sourceHealth[trimmed] = .failed("无效的 URL")
            return false
        }

        sourceHealth[trimmed] = .checking
        do {
            let index = try await fetchIndexWithTimeout(url: url)
            sourcePluginIds[trimmed] = Set(index.plugins.map(\.pluginId))
            saveSourcePluginIds()
            sourceHealth[trimmed] = .healthy(pluginCount: index.plugins.count)
            mergeLatestRemoteItems(index.plugins)

            let existingIds = Set(remotePlugins.map(\.id))
            let newItems = index.plugins.filter { !existingIds.contains($0.pluginId) }
            if !newItems.isEmpty {
                remotePlugins.append(contentsOf: newItems.map(makeRemoteDisplayItem))
            }
            return true
        } catch {
            sourceHealth[trimmed] = .failed(Self.detailedErrorDescription(error))
            return false
        }
    }

    public func installPlugin(_ displayItem: RemotePluginDisplayItem) async -> Bool {
        displayItem.installState = .installing

        // manifest 落地后、smoke test 之前调用,只对真有登录的插件弹确认。
        let displayName = displayItem.displayName
        let consentHook: (@Sendable (LiveParsePluginManifest) async -> Bool)?
        if let requester = consentRequester {
            consentHook = { @Sendable manifest in
                guard manifest.requiresLogin else { return true }
                return await requester.requestConsent(
                    reason: .installingLoginPlugin(
                        pluginId: manifest.pluginId,
                        displayName: displayName
                    )
                )
            }
        } else {
            consentHook = nil
        }

        do {
            try await updater.installAndActivate(
                item: displayItem.item,
                manager: LiveParsePlugins.shared,
                afterInstallConsent: consentHook
            )
            displayItem.installState = .installed
            return true
        } catch is PluginInstallConsentError {
            Logger.info("User declined login plugin install: \(displayItem.id)", category: .plugin)
            displayItem.installState = .notInstalled
            return false
        } catch {
            Logger.error(
                error,
                message: "安装插件失败: \(displayItem.id)@\(displayItem.item.version)",
                category: .general
            )
            displayItem.installState = .failed(error.localizedDescription)
            return false
        }
    }

    /// 安装所有未安装的插件。
    ///
    /// 三阶段:
    /// 1. 根据远程索引中的 auth.required 元数据,在下载前先做一次批量登录确认;
    ///    用户取消则跳过所有登录类插件,继续安装非登录类插件;
    /// 2. 下载 + 解压用户同意安装的插件;
    /// 3. 激活已下载的插件并写 last-good。
    ///
    /// 这样把原来"安装完全部再弹登录确认"的体验前置到点击"全部安装"瞬间,
    /// 避免用户白等下载时间后才发现需要登录。
    public func installAll() async -> Int {
        let toInstall = remotePlugins.filter { $0.installState == .notInstalled }
        installTotalCount = toInstall.count
        installCompletedCount = 0
        defer {
            installTotalCount = 0
            installCompletedCount = 0
        }

        // Phase 1: 下载前先弹一次批量登录确认 — 利用索引中的 auth.required 元数据。
        // 发布器约定: 只要 manifest 含 loginFlow, 索引会把 auth.required 标为 true。
        let loginPlugins = toInstall.filter { $0.item.auth?.required == true }
        var declinedIds: Set<String> = []
        if !loginPlugins.isEmpty, let requester = consentRequester {
            let payload = loginPlugins.map {
                LoginPluginEntry(
                    pluginId: $0.item.pluginId,
                    displayName: $0.displayName
                )
            }
            let approved = await requester.requestConsent(
                reason: .installingLoginPluginsBatch(plugins: payload)
            )
            if !approved {
                Logger.info(
                    "User declined batch login plugin install: \(loginPlugins.count) plugins",
                    category: .plugin
                )
                for plugin in loginPlugins {
                    plugin.installState = .notInstalled
                    declinedIds.insert(plugin.id)
                    installCompletedCount += 1
                }
            }
        }

        struct Staged {
            let displayItem: RemotePluginDisplayItem
            let manifest: LiveParsePluginManifest
        }

        // Phase 2: 下载 + 解压用户同意的插件。
        var staged: [Staged] = []
        for plugin in toInstall where !declinedIds.contains(plugin.id) {
            plugin.installState = .installing
            do {
                let manifest = try await updater.install(item: plugin.item)
                staged.append(Staged(displayItem: plugin, manifest: manifest))
            } catch {
                Logger.error(
                    error,
                    message: "下载插件失败: \(plugin.id)@\(plugin.item.version)",
                    category: .general
                )
                plugin.installState = .failed(error.localizedDescription)
                installCompletedCount += 1
            }
        }

        // Phase 3: 激活已下载的插件
        var successCount = 0
        for entry in staged {
            do {
                try await updater.activateInstalled(
                    manifest: entry.manifest,
                    manager: LiveParsePlugins.shared
                )
                entry.displayItem.installState = .installed
                successCount += 1
            } catch {
                Logger.error(
                    error,
                    message: "激活插件失败: \(entry.manifest.pluginId)@\(entry.manifest.version)",
                    category: .general
                )
                entry.displayItem.installState = .failed(error.localizedDescription)
            }
            installCompletedCount += 1
        }

        return successCount
    }

    // MARK: - 版本与更新状态

    public func installedVersion(for pluginId: String) -> String? {
        let versions = LiveParsePlugins.shared.storage.listInstalledVersions(pluginId: pluginId)
            .map(\.lastPathComponent)
            .filter { !$0.isEmpty }
            .sorted { semverCompare($0, $1) > 0 }
        return versions.first
    }

    public func hasUpdate(for pluginId: String) -> Bool {
        guard let installedVersion = installedVersion(for: pluginId),
              let remoteVersion = latestRemoteItemsByPluginId[pluginId]?.version else {
            return false
        }
        return semverCompare(remoteVersion, installedVersion) > 0
    }

    public func latestVersion(for pluginId: String) -> String? {
        latestRemoteItemsByPluginId[pluginId]?.version
    }

    @discardableResult
    public func updatePlugin(pluginId: String) async -> Bool {
        guard let item = latestRemoteItemsByPluginId[pluginId] else { return false }
        if updatingPluginIds.contains(pluginId) { return false }

        errorMessage = nil
        updatingPluginIds.insert(pluginId)
        defer { updatingPluginIds.remove(pluginId) }

        do {
            try await updater.installAndActivate(item: item, manager: LiveParsePlugins.shared)
            if let remoteItem = remotePlugins.first(where: { $0.id == pluginId }) {
                remoteItem.installState = .installed
            }
            return true
        } catch {
            errorMessage = "更新插件失败: \(error.localizedDescription)"
            return false
        }
    }

    private func mergeLatestRemoteItems(_ items: [LiveParseRemotePluginItem]) {
        var merged = latestRemoteItemsByPluginId
        for item in items {
            guard let existing = merged[item.pluginId] else {
                merged[item.pluginId] = item
                continue
            }
            if semverCompare(item.version, existing.version) > 0 {
                merged[item.pluginId] = item
            }
        }
        latestRemoteItemsByPluginId = merged
    }

    @discardableResult
    public func uninstallPlugin(pluginId: String) -> Bool {
        let storage = LiveParsePlugins.shared.storage
        let pluginDirectory = storage.pluginDirectory(pluginId: pluginId)
        let start = Date()
        let consoleRequest = """
        pluginId: \(pluginId)
        directory: \(pluginDirectory.path)
        """
        let consoleIdBox = ConsoleEntryIdBox()
        Task { @MainActor in
            let id = PluginConsoleService.shared.log(tag: "Plugin", method: "uninstall", status: .loading)
            PluginConsoleService.shared.updateRequest(id: id, body: consoleRequest)
            consoleIdBox.id = id
        }

        // 1. 先从内存中驱逐插件，防止卸载过程中被调用
        LiveParsePlugins.shared.evict(pluginId: pluginId)

        // 2. 先更新持久化状态（标记移除），确保即使后续步骤崩溃，
        //    重启后也不会再加载该插件
        do {
            var state = storage.loadState()
            state.plugins.removeValue(forKey: pluginId)
            try storage.saveState(state)
        } catch {
            errorMessage = "删除插件状态失败: \(error.localizedDescription)"
            Logger.error(error, message: "Failed to update state for plugin uninstall: \(pluginId)", category: .plugin)
            let errMsg = "saveState 失败: \(error.localizedDescription)"
            let duration = Date().timeIntervalSince(start)
            Task { @MainActor in
                if let id = consoleIdBox.id {
                    PluginConsoleService.shared.updateStatus(
                        id: id,
                        status: .error,
                        duration: duration,
                        errorMessage: errMsg
                    )
                }
            }
            return false
        }

        // 3. 删除文件（状态已安全，文件删除失败不影响一致性）
        var fileRemovalError: Error?
        do {
            if FileManager.default.fileExists(atPath: pluginDirectory.path) {
                try FileManager.default.removeItem(at: pluginDirectory)
            }
        } catch {
            Logger.warning("Failed to delete plugin files for \(pluginId): \(error.localizedDescription)", category: .plugin)
            fileRemovalError = error
            // 文件删除失败不视为致命错误，状态已正确更新
        }

        // 4. 刷新运行时
        try? LiveParsePlugins.shared.reload()
        PlatformCapability.invalidateCache()

        if let item = remotePlugins.first(where: { $0.id == pluginId }) {
            item.installState = .notInstalled
        }
        var responseLines = ["已驱逐插件: \(pluginId)", "状态文件已更新"]
        if let fileRemovalError {
            responseLines.append("⚠ 文件未能完全删除: \(fileRemovalError.localizedDescription)")
        } else {
            responseLines.append("文件已删除")
        }
        let responseBody = responseLines.joined(separator: "\n")
        let duration = Date().timeIntervalSince(start)
        Task { @MainActor in
            if let id = consoleIdBox.id {
                PluginConsoleService.shared.updateStatus(
                    id: id,
                    status: .success,
                    duration: duration,
                    responseBody: responseBody
                )
            }
        }
        return true
    }

    /// 在 sync 上下文里跟 main-actor Task 之间传递 console entry id 的小盒子。
    /// 所有 Task 都 hop 到 MainActor 后才读写 id,顺序由 MainActor 串行性保证。
    private final class ConsoleEntryIdBox: @unchecked Sendable {
        var id: UUID?
    }

    // MARK: - Error Description Helper

    /// 将错误转为更具体的描述，方便排查问题
    static func detailedErrorDescription(_ error: Error) -> String {
        if let fetchError = error as? LiveParsePluginIndexFetchError {
            switch fetchError {
            case .nonJSONResponse(let diagnostics):
                return "返回的不是 JSON。\(responseDiagnosticsDescription(diagnostics))"
            case .decodingFailed(let diagnostics, let decodingError):
                return "\(detailedDecodingErrorDescription(decodingError))。\(responseDiagnosticsDescription(diagnostics))"
            }
        }

        if let decodingError = error as? DecodingError {
            return detailedDecodingErrorDescription(decodingError)
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "请求超时"
            case .notConnectedToInternet:
                return "无网络连接"
            case .cannotFindHost:
                return "无法解析域名"
            case .secureConnectionFailed:
                return "SSL 连接失败"
            default:
                return "网络错误(\(urlError.code.rawValue)): \(urlError.localizedDescription)"
            }
        }

        return error.localizedDescription
    }

    private static func detailedDecodingErrorDescription(_ decodingError: DecodingError) -> String {
        switch decodingError {
        case .typeMismatch(let type, let context):
            return "类型不匹配: 期望 \(type), 路径 \(codingPathDescription(context.codingPath))"
        case .valueNotFound(let type, let context):
            return "缺少值: \(type), 路径 \(codingPathDescription(context.codingPath))"
        case .keyNotFound(let key, let context):
            return "缺少字段: \(key.stringValue), 路径 \(codingPathDescription(context.codingPath))"
        case .dataCorrupted(let context):
            return "数据损坏: \(context.debugDescription), 路径 \(codingPathDescription(context.codingPath))"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func responseDiagnosticsDescription(_ diagnostics: LiveParsePluginIndexResponseDiagnostics) -> String {
        let statusText = diagnostics.statusCode.map(String.init) ?? "n/a"
        let contentTypeText = diagnostics.contentType ?? "unknown"
        return "URL \(diagnostics.url.absoluteString), HTTP \(statusText), Content-Type \(contentTypeText), 响应片段 \(diagnostics.bodyPreview)"
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }

    // MARK: - Timeout Helper

    private func fetchIndexWithTimeout(url: URL) async throws -> LiveParseRemotePluginIndex {
        let timeout = fetchTimeoutSeconds
        let localUpdater = updater
        return try await withThrowingTaskGroup(of: LiveParseRemotePluginIndex.self) { group in
            group.addTask {
                try await localUpdater.fetchIndex(url: url)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return result
        }
    }

}
