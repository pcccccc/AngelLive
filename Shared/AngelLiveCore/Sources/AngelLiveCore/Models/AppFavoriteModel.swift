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
public enum CloudSyncStatus: Equatable {
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
    public private(set) var favoriteForegroundPhase: FavoriteForegroundPhase = .idle
    public private(set) var pluginRefreshPhases: [String: FavoritePluginRefreshPhase] = [:]
    /// 逐房间 freshness 是刷新内部 sidecar，不直接驱动整页 Observation。
    /// 页面若要展示单卡 freshness，应由卡片级模型订阅，不能让 100+ 条回写重算整页。
    @ObservationIgnored public private(set) var favoriteStatusFreshness: [String: FavoriteStatusFreshness] = [:]
    public private(set) var lastFavoriteRefreshSummary: FavoriteRefreshSummary?
    public private(set) var lastFavoriteRefreshTime: Date?
    public private(set) var currentFavoriteGenerationID: UUID?
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

    /// 收藏页顶部「正在同步收藏…」提示条是否展示:同步进行中即展示,完成/失败后自动隐藏。
    /// 非阻塞提示,与是否有本地缓存无关——本地收藏照常可交互。
    public var isCloudSyncing: Bool { syncStatus == .syncing }

    /// 直播状态刷新与 CloudKit 成员同步分别拥有状态；页面菊花只跟随前台预算。
    public var isFavoriteStatusRefreshing: Bool {
        if case .refreshing = favoriteForegroundPhase { return true }
        return false
    }

    public var pendingPluginIds: Set<String> {
        switch favoriteForegroundPhase {
        case .finished(_, let pending): pending
        case .refreshing:
            Set(pluginRefreshPhases.compactMap { pluginId, phase in
                if case .pending = phase { return pluginId }
                return nil
            })
        case .idle: []
        }
    }

    /// 云同步不可用时仅在本地也没有收藏可展示的情况下使用整页错误态。
    public var shouldShowBlockingCloudError: Bool { cloudReturnError && roomList.isEmpty }

    @ObservationIgnored private let refreshSession: FavoriteRefreshSession
    @ObservationIgnored private var refreshEventTask: Task<Void, Never>?
    @ObservationIgnored private var activeFavoriteRefreshGenerationID: UUID?
    @ObservationIgnored private var activeFavoriteForegroundCompletion: Task<Void, Never>?
    @ObservationIgnored private var patchFlushTask: Task<Void, Never>?
    @ObservationIgnored private var patchPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRoomPatches: [String: LiveModel] = [:]
    @ObservationIgnored private var hasFlushedFirstRoomPatch = false
    @ObservationIgnored private var favoriteLastConfirmedAt: [String: Date] = [:]
    @ObservationIgnored private var activePluginIDsByRoomKey: [String: String] = [:]
    @ObservationIgnored private var favoriteIdentityKeysByLiveType: [String: FavoriteIdentityKey] = [:]
    @ObservationIgnored private var latestPluginRefreshPhases: [String: FavoritePluginRefreshPhase] = [:]
    @ObservationIgnored private var cloudMembershipTask: Task<Void, Never>?
    @ObservationIgnored private var cloudMembershipGeneration: UUID?

    private enum Keys {
        static let favoriteICloudSyncEnabled = "AppFavoriteModel.favoriteICloudSyncEnabled"
    }

