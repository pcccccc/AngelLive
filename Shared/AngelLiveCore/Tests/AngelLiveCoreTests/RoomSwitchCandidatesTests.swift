import Testing

@testable import AngelLiveCore

@Suite("Room switch candidates")
struct RoomSwitchCandidatesTests {
    @Test("favorites only include confirmed live rooms")
    func favoritesFilterOfflineAndUnknownRooms() {
        let current = room(id: "current", state: "1")
        let live = room(id: "live", state: "1")
        let offline = room(id: "offline", state: "0")
        let unknown = room(id: "unknown", state: nil)

        let result = RoomSwitchCandidates.rooms(
            for: .favorite,
            currentRoom: current,
            favorites: [current, live, offline, unknown],
            history: [],
            category: []
        )

        #expect(result == [live])
    }

    @Test("candidate order is stable and duplicates plus current room are removed")
    func removesDuplicatesWithoutReordering() {
        let current = room(id: "current")
        let first = room(id: "first")
        let second = room(id: "second")

        let result = RoomSwitchCandidates.rooms(
            for: .category,
            currentRoom: current,
            favorites: [],
            history: [],
            category: [first, current, second, first]
        )

        #expect(result == [first, second])
    }

    @Test("same room id from different plugin sources remains independently switchable")
    func preservesRoomsFromDifferentSources() {
        let current = room(id: "current", liveType: "source-a")
        let sourceA = room(id: "shared", liveType: "source-a")
        let sourceB = room(id: "shared", liveType: "source-b")

        let count = RoomSwitchCandidates.totalSwitchableCount(
            currentRoom: current,
            favorites: [sourceA],
            history: [sourceB],
            category: [sourceA]
        )

        #expect(count == 2)
    }

    private func room(
        id: String,
        liveType: LiveType = "source-a",
        state: String? = "1"
    ) -> LiveModel {
        LiveModel(
            userName: id,
            roomTitle: "Title \(id)",
            roomCover: "",
            userHeadImg: "",
            liveType: liveType,
            liveState: state,
            userId: "user-\(id)",
            roomId: id,
            liveWatchedCount: nil
        )
    }
}
