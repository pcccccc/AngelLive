
import Foundation
import LiveParse
import Cache
import LiveParse

class LiveService {
    
    static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
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
    
    static func fetchRoomList(liveType: LiveType, category: LiveCategoryModel, parentBiz: String?, page: Int) async throws -> [LiveModel] {
        var finalCategory = category
        if liveType == .yy {
            finalCategory.id = parentBiz ?? ""
            finalCategory.parentId = category.biz ?? ""
        }
        let roomList = try await ApiManager.fetchRoomList(liveCategory: finalCategory, page: page, liveType: liveType)
        return roomList
    }
    
    static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        let bilibiliResList = try await Bilibili.searchRooms(keyword: keyword, page: page)
        let douyinResList = try await Douyin.searchRooms(keyword: keyword, page: page)
        var finalDouyinResList: [LiveModel] = []
        for room in douyinResList {
            let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            finalDouyinResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
        }
        let huyaResList = try await Huya.searchRooms(keyword: keyword, page: page)
        let douyuResList = try await Douyu.searchRooms(keyword: keyword, page: page)
        var finalDouyuResList: [LiveModel] = []
        for room in douyuResList {
            let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            finalDouyuResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
        }
        var resArray: [LiveModel] = []
        resArray.append(contentsOf: bilibiliResList)
        resArray.append(contentsOf: finalDouyinResList)
        resArray.append(contentsOf: huyaResList)
        resArray.append(contentsOf: finalDouyuResList)
        return resArray
    }
    
    static func searchRoomWithShareCode(shareCode: String) async throws -> LiveModel? {
        return try await ApiManager.fetchSearchWithShareCode(shareCode: shareCode)
    }
    
    static func fetchCurrentRoomLiveState(roomId: String, userId: String, liveType: LiveType) async throws -> LiveState {
        return try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
    }
}
