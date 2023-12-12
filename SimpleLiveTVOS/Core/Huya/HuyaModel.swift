//
//  HuyaModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/4.
//

import Foundation
import Alamofire

struct HuyaMainListModel: Codable {
    let id: String
    let name: String
    var list: Array<HuyaSubListModel>
}

struct HuyaMainData<T: Codable>: Codable {
    var status: Int
    var msg: String
    var data: T
}

struct HuyaSubListModel: Codable {
    let gid: Int
    let totalCount: Int
    let profileNum: Double
    let gameFullName: String
//    let gameHostName: String?
    let gameType: Double
    let bussType: Double
    let isHide: Double
    let pic: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gid = try container.decode(Int.self, forKey: .gid)
        self.totalCount = try container.decode(Int.self, forKey: .totalCount)
        self.profileNum = try container.decode(Double.self, forKey: .profileNum)
        self.gameFullName = try container.decode(String.self, forKey: .gameFullName)
//        self.gameHostName = try container.decode(String?.self, forKey: .gameHostName)
        self.gameType = try container.decode(Double.self, forKey: .gameType)
        self.bussType = try container.decode(Double.self, forKey: .bussType)
        self.isHide = try container.decode(Double.self, forKey: .isHide)
        self.pic = "https://huyaimg.msstatic.com/cdnimage/game/\(gid)-MS.jpg"
    }
}

struct HuyaRoomMainData: Codable {
    var status: Int
    var message: String
    var data: HuyaRoomData
}

struct HuyaRoomData: Codable {
    let page: Int
    let pageSize: Int
    let totalPage: Int
    let totalCount: Int
    let datas: Array<HuyaRoomModel>
}

struct HuyaRoomModel: Codable {
    let nick: String
    let introduction: String
    let screenshot: String
    let avatar180: String
    let uid: String
    let profileRoom: String
}


struct HuyaRoomInfoMainModel: Codable {
    let roomInfo: HuyaRoomInfoModel
    
}

struct HuyaRoomInfoModel: Codable {
    let eLiveStatus: Int
    let tLiveInfo: HuyaRoomTLiveInfo
}

struct HuyaRoomTLiveInfo: Codable {
    let lYyid: Int
    let tLiveStreamInfo: HuyaRoomTLiveStreamInfo
}

struct HuyaRoomTLiveStreamInfo: Codable {
    let vStreamInfo: HuyaRoomVStreamInfo
    let vBitRateInfo:HuyaRoomBitRateInfo
}

struct HuyaRoomBitRateInfo: Codable {
    let value: Array<HuyaRoomLiveQualityModel>
}

struct HuyaRoomVStreamInfo: Codable {
    let value: Array<HuyaRoomLiveStreamModel>
}

struct HuyaRoomLiveStreamModel: Codable {
    let sCdnType: String //'AL': '阿里', 'TX': '腾讯', 'HW': '华为', 'HS': '火山', 'WS': '网宿', 'HY': '虎牙'
    let iIsMaster: Int
    let sStreamName: String
    let sFlvUrl: String
    let sFlvUrlSuffix: String
    let sFlvAntiCode: String
    let sHlsUrl: String
    let sHlsUrlSuffix: String
    let sHlsAntiCode: String
    let sCodec: String?
    let iMobilePriorityRate: Int
    let lChannelId: Int
    let lSubChannelId: Int
}

struct HuyaRoomLiveQualityModel: Codable {
    let sDisplayName: String
    let iBitRate: Int
    let iCodecType: Int
    let iCompatibleFlag: Int
    let iHEVCBitRate: Int
    
}

struct HuyaSearchResult: Codable {
    let response: HuyaSearchResponse
}

struct HuyaSearchResponse: Codable {
    let three: HuyaSearchDocses
    
    enum CodingKeys: String, CodingKey {
    case three = "3"
    }
}

struct HuyaSearchDocses: Codable {
    let docs: Array<HuyaSearchDocs>
}

struct HuyaSearchDocs: Codable {
    let game_nick: String
    let room_id: Int
    let uid: Int
    let game_introduction: String
    let game_imgUrl: String
    let game_screenshot: String
}
    
class Huya: LiveParse {

