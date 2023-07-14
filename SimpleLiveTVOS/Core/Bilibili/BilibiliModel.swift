//
//  BilibiliModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/4.
//

import Foundation
import Alamofire

struct BilibiliMainData: Codable {
    var code: Int
    var msg: String
    var data: Array<BilibiliMainListModel>?
}

struct BilibiliMainListModel: Codable {
    let id: Int
    let name: String
    let list: Array<BilibiliSubListModel>?
}

struct BilibiliSubListModel: Codable {
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

class Bilibili {
    public class func getBiliBiliList() async throws -> BilibiliMainData  {
        print(try await AF.request("https://api.live.bilibili.com/room/v1/Area/getList", method: .get).serializingDecodable(BilibiliMainData.self).value)
        return try await AF.request("https://api.live.bilibili.com/room/v1/Area/getList", method: .get).serializingDecodable(BilibiliMainData.self).value
    }
}
