//
//  LiveParse.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/11.
//

import Foundation


 protocol LiveParse {
     static func getCategoryList() async throws -> [LiveMainListModel]
     static func getRoomList(id: String, parentId: String?, page: Int) async throws -> [LiveModel]
     static func getPlayArgs(roomId: String, userId: String?) async throws -> [LiveQuality] //抖音roomId = webrid, userId = room_id_str
     static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel]
     static func getLiveLastestInfo(roomId: String, userId: String?) async throws -> LiveModel //抖音roomId = webrid, userId = room_id_str
     static func getLiveState(roomId: String, userId: String?) async throws -> LiveState //抖音roomId = webrid, userId = room_id_str
}
