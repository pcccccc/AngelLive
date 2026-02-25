import Foundation
import Cache
import LiveParse

public enum LiveService {

    public static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        let diskConfig = DiskConfig(name: "Simple_Live_TV")
        let memoryConfig = MemoryConfig(expiry: .never, countLimit: 50, totalCostLimit: 50)
        let storage: Storage<String, [LiveMainListModel]> = try Storage<String, [LiveMainListModel]>(
          diskConfig: diskConfig,
          memoryConfig: memoryConfig,
          fileManager: .default,
          transformer: TransformerFactory.forCodable(ofType: [LiveMainListModel].self)
        )

        var categories: [LiveMainListModel] = []
        var hasKsCache = false
        if liveType == .ks {
            do {
                categories = try storage.object(forKey: "ks_categories")
                hasKsCache = true
            } catch {
                categories = []
            }
        }

        if categories.isEmpty && hasKsCache == false {
            categories = try await ApiManager.fetchCategoryList(liveType: liveType)
        }

        if liveType == .ks && hasKsCache == false {
            try storage.setObject(categories, forKey: "ks_categories")
        }

        return categories
    }

    public static func fetchRoomList(liveType: LiveType, category: LiveCategoryModel, parentBiz: String?, page: Int) async throws -> [LiveModel] {
        var finalCategory = category
        if liveType == .yy {
            finalCategory.id = parentBiz ?? ""
            finalCategory.parentId = category.biz ?? ""
        }
        let roomList = try await ApiManager.fetchRoomList(liveCategory: finalCategory, page: page, liveType: liveType)
        return roomList
    }

    /// 并行搜索所有平台的直播间
    public static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        await withTaskGroup(of: [LiveModel].self) { group in
            for platform in LiveParseJSPlatformManager.availablePlatforms {
                group.addTask {
                    do {
                        return try await LiveParseJSPlatformManager.searchRooms(platform: platform, keyword: keyword, page: page)
                    } catch {
                        print("⚠️ \(platform.displayName) 搜索失败: \(error)")
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

    public static func searchRoomWithShareCode(shareCode: String) async throws -> LiveModel? {
        return try await ApiManager.fetchSearchWithShareCode(shareCode: shareCode)
    }

    public static func fetchCurrentRoomLiveState(roomId: String, userId: String, liveType: LiveType) async throws -> LiveState {
        return try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
    }
}
