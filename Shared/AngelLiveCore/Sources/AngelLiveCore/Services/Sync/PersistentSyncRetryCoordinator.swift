import CloudKit
import CryptoKit
import Foundation
#if os(macOS)
import Security
#endif

public struct LegacyFavoriteIdentity: Codable, Sendable, Equatable {
    public enum Field: String, Codable, Sendable {
        case userID
        case roomID
    }

    public let namespace: String
    public let stableKey: String
    public let field: Field
    public let value: String

    public init(namespace: String, stableKey: String, field: Field, value: String) {
        self.namespace = namespace
        self.stableKey = stableKey
        self.field = field
        self.value = value
    }

    init(room: LiveModel) {
        let userID = room.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomID = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesUserID = PlatformHostBehavior.favoriteIdentityKey(for: room.liveType) == .userId
            && !userID.isEmpty
            && userID != "0"
        self.init(
            namespace: room.liveType.rawValue,
            stableKey: AppFavoriteModel.favoriteUniqueKey(for: room),
            field: usesUserID ? .userID : .roomID,
            value: usesUserID ? userID : roomID
        )
    }
}

struct SyncSessionVersion: Codable, Sendable, Equatable {
    let metadataRevision: String
    let updatedAt: Date?
    let state: PlatformSessionState?
    let isPresent: Bool
}

struct PersistentSyncRetryMetadata: Codable, Sendable, Equatable {
    enum Domain: String, Codable, Sendable {
        case favoriteLegacyDelete
        case credentialUpload
        case credentialDownload
        case pluginSources
    }

    enum Operation: Codable, Sendable, Equatable {
        case favoriteLegacyDelete(LegacyFavoriteIdentity)
        case credentialUpload(pluginID: String, version: SyncSessionVersion)
        case credentialDownload(pluginID: String, version: SyncSessionVersion)
        case pluginSources(revision: UInt64, digest: String)
    }

    var revision: UUID
    var accountScope: String?
    var domain: Domain
    var itemID: String
    var operation: Operation
    var businessVersion: String
    var attempt: Int
    var notBefore: Date
    var lastError: SyncError?
    var paused: Bool
}

struct FavoriteRemovalIntent: Codable, Sendable, Equatable {
    var identity: LegacyFavoriteIdentity
    var revision: UUID
    var accountScope: String?
    var legacyComplete: Bool
    var zoneDeleteComplete: Bool
}

private struct PersistentSyncRetryState: Codable, Sendable, Equatable {
    var operations: [PersistentSyncRetryMetadata] = []
    var favoriteRemovals: [FavoriteRemovalIntent] = []
    var membershipRevision: UInt64 = 0
}

enum PersistentSyncExecutionResult: Sendable, Equatable {
    case complete
    case paused
}

protocol PersistentSyncRetryExecuting: Sendable {
    func currentAccountScope() async throws -> String
    func deleteLegacyFavorite(
        identity: LegacyFavoriteIdentity,
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws
    func execute(_ operation: PersistentSyncRetryMetadata.Operation) async throws -> PersistentSyncExecutionResult
}

struct LivePersistentSyncRetryExecutor: PersistentSyncRetryExecuting {
    func currentAccountScope() async throws -> String {
        // Creating CKContainer can synchronously require an entitled host process.
        // Keep coordinator construction side-effect free and touch CloudKit only
        // when account scope is actually requested by an enabled sync flow.
        #if os(macOS)
        guard Self.hasCloudKitContainerEntitlement else { throw CKError(.notAuthenticated) }
        #endif
        let container = CKContainer(identifier: "iCloud.icloud.dev.igod.simplelive")
        return try await container.userRecordID().recordName
    }

    #if os(macOS)
    private static var hasCloudKitContainerEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let identifiers = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return identifiers.contains("iCloud.icloud.dev.igod.simplelive")
    }
    #endif

    func deleteLegacyFavorite(
        identity: LegacyFavoriteIdentity,
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws {
        try await FavoriteService.deleteLegacyRecords(identity: identity, shouldContinue: shouldContinue)
    }

    func execute(_ operation: PersistentSyncRetryMetadata.Operation) async throws -> PersistentSyncExecutionResult {
        switch operation {
        case .favoriteLegacyDelete(let identity):
            try await FavoriteService.deleteLegacyRecords(identity: identity) { true }
            return .complete
        case .credentialUpload(let pluginID, let version):
            return try await PlatformCredentialSyncService.executePersistentUpload(
                pluginID: pluginID,
                expectedVersion: version
            )
        case .credentialDownload(let pluginID, let version):
            return try await PlatformCredentialSyncService.executePersistentDownload(
                pluginID: pluginID,
                expectedVersion: version
            )
        case .pluginSources(let revision, let digest):
            return try await PluginSourceSyncService.executePersistentSync(
                expectedRevision: revision,
                expectedDigest: digest
            )
        }
    }
}

@MainActor
public final class PersistentSyncRetryCoordinator {
    public static let shared = PersistentSyncRetryCoordinator()

