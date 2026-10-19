import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Short drama progress", .timeLimit(.minutes(1)))
@MainActor
struct ShortDramaProgressTests {
    @Test("canonical episode events share one throttle and preserve sibling episodes")
    func sharedThrottleAndEventOrder() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var writes = 0
        let store = ShortDramaProgressStore(directory: directory) { data, url in
            writes += 1
            try data.write(to: url, options: .atomic)
        }
        let key = makeSession().snapshot.key
        func progress(_ position: Double, at time: TimeInterval) -> ShortDramaEpisodeProgress {
            ShortDramaEpisodeProgress(position: position, duration: 100, completed: false,
                                      updatedAt: Date(timeIntervalSinceReferenceDate: time))
        }
        try store.updateEpisode(progress(40, at: 100), episodeID: "first", for: key)
        try store.flushIfNeeded(for: key, now: Date(timeIntervalSinceReferenceDate: 100))
        #expect(writes == 1)
        try store.updateEpisode(progress(20, at: 101), episodeID: "second", for: key)
        try store.flushIfNeeded(for: key, now: Date(timeIntervalSinceReferenceDate: 101))
        #expect(writes == 1)
        // MainActor event order wins even when a later accepted backward seek has an older Date.
        try store.updateEpisode(progress(5, at: 90), episodeID: "first", for: key)
        #expect(try store.load(for: key).lastEpisodeID == "first")
        try store.flushIfNeeded(for: key, now: Date(timeIntervalSinceReferenceDate: 105))
        #expect(writes == 2)
        let disk = try ShortDramaProgressStore(directory: directory).load(for: key)
        #expect(disk.episodes["first"]?.position == 5)
        #expect(disk.episodes["second"]?.position == 20)
        try store.flush(for: key)
        #expect(writes == 2)
    }

    @Test("periodic samples deduplicate per UUID while explicit seek and EOF remain accepted events")
    func identicalSampleDeduplication() {
        var session = makeSession()
        let first = UUID(), second = UUID()
        _ = session.start(playbackID: first, episodeID: "first")
        session.ready(playbackID: first, duration: 100)
        #expect(session.record(playbackID: first, position: 0, duration: 100) == true)
        #expect(session.record(playbackID: first, position: 0, duration: 100) == false)
        #expect(session.seekSucceeded(playbackID: first, position: 0, duration: 100) == true)
        #expect(session.record(playbackID: first, position: 0, duration: 100) == false)
        #expect(session.complete(playbackID: first) == true)
        #expect(session.record(playbackID: first, position: 100, duration: 100) == false)
        _ = session.start(playbackID: second, episodeID: "first")
        session.ready(playbackID: second, duration: 100)
        #expect(session.record(playbackID: second, position: 0, duration: 100) == true)
    }

    @Test("only an absent file is treated as a new empty record")
    func missingFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        let key = makeSession().snapshot.key
        #expect(try store.load(for: key) == ShortDramaProgressSnapshot(key: key))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(key.filename),
                                                withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try ShortDramaProgressStore(directory: directory).load(for: key) }
    }

    @Test("reentry selects saved playable episodes and falls back when missing or locked")
    func preferredEpisode() throws {
        func catalog(_ secondHints: LivePlaybackHints? = nil, secondURL: String = "https://media.example.invalid/2.m3u8") throws -> [ShortDramaEpisode] {
            let qualities = [1, 2].map { number in
                LiveQualityDetail(roomId: "drama-a", title: "Episode", qn: number,
                                  url: number == 1 ? "https://media.example.invalid/1.m3u8" : secondURL,
                                  liveCodeType: .hls, liveType: "fixture.plugin",
                                  playbackHints: number == 2 ? secondHints : nil)
            }
            return try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "drama-a",
                                                 playArgs: [LiveQualityModel(cdn: "source-a", qualitys: qualities)])
        }
        var session = makeSession()
        let episodes = try catalog()
        #expect(session.preferredEpisode(in: episodes)?.number == 1)
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: episodes[1].id)
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 20, duration: 100) == true)
        #expect(session.preferredEpisode(in: episodes)?.number == 2)
        #expect(session.preferredEpisode(in: [episodes[0]])?.number == 1)
        let locked = LivePlaybackHints(authLimit: LivePlaybackAuthLimit(reason: LivePlaybackAuthLimitReason.membershipRequired))
        #expect(session.preferredEpisode(in: try catalog(locked))?.number == 1)
        #expect(session.preferredEpisode(in: try catalog(secondURL: ""))?.number == 1)
        #expect(session.preferredEpisode(in: try catalog(LivePlaybackHints(selectionBehavior: .refreshOnSelect), secondURL: ""))?.number == 2)
    }

    @Test("each plugin and drama has an isolated collision-free file")
    func identityIsolation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        let keys = [
            ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-a"),
            ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-b"),
            ShortDramaProgressKey(pluginID: "source-b", roomID: "drama-a"),
            ShortDramaProgressKey(pluginID: "a:b", roomID: "c/../d"),
            ShortDramaProgressKey(pluginID: "a", roomID: "b:c/../d")
        ]
        #expect(Set(keys.map(\.filename)).count == keys.count)
        for (index, key) in keys.enumerated() {
            var session = ShortDramaProgressSession(snapshot: ShortDramaProgressSnapshot(key: key))
            let id = UUID()
            _ = session.start(playbackID: id, episodeID: "episode")
            session.ready(playbackID: id, duration: 100)
            #expect(session.record(playbackID: id, position: Double(index + 1), duration: 120) == true)
            try store.save(session.snapshot)
        }
        for (index, key) in keys.enumerated() {
            #expect(try store.load(for: key).episodes["episode"]?.position == Double(index + 1))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == keys.count)
    }

    @Test("switching episodes retains every position and reloads the last watched episode")
    func episodePositionsSurviveReload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        var session = makeSession()
        let first = UUID(), second = UUID()
        _ = session.start(playbackID: first, episodeID: "first")
        session.ready(playbackID: first, duration: 100)
        #expect(session.record(playbackID: first, position: 42, duration: 100) == true)
        _ = session.start(playbackID: second, episodeID: "second")
        session.ready(playbackID: second, duration: 100)
        #expect(session.record(playbackID: second, position: 18, duration: 80) == true)
        try store.save(session.snapshot)
        var reloaded = ShortDramaProgressSession(snapshot: try store.load(for: session.snapshot.key))
        #expect(reloaded.snapshot.lastEpisodeID == "second")
        #expect(reloaded.start(playbackID: UUID(), episodeID: "second") == 18)
        #expect(reloaded.start(playbackID: UUID(), episodeID: "first") == 42)
    }

    @Test("unready and restoring samples cannot erase an existing position")
    func restorationGate() {
        var session = makeSession()
        let old = UUID()
        _ = session.start(playbackID: old, episodeID: "first")
        session.ready(playbackID: old, duration: 100)
        #expect(session.record(playbackID: old, position: 70, duration: 100) == true)
        let restored = UUID()
        #expect(session.start(playbackID: restored, episodeID: "first") == 70)
        for duration in [0.0, -1, .nan, .infinity] {
            #expect(session.ready(playbackID: restored, duration: duration) == false)
        }
        #expect(session.record(playbackID: restored, position: 0, duration: 100) == false)
        #expect(session.snapshot.episodes["first"]?.position == 70)
        session.ready(playbackID: restored, duration: 100)
        #expect(session.record(playbackID: restored, position: 70, duration: 100) == true)
    }

    @Test("late player callbacks and cancelled sessions cannot change progress")
    func stalePlaybackRejected() {
        var session = makeSession()
        let old = UUID(), current = UUID()
        _ = session.start(playbackID: old, episodeID: "first")
        session.ready(playbackID: old, duration: 100)
        #expect(session.record(playbackID: old, position: 20, duration: 100) == true)
        _ = session.start(playbackID: current, episodeID: "second")
        session.ready(playbackID: old, duration: 100)
        #expect(session.complete(playbackID: current) == false)
        #expect(session.snapshot.lastEpisodeID == "first")
        #expect(session.record(playbackID: old, position: 90, duration: 100) == false)
        #expect(session.complete(playbackID: old) == false)
        #expect(session.seekSucceeded(playbackID: old, position: 3, duration: 100) == false)
        session.ready(playbackID: current, duration: 100)
        #expect(session.record(playbackID: current, position: 8, duration: 100) == true)
        let snapshot = session.snapshot
        session.invalidate()
        #expect(session.record(playbackID: current, position: 10, duration: 100) == false)
        #expect(session.snapshot == snapshot)
    }

    @Test("a deliberate backward seek replaces a larger historical position")
    func backwardSeek() {
        var session = makeSession()
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: "first")
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 80, duration: 100) == true)
        #expect(session.seekSucceeded(playbackID: id, position: 12, duration: 100) == true)
        #expect(session.snapshot.episodes["first"]?.position == 12)
        #expect(session.snapshot.episodes["first"]?.completed == false)
    }

    @Test("EOF stays completed across periodic samples and replay begins at zero")
    func completionAndReplay() {
        var session = makeSession()
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: "first")
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 99, duration: 100) == true)
        #expect(session.complete(playbackID: id) == true)
        #expect(session.record(playbackID: id, position: 0, duration: 100) == false)
        #expect(session.snapshot.episodes["first"]?.position == 100)
        #expect(session.snapshot.episodes["first"]?.completed == true)
        let replay = UUID()
        #expect(session.start(playbackID: replay, episodeID: "first") == nil)
        #expect(session.ready(playbackID: replay, duration: 0) == false)
        #expect(session.snapshot.episodes["first"]?.completed == true)
        #expect(session.record(playbackID: replay, position: 0, duration: 100) == false)
        #expect(session.ready(playbackID: replay, duration: 100) == true)
        #expect(session.snapshot.episodes["first"]?.position == 0)
        #expect(session.snapshot.episodes["first"]?.completed == false)
        #expect(session.complete(playbackID: replay) == true)
        #expect(session.ready(playbackID: replay, duration: 100) == false)
        #expect(session.snapshot.episodes["first"]?.completed == true)
    }

    @Test("successful seeking cancels EOF and an endpoint seek records completion")
    func seekAfterEOF() {
        var session = makeSession()
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: "first")
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 30, duration: 100) == true)
        #expect(session.complete(playbackID: id) == true)
        #expect(session.seekSucceeded(playbackID: id, position: 20, duration: 100) == true)
        #expect(session.snapshot.episodes["first"]?.completed == false)
        #expect(session.seekSucceeded(playbackID: id, position: 100, duration: 100) == true)
        #expect(session.snapshot.episodes["first"]?.completed == true)
    }

    @Test("invalid samples leave the snapshot unchanged")
    func invalidSamples() {
        var session = makeSession()
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: "first")
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 10, duration: 100) == true)
        let snapshot = session.snapshot
        for (position, duration) in [(Double.nan, 100.0), (.infinity, 100), (-1, 100), (2, 0), (2, .infinity), (2, .nan)] {
            #expect(session.record(playbackID: id, position: position, duration: duration) == false)
            #expect(session.seekSucceeded(playbackID: id, position: position, duration: duration) == false)
        }
        #expect(session.record(playbackID: id, position: 20, duration: 100,
                                updatedAt: Date(timeIntervalSinceReferenceDate: .infinity)) == false)
        #expect(session.snapshot == snapshot)
    }

    @Test("an atomic write failure leaves the previous file and in-memory update available")
    func failedSavePreservesPreviousFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        var session = makeSession()
        let id = UUID()
        _ = session.start(playbackID: id, episodeID: "first")
        session.ready(playbackID: id, duration: 100)
        #expect(session.record(playbackID: id, position: 10, duration: 100) == true)
        try store.save(session.snapshot)
        #expect(session.record(playbackID: id, position: 20, duration: 100) == true)
        let failing = ShortDramaProgressStore(directory: directory) { _, _ in throw FixtureError.write }
        #expect(throws: FixtureError.self) { try failing.save(session.snapshot) }
        #expect(try store.load(for: session.snapshot.key).episodes["first"]?.position == 10)
        #expect(session.snapshot.episodes["first"]?.position == 20)
        try store.save(session.snapshot)
        #expect(try store.load(for: session.snapshot.key).episodes["first"]?.position == 20)
    }

    @Test("damaged or mismatched snapshots are reported and their bytes are retained")
    func corruptedSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ShortDramaProgressStore(directory: directory)
        let key = makeSession().snapshot.key
        let file = directory.appendingPathComponent(key.filename)
        let damaged = Data("{invalid".utf8)
        try damaged.write(to: file)
        #expect(throws: (any Error).self) { try store.load(for: key) }
        #expect(try Data(contentsOf: file) == damaged)
        let other = ShortDramaProgressSnapshot(key: ShortDramaProgressKey(pluginID: "source-b", roomID: "drama-a"))
        let mismatched = try JSONEncoder().encode(other)
        try mismatched.write(to: file)
        #expect(throws: ShortDramaProgressStore.StorageError.self) { try ShortDramaProgressStore(directory: directory).load(for: key) }
        #expect(try Data(contentsOf: file) == mismatched)
    }

    @Test("decoded invalid numbers and unsupported schemas cannot become saved progress")
    func invalidStoredValues() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ShortDramaProgressStore(directory: directory)
        let key = makeSession().snapshot.key
        let file = directory.appendingPathComponent(key.filename)
        for (version, position, duration) in [(1, -1, 100), (1, 10, 0), (1, 101, 100), (2, 10, 100)] {
            let data = Data("""
            {"version":\(version),"key":{"pluginID":"fixture.plugin","roomID":"drama-a"},
             "lastEpisodeID":"first","episodes":{"first":{
             "position":\(position),"duration":\(duration),"completed":false,"updatedAt":0}}}
            """.utf8)
            try data.write(to: file)
            #expect(throws: ShortDramaProgressStore.StorageError.self) { try ShortDramaProgressStore(directory: directory).load(for: key) }
            #expect(try Data(contentsOf: file) == data)
        }
        #expect(throws: ShortDramaProgressStore.StorageError.self) {
            try store.save(ShortDramaProgressSnapshot(key: ShortDramaProgressKey(pluginID: "", roomID: "drama-a")))
        }
    }

    private func makeSession() -> ShortDramaProgressSession {
        ShortDramaProgressSession(snapshot: ShortDramaProgressSnapshot(
            key: ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-a")
        ))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private enum FixtureError: Error { case write }
}
