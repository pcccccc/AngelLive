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
    
    public static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        var resArray: [LiveModel] = []

        // Bilibili 搜索
        do {
            let bilibiliResList = try await Bilibili.searchRooms(keyword: keyword, page: page)
            resArray.append(contentsOf: bilibiliResList)
        } catch {
            print("⚠️ Bilibili 搜索失败: \(error)")
        }

        // 抖音搜索
        do {
            let douyinResList = try await Douyin.searchRooms(keyword: keyword, page: page)
            var finalDouyinResList: [LiveModel] = []
            for room in douyinResList {
                do {
                    let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    finalDouyinResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
                } catch {
                    print("⚠️ 抖音获取直播状态失败: \(room.roomId)")
                }
            }
            resArray.append(contentsOf: finalDouyinResList)
        } catch {
            print("⚠️ 抖音搜索失败: \(error)")
        }

        // 虎牙搜索
        do {
            let huyaResList = try await Huya.searchRooms(keyword: keyword, page: page)
            resArray.append(contentsOf: huyaResList)
        } catch {
            print("⚠️ 虎牙搜索失败: \(error)")
        }

        // 斗鱼搜索
        do {
            let douyuResList = try await Douyu.searchRooms(keyword: keyword, page: page)
            var finalDouyuResList: [LiveModel] = []
            for room in douyuResList {
                do {
                    let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    finalDouyuResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
                } catch {
                    print("⚠️ 斗鱼获取直播状态失败: \(room.roomId)")
                }
            }
            resArray.append(contentsOf: finalDouyuResList)
        } catch {
            print("⚠️ 斗鱼搜索失败: \(error)")
        }

        return resArray
    }
    
    public static func searchRoomWithShareCode(shareCode: String) async throws -> LiveModel? {
        return try await ApiManager.fetchSearchWithShareCode(shareCode: shareCode)
    }
    
    public static func fetchCurrentRoomLiveState(roomId: String, userId: String, liveType: LiveType) async throws -> LiveState {
        return try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
    }
}
