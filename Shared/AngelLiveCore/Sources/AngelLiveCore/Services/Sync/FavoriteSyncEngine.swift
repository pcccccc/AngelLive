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
        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        engine = CKSyncEngine(config)
        Logger.info("FavoriteSyncEngine 已启动", category: .general)
    }

    // MARK: - 本地变更入队(由 AppFavoriteModel 在加/删收藏后调用)

    public func enqueueSave(_ room: LiveModel) {
        guard let engine else { return }
        let id = recordID(forKey: AppFavoriteModel.favoriteUniqueKey(for: room))
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    public func enqueueDelete(_ room: LiveModel) {
        guard let engine else { return }
        let id = recordID(forKey: AppFavoriteModel.favoriteUniqueKey(for: room))
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
    }

    /// 手动触发一次拉取(如回前台 / 网络恢复)。
    public func fetchChanges() async {
        guard let engine else { return }
        do { try await engine.fetchChanges() } catch {
            Logger.warning("fetchChanges 失败: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - 记录映射

    private func recordID(forKey key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: key, zoneID: zoneID)
    }

    private func makeRecord(room: LiveModel, recordID: CKRecord.ID) -> CKRecord {
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

        await FavoriteLocalStore.shared.save(rooms)
        if let onRemoteChange { await onRemoteChange() }
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
            await applyFetched(modifications: mods, deletions: dels)

        case .sentRecordZoneChanges(let sent):
            for failed in sent.failedRecordSaves {
                Logger.warning("收藏记录上传失败: \(failed.record.recordID.recordName) - \(failed.error.localizedDescription)", category: .general)
            }

        case .fetchedDatabaseChanges, .sentDatabaseChanges,
             .willFetchChanges, .didFetchChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges:
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
