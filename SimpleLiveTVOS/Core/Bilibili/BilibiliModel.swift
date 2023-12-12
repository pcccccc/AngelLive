//
//  BilibiliModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/4.
//

import Foundation
import Alamofire

struct BiliBiliCookie {
    static let cookie = UserDefaults.standard.value(forKey: "BilibiliCookie") as? String ?? ""
}

struct BilibiliMainData<T: Codable>: Codable {
    var code: Int
    var msg: String
    var data: T
    
    enum CodingKeys: String, CodingKey {
        case code
        case msg = "message"
        case data
    }
}

struct BilibiliMainListModel: Codable {
    let id: Int
    let name: String
    let list: Array<BilibiliCategoryModel>?
}

struct BilibiliCategoryModel: Codable {
    let id: String
    let parent_id: String
    let old_area_id: String
    let name: String
    let act_id: String
    let pk_status: String
    let hot_status: Int
    let lock_status: String
    let pic: String
    let parent_name: String
    let area_type: Int
}


struct BiliBiliCategoryRoomMainModel: Codable {
    let banner: Array<BiliBiliCategoryBannerModel>?
    let list: Array<BiliBiliCategoryListModel>?
}

struct BiliBiliCategoryBannerModel: Codable {
    let id: Int
    let title: String
    let location: String
    let position: Int
    let pic: String
    let link: String
    let weight: Int
    let room_id: Int
    let up_id: Int
    let parent_area_id: Int
    let area_id: Int
    let live_status: Int
    let av_id: Int
    let is_ad: Bool
}

struct BiliBiliCategoryListModel: Codable {
    let roomid: Int
    let uid: Int
    let title: String?
    let uname: String
    let online: Int?
    let user_cover: String?
    let user_cover_flag: Int?
    let system_cover: String?
    let cover: String?
    let show_cover: String?
    let link: String?
    let face: String?
    let uface: String?
    let parent_id: Int?
    let parent_name: String?
    let area_id: Int?
    let area_name: String?
    let area_v2_parent_id: Int?
    let area_v2_parent_name: String?
    let area_v2_id: Int?
    let area_v2_name: String?
    let session_id: String?
    let group_id: Int?
    let show_callback: String?
    let click_callback: String?
    let live_status: Int?
    let attentions: Int?
    let cate_name: String?
//    let verify: BiliBiliVerifyModel?
//    let watched_show: BiliBiliWatchedShowModel?
}

struct BiliBiliVerifyModel: Codable {
    let role: Int?
    let desc: String?
    let type: Int?
}

struct BiliBiliWatchedShowModel: Codable {

    let the_switch: Bool?
    let num: Int?
    let text_small: String?
    let text_large: String?
    let icon: String?
    let icon_location: Int?
    let icon_web: String?
    
    private enum CodingKeys: String, CodingKey {
        case the_switch = "switch"
        case num
        case text_small
        case text_large
        case icon
        case icon_location
        case icon_web
    }
}


struct BiliBiliQualityModel: Codable {
    let current_qn: Int
    let quality_description: Array<BiliBiliQualityDetailModel>?
//    let durl: Array<BilibiliPlayInfoModel>?
}

struct BiliBiliQualityDetailModel: Codable {
    let qn: Int
    let desc: String
}


struct BiliBiliPlayURLInfoMain: Codable {
    var playurl_info: BiliBiliPlayURLPlayURLInfo
    
//    var room_id: Int
}

struct BiliBiliPlayURLPlayURLInfo: Codable {
    var playurl: BiliBiliPlayURLPlayURL
    var conf_json: String
}

struct BiliBiliPlayURLPlayURL: Codable {
    var stream: Array<BiliBiliPlayURLStreamInfo>
}

struct BiliBiliPlayURLStreamInfo: Codable {
    var protocol_name: String
    var format: Array<BiliBiliPlayURLFormatInfo>
}

struct BiliBiliPlayURLFormatInfo: Codable {
    var format_name: String
    var codec: Array<BiliBiliPlayURLCodeCInfo>
}


struct BiliBiliPlayURLCodeCInfo: Codable {
    var codec_name: String
    var base_url: String
    var url_info: Array<BilibiliPlayInfoModel>
}

struct BilibiliPlayInfoModel: Codable {
    let host: String
    let extra: String
}

struct BilibiliQRMainModel: Codable {
    let code: Int
    let message: String
    let ttl: Int
    let data: BilibiliQRMainData
}

struct BilibiliQRMainData: Codable {
    let url: String?
    let qrcode_key: String?
    let refresh_token: String?
    let timestamp: Int?
    let code: Int?
    let message: String?
}

struct BilibiliBuvidModel: Codable {
    let b_3: String
    let b_4: String
}

