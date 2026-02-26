//
//  AppFavoriteModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import Foundation
import SwiftUI
import CloudKit
import Observation
import LiveParse

/// iCloud同步状态
public enum CloudSyncStatus {
    case syncing      // 正在同步
    case success      // 同步成功
    case error        // 同步错误
    case notLoggedIn  // 未登录iCloud
}

@Observable
public final class AppFavoriteModel {
    public let actor = FavoriteStateModel()
    public var groupedRoomList: [FavoriteLiveSectionModel] = []
    public var roomList: [LiveModel] = []
    public var isLoading: Bool = false
    public var cloudKitReady: Bool = false
    public var cloudKitStateString: String = "正在检查iCloud状态"
    public var syncProgressInfo: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    public var cloudReturnError = false
    public var syncStatus: CloudSyncStatus = .syncing
    public var lastSyncTime: Date?
    public var listVersion: Int = 0
    private var isSyncing: Bool = false  // 添加同步状态标记

    public init() {}

    /// 判断是否需要同步数据
    /// - Returns: 如果列表为空或距离上次同步超过1分钟则返回true
    public func shouldSync() -> Bool {
        // 如果列表为空，需要同步
        if roomList.isEmpty {
            return true
        }

        // 如果从未同步过，需要同步
        guard let lastSync = lastSyncTime else {
            return true
        }

        // 如果距离上次同步超过1分钟，需要同步
        let timeInterval = Date().timeIntervalSince(lastSync)
        return timeInterval > 60 // 60秒 = 1分钟
    }

    @MainActor
    public func syncWithActor() async {
        // 防止并发刷新：如果正在同步中，直接返回
        guard !isSyncing else {
            print("正在同步中，忽略此次刷新请求")
            return
        }

        isSyncing = true
        defer { isSyncing = false }  // 确保无论成功或失败都重置状态

        roomList.removeAll()
        groupedRoomList.removeAll()
        cloudReturnError = false
        syncProgressInfo = ("", "", "", 0, 0)
        self.isLoading = true
        self.syncStatus = .syncing

        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1

        if self.cloudKitReady {
            do {
                let resp = try await actor.syncStreamerLiveStates()
                self.roomList = resp.0
                self.groupedRoomList = resp.1
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                syncStatus = .success
                lastSyncTime = Date() // 记录同步时间
                listVersion &+= 1
            } catch {
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                cloudReturnError = true
                syncStatus = .error
            }
        } else {
            let state = await FavoriteService.getCloudState()
            if state == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + state + "请尝试重新在设置中登录iCloud"
            } else {
                self.cloudKitStateString = state
            }
            syncProgressInfo = ("", "", "", 0, 0)
            isLoading = false
            cloudReturnError = true
            syncStatus = .notLoggedIn
        }
    }

    /// 下拉刷新专用方法 - 不清空数据，保持 List 结构稳定
    @MainActor
    public func pullToRefresh() async {
        // 防止并发刷新
        guard !isSyncing else {
            print("正在同步中，忽略此次刷新请求")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // 不清空数据，不改变 isLoading 状态
        self.syncStatus = .syncing

        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1

        if self.cloudKitReady {
            do {
                let resp = try await actor.syncStreamerLiveStates()
                // 直接更新数据，不清空
                self.roomList = resp.0
                self.groupedRoomList = resp.1
                syncStatus = .success
                lastSyncTime = Date()
                listVersion &+= 1
            } catch {
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                cloudReturnError = true
                syncStatus = .error
            }
        } else {
            let state = await FavoriteService.getCloudState()
            if state == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + state + "请尝试重新在设置中登录iCloud"
            } else {
                self.cloudKitStateString = state
            }
            cloudReturnError = true
            syncStatus = .notLoggedIn
        }
    }

    @MainActor
    public func addFavorite(room: LiveModel) async throws {
        if roomList.contains(where: { AppFavoriteModel.favoriteUniqueKey(for: $0) == AppFavoriteModel.favoriteUniqueKey(for: room) }) {
            return
        }

        try await FavoriteService.saveRecord(liveModel: room)
        // 查找第一个非直播状态的房间位置
        var favIndex = -1
        for (index, favoriteRoom) in roomList.enumerated() {
            if LiveState(rawValue: favoriteRoom.liveState ?? "3") != .live {
                favIndex = index
                break
            }
        }

        // 插入到合适的位置
        if favIndex != -1 {
            roomList.insert(room, at: favIndex)
        } else {
            // 如果所有房间都在直播，则添加到末尾
            roomList.append(room)
        }

        // 更新分组列表
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            // 按平台分组
            var found = false
            for (index, model) in groupedRoomList.enumerated() {
                if model.type == room.liveType {
                    groupedRoomList[index].roomList.append(room)
                    found = true
                    break
                }
            }
            // 如果没有找到对应平台的分组，创建新分组
            if !found {
                var newSection = FavoriteLiveSectionModel()
                newSection.roomList = [room]
                newSection.title = LiveParseTools.getLivePlatformName(room.liveType)
                newSection.type = room.liveType
                groupedRoomList.append(newSection)
            }
        } else {
            // 按直播状态分组
            var found = false
            for (index, model) in groupedRoomList.enumerated() {
                if model.title == room.liveStateFormat() {
                    groupedRoomList[index].roomList.append(room)
                    found = true
                    break
                }
            }
            // 如果没有找到对应状态的分组，创建新分组
            if !found {
                var newSection = FavoriteLiveSectionModel()
                newSection.roomList = [room]
                newSection.title = room.liveStateFormat()
                newSection.type = room.liveType
                groupedRoomList.append(newSection)
            }
        }
        listVersion &+= 1
    }

    @MainActor
    public func removeFavoriteRoom(room: LiveModel) async throws {
        try await FavoriteService.deleteRecord(liveModel: room)
        let targetKey = AppFavoriteModel.favoriteUniqueKey(for: room)
        // 从 roomList 中删除
        roomList.removeAll(where: { AppFavoriteModel.favoriteUniqueKey(for: $0) == targetKey })

        // 从 groupedRoomList 中删除
        for index in groupedRoomList.indices {
            groupedRoomList[index].roomList.removeAll(where: { AppFavoriteModel.favoriteUniqueKey(for: $0) == targetKey })
        }
        groupedRoomList.removeAll(where: { $0.roomList.isEmpty })
        listVersion &+= 1
    }

    public func refreshView() {
        // 触发 Observation 更新
        let theRoomList = roomList
        roomList.removeAll()
        roomList = theRoomList
        
        // 使用抽取的分组方法，消除重复代码
        let style = AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) ?? .liveState
        self.groupedRoomList = roomList.groupedBySections(style: style)
        listVersion &+= 1
    }
}

private extension AppFavoriteModel {
    static func favoriteUniqueKey(for room: LiveModel) -> String {
        let liveType = room.liveType.rawValue
        let userId = room.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userId.isEmpty {
            return "\(liveType)_u_\(userId)"
        }
        let roomId = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !roomId.isEmpty {
            return "\(liveType)_r_\(roomId)"
        }
        return "\(liveType)_n_\(room.userName.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
