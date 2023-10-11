//
//  LiveModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/8.
//

import Foundation

struct LiveModel: Codable {
    let userName: String
    let roomTitle: String
    let roomCover: String
    let userHeadImg: String
    let liveType: LiveType
    let liveState: String?
    let userId: String //B站 userId 抖音id_str
    let roomId: String //B站 roomId 抖音web_rid
    
    init(userName: String, roomTitle: String, roomCover: String, userHeadImg: String, liveType: LiveType, liveState: String?, userId: String, roomId: String) {
        self.userName = userName
        self.roomTitle = roomTitle
        self.roomCover = roomCover
        self.userHeadImg = userHeadImg
        self.liveType = liveType
        self.liveState = liveState
        self.userId = userId
        self.roomId = roomId
    }

    
    var description: String {
        return "\(userName)-\(roomTitle)-\(roomCover)-\(userHeadImg)-\(liveType)-\(liveState ?? "")-\(userId)-\(roomId)"
    }
}

struct LiveQuality {
    var title: String
    var url: String
    var qn: Int //bilibili用qn请求地址
}
