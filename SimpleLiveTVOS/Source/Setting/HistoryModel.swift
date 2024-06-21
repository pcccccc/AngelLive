//
//  HistoryModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/21.
//

import SwiftUI
import LiveParse

class HistoryModel: ObservableObject {
    @AppStorage("SimpleLive.History.WatchList") var watchList: Array<LiveModel> = []
}