struct BilibiliDanmuModel: Codable {
    let group: String
    let business_id: Int
    let refresh_row_factor: Double
    let refresh_rate: Int
    let max_delay: Int
    let token: String
    let host_list: Array<BilibiliDanmuServerInfo>
}

struct BilibiliDanmuServerInfo: Codable {
    let host: String
    let port: Int
    let wss_port: Int
    let ws_port: Int
}

struct BilibiliSearchMainData: Codable {
    var code: Int
    var msg: String
    var data: BilibiliSearchResultData?
    
    enum CodingKeys: String, CodingKey {
        case code
        case msg = "message"
        case data
    }
}

struct BilibiliSearchResultData: Codable {
    let result: BilibiliSearchResultMain?
}

struct BilibiliSearchResultMain: Codable {
    let live_room: Array<BiliBiliCategoryListModel>?
    let live_user: Array<BiliBiliCategoryListModel>?
}

class Bilibili: LiveParse {
    static func getCategoryList() async throws -> [LiveMainListModel] {
        let dataReq = try await AF.request("https://api.live.bilibili.com/room/v1/Area/getList", method: .get).serializingDecodable(BilibiliMainData<[BilibiliMainListModel]>.self).value
        var tempArray: [LiveMainListModel] = []
        for item in dataReq.data {
            var subList: [LiveCategoryModel] = []
            guard let subCategoryList = item.list else {
                continue
            }
            for subItem in subCategoryList {
                subList.append(.init(id: subItem.id, parentId: subItem.parent_id, title: subItem.name, icon: subItem.pic))
            }
            tempArray.append(.init(id: "\(item.id)", title: item.name, icon: "", subList: subList))
        }
        return tempArray
    }
    
