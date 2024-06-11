//
//  ApiManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/29.
//

import Foundation
import LiveParse

class ApiManager {
    /**
     获取当前房间直播状态。
     
     - Returns: 直播状态
    */
    class func getCurrentRoomLiveState(roomId: String, userId: String?, liveType: LiveType) async throws -> LiveState {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getLiveState(roomId: roomId, userId: nil)
            case .huya:
                return try await Huya.getLiveState(roomId: roomId, userId: nil)
            case .douyin:
                return try await Douyin.getLiveState(roomId: roomId, userId: userId)
            case .douyu:
                return try await Douyu.getLiveState(roomId: roomId, userId: nil)
            case .cc:
                return try await NeteaseCC.getLiveState(roomId: roomId, userId: userId)
            case .ks:
                return try await KuaiShou.getLiveState(roomId: roomId, userId: userId)
            default:
                return .unknow
        }
    }

    class func fetchRoomList(liveCategory: LiveCategoryModel, page: Int, liveType: LiveType) async throws -> [LiveModel] {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .huya:
                return try await Huya.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .douyin:
                return try await Douyin.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .douyu:
                return try await Douyu.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .cc:
                return try await NeteaseCC.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .ks:
                return try await KuaiShou.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            default:
                return []
        }
    }

    class func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getCategoryList()
            case .huya:
                return try await Huya.getCategoryList()
            case .douyin:
                return try await Douyin.getCategoryList()
            case .douyu:
                return try await Douyu.getCategoryList()
            case .cc:
                return try await NeteaseCC.getCategoryList()
            case .ks:
                return try await KuaiShou.getCategoryList()
            default:
                return []
        }
    }
    
    class func fetchLastestLiveInfo(liveModel: LiveModel) async throws -> LiveModel {
        switch liveModel.liveType {
            case .bilibili:
                return try await Bilibili.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .huya:
                return try await Huya.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .douyin:
                return try await Douyin.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .douyu:
                return try await Douyu.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .cc:
                return try await NeteaseCC.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .ks:
                return try await KuaiShou.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            default:
                return try await Bilibili.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
        }
    }

}