    func getCategoryList() async throws -> [LiveMainListModel] {
        return [
            LiveMainListModel(id: 1, title: "网游", icon: "", subList: try await getCategorySubList(id: "1")),
            LiveMainListModel(id: 2, title: "单机", icon: "", subList: try await getCategorySubList(id: "2")),
            LiveMainListModel(id: 8, title: "娱乐", icon: "", subList: try await getCategorySubList(id: "8")),
            LiveMainListModel(id: 3, title: "手游", icon: "", subList: try await getCategorySubList(id: "3")),
        ]
    }
    
    func getCategorySubList(id: String) async throws -> [LiveCategoryModel] {
        let dataReq = try await AF.request("https://live.cdn.huya.com/liveconfig/game/bussLive", method: .get, parameters: ["bussType": id]).serializingDecodable(HuyaMainData<[HuyaSubListModel]>.self).value
        var tempArray: [LiveCategoryModel] = []
        for item in dataReq.data {
            tempArray.append(LiveCategoryModel(id: "\(item.gid)", parentId: "", title: item.gameFullName, icon: item.pic))
        }
        return tempArray
    }
    
    func getRoomList(id: String, parentId: String?, page: Int = 1) async throws -> [LiveModel] {
        let dataReq = try await AF.request(
            "https://www.huya.com/cache.php",
            method: .get,
            parameters: [
                "m": "LiveList",
                "do": "getLiveListByPage",
                "tagAll": 0,
                "gameId": id,
                "page": page
            ]
        ).serializingDecodable(HuyaRoomMainData.self).value
        var tempArray: Array<LiveModel> = []
        for item in dataReq.data.datas {
            tempArray.append(LiveModel(userName: item.nick, roomTitle: item.introduction, roomCover: item.screenshot, userHeadImg: item.avatar180, liveType: .huya, liveState: "", userId: item.uid, roomId: item.profileRoom))
        }
        return tempArray
    }
    
