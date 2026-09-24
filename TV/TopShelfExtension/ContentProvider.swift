//
//  ContentProvider.swift
//  TopShelfExtension
//
//  Created by pangchong on 12/12/25.
//

@preconcurrency import TVServices
import AngelLiveCore

class ContentProvider: TVTopShelfContentProvider {

    // 基类 init 是 nonisolated,显式对齐,避免默认 MainActor 隔离下的重写隔离不匹配
    nonisolated override init() {
        super.init()
    }

    /// 整体超时时间（秒）
    private let totalTimeout: TimeInterval = 20
    /// 单个请求超时时间（秒）
    private let singleRequestTimeout: TimeInterval = 8

    private static let appGroupIdentifier = "group.dev.idog.angellivetvos"

    /// 从 App Group 容器复制插件到 TopShelf 的 Caches 目录，
    /// 使 LiveParsePlugins.shared 能加载到沙盒插件。
    private func syncPluginsFromAppGroup() {
        let fm = FileManager.default

        guard let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            Logger.warning("[TopShelf] App Group container not available.", category: .app)
            return
        }

        let sourcePluginsDir = containerURL
            .appendingPathComponent("LiveParse", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        let sourceState = containerURL
            .appendingPathComponent("LiveParse", isDirectory: true)
            .appendingPathComponent("state.json")

        guard fm.fileExists(atPath: sourcePluginsDir.path) else {
            Logger.debug("[TopShelf] No plugins in App Group container.", category: .app)
            return
        }

        // 复制到 LiveParsePlugins.shared.storage 实际使用的目录
        let destLiveParseDir = LiveParsePlugins.shared.storage.baseDirectory
        let destPluginsDir = destLiveParseDir.appendingPathComponent("plugins", isDirectory: true)
        let destState = destLiveParseDir.appendingPathComponent("state.json")

        Logger.debug("[TopShelf] Syncing plugins to: \(destLiveParseDir.path)", category: .app)

        do {
            try fm.createDirectory(at: destLiveParseDir, withIntermediateDirectories: true)

            if fm.fileExists(atPath: destPluginsDir.path) {
                try fm.removeItem(at: destPluginsDir)
            }
            try fm.copyItem(at: sourcePluginsDir, to: destPluginsDir)

            if fm.fileExists(atPath: sourceState.path) {
                if fm.fileExists(atPath: destState.path) {
                    try fm.removeItem(at: destState)
                }
                try fm.copyItem(at: sourceState, to: destState)
            }

            Logger.debug("[TopShelf] Synced plugins from App Group to local Caches.", category: .app)
        } catch {
            Logger.warning("[TopShelf] Failed to sync plugins: \(error)", category: .app)
        }
    }

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        Logger.debug("[TopShelf] loadTopShelfContent() called", category: .app)

