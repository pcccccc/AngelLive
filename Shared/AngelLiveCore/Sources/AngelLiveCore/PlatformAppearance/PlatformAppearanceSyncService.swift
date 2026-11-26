import CloudKit
import Foundation
import Observation

public enum PlatformAppearanceSyncMerge {
    public static func merge(local: PlatformAppearanceSnapshot, remote: PlatformAppearanceSnapshot) -> PlatformAppearanceSnapshot {
        let local = local.normalized
        let remote = remote.normalized
        var merged = remote.globalUpdatedAt >= local.globalUpdatedAt ? remote : local
        let orderIsRemote = remote.orderUpdatedAt >= local.orderUpdatedAt
        let primary = orderIsRemote ? remote : local
        let secondary = orderIsRemote ? local : remote
        merged.orderedPluginIds = (primary.orderedPluginIds + secondary.orderedPluginIds).preservingFirstOccurrence
        merged.orderUpdatedAt = primary.orderUpdatedAt

        merged.idiomMetrics = [:]
        merged.idiomUpdatedAt = [:]
        for idiom in PlatformDeviceIdiom.allCases {
            let localDate = local.idiomUpdatedAt[idiom] ?? .distantPast
            let remoteDate = remote.idiomUpdatedAt[idiom] ?? .distantPast
            let winner = remoteDate >= localDate ? remote : local
            merged.idiomMetrics[idiom] = winner.idiomMetrics[idiom]
            merged.idiomUpdatedAt[idiom] = winner.idiomUpdatedAt[idiom]
        }

        merged.cardOverrides = local.cardOverrides.merging(remote.cardOverrides) {
            $0.updatedAt > $1.updatedAt ? $0 : $1
        }
        merged.resetTombstones = local.resetTombstones.merging(remote.resetTombstones, uniquingKeysWith: max)
        merged.allCardsResetAt = [local.allCardsResetAt, remote.allCardsResetAt].compactMap { $0 }.max()
        if let reset = merged.allCardsResetAt {
            merged.cardOverrides = merged.cardOverrides.filter { $0.value.updatedAt > reset }
            merged.resetTombstones = merged.resetTombstones.filter { $0.value > reset }
        }
        for (id, tombstone) in merged.resetTombstones {
            guard let card = merged.cardOverrides[id] else { continue }
            if card.updatedAt > tombstone {
                merged.resetTombstones.removeValue(forKey: id)
            } else {
                merged.cardOverrides.removeValue(forKey: id)
            }
        }
        return merged
    }
}

struct PlatformAppearanceCloudPayload: Sendable {
    let snapshot: PlatformAppearanceSnapshot
    let systemFields: Data?
}

enum PlatformAppearanceCloudWriteResult: Equatable, Sendable { case saved, conflict }

protocol PlatformAppearanceCloudStoring: Sendable {
    func accountScope() async throws -> String
    func fetch() async throws -> PlatformAppearanceCloudPayload
    func save(_ snapshot: PlatformAppearanceSnapshot, over systemFields: Data?) async throws -> PlatformAppearanceCloudWriteResult
    func fetchAsset(_ id: String) async throws -> Data?
    func saveAssetIfNeeded(_ data: Data, id: String) async throws
}

struct CloudKitPlatformAppearanceStore: PlatformAppearanceCloudStoring {
    private static let recordType = "platform_appearance"
    private static let assetRecordType = "platform_appearance_asset"
    private static let recordID = CKRecord.ID(recordName: "user_platform_appearance")

    func accountScope() async throws -> String {
        // The shared executor verifies the current macOS process entitlement before creating CKContainer.
        let recordName = try await LivePersistentSyncRetryExecutor().currentAccountScope()
        return PlatformAppearanceAssetCache.digest(for: Data(recordName.utf8))
    }

    private func database() throws -> CKDatabase {
        #if os(macOS)
        guard LivePersistentSyncRetryExecutor.hasCloudKitContainerEntitlement else { throw CKError(.notAuthenticated) }
        #endif
        return CKContainer(identifier: CloudKitPlaylistStore.containerIdentifier).privateCloudDatabase
    }

