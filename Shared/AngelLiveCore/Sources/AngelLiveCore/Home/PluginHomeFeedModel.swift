import Foundation
import Observation

public struct HomeBannerEntry: Identifiable, Sendable {
    public let banner: PluginHomeBanner
    public let pluginId: String
    public let pluginDisplayName: String
    public let liveType: LiveType

    public var id: String { "\(pluginId)::\(banner.id)" }

    public init(banner: PluginHomeBanner, pluginId: String, pluginDisplayName: String, liveType: LiveType) {
        self.banner = banner
        self.pluginId = pluginId
        self.pluginDisplayName = pluginDisplayName
        self.liveType = liveType
    }
}

public struct HomeSectionEntry: Identifiable, Sendable {
    public let section: PluginHomeSection
    public let pluginId: String
    public let pluginDisplayName: String
    public let liveType: LiveType

    public var id: String { "\(pluginId)::\(section.id)" }

    public init(section: PluginHomeSection, pluginId: String, pluginDisplayName: String, liveType: LiveType) {
        self.section = section
        self.pluginId = pluginId
        self.pluginDisplayName = pluginDisplayName
        self.liveType = liveType
    }
}

public struct HomePlatformOption: Identifiable, Hashable, Sendable {
    public let pluginId: String
    public let displayName: String
    public let liveType: LiveType

    public var id: String { pluginId }

    public init(pluginId: String, displayName: String, liveType: LiveType) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.liveType = liveType
    }
}

public struct PluginHomeFeedRefreshContext: Equatable, Sendable {
    public var pluginRevisions: [String: String]

    public init(pluginRevisions: [String: String] = [:]) {
        self.pluginRevisions = pluginRevisions
    }

    public static func current(for installedPluginIds: [String]) async -> Self {
        let pluginIds = Set(installedPluginIds)
        while true {
            let captured = await capture(pluginIds: pluginIds)
            if Task.isCancelled { return Self(pluginRevisions: captured) }
            let confirmed = await capture(pluginIds: pluginIds)
            if Task.isCancelled { return Self(pluginRevisions: confirmed) }
            guard captured == confirmed else { continue }
            return Self(pluginRevisions: captured)
        }
    }

    private static func capture(pluginIds: Set<String>) async -> [String: String] {
        var revisions: [String: String] = [:]
        for pluginId in pluginIds {
            let version = (try? LiveParsePlugins.shared.resolve(pluginId: pluginId).manifest.version) ?? "unresolved"
            let session = LiveParsePlatformSessionVault.revision(for: pluginId)
            let api = await PlatformAPITokenVault.shared.generationSnapshot(pluginId: pluginId).generation.uuidString
            revisions[pluginId] = opaqueRevision(version: version, sessionRevision: session, apiGeneration: api)
        }
        return revisions
    }

    private static func opaqueRevision(
        version: String,
        sessionRevision: String,
        apiGeneration: String
    ) -> String {
        [version, sessionRevision, apiGeneration]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }
}

public enum PluginHomeFeedPluginState: Equatable, Sendable {
    case cached
    case loading
    case refreshing
    case stale
    case failed(message: String)
}

/// Cross-platform presentation state for the plugin-driven home feed.
/// Each scene owns its instance; plugin execution and persistence remain in AngelLiveCore.
@MainActor
@Observable
public final class PluginHomeFeedModel {
    public private(set) var bannerEntries: [HomeBannerEntry] = []
    public private(set) var sectionEntries: [HomeSectionEntry] = []
    public private(set) var failedPluginNames: [String] = []
    public private(set) var pluginStates: [String: PluginHomeFeedPluginState] = [:]
    public private(set) var platformOptions: [HomePlatformOption] = []
    public private(set) var selectedPluginId: String?
    public private(set) var isRefreshing = false
    public private(set) var hasLoaded = false
    public private(set) var hasRestoredCache = false

