import Foundation
import Testing
import AngelLiveCore

@Suite("Watch history identity and persistence")
struct HistoryModelTests {
    @Test("Rewatching and deleting only affect the same source and room")
    func singleRoomMutations() throws {
        try withHistory { history, defaults in
            let first = room("room-1", source: "source-a", title: "Previous title")
            let other = room("room-1", source: "source-b")
            let updated = room("room-1", source: "source-a", title: "Updated title", state: "1")

            history.addHistory(room: first)
            history.addHistory(room: other)
            #expect(history.watchList == [other, first])

            history.addHistory(room: updated)
            let saved = HistoryModel(defaults: defaults).watchList
            #expect(saved == [updated, other])
            #expect(saved.first?.roomTitle == "Updated title")
            #expect(saved.first?.liveState == "1")

            history.removeHistory(room: first)
            #expect(history.watchList == [other])
            #expect(HistoryModel(defaults: defaults).watchList == [other])
        }
    }

    @Test("Adding at the limit evicts the oldest room")
    func recencyLimit() throws {
        try withHistory { history, defaults in
            let existing = (0..<100).map { room("room-\($0)") }
            let newest = room("newest")
            history.replaceHistories(existing)

            history.addHistory(room: newest)

            let expected = [newest] + existing.dropLast()
            #expect(history.watchList == expected)
            #expect(HistoryModel(defaults: defaults).watchList == expected)
        }
    }

    @Test("Replacing saves the first occurrence of each room before applying the limit")
    func replacePreservesFirstOccurrence() throws {
        try withHistory { history, defaults in
            let first = room("room-1", source: "source-a", title: "First title")
            let duplicate = room("room-1", source: "source-a", title: "Later title")
            let other = room("room-1", source: "source-b")
            let remaining = (2...105).map { room("room-\($0)") }
            history.addHistory(room: room("old-room"))

            history.replaceHistories([first, duplicate, other] + remaining)

            let expected = [first, other] + remaining.prefix(98)
            let saved = HistoryModel(defaults: defaults).watchList
            #expect(history.watchList == expected)
            #expect(saved == expected)
            #expect(saved.first?.roomTitle == "First title")

            history.replaceHistories([])
            #expect(HistoryModel(defaults: defaults).watchList.isEmpty)
        }
    }

    @Test("Merging keeps local data and appends only new rooms up to the limit")
    func mergePreservesLocalOrder() throws {
        try withHistory { history, defaults in
            let local = room("room-1", source: "source-a", title: "Local title")
            let remote = room("room-1", source: "source-a", title: "Remote title")
            let other = room("room-1", source: "source-b", title: "First imported title")
            let duplicate = room("room-1", source: "source-b", title: "Later imported title")
            let existing = [local] + (2...99).map { room("room-\($0)") }
            history.replaceHistories(existing)

            history.mergeHistories([remote, other, duplicate, room("overflow")])

            let expected = existing + [other]
            let saved = HistoryModel(defaults: defaults).watchList
            #expect(history.watchList == expected)
            #expect(saved == expected)
            #expect(saved.first?.roomTitle == "Local title")
            #expect(saved.last?.roomTitle == "First imported title")
        }
    }

    @Test("Removing selected IDs leaves the same room from another source and persists")
    func removeSelectedIDs() throws {
        try withHistory { history, defaults in
            let first = room("room-1", source: "source-a")
            let other = room("room-1", source: "source-b")
            history.replaceHistories([first, other])
            history.removeHistories(ids: [first.id])
            #expect(history.watchList == [other])
            #expect(HistoryModel(defaults: defaults).watchList == [other])
        }
    }

    @Test("Merging an empty list preserves existing history and its persisted order")
    func mergeEmpty() throws {
        try withHistory { history, defaults in
            let rooms = [room("room-1"), room("room-2")]
            history.replaceHistories(rooms)
            history.mergeHistories([])
            #expect(history.watchList == rooms)
            #expect(HistoryModel(defaults: defaults).watchList == rooms)
        }
    }

    private func withHistory(_ body: (HistoryModel, UserDefaults) -> Void) throws {
        let suite = "HistoryModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(HistoryModel(defaults: defaults), defaults)
    }

    private func room(_ id: String, source: LiveType = "source-a", title: String = "Fixture room", state: String? = nil) -> LiveModel {
        LiveModel(
            userName: "Fixture user",
            roomTitle: title,
            roomCover: "",
            userHeadImg: "",
            liveType: source,
            liveState: state,
            userId: "fixture-user",
            roomId: id,
            liveWatchedCount: nil
        )
    }
}
