import CloudKit
import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Persistent sync retry coordinator", .serialized)
@MainActor
struct PersistentSyncRetryCoordinatorTests {
    @Test("FullUI disabled does not create retry work")
    func fullUIDisabledDoesNotRun() throws {
        let fixture = try Fixture()
        try fixture.coordinator.enqueuePluginSources(revision: 1, digest: "digest")
        #expect(fixture.coordinator.pendingMetadataForTesting().isEmpty)
    }

    @Test("Persisted metadata contains no credential or source values")
    func metadataContainsNoSecrets() async throws {
        let fixture = try Fixture(mode: .scope("account-a"), execution: .paused)
        fixture.coordinator.setFullUIEnabled(true)
        await fixture.coordinator.resumePendingOperations()
        try fixture.coordinator.enqueuePluginSources(
            revision: 4,
            digest: PersistentSyncRetryCoordinator.pluginSourceDigest([
                "https://source-a.example.invalid/private-index.json"
            ])
        )
        _ = try fixture.coordinator.enqueueCredentialUpload(
            pluginID: "fixture.plugin",
            version: .init(
                metadataRevision: "metadata-revision",
                updatedAt: Date(timeIntervalSince1970: 20),
                state: .authenticated,
                isPresent: true
            )
        )

        let encoded = String(decoding: try Data(contentsOf: fixture.stateURL), as: UTF8.self)
        #expect(!encoded.contains("private-index"))
        #expect(!encoded.contains("cookie"))
        #expect(!encoded.contains("token"))
    }

    @Test("Server retryAfter controls the persisted retry deadline")
    func serverRetryAfterControlsDeadline() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let retry = CKError(
            .requestRateLimited,
            userInfo: [CKErrorRetryAfterKey: 45.0]
        )
        let fixture = try Fixture(
            mode: .scope("account-a"),
            execution: .failure(retry),
            now: now
        )
        fixture.coordinator.setFullUIEnabled(true)
        await fixture.coordinator.resumePendingOperations()
        let revision = try fixture.coordinator.enqueueCredentialUpload(
            pluginID: "fixture.plugin",
            version: .init(
                metadataRevision: "revision-a",
                updatedAt: nil,
                state: nil,
                isPresent: false
            )
        )