    @ObservationIgnored private let service: PluginHomeFeedService
    @ObservationIgnored private let cacheStore: PluginHomeFeedCacheStore
    @ObservationIgnored private var feedsByPluginId: [String: PluginHomeFeed] = [:]
    @ObservationIgnored private var fetchedAtByPluginId: [String: Date] = [:]
    @ObservationIgnored private var cachedRevisionByPluginId: [String: String] = [:]
    @ObservationIgnored private var platformOrder: [String] = []
    @ObservationIgnored private var cacheRestoreTask: Task<PluginHomeFeedCacheStore.Snapshot?, Never>?
    @ObservationIgnored private var activeRefresh: (identity: RefreshIdentity, task: Task<Void, Never>)?
    @ObservationIgnored private var retirementBarrier: Task<Void, Never>?
    @ObservationIgnored private var retirementBarrierGeneration: UInt64 = 0
    @ObservationIgnored private var refreshIntent: UInt64 = 0
    @ObservationIgnored private var refreshGeneration: UInt64 = 0
    @ObservationIgnored private let now: @MainActor @Sendable () -> Date
    @ObservationIgnored private let platformProvider: @MainActor @Sendable ([String]) -> [LiveParseJSPlatform]

    public init(
        service: PluginHomeFeedService = PluginHomeFeedService(),
        cacheStore: PluginHomeFeedCacheStore = .shared
    ) {
        self.service = service
        self.cacheStore = cacheStore
        now = Date.init
        platformProvider = {
            SandboxPluginCatalog.availablePlatforms(installedPluginIds: $0)
                .filter { PlatformCapability.supports(.homeFeed, for: $0.liveType) }
        }
    }

    init(
        service: PluginHomeFeedService,
        cacheStore: PluginHomeFeedCacheStore,
        now: @escaping @MainActor @Sendable () -> Date,
        platformProvider: @escaping @MainActor @Sendable ([String]) -> [LiveParseJSPlatform]
    ) {
        self.service = service
        self.cacheStore = cacheStore
        self.now = now
        self.platformProvider = platformProvider
    }

    public func refresh(
        installedPluginIds: [String],
        availabilityConfirmed: Bool = true,
        context: PluginHomeFeedRefreshContext = .init(),
        force: Bool = false
    ) async {
        refreshIntent &+= 1
        let intent = refreshIntent

        await restoreCacheIfNeeded()
        guard refreshIntent == intent, !Task.isCancelled else { return }

        // The host briefly reports an empty plugin list while catalog detection runs.
        // Keep the compatible snapshot until absence has been confirmed.
        guard availabilityConfirmed else { return }

        let platforms = platformProvider(installedPluginIds)

        guard !platforms.isEmpty else {
            cancelActiveRefresh()
            await awaitRetirementBarrier()
            guard refreshIntent == intent, !Task.isCancelled else { return }
            applyPlatforms([])
            hasLoaded = true
            await cacheStore.save([], contextRevisions: [:], fetchedAtByPluginId: [:])
            return
        }

        let identity = RefreshIdentity(
            pluginIds: platforms.map(\.pluginId).sorted(),
            revisions: platforms.map {
                ($0.pluginId, context.pluginRevisions[$0.pluginId] ?? "legacy")
            }.sorted { $0.0 < $1.0 }
        )
        if let activeRefresh, activeRefresh.identity == identity {
            await activeRefresh.task.value
            return
        }

        cancelActiveRefresh()
        await awaitRetirementBarrier()
        guard refreshIntent == intent, !Task.isCancelled else { return }
        applyPlatforms(platforms)
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let fetchedAt = now()
        let platformsToFetch = platforms.filter { platform in
            let id = platform.pluginId
            let revision = context.pluginRevisions[id] ?? "legacy"
            let valid = isCacheValid(pluginId: id, revision: revision, at: fetchedAt)
            if force || !valid {
                pluginStates[id] = feedsByPluginId[id] == nil ? .loading : (valid ? .refreshing : .stale)
                return true
            }
            pluginStates[id] = .cached
            return false
        }
        rebuildFailedPluginNames()

        guard !platformsToFetch.isEmpty else {
            hasLoaded = true
            isRefreshing = false
            return
        }

        isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(
                platforms: platformsToFetch,
                allPlatforms: platforms,
                revisions: context.pluginRevisions,
                generation: generation
            )
        }
        activeRefresh = (identity, task)
        await task.value
    }

    public func cancelRefresh() {
        refreshIntent &+= 1
        cancelActiveRefresh()
    }

    public func selectPlatform(pluginId: String?) {
        guard selectedPluginId != pluginId else { return }
        selectedPluginId = pluginId
        normalizePlatformSelection()
        rebuildEntries()
    }
}