    static func getRoomList(id: String, parentId: String?, page: Int) async throws -> [LiveModel] {
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList",
            method: .get,
            parameters: [
                "platform": "web",
                "parent_area_id": parentId,
                "area_id": id,
                "sort_type": "",
                "page": page
            ],
            headers: [
            ]
        ).serializingDecodable(BilibiliMainData<BiliBiliCategoryRoomMainModel>.self).value
        if let listModelArray = dataReq.data.list {
            var tempArray: Array<LiveModel> = []
            for item in listModelArray {
                tempArray.append(LiveModel(userName: item.uname, roomTitle: item.title ?? "", roomCover: item.cover ?? "", userHeadImg: item.face ?? "", liveType: .bilibili, liveState: "", userId: "\(item.uid)", roomId: "\(item.roomid)"))
            }
            return tempArray
        }else {
            return []
        }
    }
    
    static func getPlayArgs(roomId: String, userId: String?) async throws -> [LiveQuality] {
        
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/room/v1/Room/playUrl",
            method: .get,
            parameters: [
                "platform": "web",
                "cid": roomId,
                "qn": ""
            ],
            headers: BiliBiliCookie.cookie == "" ? nil : [
                "cookie": BiliBiliCookie.cookie
            ]
        ).serializingDecodable(BilibiliMainData<BiliBiliQualityModel>.self).value
        var liveQualitys: [LiveQuality] = []
        if let qualityDescription = dataReq.data.quality_description {
            for item in qualityDescription {
//                    liveQualtys.append(.init(roomId: roomId, title: item.desc, qn: item.qn, liveType: .bilibili))
                let dataReq = try await AF.request(
                    "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
                    method: .get,
                    parameters: [
                        "platform": "web",
                        "room_id": roomId,
                        "qn": item.qn,
                        "protocol": "0,1",
                        "format": "0,2",
                        "codec": "0,1",
                        "mask": "0"
                    ],
                    headers: BiliBiliCookie.cookie == "" ? nil : [
                        "cookie": BiliBiliCookie.cookie
                    ]
                ).serializingDecodable(BilibiliMainData<BiliBiliPlayURLInfoMain>.self).value
                for streamInfo in dataReq.data.playurl_info.playurl.stream {
                    if streamInfo.protocol_name == "http_hls" {
                        let url = (streamInfo.format.last?.codec.last?.url_info.last?.host ?? "") + (streamInfo.format.last?.codec.last?.base_url ?? "") + (streamInfo.format.last?.codec.last?.url_info.last?.extra ?? "")
                        liveQualitys.append(.init(roomId: roomId, title: item.desc, qn: item.qn, url: url, liveCodeType: .hls, liveType: .bilibili))
                    }
                }
                for streamInfo in dataReq.data.playurl_info.playurl.stream {
                    if streamInfo.protocol_name == "http_stream" {
                        let url = (streamInfo.format.first?.codec.first?.url_info.first?.host ?? "") + (streamInfo.format.first?.codec.first?.base_url ?? "") + (streamInfo.format.first?.codec.first?.url_info.first?.extra ?? "")
                        liveQualitys.append(.init(roomId: roomId, title: item.desc, qn: item.qn, url: url, liveCodeType: .flv, liveType: .bilibili))
                    }
                }
                return liveQualitys
            }
        }
        return liveQualitys
    }
    
    static func getLiveLastestInfo(roomId: String, userId: String?) async throws -> LiveModel {
        return LiveModel(userName: "", roomTitle: "", roomCover: "", userHeadImg: "", liveType: .bilibili, liveState: "", userId: "", roomId: "")
    }
    
    static func getLiveState(roomId: String, userId: String?) async throws -> LiveState {
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            method: .get,
            parameters: [
                "room_id": roomId
            ],
            headers: BiliBiliCookie.cookie == "" ? nil : [
                "cookie": BiliBiliCookie.cookie
            ]
        ).serializingData().value
        let json = try JSONSerialization.jsonObject(with: dataReq, options: .mutableContainers)
        let jsonDict = json as! Dictionary<String, Any>
        let dataDict = jsonDict["data"] as! Dictionary<String, Any>
        let liveStatus = dataDict["live_status"] as? Int ?? -1
        switch liveStatus {
            case 0:
                return .close
            case 1:
                return .live
            case 2:
                return .close
            default:
                return .unknow
        }
    }
    
    
    
    
    
    
    public class func getBiliBiliList() async throws -> BilibiliMainData<[BilibiliMainListModel]> {
        return try await AF.request("https://api.live.bilibili.com/room/v1/Area/getList", method: .get).serializingDecodable(BilibiliMainData.self).value
    }
    
    public class func getCategoryRooms(category: BilibiliCategoryModel, page: Int) async throws -> Array<LiveModel> {
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList",
            method: .get,
            parameters: [
                "platform": "web",
                "parent_area_id": category.parent_id,
                "area_id": category.id,
                "sort_type": "",
                "page": page
            ],
            headers: [
            ]
        ).serializingDecodable(BilibiliMainData<BiliBiliCategoryRoomMainModel>.self).value
        if dataReq.code == 0 {
            if let listModelArray = dataReq.data.list {
                var tempArray: Array<LiveModel> = []
                for item in listModelArray {
                    tempArray.append(LiveModel(userName: item.uname, roomTitle: item.title ?? "", roomCover: item.cover ?? "", userHeadImg: item.face ?? "", liveType: .bilibili, liveState: "", userId: "\(item.uid)", roomId: "\(item.roomid)"))
                }
                return tempArray
            }else {
                return []
            }
        }else {
            return []
        }
    }

    public class func getVideoQualites(roomId: String) async throws -> BilibiliMainData<BiliBiliQualityModel> {
        do {
            let dataReq = try await AF.request(
                "https://api.live.bilibili.com/room/v1/Room/playUrl",
                method: .get,
                parameters: [
                    "platform": "web",
                    "cid": roomId,
                    "qn": ""
                ],
                headers: BiliBiliCookie.cookie == "" ? nil : [
                    "cookie": BiliBiliCookie.cookie
                ]
            ).serializingDecodable(BilibiliMainData<BiliBiliQualityModel>.self).value
            if dataReq.code != 0 {
                return BilibiliMainData(code: 0, msg: "解析清晰度错误", data: .init(current_qn: 10000, quality_description: [.init(qn: 10000, desc: "清晰")]))
            }else {
                return dataReq
            }
            
        }catch {
            return BilibiliMainData(code: 0, msg: "解析清晰度错误", data: .init(current_qn: 10000, quality_description: [.init(qn: 10000, desc: "清晰")]))
        }
    }

    public class func getPlayUrl(roomId: String, qn: Int) async throws -> BilibiliMainData<BiliBiliPlayURLInfoMain> {
        return try await AF.request(
            "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
            method: .get,
            parameters: [
                "platform": "web",
                "room_id": roomId,
                "qn": qn,
                "protocol": "0,1",
                "format": "0,2",
                "codec": "0,1",
                "mask": "0"
            ],
            headers: BiliBiliCookie.cookie == "" ? nil : [
                "cookie": BiliBiliCookie.cookie
            ]
        ).serializingDecodable(BilibiliMainData.self).value
    }
    
    public class func getLiveStatus(roomId: String) async throws -> Int {
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            method: .get,
            parameters: [
                "room_id": roomId
            ],
            headers: BiliBiliCookie.cookie == "" ? nil : [
                "cookie": BiliBiliCookie.cookie
            ]
        ).serializingData().value
        
        let json = try JSONSerialization.jsonObject(with: dataReq, options: .mutableContainers)
        let jsonDict = json as! Dictionary<String, Any>
        let dataDict = jsonDict["data"] as! Dictionary<String, Any>
        let liveStatus = dataDict["live_status"] as? Int ?? -1
        return liveStatus
    }
    
    public class func getQRCodeUrl() async throws -> BilibiliQRMainModel {
        let dataReq = try await AF.request(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/generate",
            method: .get
        ).serializingDecodable(BilibiliQRMainModel.self).value
        return dataReq
    }
    
    public class func getQRCodeState(qrcode_key: String) async throws -> BilibiliQRMainModel {
        let resp = AF.request(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/poll",
            method: .get,
            parameters: [
                "qrcode_key": qrcode_key
            ]
        )
        
        let dataReq = try await resp.serializingDecodable(BilibiliQRMainModel.self).value
        if dataReq.data.code == 0 {
            UserDefaults.standard.setValue(resp.response?.headers["Set-Cookie"] ?? "", forKey: "BilibiliCookie")
        }
        return dataReq
    }
    
    public class func getBuvid() async throws -> String {
        do {
            let cookie = BiliBiliCookie.cookie
            if NSString(string: cookie).contains("buvid3") {
                let regex = try NSRegularExpression(pattern: "buvid3=(.*?);", options: [])
                let matchs =  regex.matches(in: cookie, range: NSRange(location: 0, length: cookie.count))
                for match in matchs {
                    let matchRange = Range(match.range, in: cookie)!
                    let matchedSubstring = cookie[matchRange]
                    return "\(matchedSubstring)"
                }
            }else {
                let dataReq = try await AF.request(
                    "https://api.bilibili.com/x/frontend/finger/spi",
                    method: .get,
                    headers: BiliBiliCookie.cookie == "" ? nil : [
                        "cookie": BiliBiliCookie.cookie
                    ]
                ).serializingDecodable(BilibiliMainData<BilibiliBuvidModel>.self).value
                return dataReq.data.b_3
            }
        }catch {
            return ""
        }
        return ""
    }
    
    public class func getRoomDanmuDetail(roomId: String) async throws -> BilibiliDanmuModel {
        let dataReq = try await AF.request(
            "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo",
            method: .get,
            parameters: [
                "id":roomId
            ],
            headers: BiliBiliCookie.cookie == "" ? nil : [
                "cookie": BiliBiliCookie.cookie
            ]
        ).serializingDecodable(BilibiliMainData<BilibiliDanmuModel>.self).value
        return dataReq.data
    }
    
    public class func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        let dataReq = try await AF.request(
            "https://api.bilibili.com/x/web-interface/search/type?context=&search_type=live&cover_type=user_cover",
            method: .get,
            parameters: [
                "order": "",
                "keyword": keyword,
                "category_id": "",
                "__refresh__": "",
                "_extra": "",
                "highlight": 0,
                "single_column": 0,
                "page": page
            ],
            headers: BiliBiliCookie.cookie == "" ?
            ["cookie": "buvid3=infoc"] :
            ["cookie": BiliBiliCookie.cookie]
        ).serializingDecodable(BilibiliSearchMainData.self).value
        var tempArray: Array<LiveModel> = []
        for item in dataReq.data?.result?.live_room ?? [] {
            tempArray.append(LiveModel(userName: item.uname, roomTitle: item.title ?? "", roomCover: "https:\(item.cover ?? "")", userHeadImg: "https:\(item.uface ?? "")", liveType: .bilibili, liveState: Bilibili.getBilibiliLiveStateString(liveStatus: item.live_status ?? 0), userId: "\(item.uid)", roomId: "\(item.roomid)"))
        }
        for item in dataReq.data?.result?.live_user ?? [] {
            let flowCount = item.attentions ?? 0
            var flowFormatString = ""
            if flowCount > 10000 {
                flowFormatString = String(format: "%.2f 万人关注直播间", Float(flowCount) / 10000.0)
            }else {
                flowFormatString = "\(flowCount) 人关注直播间"
            }
            let userName = String.stripHTML(from: item.uname)
            tempArray.append(LiveModel(userName: userName, roomTitle: item.title ?? "\(item.cate_name ?? "无分区") · \(flowFormatString)", roomCover: "https:\(item.uface ?? "")", userHeadImg: "https:\(item.uface ?? "")", liveType: .bilibili, liveState: Bilibili.getBilibiliLiveStateString(liveStatus: item.live_status ?? 0), userId: "\(item.uid)", roomId: "\(item.roomid)"))
        }
        return tempArray
    }
    
    class func getBilibiliLiveStateString(liveStatus: Int) -> String {
        var liveState = ""
        let liveStatus = liveStatus
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
        return liveState
    }
    
}
