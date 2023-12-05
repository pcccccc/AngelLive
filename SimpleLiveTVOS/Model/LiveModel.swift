//
//  LiveModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/8.
//

import Foundation
import Alamofire
import CloudKit

public struct LiveModel: Codable {
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
                case 2:
                    liveState = "已下播"
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

    func getPlayArgs() async throws -> String? {
        if liveType == .bilibili {
            do {
                let quality = try await Bilibili.getVideoQualites(roomModel:self)
                if quality.code == 0 {
                    if let qualityDescription = quality.data.quality_description {
                        var maxQn = 0
                        for item in qualityDescription {
                            if item.qn > maxQn {
                                maxQn = item.qn
                            }
                        }
                        let playInfo = try await Bilibili.getPlayUrl(roomId: roomId, qn: maxQn)
                        for streamInfo in playInfo.data.playurl_info.playurl.stream {
                            if streamInfo.protocol_name == "http_hls" {
                                let url = (streamInfo.format.last?.codec.last?.url_info.last?.host ?? "") + (streamInfo.format.last?.codec.last?.base_url ?? "") + (streamInfo.format.last?.codec.last?.url_info.last?.extra ?? "")
                                return url
                            }
                        }
                        for streamInfo in playInfo.data.playurl_info.playurl.stream {
                            if streamInfo.protocol_name == "http_stream" {
                                let url = (streamInfo.format.first?.codec.first?.url_info.first?.host ?? "") + (streamInfo.format.first?.codec.first?.base_url ?? "") + (streamInfo.format.first?.codec.first?.url_info.first?.extra ?? "")
                                return url
                            }
                        }
                    }
                }
                return nil
            }catch {
                return nil
            }
        }else if liveType == .douyin {
            do {
                let liveData = try await Douyin.getDouyinRoomDetail(streamerData: self)
                if liveData.data?.data?.count ?? 0 > 0 {
                    let FULL_HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.FULL_HD1 ?? ""
                    let HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.HD1 ?? ""
                    let SD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD1 ?? ""
                    let SD2 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD2 ?? ""
                    var url = ""
                    if FULL_HD1.count > 0 {
                        url = FULL_HD1
                    }else if HD1.count > 0 {
                        url = HD1
                    }else if SD1.count > 0 {
                        url = SD1
                    }else if SD2.count > 0 {
                        url = SD2
                    }else {
                        url = ""
                    }
                    return url
                }
                return nil
            }catch {
                return nil
            }
        }else if liveType == .douyu {
            do {
                let dataReq = try await Douyu.getPlayArgs(rid: roomId)
                return "\(dataReq.data?.rtmp_url ?? "")/\(dataReq.data?.rtmp_live ?? "")"
            }catch {
                return nil
            }
        }else if liveType == .huya {
            do {
                let liveData = try await Huya.getPlayArgs(rid: self.roomId)
                if liveData != nil {
                    let streamInfo = liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first
                    var playQualitiesInfo: Dictionary<String, String> = [:]
                    if let urlComponent = URLComponents(string: "?\(streamInfo?.sFlvAntiCode ?? "")") {
                        if let queryItems = urlComponent.queryItems {
                            for item in queryItems {
                                playQualitiesInfo.updateValue(item.value ?? "", forKey: item.name)
                            }
                        }
                    }
                    playQualitiesInfo.updateValue("1", forKey: "ver")
                    playQualitiesInfo.updateValue("2110211124", forKey: "sv")
                    let uid = try await Huya.getAnonymousUid()
                    let now = Int(Date().timeIntervalSince1970) * 1000
                    playQualitiesInfo.updateValue("\((Int(uid) ?? 0) + Int(now))", forKey: "seqid")
                    playQualitiesInfo.updateValue(uid, forKey: "uid")
                    playQualitiesInfo.updateValue(Huya.getUUID(), forKey: "uuid")
                    playQualitiesInfo.updateValue("100", forKey: "t")
                    playQualitiesInfo.updateValue("huya_live", forKey: "ctype")
                    let ss = "\(playQualitiesInfo["seqid"] ?? "")|\("huya_live")|\("100")".md5
                    let base64EncodedData = (playQualitiesInfo["fm"] ?? "").data(using: .utf8)!
                    if let data = Data(base64Encoded: base64EncodedData) {
                        let fm = String(data: data, encoding: .utf8)!
                        var nsFM = fm as NSString
                        nsFM = nsFM.replacingOccurrences(of: "$0", with: uid).replacingOccurrences(of: "$1", with: streamInfo?.sStreamName ?? "").replacingOccurrences(of: "$2", with: ss).replacingOccurrences(of: "$3", with: playQualitiesInfo["wsTime"] ?? "") as NSString
                        playQualitiesInfo.updateValue((nsFM as String).md5, forKey: "wsSecret")
                        playQualitiesInfo.removeValue(forKey: "fm")
                        playQualitiesInfo.removeValue(forKey: "txyp")
                        var playInfo: Array<URLQueryItem> = []
                        for key in playQualitiesInfo.keys {
                            let value = playQualitiesInfo[key] ?? ""
                            playInfo.append(.init(name: key, value: value))
                        }
                        var urlComps = URLComponents(string: "")!
                        urlComps.queryItems = playInfo
                        let result = urlComps.url!
                        var res = result.absoluteString as NSString

                        var url = ""
                        var maxRate = 0
                        for streamInfo in liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value ?? [] {
                            if maxRate < streamInfo.iMobilePriorityRate {
                                maxRate = streamInfo.iMobilePriorityRate
                                url = "\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)"
                            }
                        }
                        return url
                    }
                }
                
            }catch {
                return nil
            }
        }
        return nil
    }
    
