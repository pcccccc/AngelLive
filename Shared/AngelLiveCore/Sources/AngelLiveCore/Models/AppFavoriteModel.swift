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
    /// 收藏是否启用 iCloud 同步。关闭 = 纯本地(服务「只有一台设备」的用户)。默认开启,保留既有行为。
    public var favoriteICloudSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(favoriteICloudSyncEnabled, forKey: Keys.favoriteICloudSyncEnabled) }
    }
    /// 最近一次收藏「云端同步」的错误(本地操作不受其影响)。非阻塞,供页面展示。
    public var lastSyncError: SyncError?
    private var isSyncing: Bool = false  // 添加同步状态标记

    private enum Keys {
        static let favoriteICloudSyncEnabled = "AppFavoriteModel.favoriteICloudSyncEnabled"
    }

    public init() {
        if UserDefaults.standard.object(forKey: Keys.favoriteICloudSyncEnabled) == nil {
            self.favoriteICloudSyncEnabled = true   // 默认开启,保留旧行为
        } else {
            self.favoriteICloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.favoriteICloudSyncEnabled)
        }
    }

    // MARK: - Phase② 本地存储(本地优先)

    /// 把当前 roomList 落本地(fire-and-forget)。
    private func persistLocal() {
        let snapshot = roomList
        Task { await FavoriteLocalStore.shared.save(snapshot) }
    }

    /// 用给定列表重建排序与分组(与 FavoriteStateModel 分组规则一致)。
    @MainActor
    private func applyRoomList(_ rooms: [LiveModel]) {
        let sorted = rooms.sortedByLiveState()
        let style = AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) ?? .liveState
        roomList = sorted
        groupedRoomList = sorted.groupedBySections(style: style)
        listVersion &+= 1
    }

    /// 合并本地与云端(union,云端优先以保留新鲜直播状态;不丢离线新增)。
    private func mergeLocalAndCloud(local: [LiveModel], cloud: [LiveModel]) -> [LiveModel] {
        var merged = cloud
        let cloudKeys = Set(cloud.map { AppFavoriteModel.favoriteUniqueKey(for: $0) })
        for item in local where !cloudKeys.contains(AppFavoriteModel.favoriteUniqueKey(for: item)) {
            merged.append(item)
        }
        return merged
    }

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

        // 本地优先:先用本地数据秒显(仅当内存为空,避免整页重建导致滚动卡顿)。
        let local = await FavoriteLocalStore.shared.load()
        let hasExistingData = !roomList.isEmpty
        if !hasExistingData {
            if local.isEmpty {
                roomList.removeAll()
                groupedRoomList.removeAll()
            } else {
                applyRoomList(local)
            }
        }
        cloudReturnError = false
        syncProgressInfo = ("", "", "", 0, 0)
        // 有(本地或旧)数据时不显示 loading 骨架屏，保持列表可滚动
        self.isLoading = roomList.isEmpty
        self.syncStatus = .syncing

        // iCloud 关闭:纯本地,不触碰 CloudKit。
        guard favoriteICloudSyncEnabled else {
            isLoading = false
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1

        if self.cloudKitReady {
            do {
                let resp = try await actor.syncStreamerLiveStates()
                // 合并本地与云端,避免冲掉离线新增;再回写本地。
                let merged = mergeLocalAndCloud(local: local, cloud: resp.0)
                applyRoomList(merged)
                persistLocal()
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                syncStatus = .success
                lastSyncTime = Date() // 记录同步时间
                lastSyncError = nil
            } catch {
                // 云端失败:保留本地展示,不清空。
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                self.lastSyncError = SyncError.from(error)
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                cloudReturnError = true
                syncStatus = .error
            }
        } else {
            let stateStr = await FavoriteService.getCloudState()
            if stateStr == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + stateStr + "请尝试重新在设置中登录iCloud"
            } else {
                self.cloudKitStateString = stateStr
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

        let local = await FavoriteLocalStore.shared.load()

        // iCloud 关闭:纯本地刷新。
        guard favoriteICloudSyncEnabled else {
            if !local.isEmpty { applyRoomList(local) }
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1

        if self.cloudKitReady {
            do {
                let resp = try await actor.syncStreamerLiveStates()
                // 合并本地与云端,不清空;再回写本地。
                let merged = mergeLocalAndCloud(local: local, cloud: resp.0)
                applyRoomList(merged)
                persistLocal()
                syncStatus = .success
                lastSyncTime = Date()
                lastSyncError = nil
            } catch {
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                self.lastSyncError = SyncError.from(error)
                cloudReturnError = true
                syncStatus = .error
            }
        } else {
            let stateStr = await FavoriteService.getCloudState()
            if stateStr == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + stateStr + "请尝试重新在设置中登录iCloud"
            } else {
                self.cloudKitStateString = stateStr
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

        let consoleEntryId = PluginConsoleService.shared.log(tag: "Favorite", method: "addFavorite", status: .loading)
        PluginConsoleService.shared.updateRequest(id: consoleEntryId, body: AppFavoriteModel.consoleRequestBody(for: room))
        let consoleStart = Date()

        // 本地优先:先更新内存与本地存储(立即成功),云端同步放最后且非阻塞。
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
        persistLocal()

        // 云端同步(非阻塞):关闭则跳过;失败仅记 lastSyncError,不回滚本地。
        if favoriteICloudSyncEnabled {
            do {
                try await FavoriteService.saveRecord(liveModel: room)
                lastSyncError = nil
            } catch {
                lastSyncError = SyncError.from(error)
                Logger.warning("收藏已存本地,但同步到 iCloud 失败: \(lastSyncError?.displayText ?? "")", category: .general)
            }
        }

        PluginConsoleService.shared.updateStatus(
            id: consoleEntryId,
            status: .success,
            duration: Date().timeIntervalSince(consoleStart),
            responseBody: AppFavoriteModel.consoleSuccessSummary(verb: "已收藏", room: room, totalCount: roomList.count)
        )
    }

    @MainActor
    public func removeFavoriteRoom(room: LiveModel) async throws {
        let consoleEntryId = PluginConsoleService.shared.log(tag: "Favorite", method: "removeFavoriteRoom", status: .loading)
        PluginConsoleService.shared.updateRequest(id: consoleEntryId, body: AppFavoriteModel.consoleRequestBody(for: room))
        let consoleStart = Date()

        // 本地优先:先从内存与本地删除(立即成功),云端删除放最后且非阻塞。
        let targetKey = AppFavoriteModel.favoriteUniqueKey(for: room)
        // 从 roomList 中删除
        roomList.removeAll(where: { AppFavoriteModel.favoriteUniqueKey(for: $0) == targetKey })

        // 从 groupedRoomList 中删除
        for index in groupedRoomList.indices {
            groupedRoomList[index].roomList.removeAll(where: { AppFavoriteModel.favoriteUniqueKey(for: $0) == targetKey })
        }
        groupedRoomList.removeAll(where: { $0.roomList.isEmpty })
        listVersion &+= 1
        persistLocal()

        // 云端删除(非阻塞):关闭则跳过;失败仅记 lastSyncError,不回滚本地删除。
        if favoriteICloudSyncEnabled {
            do {
                try await FavoriteService.deleteRecord(liveModel: room)
                lastSyncError = nil
            } catch {
                lastSyncError = SyncError.from(error)
                Logger.warning("收藏已从本地删除,但 iCloud 删除失败: \(lastSyncError?.displayText ?? "")", category: .general)
            }
        }

        PluginConsoleService.shared.updateStatus(
            id: consoleEntryId,
            status: .success,
            duration: Date().timeIntervalSince(consoleStart),
            responseBody: AppFavoriteModel.consoleSuccessSummary(verb: "已取消收藏", room: room, totalCount: roomList.count)
        )
    }

    /// 构造统一的控制台请求摘要,用于开发者面板查看本次收藏操作针对哪个房间。
    private static func consoleRequestBody(for room: LiveModel) -> String {
        let platform = room.liveType.rawValue
        let userId = room.userId.isEmpty ? "-" : room.userId
        let roomId = room.roomId.isEmpty ? "-" : room.roomId
        let userName = room.userName.isEmpty ? "-" : room.userName
        let roomTitle = room.roomTitle.isEmpty ? "-" : room.roomTitle
        return """
        platform: \(platform)
        userId: \(userId)
        roomId: \(roomId)
        userName: \(userName)
        roomTitle: \(roomTitle)
        """
    }

    /// 控制台成功面板:把操作结果(收藏/取消)+ 房间识别信息 + 当前收藏总数都打出来。
    private static func consoleSuccessSummary(verb: String, room: LiveModel, totalCount: Int) -> String {
        let platformName = LiveParseTools.getLivePlatformName(room.liveType)
        let userName = room.userName.isEmpty ? "-" : room.userName
        let identity: String
        if !room.userId.isEmpty {
            identity = "userId=\(room.userId)"
        } else if !room.roomId.isEmpty {
            identity = "roomId=\(room.roomId)"
        } else {
            identity = "name=\(userName)"
        }
        return """
        result: \(verb)
        platform: \(platformName)
        target: \(userName) (\(identity))
        currentFavoriteCount: \(totalCount)
        """
    }

    /// 控制台错误面板:既给出格式化的错误码,也保留原始 error 描述,方便排查。
    private static func consoleErrorMessage(for error: Error) -> String {
        let formatted = FavoriteService.formatErrorCode(error: error)
        let raw = error.localizedDescription
        if formatted == raw {
            return formatted
        }
        return """
        \(formatted)
        ── raw ──
        \(raw)
        """
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

extension AppFavoriteModel {
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
