//
//  PlaylistSyncService.swift
//  AngelLiveCore
//
//  播放列表实例的 iCloud 同步。整份「实例 + 删除墓碑」存为私有库中的一条记录，
//  各端拉取 → 合并 → 以 change tag 条件写回；冲突时重新拉取合并。
//

import CloudKit
import Foundation

// MARK: - 合并

enum PlaylistSyncMerge {
    /// 逐个实例按时间戳取最新：实例取 updatedAt，删除取墓碑时间；时间相同时删除优先。
    /// 实例 ID 不变，收藏与历史挂在 `playlist:<UUID>` 上，跨设备保持可用。
    static func merge(_ local: PlaylistInstanceSnapshot, _ remote: PlaylistInstanceSnapshot) -> PlaylistInstanceSnapshot {
        enum Candidate {
            case live(PlaylistInstance)
            case deleted(Date)

            var date: Date {
                switch self {
                case .live(let instance): instance.updatedAt
                case .deleted(let date): date
                }
            }
        }

        func newer(_ lhs: Candidate?, _ rhs: Candidate?) -> Candidate? {
            guard let lhs else { return rhs }
            guard let rhs else { return lhs }
            if lhs.date != rhs.date { return lhs.date > rhs.date ? lhs : rhs }
            if case .deleted = lhs { return lhs }
            return rhs
        }

        func candidates(_ snapshot: PlaylistInstanceSnapshot) -> [UUID: Candidate] {
            var result: [UUID: Candidate] = [:]
            for instance in snapshot.instances {
                result[instance.id] = newer(result[instance.id], .live(instance))
            }
            for (id, date) in snapshot.tombstones {
                result[id] = newer(result[id], .deleted(date))
            }
            return result
        }

        let localCandidates = candidates(local)
        let remoteCandidates = candidates(remote)

        // 保持顺序：先本地顺序，再远端新增。
        var order: [UUID] = []
        var seen = Set<UUID>()
        for id in local.instances.map(\.id) + remote.instances.map(\.id) where seen.insert(id).inserted {
            order.append(id)
        }

        var instances: [PlaylistInstance] = []
        var tombstones: [UUID: Date] = [:]
        for id in Set(localCandidates.keys).union(remoteCandidates.keys) {
            switch newer(localCandidates[id], remoteCandidates[id]) {
            case .live(let instance)?:
                instances.append(instance)
            case .deleted(let date)?:
                tombstones[id] = date
            case nil:
                break
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        instances.sort { (rank[$0.id] ?? .max, $0.createdAt) < (rank[$1.id] ?? .max, $1.createdAt) }
        return PlaylistInstanceSnapshot(instances: instances, tombstones: tombstones)
    }
}

// MARK: - 云端存储

struct PlaylistCloudPayload: Sendable {
    let snapshot: PlaylistInstanceSnapshot
    /// 不透明的版本标识，用于条件写入。nil 表示云端尚无记录。
    let version: CKRecord?
}

enum PlaylistCloudWriteResult: Sendable {
    case saved
    case conflict
}

protocol PlaylistCloudStoring: Sendable {
    func fetch() async throws -> PlaylistCloudPayload
    func save(_ snapshot: PlaylistInstanceSnapshot, over version: CKRecord?) async throws -> PlaylistCloudWriteResult
}

struct CloudKitPlaylistStore: PlaylistCloudStoring {
    static let containerIdentifier = "iCloud.icloud.dev.igod.simplelive"
    static let recordType = "playlist_instances"
    static let recordName = "user_playlist_instances"
    static let payloadField = "payload"
    static let updatedAtField = "updated_at"

    private var database: CKDatabase {
        CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
    }

    private var recordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.recordName)
    }

    func fetch() async throws -> PlaylistCloudPayload {
        do {
            let record = try await database.record(for: recordID)
            guard let data = record[Self.payloadField] as? Data else {
                return PlaylistCloudPayload(snapshot: .empty, version: record)
            }
            return PlaylistCloudPayload(snapshot: try PlaylistInstanceSnapshot.decode(data), version: record)
        } catch let error as CKError where error.code == .unknownItem {
            return PlaylistCloudPayload(snapshot: .empty, version: nil)
        }
    }

