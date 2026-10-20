import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Short drama history", .timeLimit(.minutes(1)))
@MainActor
struct ShortDramaHistoryTests {
    @Test("version one files without display data remain resumable and use a neutral title")
    func oldProgressRemainsUsable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ShortDramaProgressStore(directory: directory)
        let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-a")
        try seed(source, key: key, position: 34)
        let data = try Data(contentsOf: directory.appendingPathComponent(key.filename))
        #expect(!String(decoding: data, as: UTF8.self).contains("historyMetadata"))
        let store = ShortDramaProgressStore(directory: directory)
        store.loadHistory()
        let entry = try #require(store.historyEntries.first)
        #expect(store.historyWarning == nil)
        #expect(entry.key == key)
        #expect(entry.title == "未命名短剧")
        #expect(entry.coverURL == nil)
        #expect(entry.position == 34)
        #expect(entry.duration == 100)
        #expect(entry.episodeTitle == nil)
        let room = entry.makeRoom(liveType: "current-alias")
        #expect(room.liveType == "current-alias")
        #expect(room.roomId == key.roomID)
        #expect(room.userId.isEmpty)
        #expect(try store.load(for: key).episodes["first"]?.position == 34)
    }

    @Test("deleting history keeps every episode and ordinary updates cannot make it visible again")
    func hidingPreservesProgress() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-a")
        try seed(store, key: key, position: 30)
        try store.updateEpisode(sample(60), episodeID: "second", for: key)
        try store.recordPlaybackStarted(metadata: metadata(key: key, episodeID: "second"), for: key)
        try store.removeHistory(for: key)
        #expect(store.historyEntries.isEmpty)
        try store.updateEpisode(sample(65), episodeID: "second", for: key,
                                historyMetadata: metadata(key: key, episodeID: "second"))
        try store.flush(for: key)
        #expect(store.historyEntries.isEmpty)
        let disk = ShortDramaProgressStore(directory: directory)
        disk.loadHistory()
        #expect(disk.historyEntries.isEmpty)
        #expect(try disk.load(for: key).episodes["first"]?.position == 30)
        #expect(try disk.load(for: key).episodes["second"]?.position == 65)
        try store.recordPlaybackStarted(metadata: metadata(key: key, episodeID: "second"), for: key)
        #expect(store.historyEntries.count == 1)
        #expect(store.historyEntries.first?.position == 65)
    }

    @Test("a failed removal preserves both the visible record and existing disk data")
    func failedRemovalIsNotReportedAsSuccess() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var failWrite = false
        let store = ShortDramaProgressStore(directory: directory) { data, url in
            if failWrite { throw FixtureFailure.write }
            try data.write(to: url, options: .atomic)
        }
        let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-a")
        try seed(store, key: key, position: 40)
        let file = directory.appendingPathComponent(key.filename)
        let original = try Data(contentsOf: file)
        failWrite = true
        #expect(throws: FixtureFailure.self) { try store.removeHistory(for: key) }
        #expect(store.historyEntries.map(\.key) == [key])
        #expect(try Data(contentsOf: file) == original)
        #expect(try store.load(for: key).historyHidden != true)
        failWrite = false
        try store.removeHistory(for: key)
        #expect(store.historyEntries.isEmpty)
    }

    @Test("clear retries failed records without losing progress from files already hidden")
    func clearHandlesPartialWriteFailure() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ShortDramaProgressKey(pluginID: "source-a", roomID: "shared-room")
        let second = ShortDramaProgressKey(pluginID: "source-b", roomID: "shared-room")
        var failedFilename: String?
        let store = ShortDramaProgressStore(directory: directory) { data, url in
            if url.lastPathComponent == failedFilename { throw FixtureFailure.write }
            try data.write(to: url, options: .atomic)
        }
        try seed(store, key: first, position: 10)
        try seed(store, key: second, position: 20)
        failedFilename = second.filename
        #expect(throws: FixtureFailure.self) { try store.clearHistory() }
        #expect(store.historyEntries.map(\.key) == [second])
        #expect(try store.load(for: first).episodes["first"]?.position == 10)
        #expect(try store.load(for: second).episodes["first"]?.position == 20)
        failedFilename = nil
        try store.clearHistory()
        #expect(store.historyEntries.isEmpty)
    }

    @Test("damaged files do not hide good records and can be retried after repair")
    func corruptHistoryCanRetry() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ShortDramaProgressStore(directory: directory)
        let good = ShortDramaProgressKey(pluginID: "source-a", roomID: "drama-a")
        let damaged = ShortDramaProgressKey(pluginID: "source-b", roomID: "drama-b")
        try seed(source, key: good, position: 10)
        try seed(source, key: damaged, position: 20)
        let file = directory.appendingPathComponent(damaged.filename)
        let original = try Data(contentsOf: file)
        let broken = Data("{broken".utf8)
        try broken.write(to: file)
        let store = ShortDramaProgressStore(directory: directory)
        store.loadHistory()
        #expect(store.historyWarning != nil)
        #expect(store.historyEntries.map(\.key) == [good])
        #expect(try Data(contentsOf: file) == broken)
        try original.write(to: file, options: .atomic)
        store.loadHistory()
        #expect(store.historyWarning == nil)
        #expect(Set(store.historyEntries.map(\.key)) == [good, damaged])
    }

    @Test("legacy identity enrichment is exact, survives uninstall and never unhides a deleted record")
    func legacyMigrationAndClassification() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "shared-room")
        let source = ShortDramaProgressStore(directory: directory)
        try seed(source, key: key, position: 27)
        try source.removeHistory(for: key)
        let room = makeRoom(roomID: key.roomID, liveType: "old-alias")
        var installed = true
        let store = ShortDramaProgressStore(directory: directory,
            write: { data, url in try data.write(to: url, options: .atomic) },
            resolveHistoryPlugin: { room in installed && room.liveType == "old-alias" ? key.pluginID : nil })
        store.loadHistory(legacyRooms: [room, makeRoom(roomID: "unwatched", liveType: "old-alias")])
        #expect(store.historyEntries.isEmpty)
        let enriched = try store.load(for: key)
        #expect(enriched.historyMetadata?.roomTitle == "Fixture drama")
        #expect(enriched.historyMetadata?.recordedLiveType == "old-alias")
        #expect(enriched.historyMetadata?.lastWatchedAt == sample(27).updatedAt)
        #expect(enriched.episodes["first"]?.position == 27)
        installed = false
        let reloaded = ShortDramaProgressStore(directory: directory,
            write: { data, url in try data.write(to: url, options: .atomic) }, resolveHistoryPlugin: { _ in nil })
        reloaded.loadHistory()
        #expect(reloaded.isShortDramaHistory(room))
        #expect(!reloaded.isShortDramaHistory(makeRoom(roomID: key.roomID, liveType: "other-alias")))
        #expect(reloaded.historyEntries.isEmpty)
        try reloaded.recordPlaybackStarted(metadata: metadata(key: key), for: key)
        let entry = try #require(reloaded.historyEntries.first)
        let currentRoom = entry.makeRoom(liveType: "new-alias")
        #expect(currentRoom.liveType == "new-alias")
        #expect(currentRoom.roomId == key.roomID)
    }

    @Test("history entries use namespaced identities and deterministic sorting for matching dates")
    func namespacedSorting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        let keys = [ShortDramaProgressKey(pluginID: "source-b", roomID: "same"),
                    ShortDramaProgressKey(pluginID: "source-a", roomID: "same"),
                    ShortDramaProgressKey(pluginID: "source-a", roomID: "before")]
        for key in keys { try seed(store, key: key, position: 10) }
        #expect(store.historyEntries.map(\.key) == [keys[2], keys[1], keys[0]])
        try store.updateEpisode(sample(40), episodeID: "first", for: keys[0])
        #expect(store.historyEntries.last?.position == 40)
    }

    private func metadata(key: ShortDramaProgressKey, episodeID: String = "first") -> ShortDramaHistoryMetadata {
        ShortDramaHistoryMetadata(room: makeRoom(roomID: key.roomID, liveType: "old-alias"),
                                  episodeID: episodeID, episodeTitle: "Episode 3", episodeNumber: 3,
                                  lastWatchedAt: sample(0).updatedAt)
    }

    private func seed(_ store: ShortDramaProgressStore, key: ShortDramaProgressKey, position: Double) throws {
        try store.updateEpisode(sample(position), episodeID: "first", for: key)
        try store.flush(for: key)
    }

    private func sample(_ position: Double) -> ShortDramaEpisodeProgress {
        ShortDramaEpisodeProgress(position: position, duration: 100, completed: false,
                                  updatedAt: Date(timeIntervalSinceReferenceDate: 100))
    }

    private func makeRoom(roomID: String, liveType: LiveType) -> LiveModel {
        LiveModel(userName: "Fixture author", roomTitle: "Fixture drama",
                  roomCover: "https://images.example.invalid/cover.png", userHeadImg: "",
                  liveType: liveType, liveState: nil, userId: "author", roomId: roomID, liveWatchedCount: nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private enum FixtureFailure: Error { case write }
}

@Suite("History category removal", .timeLimit(.minutes(1)))
struct HistoryCategoryRemovalTests {
    @Test("removing selected full identities retains another source with the same room ID")
    func removeOnlySelectedNamespace() throws {
        let suite = "fixture.history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = HistoryModel(defaults: defaults)
        let first = room(source: "source-a"), second = room(source: "source-b")
        model.watchList = [first, second]
        model.removeHistories(ids: [first.id])
        #expect(model.watchList.map(\.id) == [second.id])
        #expect(HistoryModel(defaults: defaults).watchList.map(\.id) == [second.id])
        model.removeHistories(ids: [])
        #expect(model.watchList.map(\.id) == [second.id])
    }

    private func room(source: LiveType) -> LiveModel {
        LiveModel(userName: "Fixture", roomTitle: "Fixture room", roomCover: "", userHeadImg: "",
                  liveType: source, liveState: nil, userId: "author", roomId: "shared-room", liveWatchedCount: nil)
    }
}
