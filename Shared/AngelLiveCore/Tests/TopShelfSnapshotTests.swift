import Foundation
import Testing
@testable import AngelLiveCore

struct TopShelfSnapshotTests {
    @Test("Top Shelf snapshot keeps live favorites and round-trips offline")
    func roundTrip() throws {
        let containerURL = temporaryContainerURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let snapshot = TopShelfSnapshot(favorites: [
            room(
                userName: "Source A", roomTitle: "Live room",
                roomCover: "https://images.example.invalid/cover.jpg",
                liveType: "source-a", userId: "user-a", roomId: "room-a"
            ),
            room(liveType: "source-a", liveState: LiveState.close.rawValue, roomId: "offline")
        ])
        let store = TopShelfSnapshotStore(containerURL: containerURL)

        #expect(try store.save(snapshot))
        #expect(!(try store.save(snapshot)))

        guard let restored = try store.load() else {
            Issue.record("Expected a saved snapshot")
            return
        }
        #expect(restored == snapshot)
        #expect(restored.items.map { $0.title } == ["Live room - Source A"])
    }

    @Test("Top Shelf snapshot saves title and image changes for the same live room")
    func updatedPresentationForSameRoomIsWritten() throws {
        let containerURL = temporaryContainerURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let store = TopShelfSnapshotStore(containerURL: containerURL)
        let original = TopShelfSnapshot(favorites: [
            room(
                roomTitle: "Earlier title",
                roomCover: "https://images.example.invalid/earlier.jpg",
                liveType: "source-a", roomId: "room-a"
            )
        ])
        let updated = TopShelfSnapshot(favorites: [
            room(
                roomTitle: "Updated title",
                roomCover: "https://images.example.invalid/updated.jpg",
                liveType: "source-a", roomId: "room-a"
            )
        ])

        #expect(try store.save(original))
        #expect(try store.save(updated))

        guard let restored = try store.load() else {
            Issue.record("Expected an updated snapshot")
            return
        }
        #expect(restored == updated)
        #expect(restored.items.first?.title == "Updated title - Streamer")
        #expect(restored.items.first?.imageURL == URL(string: "https://images.example.invalid/updated.jpg"))
    }

    @Test("Top Shelf snapshot replaces content with an empty live snapshot")
    func emptySnapshotOverwritesExistingContent() throws {
        let containerURL = temporaryContainerURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let store = TopShelfSnapshotStore(containerURL: containerURL)

        #expect(try store.save(TopShelfSnapshot(favorites: [room()])))
        let emptySnapshot = TopShelfSnapshot(favorites: [
            room(liveState: LiveState.close.rawValue)
        ])
        #expect(emptySnapshot.items.isEmpty)
        #expect(try store.save(emptySnapshot))

        guard let restored = try store.load() else {
            Issue.record("Expected an empty saved snapshot")
            return
        }
        #expect(restored == emptySnapshot)
    }

    @Test("Top Shelf snapshot uses a stable platform and room identifier")
    func deDuplicatesAfterFilteringAndKeepsDifferentPlatforms() throws {
        let snapshot = TopShelfSnapshot(favorites: [
            room(
                roomTitle: "Old state", roomCover: "https://images.example.invalid/old.jpg",
                liveType: "source-a", liveState: LiveState.close.rawValue, roomId: "shared"
            ),
            room(
                roomTitle: "Updated state", roomCover: "https://images.example.invalid/new.jpg",
                liveType: "source-a", roomId: "shared"
            ),
            room(
                roomTitle: "Other source", roomCover: "https://images.example.invalid/other.jpg",
                liveType: "source-b", roomId: "shared"
            ),
            room(
                roomTitle: "Duplicate", roomCover: "https://images.example.invalid/duplicate.jpg",
                liveType: "source-a", roomId: "shared"
            ),
            room(
                roomTitle: "Underscore source", liveType: "source_a", roomId: "room"
            ),
            room(
                roomTitle: "Underscore room", liveType: "source", roomId: "a_room"
            )
        ])

        #expect(snapshot.items.map { $0.identifier } == [
            "source-a/shared", "source-b/shared", "source_a/room", "source/a_room"
        ])
        #expect(snapshot.items.map { $0.title } == [
            "Updated state - Streamer", "Other source - Streamer",
            "Underscore source - Streamer", "Underscore room - Streamer"
        ])
        #expect(snapshot.items.first?.imageURL == URL(string: "https://images.example.invalid/new.jpg"))
    }

    @Test("Top Shelf snapshot falls back to a valid avatar image")
    func imageValidationFallsBackToAvatar() throws {
        let snapshot = TopShelfSnapshot(favorites: [
            room(
                roomCover: "ftp://images.example.invalid/cover.jpg",
                userHeadImg: "https://images.example.invalid/avatar.jpg"
            ),
            room(
                roomCover: "https:///missing-host.jpg",
                userHeadImg: "file:///avatar.jpg",
                liveType: "source-b", roomId: "no-image"
            )
        ])

        #expect(snapshot.items[0].imageURL == URL(string: "https://images.example.invalid/avatar.jpg"))
        #expect(snapshot.items[1].imageURL == nil)
    }

    @Test("Top Shelf action URL encodes path segments and an optional user identifier")
    func actionURLPreservesSpecialCharacters() throws {
        let snapshot = TopShelfSnapshot(favorites: [
            room(
                liveType: "source a/β", userId: "user &?β",
                roomId: "room /?β"
            ),
            room(liveType: "source-b", userId: "", roomId: "room-b")
        ])
        let encoded = snapshot.items[0].actionURL
        let encodedComponents = try #require(URLComponents(url: encoded, resolvingAgainstBaseURL: false))
        let encodedPath = encoded.pathComponents.filter { $0 != "/" }

        #expect(encodedComponents.scheme == "simplelive")
        #expect(encodedComponents.host == "room")
        #expect(encodedPath == ["source a/β", "room /?β"])
        #expect(encodedComponents.queryItems?.first(where: { $0.name == "userId" })?.value == "user &?β")
        #expect(snapshot.items[1].actionURL.query == nil)
    }

    @Test("Top Shelf snapshot reports missing and corrupted cache files distinctly")
    func missingAndCorruptedFiles() throws {
        let containerURL = temporaryContainerURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let store = TopShelfSnapshotStore(containerURL: containerURL)
        #expect(try store.load() == nil)

        let fileURL = snapshotFileURL(in: containerURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        #expect(throws: (any Error).self) {
            try store.load()
        }

        let recovered = TopShelfSnapshot(favorites: [room(roomTitle: "Recovered")])
        #expect(try store.save(recovered))
        #expect(try store.load() == recovered)
    }
}

private extension TopShelfSnapshotTests {
    func room(
        userName: String = "Streamer",
        roomTitle: String = "Room",
        roomCover: String = "https://images.example.invalid/cover.jpg",
        userHeadImg: String = "https://images.example.invalid/avatar.jpg",
        liveType: String = "source-a",
        liveState: String? = LiveState.live.rawValue,
        userId: String = "user-a",
        roomId: String = "room-a"
    ) -> LiveModel {
        LiveModel(
            userName: userName,
            roomTitle: roomTitle,
            roomCover: roomCover,
            userHeadImg: userHeadImg,
            liveType: LiveType(rawValue: liveType)!,
            liveState: liveState,
            userId: userId,
            roomId: roomId,
            liveWatchedCount: nil
        )
    }

    func temporaryContainerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func snapshotFileURL(in containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("TopShelf", isDirectory: true)
            .appendingPathComponent("favorites-v1.json")
    }
}
