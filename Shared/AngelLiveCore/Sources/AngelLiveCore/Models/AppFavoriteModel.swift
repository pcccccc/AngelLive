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

    /// 三端统一的「数据同步」状态展示文案,设置页/同步页共用,避免各端各写一套。
    /// 关同步 = 已关闭(仅本地);开启时按 syncStatus 走:同步中 / 已同步 / 具体原因。
    public var syncStatusDisplayText: String {
        guard favoriteICloudSyncEnabled else { return "已关闭(仅本地)" }
        switch syncStatus {
        case .syncing:
            return "正在同步..."
        case .success:
            return "已同步"
        case .error, .notLoggedIn:
            return cloudKitStateString
        }
    }

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
    /// Phase③ 接入 CKSyncEngine 后,跨设备成员合并由引擎负责,此方法保留备用。
    private func mergeLocalAndCloud(local: [LiveModel], cloud: [LiveModel]) -> [LiveModel] {
        var merged = cloud
        let cloudKeys = Set(cloud.map { AppFavoriteModel.favoriteUniqueKey(for: $0) })
        for item in local where !cloudKeys.contains(AppFavoriteModel.favoriteUniqueKey(for: item)) {
            merged.append(item)
        }
        return merged
    }

    // MARK: - Phase③ CKSyncEngine 接入

    private var cloudSyncStarted = false

    /// 启动收藏同步引擎(幂等):设回调 + 启动 + 首次默认 Zone 迁移。仅在 iCloud 开启时调用。
    @MainActor
    private func startCloudSyncIfNeeded() {
        guard !cloudSyncStarted else { return }
        cloudSyncStarted = true
        FavoriteSyncEngine.shared.onRemoteChange = { [weak self] in
            await self?.reloadFromLocalAfterRemoteChange()
        }
        FavoriteSyncEngine.shared.start()
        Task { await FavoriteSyncEngine.shared.migrateFromDefaultZoneIfNeeded() }
    }

    /// 引擎拉到远端成员变更后:用本地真相刷新列表(直播状态下次刷新时更新)。
    @MainActor
    private func reloadFromLocalAfterRemoteChange() async {
        let local = await FavoriteLocalStore.shared.load()
        applyRoomList(local)
    }

    /// 对给定成员刷新直播状态并应用 + 回写本地;若探测到身份变化且开启同步,回写身份元数据。
    @MainActor
    private func refreshStatesAndApply(members: [LiveModel]) async {
        guard !members.isEmpty else {
            applyRoomList([])
            return
        }
        guard let result = try? await actor.syncStreamerLiveStates(members: members) else { return }
        applyRoomList(result.rooms)
        // 步骤4(修 R4):身份回写依赖 nextRecordZoneChangeBatch 从本地真相取新 key 对应的 room,
        // 因此必须**先等本地保存完成**,再入队,否则 recordProvider 找不到新 key。
        await FavoriteLocalStore.shared.save(result.rooms)
        // §10.7:关闭 iCloud 同步 = 纯本地,绝不触发任何身份回写。
        guard favoriteICloudSyncEnabled, !result.identityChanges.isEmpty else { return }
        startCloudSyncIfNeeded()
        for change in result.identityChanges {
            FavoriteSyncEngine.shared.enqueueIdentityMetadataRefresh(oldKey: change.oldKey, room: change.newRoom)
        }
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
            Logger.debug("正在同步中，忽略此次刷新请求", category: .favorite)
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

        // iCloud 关闭:纯本地,只刷新直播状态。
        guard favoriteICloudSyncEnabled else {
            await refreshStatesAndApply(members: local)
            isLoading = false
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        // 启动引擎(幂等)+ 拉一次云端变更进本地真相(CKSyncEngine 负责跨设备成员合并)。
        startCloudSyncIfNeeded()
        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1
        // 拉取不依赖 cloudKitReady 预检:该账号预检在分流/代理环境下会瞬时假阴性,
        // 导致 fetchChanges 被永久跳过 —— 对端的增/删永远拉不到。引擎自带退避与错误处理,
        // 账号真不可用时 fetch 会安全失败、不阻塞本地。cloudKitReady 仅用于下方 UI 状态展示。
        await FavoriteSyncEngine.shared.fetchChanges()
        // 不依赖 token 的全量对账兜底:补回增量 token 漂掉的对端新增。
        await FavoriteSyncEngine.shared.fullReconcile()

        // 用本地真相(引擎可能已更新)刷新直播状态并应用。
        let current = await FavoriteLocalStore.shared.load()
        await refreshStatesAndApply(members: current)
        syncProgressInfo = ("", "", "", 0, 0)
        isLoading = false
        if cloudKitReady {
            syncStatus = .success
            lastSyncTime = Date()
            lastSyncError = nil
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

    /// 下拉刷新专用方法 - 不清空数据，保持 List 结构稳定
    @MainActor
    public func pullToRefresh() async {
        // 防止并发刷新
        guard !isSyncing else {
            Logger.debug("正在同步中，忽略此次刷新请求", category: .favorite)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // 不清空数据，不改变 isLoading 状态
        self.syncStatus = .syncing

        let local = await FavoriteLocalStore.shared.load()

        // iCloud 关闭:纯本地刷新直播状态。
        guard favoriteICloudSyncEnabled else {
            await refreshStatesAndApply(members: local)
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        startCloudSyncIfNeeded()
        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1
        // 拉取不依赖 cloudKitReady 预检:该账号预检在分流/代理环境下会瞬时假阴性,
        // 导致 fetchChanges 被永久跳过 —— 对端的增/删永远拉不到。引擎自带退避与错误处理,
        // 账号真不可用时 fetch 会安全失败、不阻塞本地。cloudKitReady 仅用于下方 UI 状态展示。
        await FavoriteSyncEngine.shared.fetchChanges()
        // 不依赖 token 的全量对账兜底:补回增量 token 漂掉的对端新增。
        await FavoriteSyncEngine.shared.fullReconcile()

        let current = await FavoriteLocalStore.shared.load()
        await refreshStatesAndApply(members: current)
        if cloudKitReady {
            syncStatus = .success
            lastSyncTime = Date()
            lastSyncError = nil
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
        // 多维度冲突判断:同平台下 userId 或 roomId 任一有效维度命中已有收藏,即视为已收藏,不再重复添加。
        if roomList.contains(where: { AppFavoriteModel.isSameStreamer($0, room) }) {
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

        // 云端同步(非阻塞):交给 CKSyncEngine 入队,引擎自带退避/续传。
        if favoriteICloudSyncEnabled {
            startCloudSyncIfNeeded()
            FavoriteSyncEngine.shared.enqueueSave(room)
            lastSyncError = nil
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

        // 云端删除(非阻塞):交给 CKSyncEngine 入队。
        if favoriteICloudSyncEnabled {
            startCloudSyncIfNeeded()
            FavoriteSyncEngine.shared.enqueueDelete(room)
            lastSyncError = nil
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
    /// 规整一个标识字段:非空、非 "0"、去空白后才算「有效维度」,否则返回 nil。
    static func validIdentity(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t == "0") ? nil : t
    }

    /// 多维度判断是否同一主播(平台无关)。同平台下,userId 或 roomId 任一**有效维度**
    /// 相同即视为同一主播。这样不依赖平台适配也能罩住脏数据:
    /// - userId 时有时无(空/0)的平台靠 roomId 命中;
    /// - roomId 每场直播会变的平台靠 userId 命中。
    static func isSameStreamer(_ a: LiveModel, _ b: LiveModel) -> Bool {
        guard a.liveType.rawValue == b.liveType.rawValue else { return false }
        if let au = validIdentity(a.userId), let bu = validIdentity(b.userId), au == bu { return true }
        if let ar = validIdentity(a.roomId), let br = validIdentity(b.roomId), ar == br { return true }
        return false
    }

    /// 刷新后判断是否发生**值得回写**的身份变化。身份回写**只服务于声明了
    /// `favoriteIdentityKey: userId` 的平台**(roomId 每场会变、userId 稳定)。
    ///
    /// 默认 `roomId` 身份平台一律返回 false,**不自动回写**,原因:
    /// 1. roomId 即主键且通常稳定,无需回写;
    /// 2. roomId 的"变化"无法区分「真换房」与「占位漂移」——部分平台(如主播未直播时)
    ///    `getRoomDetail` 会返回**共享占位 roomId + userId=0**,多个主播漂到同一占位值。
    ///    若据此回写会把不同主播 re-key 到同一 recordName → CloudKit 碰撞、互相覆盖
    ///    (实测 "record to insert already exists" / Server Record Changed 14/2004)。
    /// 这正是设计 §2.3/§8 的危险组合;这类平台要么 roomId 稳定(无需回写),要么应在
    /// manifest 声明 `preserveFavoriteRoomInfoOnRefresh` 保留原房间信息。
    ///
    /// 也故意**不**把昵称/标题/封面/头像纳入触发条件:高频快照若当触发器会导致几乎每次
    /// 刷新都全量回写 → 写放大(§3 R3)。快照仍随记录上云(makeRecord 写全字段),只是不单独触发。
    static func favoriteIdentityChanged(old: LiveModel, new: LiveModel) -> Bool {
        guard PlatformHostBehavior.favoriteIdentityKey(for: old.liveType) == .userId else {
            return false
        }
        // userId 稳定身份平台:userId 补全,或 userId 仍有效前提下每场换 roomId。
        // 防降级:新 id 必须有效(validIdentity),绝不把有效值回写成空/"0"。
        if let nu = validIdentity(new.userId), validIdentity(old.userId) != nu { return true }
        if validIdentity(new.userId) != nil,
           let nr = validIdentity(new.roomId), validIdentity(old.roomId) != nr { return true }
        return false
    }

    /// 按多维度身份去重(同平台 userId 或 roomId 任一有效维度相同即合并),保留先到的。
    static func deduplicated(_ rooms: [LiveModel]) -> [LiveModel] {
        var byUser: [String: Int] = [:]   // "liveType|userId" -> result 下标
        var byRoom: [String: Int] = [:]   // "liveType|roomId" -> result 下标
        var result: [LiveModel] = []
        result.reserveCapacity(rooms.count)
        for room in rooms {
            let lt = room.liveType.rawValue
            let uKey = validIdentity(room.userId).map { "\(lt)|\($0)" }
            let rKey = validIdentity(room.roomId).map { "\(lt)|\($0)" }
            if let uKey, byUser[uKey] != nil { continue }
            if let rKey, byRoom[rKey] != nil { continue }
            let idx = result.count
            result.append(room)
            if let uKey { byUser[uKey] = idx }
            if let rKey { byRoom[rKey] = idx }
        }
        return result
    }

    /// 收藏同步主键(CKRecord recordName)。按平台 `favoriteIdentityKey` 选主键身份,保留
    /// `_r_/_u_/_n_` 桶前缀,把 ""/"0"/纯空白统一视为"无效"(避免 `_u_0` 这类碰撞桶)。
    ///
    /// - 默认(`.roomId`):roomId 优先、userId 兜底。历史教训:userId 来自各平台插件常空/为 "0"
    ///   (不准),无脑用它当主键会导致同一主播跨时刻/设备生成不同 key → 对不齐、留多份。
    /// - `.userId`(平台 manifest 显式声明):userId 优先、roomId 兜底。用于「roomId 每场会变、
    ///   userId 稳定」的平台,让 recordName 不随 roomId 漂移、同一主播始终一条记录。
    ///
    /// ⚠️ 升级注意:`reKeyRepair.v1` 只跑一次。日后**新增**某平台为 `.userId` 身份时,其存量
    /// recordName 不会自动收敛 —— 那时必须 bump `FavoriteSyncEngine.reKeyRepair` → v2 重跑对账。
    static func favoriteUniqueKey(for room: LiveModel) -> String {
        let liveType = room.liveType.rawValue
        let roomId = validIdentity(room.roomId)
        let userId = validIdentity(room.userId)
        switch PlatformHostBehavior.favoriteIdentityKey(for: room.liveType) {
        case .userId:
            if let userId { return "\(liveType)_u_\(userId)" }
            if let roomId { return "\(liveType)_r_\(roomId)" }
        case .roomId:
            if let roomId { return "\(liveType)_r_\(roomId)" }
            if let userId { return "\(liveType)_u_\(userId)" }
        }
        return "\(liveType)_n_\(room.userName.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
