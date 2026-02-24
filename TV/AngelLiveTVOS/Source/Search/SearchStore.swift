//
//  SearchStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import Observation
import AngelLiveDependencies

@Observable
class SearchViewModel {
    var searchTypeArray = ["关键词 🔍", "链接/口令 🔗"]
    var searchTypeIndex = 0
    var page = 0
    var searchText: String = ""
}
