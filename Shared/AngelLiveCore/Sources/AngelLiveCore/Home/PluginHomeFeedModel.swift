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

/// Cross-platform presentation state for the plugin-driven home feed.
/// Each scene owns its instance; plugin execution and persistence remain in AngelLiveCore.
@MainActor
@Observable
public final class PluginHomeFeedModel {
    public private(set) var bannerEntries: [HomeBannerEntry] = []
    public private(set) var sectionEntries: [HomeSectionEntry] = []
    public private(set) var failedPluginNames: [String] = []
    public private(set) var platformOptions: [HomePlatformOption] = []
    public private(set) var selectedPluginId: String?
    public private(set) var isRefreshing = false
    public private(set) var hasLoaded = false
    public private(set) var hasRestoredCache = false

    @ObservationIgnored private let service: PluginHomeFeedService
    @ObservationIgnored private let cacheStore: PluginHomeFeedCacheStore
    @ObservationIgnored private var feedsByPluginId: [String: PluginHomeFeed] = [:]
    @ObservationIgnored private var platformOrder: [String] = []

    public init(
        service: PluginHomeFeedService = PluginHomeFeedService(),
        cacheStore: PluginHomeFeedCacheStore = .shared
    ) {
        self.service = service
        self.cacheStore = cacheStore
    }

    public func refresh(installedPluginIds: [String], availabilityConfirmed: Bool = true) async {
        guard !isRefreshing else { return }

        if !hasRestoredCache {
            let cachedFeeds = await cacheStore.load()
            for feed in cachedFeeds {
                feedsByPluginId[feed.pluginId] = feed
            }
            platformOrder = cachedFeeds.map(\.pluginId)
            platformOptions = cachedFeeds.map {
                HomePlatformOption(
                    pluginId: $0.pluginId,
                    displayName: $0.pluginDisplayName,
                    liveType: LiveParseJSPlatformManager.platform(forPluginId: $0.pluginId)?.liveType
                        ?? LiveType(rawValue: $0.pluginId)
                        ?? .placeholder
                )
            }
            normalizePlatformSelection()
            hasRestoredCache = true
            rebuildEntries()
        }

        // The host briefly reports an empty plugin list while catalog detection runs.
        // Keep the compatible snapshot until absence has been confirmed.
        guard availabilityConfirmed else { return }

        let platforms = SandboxPluginCatalog
            .availablePlatforms(installedPluginIds: installedPluginIds)
            .filter { PlatformCapability.supports(.homeFeed, for: $0.liveType) }

        let activePluginIds = Set(platforms.map(\.pluginId))
        platformOptions = platforms.map {
            HomePlatformOption(pluginId: $0.pluginId, displayName: $0.displayName, liveType: $0.liveType)
        }
        normalizePlatformSelection()
        platformOrder = stableOrder(previous: platformOrder, current: platforms.map(\.pluginId))

        feedsByPluginId = feedsByPluginId.filter { activePluginIds.contains($0.key) }
        failedPluginNames.removeAll()
        rebuildEntries()

        guard !platforms.isEmpty else {
            hasLoaded = true
            await cacheStore.save([])
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        await withTaskGroup(of: HomeFeedFetchResult.self) { group in
            for platform in platforms {
                group.addTask { [service] in
                    do {
                        return .success(try await service.fetch(platform: platform))
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failure(
                            pluginId: platform.pluginId,
                            pluginDisplayName: platform.displayName,
                            message: error.localizedDescription
                        )
                    }
                }
            }

            for await result in group {
                guard !Task.isCancelled else { break }
                switch result {
                case .success(let feed):
                    feedsByPluginId[feed.pluginId] = feed
                case .failure(let pluginId, let pluginDisplayName, let message):
                    failedPluginNames.append(pluginDisplayName)
                    Logger.warning(
                        "首页内容加载失败: pluginId=\(pluginId), error=\(message)",
                        category: .plugin
                    )
                case .cancelled:
                    break
                }
                rebuildEntries()
            }
        }

        guard !Task.isCancelled else { return }
        await cacheStore.save(platformOrder.compactMap { feedsByPluginId[$0] })
    }

    public func selectPlatform(pluginId: String?) {
        guard selectedPluginId != pluginId else { return }
        selectedPluginId = pluginId
        normalizePlatformSelection()
        rebuildEntries()
    }
}

private extension PluginHomeFeedModel {
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
    case cancelled
}