    func fetch() async throws -> PlatformAppearanceCloudPayload {
        do {
            let record = try await database().record(for: Self.recordID)
            guard let data = record["payload"] as? Data else { throw PlatformAppearanceStorageError.invalidCloudRecord }
            let fields = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: fields)
            fields.finishEncoding()
            return .init(snapshot: try PlatformAppearanceSnapshot.decode(data), systemFields: fields.encodedData)
        } catch let error as CKError where error.code == .unknownItem {
            return .init(snapshot: PlatformAppearanceSnapshot(), systemFields: nil)
        }
    }

    func save(_ snapshot: PlatformAppearanceSnapshot, over systemFields: Data?) async throws -> PlatformAppearanceCloudWriteResult {
        let record: CKRecord
        if let systemFields {
            let fields = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            fields.requiresSecureCoding = true
            defer { fields.finishDecoding() }
            guard let previous = CKRecord(coder: fields) else { throw PlatformAppearanceStorageError.invalidCloudRecord }
            record = previous
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: Self.recordID)
        }
        record["payload"] = try JSONEncoder().encode(snapshot) as NSData
        record["updated_at"] = Date.now as NSDate
        do {
            _ = try await database().save(record)
            return .saved
        } catch let error as CKError where error.code == .serverRecordChanged {
            return .conflict
        }
    }

    func fetchAsset(_ id: String) async throws -> Data? {
        let recordID = CKRecord.ID(recordName: "asset_\(id)")
        do {
            let record = try await database().record(for: recordID)
            guard let url = (record["asset"] as? CKAsset)?.fileURL, let digest = record["sha256"] as? String
            else { throw PlatformAppearanceStorageError.invalidCloudRecord }
            let data = try PlatformAppearanceAssetCache.readBoundedFile(url)
            guard PlatformAppearanceAssetCache.digest(for: data) == digest else {
                throw PlatformAppearanceAssetCache.AssetError.integrityMismatch
            }
            return data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveAssetIfNeeded(_ data: Data, id: String) async throws {
        let database = try database()
        let recordID = CKRecord.ID(recordName: "asset_\(id)")
        let records = try await database.records(for: [recordID], desiredKeys: ["sha256"])
        let digest = PlatformAppearanceAssetCache.digest(for: data)
        guard let existing = records[recordID] else { throw PlatformAppearanceStorageError.invalidCloudRecord }
        switch existing {
        case .success(let record):
            guard record["sha256"] as? String == digest else { throw PlatformAppearanceAssetCache.AssetError.integrityMismatch }
            return
        case .failure(let error):
            guard (error as? CKError)?.code == .unknownItem else { throw error }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        let record = CKRecord(recordType: Self.assetRecordType, recordID: recordID)
        record["asset"] = CKAsset(fileURL: url)
        record["sha256"] = digest as NSString
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Two devices can upload identical content to the same immutable record concurrently.
            guard error.serverRecord?["sha256"] as? String == digest else { throw error }
        }
    }
}

@MainActor
@Observable
public final class PlatformAppearanceSyncStatus {
    public fileprivate(set) var isSyncing = false
    public fileprivate(set) var lastSuccessfulSync: Date?
    public fileprivate(set) var outcome: PlatformAppearanceSyncService.Outcome?
}

public actor PlatformAppearanceSyncService {
    public enum Outcome: Equatable, Sendable {
        case disabled, synced, accountUnavailable, failed
    }

    public nonisolated static let settingKey = "SimpleLive.Setting.PlatformAppearanceICloudSyncEnabled"
    public nonisolated static var syncEnabled: Bool {
        return UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    @MainActor public static let status = PlatformAppearanceSyncStatus()
    @MainActor public static let shared = PlatformAppearanceSyncService(
        store: .shared, assets: .shared, cloud: CloudKitPlatformAppearanceStore(),
        status: status, fullUIAvailable: false,
        isEnabled: { syncEnabled && PlatformCredentialSyncService.iCloudSyncSettingEnabled }
    )

    private let store: PlatformAppearanceStore
    private let assets: PlatformAppearanceAssetCache
    private let cloud: any PlatformAppearanceCloudStoring
    private let status: PlatformAppearanceSyncStatus?
    private let isEnabled: @Sendable () -> Bool
    private var fullUIAvailable: Bool
    private var configuredEnabled = false
    private var observers: [any NSObjectProtocol] = []
    private var running: Task<Outcome, Never>?
    private var pending = false
    private var localChangeTask: Task<Void, Never>?
    private var lastOrphanCleanup: Date?

    init(store: PlatformAppearanceStore, assets: PlatformAppearanceAssetCache, cloud: any PlatformAppearanceCloudStoring,
         status: PlatformAppearanceSyncStatus? = nil, fullUIAvailable: Bool = true,
         isEnabled: @escaping @Sendable () -> Bool) {
        self.store = store
        self.assets = assets
        self.cloud = cloud
        self.status = status
        self.fullUIAvailable = fullUIAvailable
        self.isEnabled = isEnabled
    }

    public func start() {
        guard observers.isEmpty else { return }
        configuredEnabled = isEnabled()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .platformAppearanceDidChange, object: nil, queue: nil) { [weak self, store] notification in
            guard notification.object as? PlatformAppearanceStore === store,
                  notification.userInfo?[PlatformAppearanceStore.changeSourceKey] as? String
                    == PlatformAppearanceStore.ChangeSource.local.rawValue else { return }
            Task { await self?.scheduleLocalChange() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.settingsChanged() }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.accountChanged() }
        })
        for name in ["UIApplicationDidBecomeActiveNotification", "NSApplicationDidBecomeActiveNotification"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [weak self] _ in
                Task { await self?.sync() }
            })
        }
        if fullUIAvailable { Task { await sync() } }
    }

    public func setFullUIAvailable(_ available: Bool) async {
        guard !Task.isCancelled, available != fullUIAvailable else { return }
        fullUIAvailable = available
        if available {
            await sync()
        } else {
            pause()
        }
    }

    @discardableResult
    public func sync() async -> Outcome {
        guard fullUIAvailable, isEnabled() else { return .disabled }
        if let running {
            pending = true
            return await running.value
        }
        let task = Task { await runUntilIdle() }
        running = task
        return await task.value
    }

    private func runUntilIdle() async -> Outcome {
        await MainActor.run { status?.isSyncing = true }
        var result: Outcome
        repeat {
            pending = false
            result = await performSync()
        } while pending && !Task.isCancelled
        await MainActor.run {
            status?.isSyncing = false
            status?.outcome = result
            if result == .synced { status?.lastSuccessfulSync = .now }
        }
        running = nil
        if pending {
            Task { await sync() }
        }
        return result
    }

    private func scheduleLocalChange() {
        guard fullUIAvailable else { return }
        localChangeTask?.cancel()
        localChangeTask = Task {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await cleanOrphansIfNeeded()
            await sync()
        }
    }

    private func settingsChanged() async {
        let enabled = isEnabled()
        guard enabled != configuredEnabled else { return }
        configuredEnabled = enabled
        if enabled {
            await sync()
        } else {
            pause()
        }
    }

    private func accountChanged() async {
        pause()
        await MainActor.run { status?.lastSuccessfulSync = nil }
        await sync()
    }

    private func pause() {
        pending = false
        running?.cancel()
    }

    private func validateSession(_ scope: String? = nil) async throws {
        try Task.checkCancellation()
        guard fullUIAvailable, isEnabled() else { throw CancellationError() }
        if let scope {
            guard try await cloud.accountScope() == scope else { throw PlatformAppearanceStorageError.accountChanged }
            try Task.checkCancellation()
            guard fullUIAvailable, isEnabled() else { throw CancellationError() }
        }
    }

    private func performSync() async -> Outcome {
        do {
            try await validateSession()
            let scope = try await cloud.accountScope()
            try await validateSession()
            try await store.bind(to: scope)
            for _ in 0..<3 {
                try await validateSession()
                let local = await store.snapshot
                let remote = try await cloud.fetch()
                let merged = PlatformAppearanceSyncMerge.merge(local: local, remote: remote.snapshot)
                try await validateSession(scope)
                guard await store.snapshot == local else { continue }

                let missing = try await prepareAssets(for: merged, remote: remote.snapshot, scope: scope)
                if merged != remote.snapshot {
                    try await validateSession(scope)
                    guard await store.snapshot == local else { continue }
                    if try await cloud.save(merged, over: remote.systemFields) == .conflict { continue }
                }
                // Publish the merge only after the cloud accepted this version and the local edit still matches.
                try await validateSession(scope)
                guard await store.applySynced(merged, expected: local, scope: scope) else { continue }
                try await store.flush()
                await cleanOrphansIfNeeded()
                return missing ? .failed : .synced
            }
            return .failed
        } catch is CancellationError {
            return .disabled
        } catch let error as CKError where error.code == .notAuthenticated {
            return .accountUnavailable
        } catch {
            return .failed
        }
    }

    private func prepareAssets(
        for snapshot: PlatformAppearanceSnapshot, remote: PlatformAppearanceSnapshot, scope: String
    ) async throws -> Bool {
        var remoteAssetMissing = false
        let knownRemote = remote.referencedAssetIDs
        for id in snapshot.referencedAssetIDs.sorted() {
            try await validateSession()
            let localData: Data?
            do {
                localData = try await assets.data(for: id)
            } catch PlatformAppearanceAssetCache.AssetError.integrityMismatch {
                localData = nil
            } catch PlatformAppearanceAssetCache.AssetError.exceedsSizeLimit {
                localData = nil
            }
            if let localData {
                // Existing metadata can outlive its asset record. Check only the remote digest before uploading.
                try await validateSession(scope)
                try await cloud.saveAssetIfNeeded(localData, id: id)
            } else if let data = try await cloud.fetchAsset(id) {
                try await validateSession(scope)
                try await assets.storeDownloaded(data, assetID: id)
                await store.notifyDownloadedAsset()
            } else if knownRemote.contains(id) {
                remoteAssetMissing = true
            } else {
                // A missing local import must never create a dangling cloud reference.
                throw PlatformAppearanceStorageError.invalidCloudRecord
            }
        }
        return remoteAssetMissing
    }

    private func cleanOrphansIfNeeded() async {
        let now = Date.now
        guard lastOrphanCleanup.map({ now.timeIntervalSince($0) >= 86_400 }) ?? true else { return }
        lastOrphanCleanup = now
        if let retained = try? await store.retainedAssetIDs() {
            try? await assets.removeOrphans(retaining: retained, olderThan: now.addingTimeInterval(-7 * 86_400))
        }
    }
}