        let failures = await fixture.coordinator.runNowAndCollectFailures(revisions: [revision])
        let pending = try #require(fixture.coordinator.pendingMetadataForTesting().first)
        #expect(failures.first?.serverRetryAfter == 45)
        #expect(pending.notBefore == now.addingTimeInterval(45))
    }

    @Test("An unbound offline operation stays unbound after restart")
    func unboundOperationDoesNotAdoptFutureAccount() async throws {
        let stateURL = try Fixture.makeStateURL()
        let offline = MockPersistentSyncExecutor(mode: .unavailable, execution: .paused)
        let first = PersistentSyncRetryCoordinator(executor: offline, stateURL: stateURL, now: Date.init)
        first.setFullUIEnabled(true)
        await first.resumePendingOperations()
        try first.enqueuePluginSources(revision: 1, digest: "digest")
        #expect(first.pendingMetadataForTesting().first?.accountScope == nil)
        first.setFullUIEnabled(false)

        let online = MockPersistentSyncExecutor(mode: .scope("account-b"), execution: .complete)
        let restored = PersistentSyncRetryCoordinator(executor: online, stateURL: stateURL, now: Date.init)
        restored.setFullUIEnabled(true)
        await restored.resumePendingOperations()
        #expect(restored.pendingMetadataForTesting().first?.accountScope == nil)
        #expect(await online.executionCount() == 0)
    }

    @Test("Favorite deletion needs both cloud paths and explicit re-add cancels it")
    func favoriteDualCompletionAndReAdd() async throws {
        let retry = CKError(.networkFailure)
        let fixture = try Fixture(
            mode: .scope("account-a"),
            execution: .paused,
            legacyFailure: retry
        )
        fixture.coordinator.setFullUIEnabled(true)
        await fixture.coordinator.resumePendingOperations()
        let room = Self.room(namespace: "source-a", roomID: "room-1")
        let recordedRevision = try fixture.coordinator.recordFavoriteRemoval(room)
        let removalRevision = try #require(recordedRevision)
        fixture.coordinator.markFavoriteZoneDeleteComplete(
            stableKey: AppFavoriteModel.favoriteUniqueKey(for: room),
            revision: removalRevision
        )
        #expect(fixture.coordinator.favoriteRemovalsForTesting().count == 1)

        try fixture.coordinator.recordFavoriteAddition(room)
        #expect(fixture.coordinator.favoriteRemovalsForTesting().isEmpty)
        #expect(fixture.coordinator.pendingMetadataForTesting().allSatisfy {
            $0.domain != .favoriteLegacyDelete
        })
    }

    @Test("Favorite identity keeps source namespace for equal room IDs")
    func favoriteIdentityNamespacesRoomID() {
        let first = LegacyFavoriteIdentity(room: Self.room(namespace: "source-a", roomID: "same"))
        let second = LegacyFavoriteIdentity(room: Self.room(namespace: "source-b", roomID: "same"))
        #expect(first.namespace != second.namespace)
        #expect(first.stableKey != second.stableKey)
    }

    @Test("Favorite delete replay is scoped to the verified account")
    func favoriteDeleteReplayUsesVerifiedAccount() async throws {
        let executor = MockPersistentSyncExecutor(mode: .scope("account-a"), execution: .paused)
        let coordinator = PersistentSyncRetryCoordinator(
            executor: executor,
            stateURL: try Fixture.makeStateURL(),
            now: Date.init
        )
        coordinator.setFullUIEnabled(true)
        await coordinator.resumePendingOperations()
        _ = try coordinator.recordFavoriteRemoval(Self.room(namespace: "source-a", roomID: "room-1"))
        #expect(coordinator.pendingFavoriteZoneDeleteIntents().count == 1)

        coordinator.setFullUIEnabled(false)
        await executor.setScope(.scope("account-b"))
        coordinator.setFullUIEnabled(true)
        await coordinator.resumePendingOperations()
        #expect(coordinator.pendingFavoriteZoneDeleteIntents().isEmpty)
    }

    @Test("A delayed delete receipt cannot complete a newer removal")
    func delayedDeleteReceiptDoesNotCompleteNewRemoval() async throws {
        let fixture = try Fixture(mode: .scope("account-a"), execution: .paused)
        fixture.coordinator.setFullUIEnabled(true)
        await fixture.coordinator.resumePendingOperations()
        let room = Self.room(namespace: "source-a", roomID: "room-1")
        let firstRecorded = try fixture.coordinator.recordFavoriteRemoval(room)
        let first = try #require(firstRecorded)
        try fixture.coordinator.recordFavoriteAddition(room)
        let secondRecorded = try fixture.coordinator.recordFavoriteRemoval(room)
        let second = try #require(secondRecorded)

        fixture.coordinator.markFavoriteZoneDeleteComplete(
            stableKey: AppFavoriteModel.favoriteUniqueKey(for: room),
            revision: first
        )
        #expect(fixture.coordinator.favoriteRemovalIsCurrent(
            stableKey: AppFavoriteModel.favoriteUniqueKey(for: room),
            revision: second
        ))
        #expect(fixture.coordinator.favoriteRemovalsForTesting().first?.zoneDeleteComplete == false)
    }

    @Test("A paused operation only runs again after an explicit resume")
    func pausedOperationRequiresResume() async throws {
        let executor = MockPersistentSyncExecutor(mode: .scope("account-a"), execution: .paused)
        let coordinator = PersistentSyncRetryCoordinator(
            executor: executor,
            stateURL: try Fixture.makeStateURL(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        coordinator.setFullUIEnabled(true)
        await coordinator.resumePendingOperations()
        let revision = try coordinator.enqueueCredentialUpload(
            pluginID: "fixture.plugin",
            version: .init(metadataRevision: "one", updatedAt: nil, state: nil, isPresent: false)
        )

        _ = await coordinator.runNowAndCollectFailures(revisions: [revision])
        #expect(await executor.executionCount() == 1)
        #expect(coordinator.pendingMetadataForTesting().first?.paused == true)

        await coordinator.resumePendingOperations()
        _ = await coordinator.runNowAndCollectFailures(revisions: [revision])
        #expect(await executor.executionCount() == 2)
    }

    @Test("Persisted failures discard raw external descriptions")
    func persistedFailureSanitizesRawDescription() async throws {
        let marker = "secret-marker-should-not-persist"
        let failure = NSError(domain: "fixture.error", code: 91, userInfo: [
            NSLocalizedDescriptionKey: marker
        ])
        let fixture = try Fixture(mode: .scope("account-a"), execution: .failure(failure))
        fixture.coordinator.setFullUIEnabled(true)
        await fixture.coordinator.resumePendingOperations()
        let revision = try fixture.coordinator.enqueueCredentialUpload(
            pluginID: "fixture.plugin",
            version: .init(metadataRevision: "one", updatedAt: nil, state: nil, isPresent: false)
        )

        _ = await fixture.coordinator.runNowAndCollectFailures(revisions: [revision])
        let encoded = String(decoding: try Data(contentsOf: fixture.stateURL), as: UTF8.self)
        #expect(!encoded.contains(marker))
        #expect(fixture.coordinator.pendingMetadataForTesting().first?.lastError?.rawDescription == "persisted-sync-error")
    }

    @Test("Account retry delay backs off and honors the server deadline")
    func accountRetryDelayPolicy() {
        let error = SyncError(
            code: 7,
            kind: .networkBlocked,
            title: "Unavailable",
            advice: nil,
            rawDescription: "fixture",
            serverRetryAfter: 45
        )
        #expect(PersistentSyncRetryCoordinator.accountRetryDelay(attempt: 1, error: error) == 45)
        #expect(PersistentSyncRetryCoordinator.accountRetryDelay(attempt: 9, error: error) == 300)
    }

    private static func room(namespace: String, roomID: String) -> LiveModel {
        LiveModel(
            userName: "Fixture",
            roomTitle: "Fixture",
            roomCover: "",
            userHeadImg: "",
            liveType: LiveType(rawValue: namespace)!,
            liveState: nil,
            userId: "user-1",
            roomId: roomID,
            liveWatchedCount: nil
        )
    }
}

private struct Fixture {
    let stateURL: URL
    let coordinator: PersistentSyncRetryCoordinator

    @MainActor
    init(
        mode: MockPersistentSyncExecutor.ScopeMode = .scope("account-a"),
        execution: MockPersistentSyncExecutor.Execution = .paused,
        legacyFailure: (any Error)? = nil,
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) throws {
        stateURL = try Self.makeStateURL()
        coordinator = PersistentSyncRetryCoordinator(
            executor: MockPersistentSyncExecutor(
                mode: mode,
                execution: execution,
                legacyFailure: legacyFailure
            ),
            stateURL: stateURL,
            now: { now }
        )
    }

    static func makeStateURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("persistent-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.plist")
    }
}