private extension PluginHomeFeedModel {
    func applyPlatforms(_ platforms: [LiveParseJSPlatform]) {
        let activePluginIds = Set(platforms.map(\.pluginId))
        platformOptions = platforms.map {
            HomePlatformOption(pluginId: $0.pluginId, displayName: $0.displayName, liveType: $0.liveType)
        }
        normalizePlatformSelection()
        platformOrder = stableOrder(previous: platformOrder, current: platforms.map(\.pluginId))
        feedsByPluginId = feedsByPluginId.filter { activePluginIds.contains($0.key) }
        fetchedAtByPluginId = fetchedAtByPluginId.filter { activePluginIds.contains($0.key) }
        cachedRevisionByPluginId = cachedRevisionByPluginId.filter { activePluginIds.contains($0.key) }
        pluginStates = pluginStates.filter { activePluginIds.contains($0.key) }
        rebuildFailedPluginNames()
        rebuildEntries()
    }

    func performRefresh(
        platforms: [LiveParseJSPlatform],
        allPlatforms: [LiveParseJSPlatform],
        revisions: [String: String],
        generation: UInt64
    ) async {
        defer {
            if refreshGeneration == generation {
                activeRefresh = nil
                isRefreshing = false
                hasLoaded = true
            }
        }

        var iterator = platforms.makeIterator()
        await withTaskGroup(of: HomeFeedFetchResult.self) { group in
            for _ in 0..<min(3, platforms.count) {
                if let platform = iterator.next() { addFetch(platform, to: &group) }
            }

            while let result = await group.next() {
                guard refreshGeneration == generation, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                apply(result, revisions: revisions)
                if let platform = iterator.next() { addFetch(platform, to: &group) }
            }
        }

        guard refreshGeneration == generation, !Task.isCancelled else { return }
        let activeIds = Set(allPlatforms.map(\.pluginId))
        let feeds = platformOrder.compactMap { activeIds.contains($0) ? feedsByPluginId[$0] : nil }
        await cacheStore.save(
            feeds,
            contextRevisions: Dictionary(
                uniqueKeysWithValues: feeds.compactMap { feed in
                    cachedRevisionByPluginId[feed.pluginId].map { (feed.pluginId, $0) }
                }
            ),
            fetchedAtByPluginId: fetchedAtByPluginId
        )
    }

    func addFetch(
        _ platform: LiveParseJSPlatform,
        to group: inout TaskGroup<HomeFeedFetchResult>
    ) {
        group.addTask { [service] in
            do {
                return .success(try await service.fetch(platform: platform))
            } catch is CancellationError {
                return .cancelled(pluginId: platform.pluginId)
            } catch {
                return .failure(
                    pluginId: platform.pluginId,
                    pluginDisplayName: platform.displayName,
                    message: error.localizedDescription
                )
            }
        }
    }

    func apply(_ result: HomeFeedFetchResult, revisions: [String: String]) {
        switch result {
        case .success(let feed):
            feedsByPluginId[feed.pluginId] = feed
            fetchedAtByPluginId[feed.pluginId] = now()
            cachedRevisionByPluginId[feed.pluginId] = revisions[feed.pluginId] ?? "legacy"
            pluginStates[feed.pluginId] = .cached
        case .failure(let pluginId, _, let message):
            pluginStates[pluginId] = .failed(message: message)
            Logger.warning(
                "首页内容加载失败: pluginId=\(pluginId), error=\(message)",
                category: .plugin
            )
        case .cancelled:
            break
        }
        rebuildFailedPluginNames()
        rebuildEntries()
    }

    func isCacheValid(pluginId: String, revision: String, at date: Date) -> Bool {
        guard let feed = feedsByPluginId[pluginId],
              cachedRevisionByPluginId[pluginId] == revision,
              let fetchedAt = fetchedAtByPluginId[pluginId] else { return false }
        return date.timeIntervalSince(fetchedAt) < TimeInterval(feed.ttlSeconds)
    }

    func cancelActiveRefresh() {
        guard activeRefresh != nil else { return }
        refreshGeneration &+= 1
        activeRefresh?.task.cancel()
        if let task = activeRefresh?.task {
            let previousBarrier = retirementBarrier
            retirementBarrierGeneration &+= 1
            retirementBarrier = Task {
                if let previousBarrier { await previousBarrier.value }
                await task.value
            }
        }
        activeRefresh = nil
        isRefreshing = false
        for pluginId in Array(pluginStates.keys) {
            if feedsByPluginId[pluginId] != nil {
                pluginStates[pluginId] = .cached
            } else {
                pluginStates.removeValue(forKey: pluginId)
            }
        }
        rebuildFailedPluginNames()
    }

