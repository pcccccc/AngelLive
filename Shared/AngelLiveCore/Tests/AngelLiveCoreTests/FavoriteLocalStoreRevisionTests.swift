import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Favorite local store revisions", .serialized)
struct FavoriteLocalStoreRevisionTests {
    @Test("A stale remote snapshot cannot overwrite a newer local deletion")
    func staleSnapshotCannotOverwriteDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("favorite-store-tests-\(UUID().uuidString)", isDirectory: true)
        let store = FavoriteLocalStore(directory: directory)
        let room = Self.room()
        #expect(await store.save([room]))
        let remoteBase = await store.loadVersioned()

        #expect(await store.save([]))
        #expect(await store.save([room], ifRevisionMatches: remoteBase.revision) == false)
        #expect(await store.load().isEmpty)
    }

    private static func room() -> LiveModel {
        LiveModel(
            userName: "Fixture",
            roomTitle: "Fixture",
            roomCover: "",
            userHeadImg: "",
            liveType: LiveType(rawValue: "source-a")!,
            liveState: nil,
            userId: "user-1",
            roomId: "room-1",
            liveWatchedCount: nil
        )
    }
}
