import CloudKit
import Foundation
import os.lock
import Testing
@testable import AngelLiveCore

final class PlaylistFakeCloud: PlaylistCloudStoring {
    private struct State {
        var snapshot: PlaylistInstanceSnapshot?
        var conflictsRemaining = 0
        var saves = 0
        var failFetch = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let marker = CKRecord(recordType: "fixture", recordID: CKRecord.ID(recordName: "fixture"))

    var snapshot: PlaylistInstanceSnapshot? { state.withLock { $0.snapshot } }
    var saves: Int { state.withLock { $0.saves } }

    func seed(_ snapshot: PlaylistInstanceSnapshot) { state.withLock { $0.snapshot = snapshot } }
    func injectConflicts(_ count: Int) { state.withLock { $0.conflictsRemaining = count } }
    func failFetches() { state.withLock { $0.failFetch = true } }

    func fetch() async throws -> PlaylistCloudPayload {
        let current = state.withLock { $0 }
        if current.failFetch { throw URLError(.notConnectedToInternet) }
        return PlaylistCloudPayload(snapshot: current.snapshot ?? .empty, version: current.snapshot == nil ? nil : Self.marker)
    }

    func save(_ snapshot: PlaylistInstanceSnapshot, over _: CKRecord?) async throws -> PlaylistCloudWriteResult {
        state.withLock { state in
            if state.conflictsRemaining > 0 {
                state.conflictsRemaining -= 1
                return .conflict
            }
            state.snapshot = snapshot
            state.saves += 1
            return .saved
        }
    }
}

@Suite("Playlist iCloud sync")
struct PlaylistSyncTests {
    private func instance(_ name: String, updated: TimeInterval, id: UUID = UUID()) -> PlaylistInstance {
        PlaylistInstance(
            id: id,
            name: name,
            iconURL: nil,
            sourceURL: "https://source-a.example.invalid/\(name)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    @Test("newer edits win and IDs are preserved")
    func newerWins() {
        let id = UUID()
        let local = PlaylistInstanceSnapshot(instances: [instance("old", updated: 10, id: id)], tombstones: [:])
        let remote = PlaylistInstanceSnapshot(instances: [instance("new", updated: 20, id: id)], tombstones: [:])
        let merged = PlaylistSyncMerge.merge(local, remote)
        #expect(merged.instances.map(\.name) == ["new"])
        #expect(merged.instances.first?.id == id)
    }

    @Test("deletions propagate and stale copies cannot resurrect")
    func tombstones() {
        let id = UUID()
        let stale = PlaylistInstanceSnapshot(instances: [instance("a", updated: 10, id: id)], tombstones: [:])
        let deleted = PlaylistInstanceSnapshot(instances: [], tombstones: [id: Date(timeIntervalSince1970: 20)])
        #expect(PlaylistSyncMerge.merge(stale, deleted).instances.isEmpty)
        #expect(PlaylistSyncMerge.merge(deleted, stale).instances.isEmpty)
        #expect(PlaylistSyncMerge.merge(deleted, stale).tombstones[id] != nil)

        // 删除之后的编辑仍然保留（另一台设备离线修改晚于删除）。
        let editedLater = PlaylistInstanceSnapshot(instances: [instance("a2", updated: 30, id: id)], tombstones: [:])
        #expect(PlaylistSyncMerge.merge(deleted, editedLater).instances.map(\.name) == ["a2"])
    }

    @Test("independent additions from both sides are unioned")
    func union() {
        let local = PlaylistInstanceSnapshot(instances: [instance("a", updated: 1)], tombstones: [:])
        let remote = PlaylistInstanceSnapshot(instances: [instance("b", updated: 1)], tombstones: [:])
        #expect(PlaylistSyncMerge.merge(local, remote).instances.map(\.name) == ["a", "b"])
    }

    @Test("legacy array storage still loads")
    func legacyFormat() throws {
        let legacy = try JSONEncoder().encode([instance("a", updated: 1)])
        let snapshot = try PlaylistInstanceSnapshot.decode(legacy)
        #expect(snapshot.instances.map(\.name) == ["a"])
        #expect(snapshot.tombstones.isEmpty)
    }

    @Test("removing an instance records a tombstone")
    func removeTombstone() throws {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        let added = try store.add(name: "a", iconURL: nil, sourceURL: "https://source-a.example.invalid/a")
        try store.remove(id: added.id)
        #expect(store.snapshot()?.tombstones[added.id] != nil)
    }

    @Test("sync uploads local, pulls remote and keeps both")
    func roundTrip() async throws {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        let cloud = PlaylistFakeCloud()
        let remoteOnly = instance("remote", updated: 5)
        cloud.seed(PlaylistInstanceSnapshot(instances: [remoteOnly], tombstones: [:]))
        let local = try store.add(name: "local", iconURL: nil, sourceURL: "https://source-b.example.invalid/x")
        let service = PlaylistSyncService(store: store, cloud: cloud, isEnabled: { true })

        let outcome = await service.sync()
        #expect(outcome == .synced(changedLocally: true))
        #expect(Set(store.all().map(\.id)) == [local.id, remoteOnly.id])
        #expect(Set(cloud.snapshot?.instances.map(\.id) ?? []) == [local.id, remoteOnly.id])

        // 已一致时不再写云端。
        let saves = cloud.saves
        #expect(await service.sync() == .synced(changedLocally: false))
        #expect(cloud.saves == saves)
    }

    @Test("write conflicts are retried with a fresh merge")
    func conflictRetry() async throws {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        let cloud = PlaylistFakeCloud()
        cloud.injectConflicts(1)
        _ = try store.add(name: "a", iconURL: nil, sourceURL: "https://source-a.example.invalid/a")
        let service = PlaylistSyncService(store: store, cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .synced(changedLocally: false))
        #expect(cloud.snapshot?.instances.count == 1)
    }

    @Test("disabled setting and failures never touch local data")
    func disabledAndFailure() async throws {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        _ = try store.add(name: "a", iconURL: nil, sourceURL: "https://source-a.example.invalid/a")
        let before = store.snapshot()

        let cloud = PlaylistFakeCloud()
        #expect(await PlaylistSyncService(store: store, cloud: cloud, isEnabled: { false }).sync() == .disabled)
        #expect(cloud.saves == 0)

        cloud.failFetches()
        let outcome = await PlaylistSyncService(store: store, cloud: cloud, isEnabled: { true }).sync()
        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(store.snapshot() == before)
    }
}
