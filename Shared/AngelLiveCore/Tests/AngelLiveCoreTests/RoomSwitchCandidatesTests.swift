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

    @Test func adjacentRoomsAtStartMiddleAndEnd() {
        let first = room(id: "first")
        let middle = room(id: "middle")
        let last = room(id: "last")
        let rooms = [first, middle, last]

        #expect(adjacent(.previous, to: first, in: rooms) == nil)
        #expect(adjacent(.next, to: first, in: rooms) == middle)
        #expect(adjacent(.previous, to: middle, in: rooms) == first)
        #expect(adjacent(.next, to: middle, in: rooms) == last)
        #expect(adjacent(.previous, to: last, in: rooms) == middle)
        #expect(adjacent(.next, to: last, in: rooms) == nil)
    }

    @Test func missingCurrentRoomAndEmptySource() {
        let current = room(id: "missing")
        let first = room(id: "first")

        #expect(adjacent(.previous, to: current, in: [first]) == nil)
        #expect(adjacent(.next, to: current, in: [first]) == first)
        #expect(adjacent(.previous, to: current, in: []) == nil)
        #expect(adjacent(.next, to: current, in: []) == nil)
    }

    @Test func adjacencyUsesFirstOccurrencesAndKeepsSourceIdentity() {
        let current = room(id: "same", liveType: "source-a")
        let otherSource = room(id: "same", liveType: "source-b")
        let last = room(id: "last")
        let rooms = [current, current, otherSource, last, otherSource]

        #expect(adjacent(.next, to: current, in: rooms) == otherSource)
        #expect(adjacent(.previous, to: otherSource, in: rooms) == current)
        #expect(adjacent(.next, to: otherSource, in: rooms) == last)
        #expect(adjacent(.next, to: last, in: rooms) == nil)
    }

    @Test func favoriteAdjacencyUsesOnlyConfirmedLiveRooms() {
        let current = room(id: "current")
        let offline = room(id: "offline", state: "0")
        let next = room(id: "next")

        let found = RoomSwitchCandidates.adjacentRoom(
            .next, for: .favorite, currentRoom: current,
            favorites: [current, offline, next], history: [offline], category: [offline]
        )
        #expect(found == next)
    }

    private func adjacent(
        _ direction: RoomSwitchCandidates.Direction,
        to current: LiveModel,
        in rooms: [LiveModel]
    ) -> LiveModel? {
        RoomSwitchCandidates.adjacentRoom(
            direction, for: .category, currentRoom: current,
            favorites: [], history: [], category: rooms
        )
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