        // FullUI 使用宿主已刷新的展示快照。空快照同样是有效结果，不能回退
        // 到云端旧收藏；未发布过快照的安装仍沿用原有扩展路径。
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TopShelfSnapshotStore.appGroupIdentifier
        ) {
            do {
                if let snapshot = try TopShelfSnapshotStore(containerURL: container).load() {
                    return createTopShelfContent(from: snapshot)
                }
            } catch {
                Logger.warning("[TopShelf] Favorite snapshot could not be read.", category: .app)
                return nil
            }
        }

        // 打印 App Group 插件目录内容
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            let pluginsDir = container.appendingPathComponent("LiveParse/plugins", isDirectory: true)
            Logger.debug("[TopShelf] App Group plugins dir: \(pluginsDir.path)", category: .app)
            Logger.debug("[TopShelf] Exists: \(fm.fileExists(atPath: pluginsDir.path))", category: .app)
            if let contents = try? fm.contentsOfDirectory(atPath: pluginsDir.path) {
                Logger.debug("[TopShelf] Plugin count: \(contents.count)", category: .app)
                Logger.debug("[TopShelf] Plugins: \(contents)", category: .app)
            }
        }

        // 从 App Group 同步插件到本地 Caches，供 LiveParsePlugins.shared 使用
        syncPluginsFromAppGroup()

        // 同步完成后重新加载插件（LiveParsePlugins.shared 是 static let，首次访问时 Caches 还为空）
        try? LiveParsePlugins.shared.reload()

        do {
            // 1. 从 CloudKit 读取收藏列表
            Logger.debug("[TopShelf] Fetching favorites from CloudKit...", category: .app)
            let favorites = try await FavoriteService.searchRecord()
            Logger.debug("[TopShelf] Found \(favorites.count) favorites", category: .app)

            guard !favorites.isEmpty else {
                Logger.debug("[TopShelf] No favorites, returning nil", category: .app)
                return nil
            }

            // 2. 并行获取直播状态，带整体超时保护
            let liveStreamers = await fetchLiveStatusWithTimeout(favorites: favorites)

            guard !liveStreamers.isEmpty else {
                Logger.debug("[TopShelf] No live streamers, returning nil", category: .app)
                return nil
            }

            // 3. 生成 Top Shelf 内容
            return createTopShelfContent(from: liveStreamers)

        } catch {
            Logger.warning("[TopShelf] Error loading content: \(error)", category: .app)
            return nil
        }
    }

    /// 带超时保护的并行获取直播状态
    private func fetchLiveStatusWithTimeout(favorites: [LiveModel]) async -> [LiveModel] {
        await withTaskGroup(of: LiveModel?.self) { group in
            // 为每个收藏添加任务
            for favorite in favorites {
                group.addTask {
                    await self.fetchSingleLiveStatus(favorite: favorite)
                }
            }

            var liveStreamers: [LiveModel] = []

            // 收集结果
            for await result in group {
                if let streamer = result, streamer.liveState == "1" {
                    liveStreamers.append(streamer)
                }
            }

            return liveStreamers
        }
    }

    /// 获取单个主播的直播状态
    private func fetchSingleLiveStatus(favorite: LiveModel) async -> LiveModel? {
        do {
            // 带单个请求超时
            return try await withThrowingTaskGroup(of: LiveModel.self) { group in
                group.addTask {
                    try await ApiManager.fetchLastestLiveInfo(liveModel: favorite)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.singleRequestTimeout * 1_000_000_000))
                    throw CancellationError()
                }

                guard let result = try await group.next() else {
                    throw CancellationError()
                }

                group.cancelAll()
                return result
            }
        } catch {
            Logger.warning("[TopShelf] Failed to fetch status for \(favorite.userName): \(error)", category: .app)
            return nil
        }
    }

    /// FullUI 快照只包含标题、图片和跳转地址，不在扩展中初始化插件或云同步。
    private func createTopShelfContent(from snapshot: TopShelfSnapshot) -> TVTopShelfSectionedContent? {
        guard !snapshot.items.isEmpty else { return nil }
        let items = snapshot.items.map { entry in
            let item = TVTopShelfSectionedItem(identifier: entry.identifier)
            item.imageShape = .hdtv
            item.title = entry.title
            if let imageURL = entry.imageURL {
                item.setImageURL(imageURL, for: .screenScale1x)
                item.setImageURL(imageURL, for: .screenScale2x)
            }
            item.displayAction = TVTopShelfAction(url: entry.actionURL)
            item.playAction = TVTopShelfAction(url: entry.actionURL)
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "正在直播"
        return TVTopShelfSectionedContent(sections: [section])
    }

    /// 创建 Top Shelf 内容
    private func createTopShelfContent(from streamers: [LiveModel]) -> TVTopShelfSectionedContent {
        let items = streamers.compactMap { streamer -> TVTopShelfSectionedItem? in
            // 创建 item identifier
            let identifier = "\(streamer.liveType.rawValue)_\(streamer.roomId)"
            let item = TVTopShelfSectionedItem(identifier: identifier)

            // 设置图片为 16:9 宽屏比例，与房间列表卡片一致
            item.imageShape = .hdtv

            // 设置标题
            item.title = streamer.roomTitle + " - " + streamer.userName

            // 设置封面图片
            if let coverURL = URL(string: streamer.roomCover) {
                item.setImageURL(coverURL, for: .screenScale1x)
                item.setImageURL(coverURL, for: .screenScale2x)
            } else if let headURL = URL(string: streamer.userHeadImg) {
                item.setImageURL(headURL, for: .screenScale1x)
                item.setImageURL(headURL, for: .screenScale2x)
            }

            // 设置 Deep Link
            // URL 格式: simplelive://room/{platform}/{roomId}?userId={userId}
            var urlComponents = URLComponents()
            urlComponents.scheme = "simplelive"
            urlComponents.host = "room"
            urlComponents.path = "/\(streamer.liveType.rawValue)/\(streamer.roomId)"
            if !streamer.userId.isEmpty {
                urlComponents.queryItems = [URLQueryItem(name: "userId", value: streamer.userId)]
            }

            if let url = urlComponents.url {
                item.displayAction = TVTopShelfAction(url: url)
                item.playAction = TVTopShelfAction(url: url)
            }

            return item
        }

        // 创建 section
        let section = TVTopShelfItemCollection(items: items)
        section.title = "正在直播"

        return TVTopShelfSectionedContent(sections: [section])
    }
}
