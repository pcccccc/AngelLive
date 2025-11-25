//
//  HistoryModel.swift
//  AngelLiveCore
//
//  Created by Claude on 11/1/25.
//

import Foundation
import SwiftUI
import Observation
import LiveParse

@Observable
public final class HistoryModel {

    public init() {
        loadWatchList()
    }

    @ObservationIgnored
    private let watchListKey = "SimpleLive.History.WatchList"

    public var watchList: Array<LiveModel> = []

    private func loadWatchList() {
        guard let data = UserDefaults.shared.data(forKey: watchListKey),
              let decoded = try? JSONDecoder().decode([LiveModel].self, from: data) else {
            watchList = []
            return
        }
        watchList = decoded
    }

    private func saveWatchList() {
        guard let encoded = try? JSONEncoder().encode(watchList) else { return }
        UserDefaults.shared.set(encoded, forKey: watchListKey)
    }

    public func addHistory(room: LiveModel) {
        // 移除已存在的同一房间（如果有）
        watchList.removeAll { $0.roomId == room.roomId }

        // 添加到列表开头
        watchList.insert(room, at: 0)

        // 限制历史记录数量（最多保存100条）
        if watchList.count > 100 {
            watchList = Array(watchList.prefix(100))
        }

        saveWatchList()
    }

    public func removeHistory(room: LiveModel) {
        watchList.removeAll { $0.roomId == room.roomId }
        saveWatchList()
    }

    public func clearAll() {
        watchList.removeAll()
        saveWatchList()
    }
}
