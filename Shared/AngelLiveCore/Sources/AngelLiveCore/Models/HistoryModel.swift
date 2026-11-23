//
//  HistoryModel.swift
//  AngelLiveCore
//
//  Created by Claude on 11/1/25.
//

import Foundation
import SwiftUI
import Observation

@Observable
public final class HistoryModel {
    private static let maxHistoryCount = 100

    public init() {
        defaults = .shared
        loadWatchList()
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        loadWatchList()
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let watchListKey = "SimpleLive.History.WatchList"

    public var watchList: Array<LiveModel> = []

    private func loadWatchList() {
        guard let data = defaults.data(forKey: watchListKey),
              let decoded = try? JSONDecoder().decode([LiveModel].self, from: data) else {
            watchList = []
            return
        }
        watchList = decoded
    }

    private func saveWatchList() {
        guard let encoded = try? JSONEncoder().encode(watchList) else { return }
        defaults.set(encoded, forKey: watchListKey)
    }

    public func addHistory(room: LiveModel) {
        // 移除已存在的同一房间（如果有）
        watchList.removeAll { $0 == room }

        // 添加到列表开头
        watchList.insert(room, at: 0)

        // 限制历史记录数量（最多保存100条）
        if watchList.count > Self.maxHistoryCount {
            watchList = Array(watchList.prefix(Self.maxHistoryCount))
        }

        saveWatchList()
    }

    public func removeHistory(room: LiveModel) {
        watchList.removeAll { $0 == room }
        saveWatchList()
    }

    /// Replaces the history with the first occurrence of each room, in input order.
    public func replaceHistories(_ rooms: [LiveModel]) {
        var seen: Set<LiveModel> = []
        var history: [LiveModel] = []
        for room in rooms where seen.insert(room).inserted {
            history.append(room)
            if history.count == Self.maxHistoryCount { break }
        }
        watchList = history
        saveWatchList()
    }

    /// Keeps local rooms and appends new rooms in input order.
    public func mergeHistories(_ rooms: [LiveModel]) {
        replaceHistories(watchList + rooms)
    }

    /// FullUI can remove its selected category without deleting a same-room-ID record from another source.
    public func removeHistories(ids: Set<String>) {
        watchList.removeAll { ids.contains($0.id) }
        saveWatchList()
    }

    public func clearAll() {
        watchList.removeAll()
        saveWatchList()
    }
}