    func getPlayArgsV2() async throws -> Array<LiveQuality> {
        var liveQualtys: Array<LiveQuality> = []
        if liveType == .bilibili {
            do {
                let quality = try await Bilibili.getVideoQualites(roomModel:self)
                if quality.code == 0 {
                    if let qualityDescription = quality.data.quality_description {
                        for item in qualityDescription {
                            liveQualtys.append(.init(roomId: self.roomId, title: item.desc, qn: item.qn, liveType: .bilibili))
                        }
                    }
                }
                return liveQualtys
            }catch {
                return liveQualtys
            }
        }else if liveType == .douyu {
            do {
                let dataReq = try await Douyu.getPlayArgs(rid: roomId)
                if let data = dataReq.data {
                    for item in data.multirates {
                        liveQualtys.append(.init(roomId: self.roomId, title: item.name, qn: item.rate, liveType: .douyu))
                    }
                }
                return liveQualtys
            }catch {
                return liveQualtys
            }
        }else if liveType == .huya {
            do {
                let liveData = try await Huya.getPlayArgs(rid: self.roomId)
                if liveData != nil {
                    let streamInfo = liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first
                    var playQualitiesInfo: Dictionary<String, String> = [:]
                    if let urlComponent = URLComponents(string: "?\(streamInfo?.sFlvAntiCode ?? "")") {
                        if let queryItems = urlComponent.queryItems {
                            for item in queryItems {
                                playQualitiesInfo.updateValue(item.value ?? "", forKey: item.name)
                            }
                        }
                    }
                    playQualitiesInfo.updateValue("1", forKey: "ver")
                    playQualitiesInfo.updateValue("2110211124", forKey: "sv")
                    let uid = try await Huya.getAnonymousUid()
                    let now = Int(Date().timeIntervalSince1970) * 1000
                    playQualitiesInfo.updateValue("\((Int(uid) ?? 0) + Int(now))", forKey: "seqid")
                    playQualitiesInfo.updateValue(uid, forKey: "uid")
                    playQualitiesInfo.updateValue(Huya.getUUID(), forKey: "uuid")
                    playQualitiesInfo.updateValue("100", forKey: "t")
                    playQualitiesInfo.updateValue("huya_live", forKey: "ctype")
                    let ss = "\(playQualitiesInfo["seqid"] ?? "")|\("huya_live")|\("100")".md5
                    let base64EncodedData = (playQualitiesInfo["fm"] ?? "").data(using: .utf8)!
                    if let data = Data(base64Encoded: base64EncodedData) {
                        let fm = String(data: data, encoding: .utf8)!
                        var nsFM = fm as NSString
                        nsFM = nsFM.replacingOccurrences(of: "$0", with: uid).replacingOccurrences(of: "$1", with: streamInfo?.sStreamName ?? "").replacingOccurrences(of: "$2", with: ss).replacingOccurrences(of: "$3", with: playQualitiesInfo["wsTime"] ?? "") as NSString
                        playQualitiesInfo.updateValue((nsFM as String).md5, forKey: "wsSecret")
                        playQualitiesInfo.removeValue(forKey: "fm")
                        playQualitiesInfo.removeValue(forKey: "txyp")
                        var playInfo: Array<URLQueryItem> = []
                        for key in playQualitiesInfo.keys {
                            let value = playQualitiesInfo[key] ?? ""
                            playInfo.append(.init(name: key, value: value))
                        }
                        var urlComps = URLComponents(string: "")!
                        urlComps.queryItems = playInfo
                        let result = urlComps.url!
                        var res = result.absoluteString as NSString
                        var url = ""
                        var maxRate = 0
                        for streamInfo in liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value ?? [] {
                            if maxRate < streamInfo.iMobilePriorityRate {
                                maxRate = streamInfo.iMobilePriorityRate
                                url = "\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)"
                            }
                        }
                        let bitRateInfoArray  = liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vBitRateInfo.value ?? []
                        for index in 0 ..< bitRateInfoArray.count {
                            let bitRateInfo = bitRateInfoArray[index]
                            liveQualtys.append(.init(roomId: self.roomId, title: "线路\(index + 1)", qn: bitRateInfo.iBitRate, liveType: .huya))
                        }
                        return liveQualtys
                    }
                }
                
            }catch {
                return liveQualtys
            }
        }else if (liveType == .douyin) {
            do {
                let liveData = try await Douyin.getDouyinRoomDetail(streamerData: self)
                if liveData.data?.data?.count ?? 0 > 0 {
                    let FULL_HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.FULL_HD1 ?? ""
                    let HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.HD1 ?? ""
                    let SD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD1 ?? ""
                    let SD2 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD2 ?? ""
                    var url = ""
                    if FULL_HD1.count > 0 {
                        liveQualtys.append(.init(roomId: self.roomId, title: "超清", qn: 0, liveType: .douyin))
                    }else if HD1.count > 0 {
                        liveQualtys.append(.init(roomId: self.roomId, title: "高清", qn: 0, liveType: .douyin))
                    }else if SD1.count > 0 {
                        liveQualtys.append(.init(roomId: self.roomId, title: "标清1", qn: 0, liveType: .douyin))
                    }else if SD2.count > 0 {
                        liveQualtys.append(.init(roomId: self.roomId, title: "标清2", qn: 0, liveType: .douyin))
                    }
                    return liveQualtys
                }
                return liveQualtys
            }catch {
                return liveQualtys
            }
        }
        return liveQualtys
        
    }
}

struct LiveQuality {
    var roomId: String
    var title: String
    var qn: Int //bilibili用qn请求地址
    var liveType: LiveType
    
    func getPlayURL() async throws -> String?  {
        let playInfo = try await Bilibili.getPlayUrl(roomId: roomId, qn: qn)
        var urls:Array<String> = []
        for streamInfo in playInfo.data.playurl_info.playurl.stream {
            if streamInfo.protocol_name == "http_hls" {
                let url = (streamInfo.format.last?.codec.last?.url_info.last?.host ?? "") + (streamInfo.format.last?.codec.last?.base_url ?? "") + (streamInfo.format.last?.codec.last?.url_info.last?.extra ?? "")
                urls.append(url)
            }
        }
        return urls.first
    }
}
