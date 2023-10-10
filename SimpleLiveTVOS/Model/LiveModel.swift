//
//  LiveModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/8.
//

import Foundation

struct LiveModel {
    let userName: String
    let roomTitle: String
    let roomCover: String
    let userHeadImg: String
    let liveType: LiveType
    let liveState: String?
    
    let userId: String //B站 userId 抖音id_str
    let roomId: String //B站 roomId 抖音web_rid
}

struct LiveQuality {
    var title: String
    var url: String
    var qn: Int //bilibili用qn请求地址
}
