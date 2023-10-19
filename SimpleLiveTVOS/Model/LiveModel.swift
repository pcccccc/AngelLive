//
//  LiveModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/8.
//

import Foundation
import Alamofire
import CloudKit

struct LiveModel: Codable {
    let userName: String
    let roomTitle: String
    let roomCover: String
    let userHeadImg: String
    let liveType: LiveType
    var liveState: String?
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
    
    mutating func getLiveState() async throws {
        if liveType == .bilibili { //1 正在直播 0 已下播
            let liveStatus = try await Bilibili.getLiveStatus(roomId: roomId)
            switch liveStatus {
                case 0:
                    liveState = "已下播"
                case 1:
                    liveState = "正在直播"
                default:
                    liveState = "获取状态失败"
            }
        }else if liveType == .douyin {
            do {
                let dataReq = try await Douyin.getDouyinRoomDetail(streamerData: self)
                switch dataReq.data?.data?.first?.status {
                    case 4:
                        liveState = "已下播"
                    case 2:
                        liveState = "正在直播"
                    default:
                        liveState = "获取状态失败"
                }
            }catch {
                print(error)
            }
        }else if liveType == .douyu {
            let liveStatus = try await Douyu.getLiveStatus(rid: roomId)
            switch liveStatus {
                case 0:
                    liveState = "已下播"
                case 1:
                    liveState = "正在直播"
                case 2:
                    liveState = "视频录播"
                default:
                    liveState = "获取状态失败"
            }
        }else if liveType == .huya {
            let liveStatus = try await Huya.getPlayArgs(rid: roomId)?.roomInfo.eLiveStatus
            switch liveStatus {
                case 2:
                    liveState = "正在直播"
                default:
                    liveState = "已下播"
            }
        }
    }
}

struct LiveQuality {
    var title: String
    var url: String
    var qn: Int //bilibili用qn请求地址
}