private actor MockPersistentSyncExecutor: PersistentSyncRetryExecuting {
    enum ScopeMode: Sendable {
        case scope(String)
        case unavailable
    }

    enum Execution: @unchecked Sendable {
        case complete
        case paused
        case failure(any Error)
    }

    private var mode: ScopeMode
    let execution: Execution
    let legacyFailure: (any Error)?
    private var executions = 0

    init(mode: ScopeMode, execution: Execution, legacyFailure: (any Error)? = nil) {
        self.mode = mode
        self.execution = execution
        self.legacyFailure = legacyFailure
    }

    func currentAccountScope() async throws -> String {
        switch mode {
        case .scope(let scope): return scope
        case .unavailable: throw CKError(.notAuthenticated)
        }
    }

    func deleteLegacyFavorite(
        identity: LegacyFavoriteIdentity,
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws {
        _ = identity
        guard await shouldContinue() else { throw CancellationError() }
        if let legacyFailure { throw legacyFailure }
    }

    func execute(_ operation: PersistentSyncRetryMetadata.Operation) async throws -> PersistentSyncExecutionResult {
        _ = operation
        executions += 1
        switch execution {
        case .complete: return .complete
        case .paused: return .paused
        case .failure(let error): throw error
        }
    }

    func executionCount() -> Int { executions }

    func setScope(_ mode: ScopeMode) { self.mode = mode }
}
