//
//  HomeViewModel.swift
//  AngelLive
//
//  插件驱动首页的展示状态。各插件独立加载，失败时保留其他来源的内容。
//

import AngelLiveCore
import Foundation
import Observation

struct HomeBannerEntry: Identifiable, Sendable {
    let banner: PluginHomeBanner
    let pluginId: String
    let pluginDisplayName: String
    let liveType: LiveType

    var id: String { banner.id }
}

struct HomeSectionEntry: Identifiable, Sendable {
    let section: PluginHomeSection
    let pluginId: String
    let pluginDisplayName: String
    let liveType: LiveType

    var id: String { "\(pluginId)::\(section.id)" }
}

struct HomePlatformOption: Identifiable, Hashable, Sendable {
    let pluginId: String
    let displayName: String
    let liveType: LiveType

    var id: String { pluginId }
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var bannerEntries: [HomeBannerEntry] = []
    private(set) var sectionEntries: [HomeSectionEntry] = []
    private(set) var failedPluginNames: [String] = []
    private(set) var platformOptions: [HomePlatformOption] = []
    private(set) var selectedPluginId: String?
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false
    private(set) var hasRestoredCache = false

    @ObservationIgnored
    private let service: PluginHomeFeedService
    @ObservationIgnored
    private let cacheStore: PluginHomeFeedCacheStore
    @ObservationIgnored
    private var feedsByPluginId: [String: PluginHomeFeed] = [:]
    @ObservationIgnored
    private var platformOrder: [String] = []
    init(
        service: PluginHomeFeedService = PluginHomeFeedService(),
        cacheStore: PluginHomeFeedCacheStore = .shared
    ) {
        self.service = service
        self.cacheStore = cacheStore
    }

    func refresh(
        installedPluginIds: [String],
        availabilityConfirmed: Bool = true
    ) async {
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
            hasRestoredCache = true
            rebuildEntries()
        }

        // App 启动时 installedPluginIds 会先短暂为空。此时只展示缓存，不能把它
        // 当成“用户没有插件”并清掉快照；等待 PluginAvailabilityService 明确确认。
        guard availabilityConfirmed else {
            return
        }

        let platforms = SandboxPluginCatalog
            .availablePlatforms(installedPluginIds: installedPluginIds)
            .filter { PlatformCapability.supports(.homeFeed, for: $0.liveType) }

        let activePluginIds = Set(platforms.map(\.pluginId))
        platformOptions = platforms.map {
            HomePlatformOption(
                pluginId: $0.pluginId,
                displayName: $0.displayName,
                liveType: $0.liveType
            )
        }
        normalizePlatformSelection()
        platformOrder = stableOrder(
            previous: platformOrder,
            current: platforms.map(\.pluginId)
        )

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
                        let feed = try await service.fetch(platform: platform)
                        return .success(feed)
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

        let activeFeeds = platformOrder.compactMap { feedsByPluginId[$0] }
        await cacheStore.save(activeFeeds)
    }

    func selectPlatform(pluginId: String?) {
        guard pluginId == nil || platformOptions.contains(where: { $0.pluginId == pluginId }) else {
            return
        }
        guard selectedPluginId != pluginId else { return }
        selectedPluginId = pluginId
        rebuildEntries()
    }
}

private extension HomeViewModel {
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
        let feeds = selectedPluginId.map { pluginId in
            allFeeds.filter { $0.pluginId == pluginId }
        } ?? allFeeds
        bannerEntries = fairBannerEntries(from: feeds)

        let availableSections: [HomeSectionEntry] = feeds.compactMap { feed -> HomeSectionEntry? in
            let liveType = LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                ?? LiveType(rawValue: feed.pluginId)
                ?? .placeholder

            // A plugin's first section is its primary recommendation rail;
            // later sections are category-specific rails. Prefer an explicitly
            // personalized rail when present, otherwise keep only that first
            // primary rail so the host does not expose concrete categories on
            // the home page.
            let section: PluginHomeSection?
            if let personalizedSection = feed.sections.first(where: {
                $0.personalized && !$0.items.isEmpty
            }) {
                section = personalizedSection
            } else {
                section = feed.sections.first
            }
            guard let section, !section.items.isEmpty else { return nil }

            return HomeSectionEntry(
                section: section,
                pluginId: feed.pluginId,
                pluginDisplayName: feed.pluginDisplayName,
                liveType: section.items.first?.room.liveType ?? liveType
            )
        }

        sectionEntries = availableSections
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
                result.append(
                    HomeBannerEntry(
                        banner: banner,
                        pluginId: feed.pluginId,
                        pluginDisplayName: feed.pluginDisplayName,
                        liveType: liveType
                    )
                )
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