    public init(refreshSession: FavoriteRefreshSession = FavoriteRefreshSession()) {
        self.refreshSession = refreshSession
        if UserDefaults.standard.object(forKey: Keys.favoriteICloudSyncEnabled) == nil {
            self.favoriteICloudSyncEnabled = true   // 默认开启,保留旧行为
        } else {
            self.favoriteICloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.favoriteICloudSyncEnabled)
        }
    }

    public func freshness(for room: LiveModel) -> FavoriteStatusFreshness? {
        favoriteStatusFreshness[favoriteKey(for: room)]
    }

    private func favoriteKey(for room: LiveModel) -> String {
        let identityKey = favoriteIdentityKeysByLiveType[room.liveType.rawValue]
            ?? PlatformHostBehavior.favoriteIdentityKey(for: room.liveType)
        return AppFavoriteModel.favoriteUniqueKey(for: room, identityKey: identityKey)
    }

    // MARK: - Phase② 本地存储(本地优先)

    /// 把当前 roomList 落本地(fire-and-forget)。
    @MainActor
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

    /// 收藏同步引擎的一次性预热任务(建 CKContainer + start 引擎)。
    /// 缓存 Task 而非 bool:所有调用方都 await 同一个,保证返回时 engine 必已就绪
    /// (调用方随后立即 fetch/enqueue 依赖它),同时天然幂等。
    private var cloudSyncBootstrap: Task<Void, Never>?

    /// 启动收藏同步引擎(幂等):设回调 + 启动 + 首次默认 Zone 迁移。仅在 iCloud 开启时调用。
    ///
    /// 建 CKContainer + start 引擎不需要主线程,且冷启动时创建 CKContainer 会争 CloudKit
    /// 内部的 os_unfair_lock —— 放主线程会把启动关键路径卡死并被系统判为无响应(App Hang)。
    /// 故:首次触碰 `.shared`(触发 static let 的 dispatch_once → CKContainer 创建)放到
    /// 后台线程,再 await 其完成。既不阻塞主线程,又保证返回时 engine 已就绪。
    @MainActor
    private func startCloudSyncIfNeeded() async {
        if let bootstrap = cloudSyncBootstrap {
            await bootstrap.value
            return
        }
        let bootstrap = Task { @MainActor [weak self] in
            // .shared 的首次访问必须在后台线程,否则主线程会同步卡在 CKContainer 内部锁上。
            await Task.detached(priority: .userInitiated) {
                FavoriteSyncEngine.shared.start()
            }.value
            guard let self else { return }
            self.wireRemoteChange()
            Task { await FavoriteSyncEngine.shared.migrateFromDefaultZoneIfNeeded() }
        }
        cloudSyncBootstrap = bootstrap
        await bootstrap.value
    }

    /// 引擎拉到远端变更后回调上层刷新(独立 helper,避免在预热 Task 里嵌套捕获 self)。
    @MainActor
    private func wireRemoteChange() {
        FavoriteSyncEngine.shared.onRemoteChange = { @MainActor [weak self] in
            await self?.reloadFromLocalAfterRemoteChange()
        }
    }

    /// 以同步结束时的最新账号状态收口 UI，避免启动时的瞬时失败覆盖后续恢复结果。
    @MainActor
    func applyCloudState(isReady: Bool, message: String, now: Date = Date()) {
        cloudKitReady = isReady
        cloudKitStateString = message
        cloudReturnError = !isReady

        if isReady {
            syncStatus = .success
            lastSyncTime = now
            lastSyncError = nil
        } else {
            syncStatus = .notLoggedIn
        }
    }

    /// 引擎拉到远端成员变更后:用本地真相刷新列表(直播状态下次刷新时更新)。
    @MainActor
    private func reloadFromLocalAfterRemoteChange() async {
        let local = await FavoriteLocalStore.shared.load()
        applyMembershipSnapshot(local)
    }

    /// 成员同步只决定哪些收藏存在；已在内存中刷新的直播状态不被较旧成员快照覆盖。
    @MainActor
    private func applyMembershipSnapshot(_ members: [LiveModel]) {
        let current = roomList
        let merged = members.map { member in
            current.first(where: {
                favoriteKey(for: $0) == favoriteKey(for: member)
                    || AppFavoriteModel.isSameStreamer($0, member)
            }) ?? member
        }
        applyRoomList(merged)
    }

    /// 启动新代际并只等待页面前台预算；事件消费任务继续持有慢请求的增量结果。
    @MainActor
    func refreshStatesAndApply(
        members: [LiveModel],
        trigger: FavoriteRefreshTrigger
    ) async {
        if trigger == .automatic,
           let generationID = activeFavoriteRefreshGenerationID,
           let foregroundCompletion = activeFavoriteForegroundCompletion {
            Logger.debug(
                "[FavoriteRefresh] coalesced automatic refresh into generation=\(generationID)",
                category: .favorite
            )
            await foregroundCompletion.value
            return
        }

        guard !members.isEmpty else {
            refreshEventTask?.cancel()
            await refreshSession.cancel()
            activeFavoriteRefreshGenerationID = nil
            activeFavoriteForegroundCompletion = nil
            currentFavoriteGenerationID = nil
            favoriteForegroundPhase = .idle
            pluginRefreshPhases = [:]
            applyRoomList([])
            return
        }

        refreshEventTask?.cancel()
        patchFlushTask?.cancel()
        pendingRoomPatches.removeAll(keepingCapacity: true)
        hasFlushedFirstRoomPatch = false

        let handle = await refreshSession.start(members: members, trigger: trigger)
        activeFavoriteRefreshGenerationID = handle.generationID
        activeFavoriteForegroundCompletion = handle.foregroundCompletion
        currentFavoriteGenerationID = handle.generationID
        favoriteForegroundPhase = .refreshing(generationID: handle.generationID)
        lastFavoriteRefreshSummary = nil
        activePluginIDsByRoomKey = handle.pluginIDsByRoomKey
        favoriteIdentityKeysByLiveType = handle.identityKeysByLiveType

        var nextFreshness = favoriteStatusFreshness
        for key in handle.roomKeys {
            switch nextFreshness[key] {
            case .fresh(let date): favoriteLastConfirmedAt[key] = date
            case .stale(_, let date): favoriteLastConfirmedAt[key] = date
            case .refreshing, .none: break
            }
            nextFreshness[key] = .refreshing
        }
        favoriteStatusFreshness = nextFreshness
        latestPluginRefreshPhases = handle.pluginTotals.mapValues { .pending(completed: 0, total: $0) }
        // 一次发布初始插件状态，禁止逐房间初始化触发 Observation 风暴。
        pluginRefreshPhases = latestPluginRefreshPhases

        let events = handle.events
        let generationID = handle.generationID
        refreshEventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                await self.consumeFavoriteRefreshEvent(event)
            }
            guard let self,
                  self.activeFavoriteRefreshGenerationID == generationID else { return }
            self.activeFavoriteRefreshGenerationID = nil
            self.activeFavoriteForegroundCompletion = nil
        }
        await handle.foregroundCompletion.value
    }

    @MainActor
    private func consumeFavoriteRefreshEvent(_ event: FavoriteRefreshEvent) async {
        guard event.generationID == currentFavoriteGenerationID else {
            Logger.debug(
                "[FavoriteRefresh] dropped stale generation=\(event.generationID)",
                category: .favorite
            )
            return
        }

        switch event {
        case .started:
            break

        case .roomUpdated(_, let oldKey, let room):
            pendingRoomPatches[oldKey] = room
            let updatedAt = Date()
            favoriteLastConfirmedAt[oldKey] = updatedAt
            favoriteStatusFreshness[oldKey] = .fresh(updatedAt: updatedAt)
            if let pluginId = activePluginIDsByRoomKey[oldKey],
               case .pending(let completed, let total) = latestPluginRefreshPhases[pluginId] {
                latestPluginRefreshPhases[pluginId] = .reachable(completed: completed, total: total)
            }
            schedulePatchFlush(generationID: event.generationID)

        case .roomStale(_, let key, let reason):
            let lastUpdatedAt = favoriteLastConfirmedAt[key]
            favoriteStatusFreshness[key] = .stale(reason: reason, lastUpdatedAt: lastUpdatedAt)

        case .pluginProgress(_, let pluginId, let completed, let total):
            if case .unavailable = latestPluginRefreshPhases[pluginId] { break }
            if case .reachable = latestPluginRefreshPhases[pluginId] {
                latestPluginRefreshPhases[pluginId] = .reachable(completed: completed, total: total)
            } else {
                latestPluginRefreshPhases[pluginId] = .pending(completed: completed, total: total)
            }

        case .pluginUnavailable(_, let pluginId, let skipped):
            let total = pluginTotal(pluginId: pluginId)
            latestPluginRefreshPhases[pluginId] = .unavailable(skipped: skipped, total: total)
            // 保留结构化状态供诊断与测试；宿主只展示前台 loading，不产生失败提示。
            pluginRefreshPhases[pluginId] = latestPluginRefreshPhases[pluginId]

        case .foregroundFinished(_, let pendingPluginIds):
            // 页面预算结束时才发布一次精确插件进度。
            pluginRefreshPhases = latestPluginRefreshPhases
            favoriteForegroundPhase = .finished(
                generationID: event.generationID,
                pendingPluginIds: pendingPluginIds
            )
            lastFavoriteRefreshTime = Date()

        case .completed(_, let summary):
            patchFlushTask?.cancel()
            patchFlushTask = nil
            await flushRoomPatches(generationID: event.generationID)
            for plugin in summary.plugins {
                if case .unavailable = latestPluginRefreshPhases[plugin.pluginId] {
                    latestPluginRefreshPhases[plugin.pluginId] = .unavailable(
                        skipped: plugin.skipped,
                        total: plugin.total
                    )
                } else {
                    latestPluginRefreshPhases[plugin.pluginId] = .completed(
                        success: plugin.success,
                        failure: plugin.failure,
                        skipped: plugin.skipped
                    )
                }
            }
            pluginRefreshPhases = latestPluginRefreshPhases
            favoriteForegroundPhase = .finished(
                generationID: event.generationID,
                pendingPluginIds: []
            )
            lastFavoriteRefreshSummary = summary
            lastFavoriteRefreshTime = Date()
        }
    }

    @MainActor
    private func schedulePatchFlush(generationID: UUID) {
        guard patchFlushTask == nil else { return }
        let delay: Duration = hasFlushedFirstRoomPatch ? .milliseconds(750) : .milliseconds(150)
        patchFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            self.patchFlushTask = nil
            await self.flushRoomPatches(generationID: generationID)
        }
    }

    @MainActor
    private func flushRoomPatches(generationID: UUID) async {
        guard generationID == currentFavoriteGenerationID,
              !pendingRoomPatches.isEmpty else { return }
        let patches = pendingRoomPatches
        pendingRoomPatches.removeAll(keepingCapacity: true)
        var updated = roomList
        var identityChanges: [FavoriteIdentityChange] = []
        var indexByKey = Dictionary(
            updated.indices.map { (favoriteKey(for: updated[$0]), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var didApplyPatch = false

        for (oldKey, incoming) in patches {
            guard let index = indexByKey[oldKey] else { continue }
            let old = updated[index]
            var replacement = incoming
            let identityKey = favoriteIdentityKeysByLiveType[old.liveType.rawValue]
                ?? .roomId
            if AppFavoriteModel.favoriteIdentityChanged(
                old: old,
                new: incoming,
                identityKey: identityKey
            ) {
                replacement.identityUpdatedAt = Date()
                identityChanges.append(FavoriteIdentityChange(oldKey: oldKey, newRoom: replacement))
            }
            updated[index] = replacement
            didApplyPatch = true

            let newKey = AppFavoriteModel.favoriteUniqueKey(
                for: replacement,
                identityKey: identityKey
            )
            indexByKey[oldKey] = nil
            indexByKey[newKey] = index
            let freshness = favoriteStatusFreshness.removeValue(forKey: oldKey)
                ?? .fresh(updatedAt: Date())
            favoriteStatusFreshness[newKey] = freshness
            if let lastConfirmed = favoriteLastConfirmedAt.removeValue(forKey: oldKey) {
                favoriteLastConfirmedAt[newKey] = lastConfirmed
            }
            if let pluginId = activePluginIDsByRoomKey.removeValue(forKey: oldKey) {
                activePluginIDsByRoomKey[newKey] = pluginId
            }
        }

        guard didApplyPatch else { return }
        hasFlushedFirstRoomPatch = true
        applyRoomList(AppFavoriteModel.deduplicated(updated))

        guard favoriteICloudSyncEnabled, !identityChanges.isEmpty else {
            schedulePatchPersistence()
            return
        }
        // 身份回写必须先把新 key 落入本地真相；普通直播状态则走下方防抖持久化。
        patchPersistenceTask?.cancel()
        patchPersistenceTask = nil
        await FavoriteLocalStore.shared.save(roomList)
        await startCloudSyncIfNeeded()
        for change in identityChanges {
            FavoriteSyncEngine.shared.enqueueIdentityMetadataRefresh(
                oldKey: change.oldKey,
                room: change.newRoom
            )
        }
    }

    @MainActor
    private func schedulePatchPersistence() {
        patchPersistenceTask?.cancel()
        patchPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard let self else { return }
            let snapshot = self.roomList
            self.patchPersistenceTask = nil
            await FavoriteLocalStore.shared.save(snapshot)
        }
    }

    private func pluginTotal(pluginId: String) -> Int {
        switch latestPluginRefreshPhases[pluginId] {
        case .pending(_, let total), .reachable(_, let total), .unavailable(_, let total): total
        case .completed(let success, let failure, let skipped): success + failure + skipped
        case .none: 0
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
        guard let lastSync = lastFavoriteRefreshTime else {
            return true
        }

        // 如果距离上次同步超过1分钟，需要同步
        let timeInterval = Date().timeIntervalSince(lastSync)
        return timeInterval > 60 // 60秒 = 1分钟
    }

    @MainActor
    public func syncWithActor() async {
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

        // iCloud 关闭:纯本地,只刷新直播状态。
        guard favoriteICloudSyncEnabled else {
            await refreshStatesAndApply(members: roomList.isEmpty ? local : roomList, trigger: .automatic)
            isLoading = false
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        beginCloudMembershipSync()
        await refreshStatesAndApply(members: roomList.isEmpty ? local : roomList, trigger: .automatic)
        isLoading = false
    }

    /// 下拉刷新专用方法 - 不清空数据，保持 List 结构稳定
    @MainActor
    public func pullToRefresh() async {
        let local = await FavoriteLocalStore.shared.load()
        let members = roomList.isEmpty ? local : roomList

        // iCloud 关闭:纯本地刷新直播状态。
        guard favoriteICloudSyncEnabled else {
            await refreshStatesAndApply(members: members, trigger: .manual)
            cloudKitReady = false
            syncStatus = .success
            cloudKitStateString = "iCloud 同步已关闭(仅本地)"
            lastSyncError = nil
            return
        }

        beginCloudMembershipSync(force: true)
        await refreshStatesAndApply(members: members, trigger: .manual)
    }

    /// CloudKit 成员同步独立运行，不占用直播状态刷新前台预算。
    @MainActor
    private func beginCloudMembershipSync(force: Bool = false) {
        if cloudMembershipTask != nil, !force { return }
        cloudMembershipTask?.cancel()

        let generation = UUID()
        cloudMembershipGeneration = generation
        syncStatus = .syncing
        cloudReturnError = false
        cloudMembershipTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startCloudSyncIfNeeded()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }

            let state = await self.actor.getState()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }
            self.cloudKitReady = state.0
            self.cloudKitStateString = state.1

            await FavoriteSyncEngine.shared.fetchChanges()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }
            await FavoriteSyncEngine.shared.fullReconcile()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }

            let membership = await FavoriteLocalStore.shared.load()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }
            self.applyMembershipSnapshot(membership)
            self.syncProgressInfo = ("", "", "", 0, 0)
            let finalState = await self.actor.getState()
            guard !Task.isCancelled, self.cloudMembershipGeneration == generation else { return }
            self.applyCloudState(isReady: finalState.0, message: finalState.1)
            self.cloudMembershipTask = nil
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
            await startCloudSyncIfNeeded()
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
        let targetKey = favoriteKey(for: room)
        // 从 roomList 中删除
        roomList.removeAll(where: { favoriteKey(for: $0) == targetKey })

        // 从 groupedRoomList 中删除
        for index in groupedRoomList.indices {
            groupedRoomList[index].roomList.removeAll(where: { favoriteKey(for: $0) == targetKey })
        }
        groupedRoomList.removeAll(where: { $0.roomList.isEmpty })
        listVersion &+= 1
        persistLocal()

        // 云端删除(非阻塞):交给 CKSyncEngine 入队。
        if favoriteICloudSyncEnabled {
            await startCloudSyncIfNeeded()
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

    @MainActor
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
