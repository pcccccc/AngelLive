//
//  ApiManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/29.
//

import Foundation
import LiveParse
import Alamofire

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
            case .yy:
                return try await YY.getLiveState(roomId: roomId, userId: userId)
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
            case .yy:
                return try await YY.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
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
            case .yy:
                return try await YY.getCategoryList()
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
            case .yy:
                return try await YY.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .youtube:
                return try await YoutubeParse.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
        }
    }

    /**
     获取用户是否可以访问google。
     
     - Returns: 是否
    */
    class func checkInternetConnection() async -> Bool {
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let resp = response as? HTTPURLResponse else {
                return false
            }
            if resp.statusCode == 200 {
                return true
            }else {
                return false
            }
        }catch {
            return false
        }
    }
}
