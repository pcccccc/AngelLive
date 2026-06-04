//
//  FavoriteSyncEngine.swift
//  AngelLiveCore
//
//  收藏的 CKSyncEngine 同步引擎(Phase③,见 docs/SyncResilienceAndErrorModel.md)。
//
//  分工:
//  - 本地真相 = FavoriteLocalStore(Phase②)。
//  - 本引擎只负责「收藏成员关系(增/删/拉列表)」在本地与 iCloud **自定义 Zone** 之间的增量对齐;
//    自带退避/续传/读 retryAfter/增量。
//  - 直播状态刷新(逐房间 API)不走本引擎,仍由上层在本地列表上做。
//
//  灰度策略:迁移即切换(用户已确认)。首次启动把旧默认 Zone 的 favorite_streamers
//  记录一次性导入自定义 Zone;不删除默认 Zone 记录(旧版本设备仍在用)。
//
//  注:CKSyncEngine 需要 iOS/macOS/tvOS 17+,本包部署目标满足。
//

import Foundation
import CloudKit

public final class FavoriteSyncEngine: @unchecked Sendable {
    public static let shared = FavoriteSyncEngine()

    // MARK: - 配置

    private let containerID = "iCloud.icloud.dev.igod.simplelive"
    private let zoneName = "FavoritesZone"
    private static let recordType = "favorite_streamers"
    private let zoneID: CKRecordZone.ID
    private let container: CKContainer

    private var engine: CKSyncEngine?

    /// 引擎从云端拉到变更后,回调上层在主线程刷新 roomList。
    public var onRemoteChange: (@Sendable () async -> Void)?

    private static let migrationDoneKey = "FavoriteSyncEngine.defaultZoneMigrationDone.v1"

    /// 一次性「re-key 全量对账」标记。修复历史上 userId 主键导致的 key 分裂:
    /// 重置 token 全量拉一次,把所有 recordName 迁到稳定 key,
    /// 并删掉同一主播的多余记录。每个用户升级后自动跑一次,用户无感、无需重装。
    /// (稳定 key 见 AppFavoriteModel.favoriteUniqueKey,roomId 优先)
    private static let reKeyRepairKey = "FavoriteSyncEngine.reKeyRepair.v1"
    private var repairInProgress = false
    private var repairCanonical: [String: String] = [:]   // 稳定 key -> 已保留的 recordName

    private init() {
        container = CKContainer(identifier: containerID)
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - State 持久化

    private var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AngelLive", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("favorites-sync-state.dat")
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        do {
            let data = try PropertyListEncoder().encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            Logger.warning("保存 CKSyncEngine state 失败: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - 启动

    /// 启动引擎(幂等)。会触发一次增量拉取。
    public func start() {
        guard engine == nil else { return }
        // 一次性 re-key 全量对账:删掉 token 落盘 → 本次以 nil token 全量拉取,
        // 在 fetchedRecordZoneChanges 里把旧 key 迁到稳定 key、删重复。
        if !UserDefaults.standard.bool(forKey: Self.reKeyRepairKey) {
            try? FileManager.default.removeItem(at: stateURL)
            repairInProgress = true
            repairCanonical.removeAll()
            Logger.info("FavoriteSyncEngine: 启动一次性 re-key 全量对账(token 重置)", category: .general)
        }
        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        engine = CKSyncEngine(config)
        // 不确定点①(已主动处理):显式确保自定义 Zone 存在(幂等),不依赖隐式创建。
        // 若真机验证发现 CKSyncEngine 会自动建 Zone 导致重复,可移除此行。
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        Logger.info("FavoriteSyncEngine 已启动", category: .general)
    }

    // MARK: - 本地变更入队(由 AppFavoriteModel 在加/删收藏后调用)

    public func enqueueSave(_ room: LiveModel) {
        guard let engine else { return }
        let key = AppFavoriteModel.favoriteUniqueKey(for: room)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(forKey: key))])
        Logger.info("⏱️ enqueueSave key=\(key) → 催 sendChanges", category: .general)
        kickSend()
    }

