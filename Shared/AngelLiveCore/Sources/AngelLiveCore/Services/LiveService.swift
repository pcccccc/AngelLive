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
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - page: 页码
    /// - Returns: 合并后的搜索结果
    public static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        // 使用 TaskGroup 并行搜索所有平台，显著提升搜索速度
        await withTaskGroup(of: [LiveModel].self) { group in
            // Bilibili 搜索
            group.addTask {
                do {
                    return try await Bilibili.searchRooms(keyword: keyword, page: page)
                } catch {
                    print("⚠️ Bilibili 搜索失败: \(error)")
                    return []
                }
            }
            
            // 虎牙搜索
            group.addTask {
                do {
                    return try await Huya.searchRooms(keyword: keyword, page: page)
                } catch {
                    print("⚠️ 虎牙搜索失败: \(error)")
                    return []
                }
            }
            
            // 抖音搜索（需要额外获取直播状态）
            group.addTask {
                do {
                    let douyinResList = try await Douyin.searchRooms(keyword: keyword, page: page)
                    // 并行获取所有房间的直播状态
                    return await withTaskGroup(of: LiveModel?.self) { stateGroup in
                        for room in douyinResList {
                            stateGroup.addTask {
                                do {
                                    let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                                    return LiveModel(
                                        userName: room.userName,
                                        roomTitle: room.roomTitle,
                                        roomCover: room.roomCover,
                                        userHeadImg: room.userHeadImg,
                                        liveType: room.liveType,
                                        liveState: liveState,
                                        userId: room.userId,
                                        roomId: room.roomId,
                                        liveWatchedCount: room.liveWatchedCount
                                    )
                                } catch {
                                    print("⚠️ 抖音获取直播状态失败: \(room.roomId)")
                                    return nil
                                }
                            }
                        }
                        var results: [LiveModel] = []
                        for await room in stateGroup {
                            if let room = room {
                                results.append(room)
                            }
                        }
                        return results
                    }
                } catch {
                    print("⚠️ 抖音搜索失败: \(error)")
                    return []
                }
            }
            
            // 斗鱼搜索（需要额外获取直播状态）
            group.addTask {
                do {
                    let douyuResList = try await Douyu.searchRooms(keyword: keyword, page: page)
                    // 并行获取所有房间的直播状态
                    return await withTaskGroup(of: LiveModel?.self) { stateGroup in
                        for room in douyuResList {
                            stateGroup.addTask {
                                do {
                                    let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                                    return LiveModel(
                                        userName: room.userName,
                                        roomTitle: room.roomTitle,
                                        roomCover: room.roomCover,
                                        userHeadImg: room.userHeadImg,
                                        liveType: room.liveType,
                                        liveState: liveState,
                                        userId: room.userId,
                                        roomId: room.roomId,
                                        liveWatchedCount: room.liveWatchedCount
                                    )
                                } catch {
                                    print("⚠️ 斗鱼获取直播状态失败: \(room.roomId)")
                                    return nil
                                }
                            }
                        }
                        var results: [LiveModel] = []
                        for await room in stateGroup {
                            if let room = room {
                                results.append(room)
                            }
                        }
                        return results
                    }
                } catch {
                    print("⚠️ 斗鱼搜索失败: \(error)")
                    return []
                }
            }
            
            // 收集所有平台的结果
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
