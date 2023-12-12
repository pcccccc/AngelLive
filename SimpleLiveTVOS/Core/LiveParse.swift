//
//  LiveParse.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/11.
//

import Foundation

struct LiveCategoryModel {
    
}

protocol LiveParse {
    func getCategoryList() -> [LiveCategoryModel]
    func getRoomList() -> [LiveModel]
    func getPlayArgs(roomId: String) -> [LiveQuality]
    func searchRooms(keyword: String, page: Int) -> [LiveModel]
    func getLiveLastestInfo() -> LiveModel
}
