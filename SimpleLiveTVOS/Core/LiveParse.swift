//
//  LiveParse.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/11.
//

import Foundation


 protocol LiveParse {
    func getCategoryList() async throws -> [LiveMainListModel]
    func getRoomList(id: String, parentId: String?, page: Int) async throws -> [LiveModel]
    func getPlayArgs(roomId: String) async throws -> [LiveQuality]
    func searchRooms(keyword: String, page: Int) async throws -> [LiveModel]
    func getLiveLastestInfo() async throws -> LiveModel
    func getLiveState() async throws -> LiveState
}
