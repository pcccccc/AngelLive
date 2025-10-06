//
//  SearchStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse
import SimpleToast
import Observation

@Observable
class SearchViewModel {
    var searchTypeArray = ["关键词", "链接/分享口令/房间号", "Youtube链接/VideoId"]
    var searchTypeIndex = 0
    var page = 0
    var searchText: String = ""
}