    func getPlayArgs(roomId: String) async throws -> [LiveQuality] {
        let dataReq = try await AF.request(
            "https://m.huya.com/\(roomId)",
            method: .get,
            headers: [
                HTTPHeader(name: "user-agent", value: "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/91.0.4472.69")
            ]
        ).serializingString().value
        let regex = try NSRegularExpression(pattern: "window\\.HNF_GLOBAL_INIT.=.\\{(.*?)\\}.</script>", options: [])
        let matchs =  regex.matches(in: dataReq, range: NSRange(location: 0, length:  dataReq.count))
        for match in matchs {
            let matchRange = Range(match.range, in: dataReq)!
            let matchedSubstring = dataReq[matchRange]
            var nsstr = NSString(string: "\(matchedSubstring.prefix(matchedSubstring.count - 10))")
            nsstr = nsstr.replacingOccurrences(of: "window.HNF_GLOBAL_INIT =", with: "") as NSString
            let liveData = try JSONDecoder().decode(HuyaRoomInfoMainModel.self, from: (nsstr as String).data(using: .utf8)!)
            if liveData != nil {
                let streamInfo = liveData.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first
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
                    for streamInfo in liveData.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value {
                        if maxRate < streamInfo.iMobilePriorityRate {
                            maxRate = streamInfo.iMobilePriorityRate
                            url = "\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)"
                        }
                    }
                    let bitRateInfoArray  = liveData.roomInfo.tLiveInfo.tLiveStreamInfo.vBitRateInfo.value
                    var liveQualtys: [LiveQuality] = []
                    for index in 0 ..< bitRateInfoArray.count {
                        let bitRateInfo = bitRateInfoArray[index]
                        liveQualtys.append(.init(roomId: roomId, title: "线路\(index + 1)", qn: bitRateInfo.iBitRate, url: url, liveCodeType: .flv, liveType: .huya))
                    }
                    return liveQualtys
                }
            }
        }
    }
    
    
    
    public class func getHuyaSubList(bussType: String) async throws -> HuyaMainData<Array<HuyaSubListModel>> {
        do {
            return try await AF.request("https://live.cdn.huya.com/liveconfig/game/bussLive", method: .get, parameters: ["bussType": bussType]).serializingDecodable(HuyaMainData.self).value
        }catch {
            print(error)
            return try await AF.request("https://live.cdn.huya.com/liveconfig/game/bussLive", method: .get, parameters: ["bussType": bussType]).serializingDecodable(HuyaMainData.self).value
        }
    }
    
    public class func getCategoryRooms(category: HuyaSubListModel, page: Int) async throws -> Array<LiveModel> {
        let dataReq = try await AF.request(
            "https://www.huya.com/cache.php",
            method: .get,
            parameters: [
                "m": "LiveList",
                "do": "getLiveListByPage",
                "tagAll": 0,
                "gameId": category.gid,
                "page": page
            ]
        ).serializingDecodable(HuyaRoomMainData.self).value
        var tempArray: Array<LiveModel> = []
        for item in dataReq.data.datas {
            tempArray.append(LiveModel(userName: item.nick, roomTitle: item.introduction, roomCover: item.screenshot, userHeadImg: item.avatar180, liveType: .huya, liveState: "", userId: item.uid, roomId: item.profileRoom))
        }
        return tempArray
    }
    
    public class func getPlayArgs(rid: String) async throws -> HuyaRoomInfoMainModel? {
        do {
            let dataReq = try await AF.request(
                "https://m.huya.com/\(rid)",
                method: .get,
                headers: [
                    HTTPHeader(name: "user-agent", value: "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/91.0.4472.69")
                ]
            ).serializingString().value
            let regex = try NSRegularExpression(pattern: "window\\.HNF_GLOBAL_INIT.=.\\{(.*?)\\}.</script>", options: [])
            let matchs =  regex.matches(in: dataReq, range: NSRange(location: 0, length:  dataReq.count))
            for match in matchs {
                let matchRange = Range(match.range, in: dataReq)!
                let matchedSubstring = dataReq[matchRange]
                var nsstr = NSString(string: "\(matchedSubstring.prefix(matchedSubstring.count - 10))")
                nsstr = nsstr.replacingOccurrences(of: "window.HNF_GLOBAL_INIT =", with: "") as NSString
                let data = try JSONDecoder().decode(HuyaRoomInfoMainModel.self, from: (nsstr as String).data(using: .utf8)!)
                return data
            }
        }catch {
            print(error)
            return nil
        }
        return nil
    }
    
    public class func getUUID() -> String {
        let now = Date().timeIntervalSince1970 * 1000
        let rand = Int(arc4random() % 1000 | 0)
        let uuid = (Int(now) % 10000000000 * 1000 + rand) % 4294967295
        return "\(uuid)"
    }
    
    public class func getAnonymousUid() async throws -> String {

        var request = URLRequest(url: URL(string: "https://udblgn.huya.com/web/anonymousLogin")!)
        request.httpMethod = "post"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let parameter = [
            "appId": 5002,
            "byPass": 3,
            "context": "",
            "version": "2.4",
            "data": [:]
        ] as [String : Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: parameter)
        let dataReq = try await AF.request(request).serializingData().value
        let json = try JSONSerialization.jsonObject(with: dataReq, options: .mutableContainers)
        let jsonDict = json as! Dictionary<String, Any>
        if jsonDict["returnCode"] as? Int ?? -1 == 0 {
            let data = jsonDict["data"] as? Dictionary<String, Any>
            return data?["uid"] as? String ?? ""
        }
        return ""
    }
    
    public func searchRooms(keyword: String, page: Int) async throws -> [LiveModel] {
        let dataReq = try await AF.request(
            "https://search.cdn.huya.com/",
            parameters: [
                "m": "Search",
                "do": "getSearchContent",
                "q": keyword,
                "uid": 0,
                "v": 4,
                "typ": -5,
                "livestate": 0,
                "rows": 20,
                "start": (page - 1) * 20,
            ]
        ).serializingDecodable(HuyaSearchResult.self).value
        var tempArray: Array<LiveModel> = []
        for item in dataReq.response.three.docs {
            tempArray.append(LiveModel(userName: item.game_nick, roomTitle: item.game_introduction, roomCover: item.game_screenshot, userHeadImg: item.game_imgUrl, liveType: .huya, liveState: "正在直播", userId: "\(item.uid)", roomId: "\(item.room_id)"))
        }
        return tempArray
    }
}