    private let executor: any PersistentSyncRetryExecuting
    private let stateURL: URL
    private let now: @Sendable () -> Date
    private let resumeFavoriteDeletes: @MainActor @Sendable ([(stableKey: String, revision: UUID)]) async -> Void
    private var state: PersistentSyncRetryState
    private var fullUIEnabled = false
    private var credentialBackgroundRetriesEnabled = true
    private var verifiedAccountScope: String?
    private var accountEpoch = UUID()
    private struct RunningOperation {
        let revision: UUID
        let epoch: UUID
        let task: Task<Void, Never>
    }
    private var runningTasks: [String: RunningOperation] = [:]
    private var wakeTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var accountRetryAttempt = 0
    private var accountObserver: NSObjectProtocol?

    private convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("AngelLive", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.init(
            executor: LivePersistentSyncRetryExecutor(),
            stateURL: directory.appendingPathComponent("persistent-sync-retry-v1.plist"),
            now: Date.init,
            resumeFavoriteDeletes: { intents in
                let favoriteEngine = await Task.detached { FavoriteSyncEngine.shared }.value
                await favoriteEngine.resumePendingDeletes(intents)
            }
        )
    }

    init(
        executor: any PersistentSyncRetryExecuting,
        stateURL: URL,
        now: @escaping @Sendable () -> Date,
        resumeFavoriteDeletes: @escaping @MainActor @Sendable (
            [(stableKey: String, revision: UUID)]
        ) async -> Void = { _ in }
    ) {
        self.executor = executor
        self.stateURL = stateURL
        self.now = now
        self.resumeFavoriteDeletes = resumeFavoriteDeletes
        self.state = Self.loadState(from: stateURL)
        self.accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.invalidateAccountEpoch()
            }
        }
    }

    isolated deinit {
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
    }

    public func setFullUIEnabled(_ enabled: Bool) {
        guard fullUIEnabled != enabled else { return }
        fullUIEnabled = enabled
        if enabled {
            resumeTask?.cancel()
            resumeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.resumePendingOperations()
            }
        } else {
            resumeTask?.cancel()
            resumeTask = nil
            wakeTask?.cancel()
            wakeTask = nil
            for running in runningTasks.values { running.task.cancel() }
            runningTasks.removeAll()
            accountEpoch = UUID()
            verifiedAccountScope = nil
        }
    }

    func setCredentialBackgroundRetriesEnabled(_ enabled: Bool) {
        credentialBackgroundRetriesEnabled = enabled
        for index in state.operations.indices
        where state.operations[index].domain == .credentialUpload
            || state.operations[index].domain == .credentialDownload {
            state.operations[index].paused = !enabled
        }
        if !enabled {
            let keys = runningTasks.keys.filter {
                $0.hasPrefix("credentialUpload|") || $0.hasPrefix("credentialDownload|")
            }
            for key in keys {
                runningTasks.removeValue(forKey: key)?.task.cancel()
            }
        }
        try? persist()
        if enabled { scheduleEligibleOperations(epoch: accountEpoch) }
        scheduleNextWake()
    }

    public func resumePendingOperations() async {
        guard fullUIEnabled else { return }
        let epoch = accountEpoch
        do {
            let scope = try await executor.currentAccountScope()
            guard fullUIEnabled, epoch == accountEpoch else { return }
            verifiedAccountScope = scope
            accountRetryAttempt = 0
            for index in state.operations.indices where state.operations[index].accountScope == scope {
                let domain = state.operations[index].domain
                let isCredential = domain == .credentialUpload || domain == .credentialDownload
                if !isCredential || credentialBackgroundRetriesEnabled {
                    state.operations[index].paused = false
                }
            }
            try persist()
            scheduleEligibleOperations(epoch: epoch)
            let deletes = pendingFavoriteZoneDeleteIntents()
            if !deletes.isEmpty {
                await resumeFavoriteDeletes(deletes)
            }
        } catch {
            verifiedAccountScope = nil
            let syncError = SyncError.from(error)
            guard fullUIEnabled, epoch == accountEpoch, syncError.isRetryable else { return }
            accountRetryAttempt += 1
            let delay = Self.accountRetryDelay(attempt: accountRetryAttempt, error: syncError)
            resumeTask?.cancel()
            resumeTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.resumePendingOperations()
            }
        }
    }

    var isFullUIEnabled: Bool { fullUIEnabled }

    @discardableResult
    func recordFavoriteRemoval(_ room: LiveModel) throws -> UUID? {
        guard fullUIEnabled else { return nil }
        let identity = LegacyFavoriteIdentity(room: room)
        let revision = UUID()
        state.membershipRevision &+= 1
        state.favoriteRemovals.removeAll { $0.identity.stableKey == identity.stableKey }
        state.favoriteRemovals.append(.init(
            identity: identity,
            revision: revision,
            accountScope: verifiedAccountScope,
            legacyComplete: false,
            zoneDeleteComplete: false
        ))
        upsertOperation(.init(
            revision: revision,
            accountScope: verifiedAccountScope,
            domain: .favoriteLegacyDelete,
            itemID: favoriteItemID(identity),
            operation: .favoriteLegacyDelete(identity),
            businessVersion: revision.uuidString,
            attempt: 0,
            notBefore: now(),
            lastError: nil,
            paused: false
        ))
        try persist()
        scheduleEligibleOperations(epoch: accountEpoch)
        return revision
    }

    func recordFavoriteAddition(_ room: LiveModel) throws {
        guard fullUIEnabled else { return }
        let identity = LegacyFavoriteIdentity(room: room)
        state.membershipRevision &+= 1
        state.favoriteRemovals.removeAll { $0.identity.stableKey == identity.stableKey }
        state.operations.removeAll {
            $0.domain == .favoriteLegacyDelete && $0.itemID == favoriteItemID(identity)
        }
        try persist()
    }

    @discardableResult
    func enqueueCredentialUpload(pluginID: String, version: SyncSessionVersion) throws -> UUID {
        guard fullUIEnabled else { throw disabledError() }
        let revision = UUID()
        upsertOperation(.init(
            revision: revision,
            accountScope: verifiedAccountScope,
            domain: .credentialUpload,
            itemID: pluginID,
            operation: .credentialUpload(pluginID: pluginID, version: version),
            businessVersion: Self.sessionVersionString(version),
            attempt: 0,
            notBefore: now(),
            lastError: nil,
            paused: false
        ))
        try persist()
        return revision
    }

    @discardableResult
    func enqueueCredentialDownload(pluginID: String, version: SyncSessionVersion) throws -> UUID {
        guard fullUIEnabled else { throw disabledError() }
        let revision = UUID()
        upsertOperation(.init(
            revision: revision,
            accountScope: verifiedAccountScope,
            domain: .credentialDownload,
            itemID: pluginID,
            operation: .credentialDownload(pluginID: pluginID, version: version),
            businessVersion: Self.sessionVersionString(version),
            attempt: 0,
            notBefore: now(),
            lastError: nil,
            paused: false
        ))
        try persist()
        return revision
    }

    func runNowAndCollectFailures(revisions: [UUID]) async -> [SyncError] {
        guard fullUIEnabled else { return [] }
        if verifiedAccountScope == nil { await resumePendingOperations() }
        let epoch = accountEpoch
        for revision in revisions {
            guard var snapshot = operation(revision: revision) else { continue }
            guard snapshot.accountScope != nil else {
                snapshot.lastError = Self.unboundAccountError()
                snapshot.paused = true
                replaceOperation(snapshot)
                try? persist()
                continue
            }
            let key = operationKey(snapshot)
            if let existing = runningTasks[key] {
                await existing.task.value
                if existing.revision == revision {
                    continue
                }
                guard let refreshed = operation(revision: revision) else { continue }
                snapshot = refreshed
            }
            let operationSnapshot = snapshot
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.execute(operationSnapshot, key: key, epoch: epoch)
            }
            runningTasks[key] = .init(revision: operationSnapshot.revision, epoch: epoch, task: task)
            await task.value
        }
        return revisions.compactMap { operation(revision: $0)?.lastError }
    }

    func enqueuePluginSources(revision: UInt64, digest: String) throws {
        guard fullUIEnabled else { return }
        let operationRevision = UUID()
        upsertOperation(.init(
            revision: operationRevision,
            accountScope: verifiedAccountScope,
            domain: .pluginSources,
            itemID: "source-list",
            operation: .pluginSources(revision: revision, digest: digest),
            businessVersion: "\(revision):\(digest)",
            attempt: 0,
            notBefore: now(),
            lastError: nil,
            paused: false
        ))
        try persist()
        scheduleEligibleOperations(epoch: accountEpoch)
    }

    func isFavoriteRemovalPending(stableKey: String) -> Bool {
        state.favoriteRemovals.contains { $0.identity.stableKey == stableKey }
    }

    func favoriteMembershipRevision() -> UInt64 {
        state.membershipRevision
    }

    func favoriteMembershipIsCurrent(_ revision: UInt64) -> Bool {
        state.membershipRevision == revision
    }

    func pendingFavoriteZoneDeleteIntents() -> [(stableKey: String, revision: UUID)] {
        guard let scope = verifiedAccountScope else { return [] }
        return state.favoriteRemovals
            .filter { !$0.zoneDeleteComplete && $0.accountScope == scope }
            .map { ($0.identity.stableKey, $0.revision) }
    }

    func pendingMetadataForTesting() -> [PersistentSyncRetryMetadata] {
        state.operations
    }

    func favoriteRemovalsForTesting() -> [FavoriteRemovalIntent] {
        state.favoriteRemovals
    }

    func markFavoriteZoneDeleteComplete(stableKey: String, revision: UUID) {
        guard let scope = verifiedAccountScope,
              let index = state.favoriteRemovals.firstIndex(where: {
                  $0.identity.stableKey == stableKey && $0.revision == revision && $0.accountScope == scope
              }) else {
            return
        }
        state.favoriteRemovals[index].zoneDeleteComplete = true
        finishFavoriteRemovalIfComplete(at: index)
        try? persist()
    }

    func favoriteRemovalIsCurrent(stableKey: String, revision: UUID) -> Bool {
        guard let scope = verifiedAccountScope else { return false }
        return state.favoriteRemovals.contains {
            $0.identity.stableKey == stableKey && $0.revision == revision && $0.accountScope == scope
        }
    }

    func shouldContinueLegacyDelete(identity: LegacyFavoriteIdentity, revision: UUID) async -> Bool {
        guard fullUIEnabled, let scope = verifiedAccountScope else { return false }
        return state.favoriteRemovals.contains {
            $0.identity == identity && $0.revision == revision && $0.accountScope == scope
        }
    }

    private func upsertOperation(_ operation: PersistentSyncRetryMetadata) {
        state.operations.removeAll {
            $0.domain == operation.domain && $0.itemID == operation.itemID
        }
        state.operations.append(operation)
    }

    private func favoriteItemID(_ identity: LegacyFavoriteIdentity) -> String {
        "\(identity.namespace)|\(identity.stableKey)"
    }

    private func scheduleEligibleOperations(epoch: UUID) {
        guard fullUIEnabled, let scope = verifiedAccountScope else { return }
        let eligible = state.operations.filter {
            $0.accountScope == scope && !$0.paused && $0.notBefore <= now()
                && $0.lastError?.isRetryable != false
        }
        for operation in eligible {
            let key = "\(operation.domain.rawValue)|\(operation.itemID)"
            guard runningTasks[key] == nil else { continue }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.execute(operation, key: key, epoch: epoch)
            }
            runningTasks[key] = .init(revision: operation.revision, epoch: epoch, task: task)
        }
        scheduleNextWake()
    }

    private func execute(_ snapshot: PersistentSyncRetryMetadata, key: String, epoch: UUID) async {
        defer {
            if runningTasks[key]?.revision == snapshot.revision,
               runningTasks[key]?.epoch == epoch {
                runningTasks.removeValue(forKey: key)
            }
            scheduleEligibleOperations(epoch: accountEpoch)
        }
        guard fullUIEnabled, !Task.isCancelled, epoch == accountEpoch,
              let scope = verifiedAccountScope,
              operation(revision: snapshot.revision)?.accountScope == scope else { return }
        do {
            let result: PersistentSyncExecutionResult
            if case .favoriteLegacyDelete(let identity) = snapshot.operation {
                try await executor.deleteLegacyFavorite(identity: identity) { [weak self] in
                    await self?.shouldContinueLegacyDelete(identity: identity, revision: snapshot.revision) == true
                }
                result = .complete
            } else {
                result = try await executor.execute(snapshot.operation)
            }
            guard fullUIEnabled, epoch == accountEpoch,
                  let current = operation(revision: snapshot.revision),
                  current.accountScope == verifiedAccountScope else { return }
            switch result {
            case .complete:
                state.operations.removeAll { $0.revision == snapshot.revision }
                if snapshot.domain == .favoriteLegacyDelete,
                   let index = state.favoriteRemovals.firstIndex(where: { $0.revision == snapshot.revision }) {
                    state.favoriteRemovals[index].legacyComplete = true
                    finishFavoriteRemovalIfComplete(at: index)
                }
            case .paused:
                if var current = operation(revision: snapshot.revision) {
                    current.paused = true
                    replaceOperation(current)
                }
            }
            try persist()
        } catch is CancellationError {
            return
        } catch {
            guard fullUIEnabled, epoch == accountEpoch,
                  var current = operation(revision: snapshot.revision) else { return }
            let syncError = SyncError.from(error)
            current.attempt += 1
            current.lastError = Self.persistableError(syncError)
            if syncError.isRetryable {
                let exponential = min(pow(2, Double(current.attempt)), 3_600)
                current.notBefore = now().addingTimeInterval(max(exponential, syncError.serverRetryAfter ?? 0))
            }
            replaceOperation(current)
            try? persist()
        }
    }

    private func operation(revision: UUID) -> PersistentSyncRetryMetadata? {
        state.operations.first { $0.revision == revision }
    }

    private func replaceOperation(_ operation: PersistentSyncRetryMetadata) {
        guard let index = state.operations.firstIndex(where: { $0.revision == operation.revision }) else { return }
        state.operations[index] = operation
    }

    private func finishFavoriteRemovalIfComplete(at index: Int) {
        guard state.favoriteRemovals.indices.contains(index) else { return }
        let intent = state.favoriteRemovals[index]
        guard intent.legacyComplete, intent.zoneDeleteComplete else { return }
        state.favoriteRemovals.remove(at: index)
    }

    private func scheduleNextWake() {
        wakeTask?.cancel()
        guard fullUIEnabled, let scope = verifiedAccountScope,
              let next = state.operations
                .filter({ operation in
                    operation.accountScope == scope && !operation.paused
                        && operation.lastError?.isRetryable == true
                        && operation.notBefore > now()
                        && runningTasks[operationKey(operation)] == nil
                })
                .map(\.notBefore).min() else { return }
        let delay = max(0, next.timeIntervalSince(now()))
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.scheduleEligibleOperations(epoch: self.accountEpoch)
        }
    }

    private func invalidateAccountEpoch() {
        accountEpoch = UUID()
        verifiedAccountScope = nil
        resumeTask?.cancel()
        resumeTask = nil
        for running in runningTasks.values { running.task.cancel() }
        runningTasks.removeAll()
        wakeTask?.cancel()
        wakeTask = nil
        guard fullUIEnabled else { return }
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resumePendingOperations()
        }
    }

    private func operationKey(_ operation: PersistentSyncRetryMetadata) -> String {
        "\(operation.domain.rawValue)|\(operation.itemID)"
    }

    private static func persistableError(_ error: SyncError) -> SyncError {
        SyncError(
            code: error.code,
            kind: error.kind,
            title: error.title,
            advice: error.advice,
            rawDescription: "persisted-sync-error",
            serverRetryAfter: error.serverRetryAfter
        )
    }

    private static func unboundAccountError() -> SyncError {
        SyncError(
            code: -302,
            kind: .notSignedIn,
            title: "同步操作未关联 iCloud 账户",
            advice: "请登录 iCloud 后手动重试。",
            rawDescription: "persisted-sync-error"
        )
    }

    private func persist() throws {
        do {
            let data = try PropertyListEncoder().encode(state)
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: stateURL, options: .atomic)
        } catch {
            throw SyncError(
                code: (error as NSError).code,
                kind: .configuration,
                title: "无法保存同步重试",
                advice: "请检查设备存储空间后重试。",
                rawDescription: error.localizedDescription
            )
        }
    }

    private func disabledError() -> SyncError {
        SyncError(
            code: -301,
            kind: .configuration,
            title: "当前界面模式未启用持久同步",
            advice: nil,
            rawDescription: "PersistentSyncRetryCoordinator.fullUIEnabled=false"
        )
    }

    private static func loadState(from url: URL) -> PersistentSyncRetryState {
        guard let data = try? Data(contentsOf: url),
              let state = try? PropertyListDecoder().decode(PersistentSyncRetryState.self, from: data) else {
            return .init()
        }
        return state
    }

    nonisolated static func pluginSourceDigest(_ sourceURLs: [String]) -> String {
        let joined = sourceURLs.joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func accountRetryDelay(attempt: Int, error: SyncError) -> TimeInterval {
        max(min(pow(2, Double(max(1, attempt))), 300), error.serverRetryAfter ?? 0)
    }

    private static func sessionVersionString(_ version: SyncSessionVersion) -> String {
        let time = version.updatedAt?.timeIntervalSince1970.description ?? "nil"
        return "\(version.metadataRevision)|\(version.isPresent)|\(version.state?.rawValue ?? "nil")|\(time)"
    }
}
