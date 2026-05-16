//
//  ContentProvider.swift
//  TopShelfExtension
//
//  Created by pangchong on 12/12/25.
//

import TVServices
import AngelLiveCore

class ContentProvider: TVTopShelfContentProvider {

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
            print("[TopShelf] App Group container not available.")
            return
        }

        let sourcePluginsDir = containerURL
            .appendingPathComponent("LiveParse", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        let sourceState = containerURL
            .appendingPathComponent("LiveParse", isDirectory: true)
            .appendingPathComponent("state.json")

        guard fm.fileExists(atPath: sourcePluginsDir.path) else {
            print("[TopShelf] No plugins in App Group container.")
            return
        }

        // 复制到 LiveParsePlugins.shared.storage 实际使用的目录
        let destLiveParseDir = LiveParsePlugins.shared.storage.baseDirectory
        let destPluginsDir = destLiveParseDir.appendingPathComponent("plugins", isDirectory: true)
        let destState = destLiveParseDir.appendingPathComponent("state.json")

        print("[TopShelf] Syncing plugins to: \(destLiveParseDir.path)")

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

            print("[TopShelf] Synced plugins from App Group to local Caches.")
        } catch {
            print("[TopShelf] Failed to sync plugins: \(error)")
        }
    }

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        print("[TopShelf] loadTopShelfContent() called")

        // 打印 App Group 插件目录内容
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            let pluginsDir = container.appendingPathComponent("LiveParse/plugins", isDirectory: true)
            print("[TopShelf] App Group plugins dir: \(pluginsDir.path)")
            print("[TopShelf] Exists: \(fm.fileExists(atPath: pluginsDir.path))")
            if let contents = try? fm.contentsOfDirectory(atPath: pluginsDir.path) {
                print("[TopShelf] Plugin count: \(contents.count)")
                print("[TopShelf] Plugins: \(contents)")
            }
        }

        // 从 App Group 同步插件到本地 Caches，供 LiveParsePlugins.shared 使用
        syncPluginsFromAppGroup()

        // 同步完成后重新加载插件（LiveParsePlugins.shared 是 static let，首次访问时 Caches 还为空）
        try? LiveParsePlugins.shared.reload()

        do {
            // 1. 从 CloudKit 读取收藏列表
            print("[TopShelf] Fetching favorites from CloudKit...")
            let favorites = try await FavoriteService.searchRecord()
            print("[TopShelf] Found \(favorites.count) favorites")

            guard !favorites.isEmpty else {
                print("[TopShelf] No favorites, returning nil")
                return nil
            }

            // 2. 并行获取直播状态，带整体超时保护
            let liveStreamers = await fetchLiveStatusWithTimeout(favorites: favorites)

            guard !liveStreamers.isEmpty else {
                print("[TopShelf] No live streamers, returning nil")
                return nil
            }

            // 3. 生成 Top Shelf 内容
            return createTopShelfContent(from: liveStreamers)

        } catch {
            print("[TopShelf] Error loading content: \(error)")
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
            print("[TopShelf] Failed to fetch status for \(favorite.userName): \(error)")
            return nil
        }
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
            if let coverURL = URL(string: streamer.displayRoomCover) {
                item.setImageURL(coverURL, for: .screenScale1x)
                item.setImageURL(coverURL, for: .screenScale2x)
            } else if let headURL = URL(string: streamer.displayUserHeadImg) {
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