    public func enqueueDelete(_ room: LiveModel) {
        guard let engine else { return }
        let key = AppFavoriteModel.favoriteUniqueKey(for: room)
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(forKey: key))])
        Logger.info("⏱️ enqueueDelete key=\(key) → 催 sendChanges", category: .general)
        kickSend()
    }

    /// 批量入队保存(用于全量对账把本地独有记录补推上云)。交给引擎自动同步发送。
    private func enqueueSaves(_ rooms: [LiveModel]) {
        guard let engine, !rooms.isEmpty else { return }
        let changes = rooms.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(forKey: AppFavoriteModel.favoriteUniqueKey(for: $0)))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    /// 显式催一次上传(不等 CKSyncEngine 自动调度/退避)。入队后调用以降低发送侧延迟。
    private func kickSend() {
        guard let engine else { return }
        Task {
            do { try await engine.sendChanges() } catch {
                Logger.warning("sendChanges 失败: \(error.localizedDescription)", category: .general)
            }
        }
    }

    /// 手动触发一次拉取(如回前台 / 网络恢复)。
    public func fetchChanges() async {
        guard let engine else { return }
        do { try await engine.fetchChanges() } catch {
            Logger.warning("fetchChanges 失败: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - 全量成员对账(不依赖 CKSyncEngine token)

    /// 直接查询自定义 zone 的所有 favorite_streamers,把本地缺的补上(只增不删)。
    /// 用途:CKSyncEngine 的增量 token 会漂(卡死后对端新增永远拉不到),
    /// 故下拉刷新/启动时做一次 authoritative 全量对账兜底。收藏量小(百级),成本极低。
    /// 只增不删:避免误删「本地刚加、尚未推上去」的记录;跨端删除仍走引擎正常路径。
    public func fullReconcile() async {
        let serverModels = await fetchAllZoneRecords()
        guard !serverModels.isEmpty else { return }   // 查询失败/空 → 不动本地
        let local = await FavoriteLocalStore.shared.load()
        // 拉:本地在前,多维度去重后本地优先保留、补入 server-only、合并已有重复。
        // 只增不删:本地里 server 没有的(刚加未推)会被保留(在 local 段、不会被丢)。
        let merged = AppFavoriteModel.deduplicated(local + serverModels)

        // 推:本地有、服务器任一维度都没有的记录 → 补推上云(只补缺口,已匹配的不重推,避免再造重复)。
        let localOnly = merged.filter { l in !serverModels.contains { AppFavoriteModel.isSameStreamer($0, l) } }
        enqueueSaves(localOnly)

        if merged.count != local.count {
            await FavoriteLocalStore.shared.save(merged)
            if let onRemoteChange { await onRemoteChange() }
        }
        if merged.count != local.count || !localOnly.isEmpty {
            Logger.info("fullReconcile: 本地 \(local.count)→\(merged.count),推 \(localOnly.count) 条(服务器 \(serverModels.count))", category: .general)
        }
    }

    /// 分页拉取 zone 内全部记录,按稳定 key 去重后返回。查询失败返回空。
    private func fetchAllZoneRecords() async -> [LiveModel] {
        let db = container.privateCloudDatabase
        var models: [LiveModel] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            do {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let c = cursor {
                    page = try await db.records(continuingMatchFrom: c)
                } else {
                    let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
                    page = try await db.records(matching: query, inZoneWith: zoneID,
                                                desiredKeys: nil,
                                                resultsLimit: CKQueryOperation.maximumResults)
                }
                for (_, result) in page.matchResults {
                    if let record = try? result.get(), let model = liveModel(from: record) {
                        models.append(model)
                    }
                }
                cursor = page.queryCursor
            } catch {
                Logger.warning("fullReconcile 查询失败: \(error.localizedDescription)", category: .general)
                return []
            }
        } while cursor != nil
        // 多维度去重:服务器若因 roomId 每场变而存了同主播多条,在此合并。
        return AppFavoriteModel.deduplicated(models)
    }

    // MARK: - 记录映射

    private func recordID(forKey key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: key, zoneID: zoneID)
    }

    private func makeRecord(room: LiveModel, recordID: CKRecord.ID) -> CKRecord {
        // 不确定点②:此处新建 CKRecord(不带服务端 system fields)。收藏以增/删为主,
        // 极少更新同一记录,故冲突概率低。若真机出现 serverRecordChanged,需缓存
        // sentRecordZoneChanges 回传的服务端记录、在此复用其 recordChangeTag。
        let rec = CKRecord(recordType: Self.recordType, recordID: recordID)
        rec["room_id"] = room.roomId as CKRecordValue
        rec["user_id"] = room.userId as CKRecordValue
        rec["user_name"] = room.userName as CKRecordValue
        rec["room_title"] = room.roomTitle as CKRecordValue
        rec["room_cover"] = room.roomCover as CKRecordValue
        rec["user_head_img"] = room.userHeadImg as CKRecordValue
        rec["live_type"] = room.liveType.rawValue as CKRecordValue
        rec["live_state"] = (room.liveState ?? "") as CKRecordValue
        return rec
    }

    private func liveModel(from record: CKRecord) -> LiveModel? {
        guard let liveType = LiveType(rawValue: record["live_type"] as? String ?? "") else { return nil }
        return LiveModel(
            userName: record["user_name"] as? String ?? "",
            roomTitle: record["room_title"] as? String ?? "",
            roomCover: record["room_cover"] as? String ?? "",
            userHeadImg: record["user_head_img"] as? String ?? "",
            liveType: liveType,
            liveState: record["live_state"] as? String ?? "",
            userId: record["user_id"] as? String ?? "",
            roomId: record["room_id"] as? String ?? "",
            liveWatchedCount: nil
        )
    }

    // MARK: - 应用云端变更到本地真相

    private func applyFetched(modifications: [CKRecord], deletions: [CKRecord.ID]) async {
        var rooms = await FavoriteLocalStore.shared.load()
        var byKey: [String: Int] = [:]
        for (i, r) in rooms.enumerated() { byKey[AppFavoriteModel.favoriteUniqueKey(for: r)] = i }

        for record in modifications {
            guard let model = liveModel(from: record) else { continue }
            let key = AppFavoriteModel.favoriteUniqueKey(for: model)
            if let idx = byKey[key] {
                rooms[idx] = model
            } else {
                rooms.append(model)
                byKey[key] = rooms.count - 1
            }
        }
        if !deletions.isEmpty {
            let deleteKeys = Set(deletions.map { $0.recordName })
            rooms.removeAll { deleteKeys.contains(AppFavoriteModel.favoriteUniqueKey(for: $0)) }
        }

        // 多维度去重:合并因 roomId 每场变而出现的同主播多条。
        rooms = AppFavoriteModel.deduplicated(rooms)
        await FavoriteLocalStore.shared.save(rooms)
        if let onRemoteChange { await onRemoteChange() }
    }

    // MARK: - 一次性 re-key 全量对账(把旧 recordName 迁到稳定 key + 删重复)

    /// 在全量拉取的每个批次上:对每条服务器记录算出稳定 key,
    /// - 若 recordName ≠ 稳定 key:删旧记录 + 以稳定 key 存新记录(re-key);
    /// - 若同一稳定 key 已保留过一条:这条是同主播的重复,删掉(保留先到的)。
    /// 本地侧由 applyFetched 按稳定 key 自动去重,故本方法只负责让**服务器**收敛。
    private func reKeyDuringRepair(records: [CKRecord]) {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for record in records {
            guard let model = liveModel(from: record) else { continue }
            let newKey = AppFavoriteModel.favoriteUniqueKey(for: model)
            let oldName = record.recordID.recordName
            if repairCanonical[newKey] != nil {
                // 同一主播的多余记录:删掉(但别删稳定 key 本体那条)
                if oldName != newKey {
                    changes.append(.deleteRecord(record.recordID))
                }
            } else {
                repairCanonical[newKey] = oldName
                if oldName != newKey {
                    changes.append(.deleteRecord(record.recordID))
                    changes.append(.saveRecord(recordID(forKey: newKey)))
                }
            }
        }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    // MARK: - 默认 Zone → 自定义 Zone 一次性迁移

    /// 把旧默认 Zone 的 favorite_streamers 导入自定义 Zone(幂等,基于 uniqueKey 作为 recordName)。
    public func migrateFromDefaultZoneIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.migrationDoneKey) else { return }
        guard let engine else { return }
        do {
            let legacy = try await FavoriteService.searchRecord()  // 读旧默认 Zone
            guard !legacy.isEmpty else {
                UserDefaults.standard.set(true, forKey: Self.migrationDoneKey)
                return
            }
            // 合并进本地真相
            var rooms = await FavoriteLocalStore.shared.load()
            var keys = Set(rooms.map { AppFavoriteModel.favoriteUniqueKey(for: $0) })
            var newSaves: [CKSyncEngine.PendingRecordZoneChange] = []
            for room in legacy {
                let key = AppFavoriteModel.favoriteUniqueKey(for: room)
                if !keys.contains(key) {
                    rooms.append(room)
                    keys.insert(key)
                }
                newSaves.append(.saveRecord(recordID(forKey: key)))
            }
            await FavoriteLocalStore.shared.save(rooms)
            engine.state.add(pendingRecordZoneChanges: newSaves)  // 推到自定义 Zone
            UserDefaults.standard.set(true, forKey: Self.migrationDoneKey)
            Logger.info("已迁移 \(legacy.count) 条收藏到自定义 Zone", category: .general)
            if let onRemoteChange { await onRemoteChange() }
        } catch {
            Logger.warning("默认 Zone 迁移失败,稍后重试: \(error.localizedDescription)", category: .general)
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension FavoriteSyncEngine: CKSyncEngineDelegate {

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            let mods = changes.modifications.map { $0.record }
            let dels = changes.deletions.map { $0.recordID }
            Logger.info("⏱️ fetchedRecordZoneChanges: 改\(mods.count) 删\(dels.count)", category: .general)
            if repairInProgress { reKeyDuringRepair(records: mods) }
            await applyFetched(modifications: mods, deletions: dels)

        case .sentRecordZoneChanges(let sent):
            Logger.info("⏱️ sentRecordZoneChanges: 成功存\(sent.savedRecords.count) 删\(sent.deletedRecordIDs.count) 失败\(sent.failedRecordSaves.count)", category: .general)
            for failed in sent.failedRecordSaves {
                Logger.warning("收藏记录上传失败: \(failed.record.recordID.recordName) - \(failed.error.localizedDescription)", category: .general)
            }

        case .willSendChanges:
            Logger.info("⏱️ willSendChanges(引擎开始上传)", category: .general)
        case .didSendChanges:
            Logger.info("⏱️ didSendChanges(本轮上传结束)", category: .general)
        case .willFetchChanges:
            Logger.info("⏱️ willFetchChanges(引擎开始拉取)", category: .general)
        case .didFetchChanges:
            Logger.info("⏱️ didFetchChanges(本轮拉取结束)", category: .general)
            if repairInProgress {
                repairInProgress = false
                UserDefaults.standard.set(true, forKey: Self.reKeyRepairKey)
                Logger.info("FavoriteSyncEngine: re-key 对账完成,稳定主键 \(repairCanonical.count) 个", category: .general)
                // 不在此(delegate 回调)里手动 sendChanges,否则 CKSyncEngine 会 fatalError。
                // re-key 的增删已入 pendingRecordZoneChanges,引擎自动同步会发出去。
            }

        case .fetchedDatabaseChanges, .sentDatabaseChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        let rooms = await FavoriteLocalStore.shared.load()
        let byKey = Dictionary(rooms.map { (AppFavoriteModel.favoriteUniqueKey(for: $0), $0) },
                               uniquingKeysWith: { _, latest in latest })

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self, let room = byKey[recordID.recordName] else { return nil }
            return self.makeRecord(room: room, recordID: recordID)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signOut, .switchAccounts:
            // 账号登出/切换:清掉本地云镜像状态(本地收藏保留,待重新登录再合并)。
            try? FileManager.default.removeItem(at: stateURL)
        case .signIn:
            break
        @unknown default:
            break
        }
    }
}
