//
//  DouyuModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/2.
//

import Foundation
import Alamofire

struct DouyuMainListModel: Codable {
    let id: String
    let name: String
    var list: Array<DouyuSubListModel>
}

struct DouyuSubListMain: Codable {
    var error: Int
    var msg: String
    var data: DouyuSubListData
}

struct DouyuSubListData: Codable {
    let total: Int
    let list: Array<DouyuSubListModel>
}

struct DouyuSubListModel: Codable {
    let cid1: Int
    let cid2: Int
    let shortName: String
    let cname2: String
    let orderdisplay: Int
    let isGameCate: Int
    let isRelate: Int
    let pushVerticalScreen: Int
    let pushNearby: Int
    let count: Int
    let isAudio: Int
    let squareIconUrlW: String
    let isHidden: Int
    let cateDesc: String
    let isVM: Int
    let hn: Int
    let cate2Url: String
}

struct DouyuRoomMain: Codable {
    var code: Int
    var msg: String
    var data: DouyuRoomListData
}

struct DouyuRoomListData: Codable {
    let rl: Array<DouyuRoomModel>
    let pgcnt: Int
}

struct DouyuRoomModel: Codable {
    let type: Int
    let rid: Int
    let rn: String
    let uid: Int
    let nn: String
    let cid1: Int
    let cid2: Int
    let cid3: Int
    let iv: Int
    let av: String
    let ol: Int
    let c2url: String
    let c2name: String
    let rs16_avif: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(Int.self, forKey: .type)
        self.rid = try container.decode(Int.self, forKey: .rid)
        self.rn = try container.decode(String.self, forKey: .rn)
        self.uid = try container.decode(Int.self, forKey: .uid)
        self.nn = try container.decode(String.self, forKey: .nn)
        self.cid1 = try container.decode(Int.self, forKey: .cid1)
        self.cid2 = try container.decode(Int.self, forKey: .cid2)
        self.cid3 = try container.decode(Int.self, forKey: .cid3)
        self.iv = try container.decode(Int.self, forKey: .iv)
        let av = try container.decode(String.self, forKey: .av)
        self.av = "https://apic.douyucdn.cn/upload/\(av)_middle.jpg"
        self.ol = try container.decode(Int.self, forKey: .ol)
        self.c2url = try container.decode(String.self, forKey: .c2url)
        self.c2name = try container.decode(String.self, forKey: .c2name)
        self.rs16_avif = try container.decode(String.self, forKey: .rs16_avif)
    }
}

struct DouyuPlayInfoData: Codable {
    let error: Int
    let msg: String
    let data: DouyuPlayInfoModel?
}

struct DouyuPlayInfoModel: Codable {
    let rtmp_url: String
    let rtmp_live: String
    let play_url: String
}

class Douyu {
    public class func getCategoryList(id: String) async throws -> Array<DouyuSubListModel> {
        let dataReq = try await AF.request(
            "https://www.douyu.com/japi/weblist/api/getC2List",
            method: .get,
            parameters: [
                "shortName": id,
                "offset": 0,
                "limit": 200,
            ]
        ).serializingDecodable(DouyuSubListMain.self).value
        return dataReq.data.list
    }
    
    public class func getCategoryRooms(category: DouyuSubListModel, page: Int) async throws -> DouyuRoomListData {
        let dataReq = try await AF.request(
            "https://www.douyu.com/gapi/rkc/directory/mixList/2_\(category.cid2)/\(page)",
            method: .get
        ).serializingDecodable(DouyuRoomMain.self).value
        return dataReq.data
    }
    
    
    public class func getPlayArgs(rid: String) async throws -> DouyuPlayInfoData {
        let jsEncReq = try await AF.request(
            "https://www.douyu.com/swf_api/homeH5Enc?rids=\(rid)",
            method: .get,
            headers: HTTPHeaders([
                HTTPHeader.init(name: "referer", value: "https://www.douyu.com/\(rid)"),
                HTTPHeader.init(name: "user-agent", value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43"),
            ])
        ).serializingData().value
        let jsEncJson = try JSONSerialization.jsonObject(with: jsEncReq, options: .mutableContainers)
        let jsEncDict = jsEncJson as! Dictionary<String, Any>
        let jsEncData = jsEncDict["data"] as! Dictionary<String, Any>
        let cryText = jsEncData["room\(rid)"] as? String ?? ""
        
        let regex = try NSRegularExpression(pattern: "(vdwdae325w_64we[\\s\\S]*function ub98484234[\\s\\S]*?)function", options: [])
        let matchs =  regex.matches(in: cryText, range: NSRange(location: 0, length:  cryText.count))
        if matchs.count > 0 {
            let match = matchs.first!
            let matchRange = Range(match.range, in: cryText)!
            let matchedSubstring = cryText[matchRange]
            let nsstr = NSString(string: "\(matchedSubstring.prefix(matchedSubstring.count - 9))")
            let regex = "eval.*?;\\}"
            let RE = try NSRegularExpression(pattern: regex, options: .caseInsensitive)
            let res = RE.stringByReplacingMatches(in: String(nsstr), options: .reportProgress, range: NSRange(location: 0, length: String(nsstr).count), withTemplate: "strc;}")
            var request = URLRequest(url: URL(string: "http://alive.nsapps.cn/api/AllLive/DouyuSign")!)
            request.httpMethod = "post"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            let parameter = [
                "html": res,
                "rid": rid
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: parameter)
            let dataReq = try await AF.request(request).serializingData().value
            let json = try JSONSerialization.jsonObject(with: dataReq, options: .mutableContainers)
            let jsonDict = json as! Dictionary<String, Any>
            if jsonDict["code"] as? Int ?? -1 == 0 {
                var playData = NSString(string: "{\"\(jsonDict["data"] as? String ?? "")\"}")
                playData = playData.replacingOccurrences(of: "&", with: "\",\"") as NSString
                playData = playData.replacingOccurrences(of: "=", with: "\":\"") as NSString
                let finalData = (playData as String).data(using: .utf8) ?? Data()
                let jsEncJson = try JSONSerialization.jsonObject(with: finalData, options: .mutableContainers)
                var jsEncDict = jsEncJson as! Dictionary<String, Any>
                //\("&cdn=scdncuhubwh2&rate=0&hevc=0&fa=0&ver=Douyu_223061205&ive=1&iar=1")
                jsEncDict.updateValue(0, forKey: "rate")
                let dataReq = try await AF.request(
                    "https://www.douyu.com/lapi/live/getH5Play/\(rid)",
                    method: .post,
                    parameters: jsEncDict,
                    headers: HTTPHeaders([
                        HTTPHeader.init(name: "referer", value: "https://www.douyu.com/\(rid)"),
                        HTTPHeader.init(name: "user-agent", value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43"),
                    ])
                ).serializingString().value
                let resData = dataReq.data(using: .utf8) ?? Data()
                let resJson = try JSONSerialization.jsonObject(with: resData, options: .mutableContainers)
                let resDict = resJson as! Dictionary<String, Any>
                let dataDict = resDict["data"] as! Dictionary<String, Any>
                let model = DouyuPlayInfoModel(rtmp_url: dataDict["rtmp_url"] as? String ?? "", rtmp_live: dataDict["rtmp_live"] as? String ?? "", play_url: "")
                return DouyuPlayInfoData(error: resDict["error"] as? Int ?? -1, msg: resDict["msg"] as? String ?? "error", data: model)
            }
        }
        return DouyuPlayInfoData(error: -1, msg: "error", data: nil)
    }
    
}
