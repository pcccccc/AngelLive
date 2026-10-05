import Foundation
import Cache

public enum LiveService {

    public static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            return []
        }

        // Token plugins own credential-scoped caches and authorization checks.
        // A host disk cache hit must never bypass those checks.
        if await PlatformAPITokenVault.shared.isEnabled,
           (try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId).manifest.auth?.credentialKinds?.contains(where: { ["token", "client_credentials", "oauth_device_code"].contains($0) })) == true {
            return try await ApiManager.fetchCategoryList(liveType: liveType)
        }

        let diskConfig = DiskConfig(name: "Simple_Live_TV")
        let memoryConfig = MemoryConfig(expiry: .never, countLimit: 50, totalCostLimit: 50)
        let storage: Storage<String, [LiveMainListModel]> = try Storage<String, [LiveMainListModel]>(
          diskConfig: diskConfig,
          memoryConfig: memoryConfig,
          fileManager: .default,
          transformer: TransformerFactory.forCodable(ofType: [LiveMainListModel].self)
        )

        let version = SandboxPluginCatalog.installedPluginMap()[platform.pluginId]?.version ?? "unknown"
        let cacheKey = "categories_\(platform.pluginId)_\(version)_\(liveType.rawValue)"

        if let categories = try? storage.object(forKey: cacheKey), !categories.isEmpty {
            return categories
        }

        let categories = try await ApiManager.fetchCategoryList(liveType: liveType)

        if !categories.isEmpty {
            try storage.setObject(categories, forKey: cacheKey)
        }

        return categories
    }

    public static func fetchRoomList(liveType: LiveType, category: LiveCategoryModel, parentBiz: String?, page: Int) async throws -> [LiveModel] {
        var context: [String: Any] = [
            "category": [
                "id": category.id,
                "parentId": category.parentId,
                "title": category.title,
                "icon": category.icon,
                "biz": category.biz ?? ""
            ]
        ]
        if let parentBiz {
            context["parentBiz"] = parentBiz
        }

        let roomList = try await ApiManager.fetchRoomList(
            liveCategory: category,
            page: page,
            liveType: liveType,
            context: context
        )
        return roomList
    }

    /// 并行搜索所有平台的直播间
    public static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        await withTaskGroup(of: [LiveModel].self) { group in
            for platform in SandboxPluginCatalog.availablePlatforms() {
                group.addTask {
                    do {
                        return try await LiveParseJSPlatformManager.searchRooms(platform: platform, keyword: keyword, page: page)
                    } catch {
                        Logger.warning("\(platform.displayName) 搜索失败: \(error)", category: .network)
                        return []
                    }
                }
            }

            var allResults: [LiveModel] = []
            for await platformResults in group {
                allResults.append(contentsOf: platformResults)
            }
            return allResults
        }
    }

    /// FullUI opt-in search that preserves host-trusted authentication owners
    /// without changing the legacy aggregate search contract.
    public static func searchRoomsWithOutcome(keyword: String, page: Int) async throws -> RoomSearchOutcome {
        try await searchRoomsWithOutcome(
            platforms: SandboxPluginCatalog.availablePlatforms(),
            keyword: keyword,
            page: page
        ) { platform, keyword, page in
            try await LiveParseJSPlatformManager.searchRooms(
                platform: platform,
                keyword: keyword,
                page: page
            )
        }
    }

    static func searchRoomsWithOutcome(
        platforms: [LiveParseJSPlatform],
        keyword: String,
        page: Int,
        fetch: @escaping @Sendable (LiveParseJSPlatform, String, Int) async throws -> [LiveModel]
    ) async throws -> RoomSearchOutcome {
        try await withThrowingTaskGroup(
            of: (pluginID: String, rooms: [LiveModel], authenticationRequired: Bool).self
        ) { group in
            for platform in platforms {
                group.addTask {
                    do {
                        return (platform.pluginId, try await fetch(platform, keyword, page), false)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try Task.checkCancellation()
                        Logger.warning("\(platform.displayName) 搜索失败: \(error)", category: .network)
                        return (platform.pluginId, [], error.showsLoginAction)
                    }
                }
            }

            var rooms: [LiveModel] = []
            var authenticationRequiredPluginIDs = Set<String>()
            for try await result in group {
                rooms.append(contentsOf: result.rooms)
                if result.authenticationRequired {
                    authenticationRequiredPluginIDs.insert(result.pluginID)
                }
            }
            return RoomSearchOutcome(
                rooms: rooms,
                authenticationRequiredPluginIDs: platforms.map(\.pluginId).filter(authenticationRequiredPluginIDs.contains)
            )
        }
    }

    public static func searchRoomWithShareCode(shareCode: String) async throws -> LiveModel? {
        return try await ApiManager.fetchSearchWithShareCode(shareCode: shareCode)
    }

    public static func searchRoomWithShareCodeWithOutcome(shareCode: String) async throws -> RoomSearchOutcome {
        try await ApiManager.fetchSearchWithShareCodeOutcome(shareCode: shareCode)
    }

    public static func fetchCurrentRoomLiveState(roomId: String, userId: String, liveType: LiveType) async throws -> LiveState {
        return try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
    }
}