    func awaitRetirementBarrier() async {
        guard let barrier = retirementBarrier else { return }
        let barrierGeneration = retirementBarrierGeneration
        await barrier.value
        if retirementBarrierGeneration == barrierGeneration {
            retirementBarrier = nil
        }
    }

    func restoreCacheIfNeeded() async {
        guard !hasRestoredCache else { return }
        let task: Task<PluginHomeFeedCacheStore.Snapshot?, Never>
        if let cacheRestoreTask {
            task = cacheRestoreTask
        } else {
            task = Task { [cacheStore] in await cacheStore.loadSnapshot() }
            cacheRestoreTask = task
        }
        let snapshot = await task.value
        guard !hasRestoredCache else { return }
        let cachedEntries = snapshot?.entries ?? []
        for entry in cachedEntries {
            let feed = entry.feed
            feedsByPluginId[feed.pluginId] = feed
            fetchedAtByPluginId[feed.pluginId] = entry.fetchedAt
            cachedRevisionByPluginId[feed.pluginId] = entry.contextRevision
            pluginStates[feed.pluginId] = .cached
        }
        platformOrder = cachedEntries.map(\.feed.pluginId)
        platformOptions = cachedEntries.map {
            let feed = $0.feed
            return HomePlatformOption(
                pluginId: feed.pluginId,
                displayName: feed.pluginDisplayName,
                liveType: LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                    ?? LiveType(rawValue: feed.pluginId)
                    ?? .placeholder
            )
        }
        normalizePlatformSelection()
        hasRestoredCache = true
        cacheRestoreTask = nil
        rebuildEntries()
    }

    func rebuildFailedPluginNames() {
        let namesById = Dictionary(uniqueKeysWithValues: platformOptions.map { ($0.pluginId, $0.displayName) })
        failedPluginNames = platformOrder.compactMap { id in
            guard case .failed = pluginStates[id] else { return nil }
            return namesById[id]
        }
    }

    func normalizePlatformSelection() {
        guard let selectedPluginId else { return }
        if !platformOptions.contains(where: { $0.pluginId == selectedPluginId }) {
            self.selectedPluginId = nil
        }
    }

    func stableOrder(previous: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        let retained = previous.filter(currentSet.contains)
        let retainedSet = Set(retained)
        return retained + current.filter { !retainedSet.contains($0) }
    }

    func rebuildEntries() {
        let allFeeds = platformOrder.compactMap { feedsByPluginId[$0] }
        let feeds = selectedPluginId.map { id in allFeeds.filter { $0.pluginId == id } } ?? allFeeds
        bannerEntries = fairBannerEntries(from: feeds)

        sectionEntries = feeds.compactMap { feed -> HomeSectionEntry? in
            let fallbackLiveType = LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                ?? LiveType(rawValue: feed.pluginId)
                ?? .placeholder
            let section = feed.sections.first(where: { $0.personalized && !$0.items.isEmpty })
                ?? feed.sections.first
            guard let section, !section.items.isEmpty else { return nil }

            return HomeSectionEntry(
                section: section,
                pluginId: feed.pluginId,
                pluginDisplayName: feed.pluginDisplayName,
                liveType: section.items.first?.room.liveType ?? fallbackLiveType
            )
        }
    }

    func fairBannerEntries(from feeds: [PluginHomeFeed]) -> [HomeBannerEntry] {
        let maximumSourceCount = feeds.map(\.banners.count).max() ?? 0
        var result: [HomeBannerEntry] = []

        for sourceIndex in 0..<maximumSourceCount {
            for feed in feeds where feed.banners.indices.contains(sourceIndex) {
                let banner = feed.banners[sourceIndex]
                let liveType: LiveType
                switch banner.target {
                case .room(let room):
                    liveType = room.liveType
                case .category:
                    liveType = LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                        ?? LiveType(rawValue: feed.pluginId)
                        ?? .placeholder
                }
                result.append(HomeBannerEntry(
                    banner: banner,
                    pluginId: feed.pluginId,
                    pluginDisplayName: feed.pluginDisplayName,
                    liveType: liveType
                ))
            }
        }
        return result
    }
}

private enum HomeFeedFetchResult: Sendable {
    case success(PluginHomeFeed)
    case failure(pluginId: String, pluginDisplayName: String, message: String)
    case cancelled(pluginId: String)
}

private struct RefreshIdentity: Equatable, Sendable {
    let pluginIds: [String]
    let revisions: [(String, String)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pluginIds == rhs.pluginIds
            && lhs.revisions.elementsEqual(rhs.revisions, by: ==)
    }
}
