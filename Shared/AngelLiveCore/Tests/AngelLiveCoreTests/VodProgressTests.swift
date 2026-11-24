import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
struct VodProgressTests {
    private let key = VodProgressKey(pluginID: "fixture.plugin", workID: "work-a")

    @Test func identicalWorkAndEpisodeIDsRemainIsolatedByPlugin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let other = VodProgressKey(pluginID: "source-b", workID: key.workID)
        let first = episode("episode-a", season: "season-a")
        let second = VodEpisode(pluginID: other.pluginID, workID: other.workID, episodeID: "episode-a",
                                seasonID: "season-a", number: 1, title: "Fixture")
        #expect(first.id != second.id && key != other && key.filename != other.filename)
        let store = VodProgressStore(directory: directory)
        let sample = VodEpisodeProgress(position: 5, duration: 10, completed: false, updatedAt: .now)
        try store.updateEpisode(sample, episodeID: first.id, for: key)
        try store.flush(for: key)
        #expect(try store.load(for: other).episodes.isEmpty)
    }

    @Test func writesAtFiveSecondIntervalsAndFlushesTheLatestSample() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var writes = 0
        let store = VodProgressStore(directory: directory) { data, target in
            writes += 1
            try data.write(to: target, options: .atomic)
        }
        let episode = "14:fixture.plugin6:work-aepisode-a"
        let now = Date(timeIntervalSince1970: 100)
        try store.updateEpisode(.init(position: 10, duration: 100, completed: false, updatedAt: now),
                                episodeID: episode, for: key)
        try store.flushIfNeeded(for: key, now: now)
        try store.updateEpisode(.init(position: 12, duration: 100, completed: false, updatedAt: now),
                                episodeID: episode, for: key)
        try store.flushIfNeeded(for: key, now: now.addingTimeInterval(4.999))
        #expect(writes == 1)
        try store.flushIfNeeded(for: key, now: now.addingTimeInterval(5))
        #expect(writes == 2)
        try store.updateEpisode(.init(position: 14, duration: 100, completed: false, updatedAt: now),
                                episodeID: episode, for: key)
        try store.flush(for: key)
        #expect(writes == 3)
        let snapshot = try VodProgressStore(directory: directory).load(for: key)
        #expect(snapshot.episodes[episode]?.position == 14)
        let file = try #require(FileManager.default.contentsOfDirectory(atPath: directory.path).first)
        #expect(file == key.filename && file.count == 69)
        let json = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
        #expect(!json.contains("\"url\"") && !json.contains("\"headers\"") && !json.contains("\"requestContext\""))
    }

    @Test func unreadableFileIsKeptWhileOtherWorksRemainWritable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = directory.appendingPathComponent(key.filename)
        let bytes = Data("fixture damaged".utf8)
        try bytes.write(to: damaged)
        let store = VodProgressStore(directory: directory)
        let sample = VodEpisodeProgress(position: 1, duration: 10, completed: false, updatedAt: .now)
        #expect(throws: (any Error).self) { try store.load(for: key) }
        #expect(throws: (any Error).self) { try store.updateEpisode(sample, episodeID: "episode-a", for: key) }
        #expect(try Data(contentsOf: damaged) == bytes)
        let other = VodProgressKey(pluginID: "fixture.plugin", workID: "work-b")
        try store.updateEpisode(sample, episodeID: "episode-a", for: other)
        try store.flush(for: other)
        #expect(try store.load(for: other).episodes["episode-a"] == sample)
    }

    @Test func removingHistoryKeepsProgressUntilANewPlaybackStarts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VodProgressStore(directory: directory)
        let metadata = VodHistoryMetadata(title: "雾港回声", kind: .series, episodeID: "episode-a")
        let sample = VodEpisodeProgress(position: 5, duration: 10, completed: false, updatedAt: .now)
        try store.updateEpisode(sample, episodeID: "episode-a", for: key, historyMetadata: metadata)
        try store.removeHistory(for: key)
        try store.updateEpisode(sample, episodeID: "episode-a", for: key, historyMetadata: metadata)
        try store.flush(for: key)
        let reopened = VodProgressStore(directory: directory)
        reopened.loadHistory()
        #expect(reopened.historyEntries.isEmpty)
        #expect(try reopened.load(for: key).episodes["episode-a"] == sample)
        try reopened.updateEpisode(sample, episodeID: "episode-a", for: key,
                                   historyMetadata: metadata, playbackStarted: true)
        #expect(reopened.historyEntries.map(\.title) == ["雾港回声"])
    }

    @Test func creditsRemainCompleteAndResumeAdvancesAcrossSeasons() throws {
        let next = episode("episode-b", season: "season-b")
        let first = episode("episode-a", season: "season-a")
        var session = VodProgressSession(snapshot: .init(key: key))
        let id = UUID()
        #expect(session.start(playbackID: id, episodeID: first.id) == nil)
        let premature = session.markCreditsReached(playbackID: id, position: 90, duration: 100)
        #expect(!premature)
        let ready = session.ready(playbackID: id, duration: 100)
        #expect(ready)
        let stale = session.markCreditsReached(playbackID: UUID(), position: 90, duration: 100)
        #expect(!stale)
        let completed = session.markCreditsReached(playbackID: id, position: 90, duration: 100)
        #expect(completed)
        let late = session.record(playbackID: id, position: 95, duration: 100)
        #expect(!late)
        let duplicate = session.complete(playbackID: id)
        #expect(!duplicate)
        #expect(session.snapshot.episodes[first.id]?.position == 90)
        #expect(session.preferredEpisode(in: [first, next]) == next)
        #expect(session.preferredEpisode(in: [first]) == first)
        let replay = UUID()
        #expect(session.start(playbackID: replay, episodeID: first.id) == nil)
        let replayReady = session.ready(playbackID: replay, duration: 100)
        #expect(replayReady)
        #expect(session.snapshot.episodes[first.id]?.position == 0)
        #expect(session.snapshot.episodes[first.id]?.completed == false)
    }

    @Test(arguments: [Double?.some(90), nil])
    func confirmedSeekCanReopenCompletedProgress(creditsStart: Double?) {
        var session = VodProgressSession(snapshot: .init(key: key))
        let id = UUID()
        let episodeID = "episode-a"
        let end = creditsStart ?? 100
        _ = session.start(playbackID: id, episodeID: episodeID)
        _ = session.ready(playbackID: id, duration: 100)
        let finish = session.seekSucceeded(playbackID: id, position: end, duration: 100, creditsStart: creditsStart)
        #expect(finish)
        #expect(session.snapshot.episodes[episodeID]?.completed == true)
        let stale = session.seekSucceeded(playbackID: UUID(), position: 20, duration: 100, creditsStart: creditsStart)
        #expect(!stale)
        let back = session.seekSucceeded(playbackID: id, position: 20, duration: 100, creditsStart: creditsStart)
        #expect(back)
        #expect(session.snapshot.episodes[episodeID]?.completed == false)
        #expect(session.snapshot.episodes[episodeID]?.position == 20)
        let sample = session.record(playbackID: id, position: 21, duration: 100)
        #expect(sample)
        #expect(session.snapshot.episodes[episodeID]?.position == 21)
    }

    private func episode(_ id: String, season: String) -> VodEpisode {
        VodEpisode(pluginID: key.pluginID, workID: key.workID, episodeID: id,
                   seasonID: season, number: 1, title: "雾港回声")
    }
}