    func save(_ snapshot: PlaylistInstanceSnapshot, over version: CKRecord?) async throws -> PlaylistCloudWriteResult {
        let record = version ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.payloadField] = try JSONEncoder().encode(snapshot) as NSData
        record[Self.updatedAtField] = Date() as NSDate
        do {
            // 默认保存策略只在 change tag 一致时写入，其他设备先写时返回冲突。
            _ = try await database.save(record)
            return .saved
        } catch let error as CKError where error.code == .serverRecordChanged {
            return .conflict
        }
    }
}

// MARK: - 同步服务

public actor PlaylistSyncService {
    public static let shared = PlaylistSyncService(
        store: .shared,
        cloud: CloudKitPlaylistStore(),
        isEnabled: { PlatformCredentialSyncService.iCloudSyncSettingEnabled }
    )

    public enum Outcome: Sendable, Equatable {
        case disabled
        case synced(changedLocally: Bool)
        case skipped
        case failed(String)
    }

    private static let maxConflictRetries = 3

    private let store: PlaylistInstanceStore
    private let cloud: any PlaylistCloudStoring
    private let isEnabled: @Sendable () -> Bool
    private var running: Task<Outcome, Never>?
    private var pendingRerun = false
    private var observer: (any NSObjectProtocol)?
    private var activeObservers: [any NSObjectProtocol] = []

    init(
        store: PlaylistInstanceStore,
        cloud: any PlaylistCloudStoring,
        isEnabled: @escaping @Sendable () -> Bool
    ) {
        self.store = store
        self.cloud = cloud
        self.isEnabled = isEnabled
    }

    /// 宿主启动时调用：立即同步一次，并在本地增删改后自动同步。
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .playlistInstancesDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // 同步自身写入的变更不再触发同步，避免循环。
            let source = notification.userInfo?[Notification.Name.playlistChangeSourceKey] as? String
            guard source != PlaylistInstanceStore.syncChangeSource, let self else { return }
            Task { await self.sync() }
        }
        // 回到前台时拉取其他设备的改动。用系统通知名字符串，Core 不依赖 UIKit/AppKit。
        for name in ["UIApplicationDidBecomeActiveNotification", "NSApplicationDidBecomeActiveNotification"] {
            activeObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.sync() }
            })
        }
        Task { await self.sync() }
    }

    /// 合并同一时间的多次触发：进行中时只追加一次重跑。
    @discardableResult
    public func sync() async -> Outcome {
        if let running {
            pendingRerun = true
            return await running.value
        }
        let task = Task { await self.performSync() }
        running = task
        var outcome = await task.value
        running = nil
        if pendingRerun {
            pendingRerun = false
            outcome = await sync()
        }
        return outcome
    }

    private func performSync() async -> Outcome {
        guard isEnabled() else { return .disabled }
        var changedLocally = false
        do {
            for _ in 0..<Self.maxConflictRetries {
                guard let local = store.snapshot() else { return .skipped }
                let remote = try await cloud.fetch()
                let merged = PlaylistSyncMerge.merge(local, remote.snapshot)

                if merged != local {
                    guard try store.applySynced(merged, expected: local) else {
                        // 本地刚有新改动，重新合并。
                        continue
                    }
                    changedLocally = true
                    await afterLocalChange(old: local, new: merged)
                }
                if merged == remote.snapshot, remote.version != nil {
                    return .synced(changedLocally: changedLocally)
                }
                switch try await cloud.save(merged, over: remote.version) {
                case .saved:
                    return .synced(changedLocally: changedLocally)
                case .conflict:
                    continue
                }
            }
            return .failed("同步冲突，请稍后重试。")
        } catch {
            let message = SyncError.from(error).displayText
            Logger.warning("Playlist iCloud sync failed: \(type(of: error))", category: .general)
            return .failed(message)
        }
    }

    /// 远端带来的删除清缓存，新增或改图标的实例预取图标。
    private func afterLocalChange(old: PlaylistInstanceSnapshot, new: PlaylistInstanceSnapshot) async {
        let remaining = Set(new.instances.map(\.id))
        for instance in old.instances where !remaining.contains(instance.id) {
            await PlaylistPlatformService.shared.removeCache(instanceID: instance.id)
        }
        for instance in new.instances {
            if let iconURL = instance.iconURL, PlaylistIconCache.cachedFileURL(for: instance) == nil {
                await PlaylistIconCache.fetch(iconURL: iconURL)
            }
        }
    }
}
