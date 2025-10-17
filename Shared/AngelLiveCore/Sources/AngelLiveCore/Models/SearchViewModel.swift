//
//  SearchViewModel.swift
//  AngelLiveCore
//
//  Created by pc on 2024/1/12.
//

import Foundation
import Observation

@Observable
public final class SearchViewModel {
    public var searchTypeArray = ["关键词", "链接/分享口令/房间号", "Youtube链接/VideoId"]
    public var searchTypeIndex = 0
    public var page = 0
    public var searchText: String = ""

    public init() {}
}
