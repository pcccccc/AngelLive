import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Short drama playback lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct ShortDramaPlaybackModelTests {
    @Test("a newer selection owns playback even when the old preparation ignores cancellation")
    func lateSelectionCannotReplaceNewPlayback() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let second = model.episodes[1].id
        let last = model.episodes[2].id
        fixture.heldNumbers = [2, 4]
        let oldRequest = Task { await model.selectEpisode(id: second) }
        await fixture.waitForPreparation(2)
        let newRequest = Task { await model.selectEpisode(id: last) }
        await fixture.waitForPreparation(4)

        fixture.complete(2)
        await oldRequest.value
        #expect(model.selectedEpisodeID == last)
        #expect(model.isLoading)
        #expect(model.playback == nil)
        fixture.complete(4)
        await newRequest.value
        _ = try #require(model.playback)
        #expect(model.selectedEpisode?.number == 4)
        #expect(model.playback?.quality.qn == 4)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test("an old failure cannot erase a newer successful selection")
    func lateFailureCannotReplaceSuccess() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        fixture.heldNumbers = [2]
        let oldRequest = Task { await model.selectEpisode(id: model.episodes[1].id) }
        await fixture.waitForPreparation(2)
        await model.selectEpisode(id: model.episodes[2].id)
        let current = try #require(model.playback?.id)
        fixture.complete(2, error: FixtureFailure.refresh)
        await oldRequest.value
        #expect(model.playback?.id == current)
        #expect(model.selectedEpisode?.number == 4)
        #expect(model.errorMessage == nil)
    }

    @Test("leaving during initial preparation discards a late response and later callbacks")
    func cancelWhileLoading() async {
        let fixture = PlaybackFixture()
        fixture.heldNumbers = [1]
        let model = fixture.model()
        let load = Task { await model.load() }
        await fixture.waitForPreparation(1)
        model.cancel()
        fixture.complete(1)
        await load.value
        await model.selectEpisode(id: model.episodes[1].id)
        await model.playbackFinished(id: UUID(), error: nil)
        await model.setEpisodesPresented(false)
        #expect(model.playback == nil)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
        #expect(fixture.preparedNumbers == [1])
    }

    @Test("cancelling the caller prevents an uncancellable preparation from publishing playback")
    func parentTaskCancellation() async {
        let fixture = PlaybackFixture()
        fixture.heldNumbers = [1]
        let model = fixture.model()
        let load = Task { await model.load() }
        await fixture.waitForPreparation(1)
        load.cancel()
        fixture.complete(1)
        await load.value
        #expect(model.playback == nil)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test("selecting the current unfinished episode preserves its playback UUID")
    func sameEpisodeKeepsPlayback() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let current = try #require(model.playback?.id)
        await model.selectEpisode(id: model.episodes[0].id)
        #expect(model.playback?.id == current)
        #expect(fixture.preparedNumbers == [1])
    }

    @Test("a failed refresh keeps the target and retries using the original catalog entry")
    func failedRefreshIsRetryable() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        fixture.failNextNumbers = [2]
        let target = model.episodes[1].id
        await model.selectEpisode(id: target)
        #expect(model.selectedEpisodeID == target)
        #expect(model.playback == nil)
        #expect(model.errorMessage == "Fixture refresh failed")
        #expect(!model.isLoading)

        await model.selectEpisode(id: target)
        #expect(model.selectedEpisodeID == target)
        #expect(try #require(model.playback).quality.qn == 2)
        #expect(model.errorMessage == nil)
        #expect(fixture.preparedNumbers == [1, 2, 2])
        #expect(fixture.preparedQualities.allSatisfy { $0.playbackHints?.selectionBehavior == .refreshOnSelect })
        #expect(model.episodes[1].quality.url == "https://media.example.invalid/catalog/2.m3u8")
        #expect(model.playback?.url.absoluteString == "https://media.example.invalid/resolved/2.m3u8")
    }

    @Test("normal EOF advances once and rejects repeated or stale callbacks")
    func normalAndStaleEOF() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let first = try #require(model.playback?.id)
        await model.playbackFinished(id: first, error: nil)
        let second = try #require(model.playback?.id)
        #expect(second != first)
        #expect(model.selectedEpisode?.number == 2)
        await model.playbackFinished(id: first, error: nil)
        await model.playbackFinished(id: first, error: FixtureFailure.refresh)
        #expect(model.playback?.id == second)
        #expect(fixture.preparedNumbers == [1, 2])
        #expect(model.errorMessage == nil)
    }

    @Test("the panel defers EOF until dismissal and releases it only once")
    func panelDefersEOF() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let first = try #require(model.playback?.id)
        await model.setEpisodesPresented(true)
        await model.playbackFinished(id: first, error: nil)
        await model.playbackFinished(id: first, error: nil)
        #expect(model.hasFinished)
        #expect(model.playback?.id == first)
        #expect(fixture.preparedNumbers == [1])
        await model.setEpisodesPresented(false)
        await model.setEpisodesPresented(false)
        #expect(model.selectedEpisode?.number == 2)
        #expect(fixture.preparedNumbers == [1, 2])
    }

    @Test("selecting a different episode discards the panel's pending EOF")
    func manualSelectionDiscardsDeferredEOF() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let first = try #require(model.playback?.id)
        await model.setEpisodesPresented(true)
        await model.playbackFinished(id: first, error: nil)
        await model.selectEpisode(id: model.episodes[1].id)
        let selected = try #require(model.playback?.id)
        await model.setEpisodesPresented(false)
        #expect(model.playback?.id == selected)
        #expect(model.selectedEpisode?.number == 2)
        #expect(fixture.preparedNumbers == [1, 2])
    }

    @Test("panel and gesture holds release EOF only after both end")
    func independentCompletionHolds() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let first = try #require(model.playback?.id)
        await model.setEpisodesPresented(true)
        await model.setEpisodeSwipeActive(true)
        await model.playbackFinished(id: first, error: nil)
        await model.setEpisodesPresented(false)
        #expect(model.playback?.id == first)
        await model.setEpisodeSwipeActive(false)
        #expect(model.selectedEpisode?.number == 2)
        #expect(fixture.preparedNumbers == [1, 2])
    }

    @Test("disabled autoplay is evaluated when deferred EOF is released")
    func disabledAutoplayStopsAtCurrentEpisode() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let first = try #require(model.playback?.id)
        await model.setEpisodesPresented(true)
        await model.playbackFinished(id: first, error: nil)
        model.autoplay = false
        await model.setEpisodesPresented(false)
        #expect(model.playback?.id == first)
        #expect(model.hasFinished)
        #expect(model.selectionNote == "本集已结束")
        #expect(fixture.preparedNumbers == [1])
    }

    @Test("the last episode stays ended and selecting it restarts with a new UUID")
    func lastEpisodeCanReplay() async throws {
        let fixture = PlaybackFixture(numbers: [4])
        let model = fixture.model()
        await model.load()
        let current = try #require(model.playback?.id)
        await model.playbackFinished(id: current, error: nil)
        await model.playbackFinished(id: current, error: nil)
        #expect(model.hasFinished)
        #expect(model.playback?.id == current)
        #expect(model.selectionNote == "已看完全部可播放剧集")
        await model.selectEpisode(id: model.episodes[0].id)
        #expect(try #require(model.playback?.id) != current)
        #expect(!model.hasFinished)
        #expect(model.selectionNote == nil)
        #expect(fixture.preparedNumbers == [4, 4])
    }

    @Test("failed EOF does not advance even while a panel is open")
    func playbackFailureDoesNotAdvance() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let current = try #require(model.playback?.id)
        await model.setEpisodesPresented(true)
        await model.playbackFinished(id: current, error: FixtureFailure.refresh)
        await model.setEpisodesPresented(false)
        #expect(model.playback == nil)
        #expect(model.selectedEpisode?.number == 1)
        #expect(model.errorMessage == "Fixture refresh failed")
        #expect(fixture.preparedNumbers == [1])
    }

    @Test("shared playback restores the last episode and each episode's own position")
    func restoresEachEpisode() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let firstID = try record(model, position: 48)
        let firstEpisode = try #require(model.selectedEpisodeID)
        let secondEpisode = model.episodes[1].id
        await model.selectEpisode(id: secondEpisode)
        _ = try record(model, position: 17)
        model.cancel()

        let reentryFixture = PlaybackFixture(progressStore: ShortDramaProgressStore(directory: fixture.directory))
        let reentry = reentryFixture.model()
        await reentry.load()
        let restoredID = try #require(reentry.playback?.id)
        #expect(reentry.selectedEpisodeID == secondEpisode)
        #expect(reentry.playback?.resumePosition == 17)
        reentry.recordProgress(id: restoredID, position: 0, duration: 100)
        #expect(try reentryFixture.progressStore.load(for: fixture.progressKey).episodes[secondEpisode]?.position == 17)
        await reentry.restorationCompleted(id: restoredID, position: 17, duration: 100,
                                          succeeded: true, resumePlayback: false)
        #expect(reentry.beginScrubbing(playbackID: restoredID))
        await reentry.completeScrubbing(playbackID: restoredID, targetTime: 4, duration: 100,
                                       seekSucceeded: true, resumePlayback: false)
        #expect(try ShortDramaProgressStore(directory: fixture.directory).load(for: fixture.progressKey)
            .episodes[secondEpisode]?.position == 4)
        await reentry.selectEpisode(id: firstEpisode)
        #expect(reentry.playback?.resumePosition == 48)
        reentry.recordProgress(id: firstID, position: 99, duration: 100)
        reentry.recordProgress(id: restoredID, position: 99, duration: 100)
        #expect(try reentryFixture.progressStore.load(for: fixture.progressKey).episodes[firstEpisode]?.position == 48)
    }

    @Test("completed reentry starts at zero only after one valid readiness confirmation")
    func completedReentryAndReadiness() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let id = try record(model, position: 99)
        let episode = try #require(model.selectedEpisodeID)
        await model.setEpisodesPresented(true)
        await model.playbackFinished(id: id, error: nil)
        model.cancel()
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == true)

        let reentry = fixture.model()
        await reentry.load()
        let replayID = try #require(reentry.playback?.id)
        #expect(reentry.selectedEpisodeID == episode)
        #expect(reentry.playback?.resumePosition == nil)
        reentry.playbackReady(id: replayID, duration: 0)
        reentry.recordProgress(id: replayID, position: 0, duration: 100)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == true)
        reentry.playbackReady(id: replayID, duration: 100)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.position == 0)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == false)
        reentry.autoplay = false
        reentry.recordProgress(id: replayID, position: 99, duration: 100)
        await reentry.playbackFinished(id: replayID, error: nil)
        reentry.playbackReady(id: replayID, duration: 100)
        reentry.recordProgress(id: replayID, position: 0, duration: 100)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == true)
    }

    @Test("a successful scrub cancels deferred EOF while failure keeps EOF and paused intent")
    func scrubReconcilesCompletion() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let id = try record(model, position: 60)
        let episode = try #require(model.selectedEpisodeID)
        #expect(model.beginScrubbing(playbackID: id))
        await model.playbackFinished(id: id, error: nil)
        #expect(model.hasFinished)
        await model.completeScrubbing(playbackID: id, targetTime: 12, duration: 100,
                                      seekSucceeded: true, resumePlayback: false)
        #expect(!model.hasFinished)
        #expect(model.playback?.id == id)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.position == 12)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == false)

        #expect(model.beginScrubbing(playbackID: id))
        await model.playbackFinished(id: id, error: nil)
        await model.completeScrubbing(playbackID: id, targetTime: nil, duration: 100,
                                      seekSucceeded: false, resumePlayback: false)
        #expect(model.hasFinished)
        #expect(model.playback?.id == id)
        #expect(model.selectedEpisodeID == episode)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == true)
        await model.playbackFinished(id: id, error: FixtureFailure.refresh)
        #expect(model.playback == nil)
        #expect(!model.hasFinished)
        #expect(model.errorMessage == "Fixture refresh failed")
    }

    @Test("endpoint restoration respects paused intent and independent completion holds", arguments: [false, true])
    func endpointRestoration(resumePlayback: Bool) async throws {
        let fixture = PlaybackFixture()
        let seed = fixture.model()
        await seed.load()
        _ = try record(seed, position: 100)
        seed.cancel()
        let model = fixture.model()
        await model.load()
        let id = try #require(model.playback?.id)
        let episode = try #require(model.selectedEpisodeID)
        #expect(model.playback?.resumePosition == 100)
        await model.setEpisodesPresented(true)
        await model.setEpisodeSwipeActive(true)
        await model.restorationCompleted(id: id, position: 100, duration: 100,
                                         succeeded: true, resumePlayback: resumePlayback)
        #expect(model.hasFinished)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.completed == true)
        await model.setEpisodesPresented(false)
        #expect(model.playback?.id == id)
        await model.setEpisodeSwipeActive(false)
        #expect(model.selectedEpisode?.number == (resumePlayback ? 2 : 1))
        await model.playbackFinished(id: id, error: nil)
        #expect(fixture.preparedNumbers == (resumePlayback ? [1, 1, 2] : [1, 1]))
    }

    @Test("failed restoration preserves history for retry and stale confirmations are ignored")
    func restorationFailureAndRetry() async throws {
        let fixture = PlaybackFixture()
        let seed = fixture.model()
        await seed.load()
        _ = try record(seed, position: 40)
        seed.cancel()
        let model = fixture.model()
        await model.load()
        let failedID = try #require(model.playback?.id)
        let episode = try #require(model.selectedEpisodeID)
        await model.restorationCompleted(id: failedID, position: 0, duration: 100,
                                         succeeded: false, resumePlayback: true)
        #expect(model.playback == nil)
        #expect(model.errorMessage != nil)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.position == 40)
        await model.selectEpisode(id: episode)
        let retryID = try #require(model.playback?.id)
        #expect(retryID != failedID)
        #expect(model.playback?.resumePosition == 40)
        await model.restorationCompleted(id: failedID, position: 90, duration: 100,
                                         succeeded: true, resumePlayback: true)
        #expect(model.playback?.id == retryID)
        await model.restorationCompleted(id: retryID, position: 40, duration: 100,
                                         succeeded: true, resumePlayback: false)
        #expect(try fixture.progressStore.load(for: fixture.progressKey).episodes[episode]?.position == 40)
    }

    @Test("two models merge different episode events and selection refreshes canonical progress")
    func concurrentModelsRetainEachEpisode() async throws {
        let fixture = PlaybackFixture()
        let firstWindow = fixture.model(), secondWindow = fixture.model()
        await firstWindow.load()
        await secondWindow.load()
        let firstID = try record(firstWindow, position: 30)
        let firstEpisode = try #require(firstWindow.selectedEpisodeID)
        let secondEpisode = secondWindow.episodes[1].id
        await secondWindow.selectEpisode(id: secondEpisode)
        let secondID = try record(secondWindow, position: 20)
        firstWindow.recordProgress(id: firstID, position: 40, duration: 100)
        secondWindow.recordProgress(id: secondID, position: 25, duration: 100)
        firstWindow.flushProgress()
        let disk = try ShortDramaProgressStore(directory: fixture.directory).load(for: fixture.progressKey)
        #expect(disk.episodes[firstEpisode]?.position == 40)
        #expect(disk.episodes[secondEpisode]?.position == 25)
        #expect(disk.lastEpisodeID == secondEpisode)
        await firstWindow.selectEpisode(id: secondEpisode)
        #expect(firstWindow.playback?.resumePosition == 25)
    }

    @Test("a paused model's repeated sample and flush do not steal the last watched episode")
    func pausedWindowDoesNotStealSelection() async throws {
        let fixture = PlaybackFixture()
        let pausedWindow = fixture.model(), activeWindow = fixture.model()
        await pausedWindow.load()
        await activeWindow.load()
        let pausedID = try record(pausedWindow, position: 30)
        await activeWindow.selectEpisode(id: activeWindow.episodes[1].id)
        _ = try record(activeWindow, position: 20)
        let activeEpisode = try #require(activeWindow.selectedEpisodeID)
        for _ in 0..<4 {
            pausedWindow.recordProgress(id: pausedID, position: 30, duration: 100)
            pausedWindow.flushProgress()
        }
        #expect(try fixture.progressStore.load(for: fixture.progressKey).lastEpisodeID == activeEpisode)
        pausedWindow.cancel()
        #expect(try ShortDramaProgressStore(directory: fixture.directory).load(for: fixture.progressKey).lastEpisodeID == activeEpisode)
    }

    @Test("a failed shared save remains dirty and can be retried without another playback sample")
    func failedSaveCanRetryUnchangedSample() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var failWrite = true
        var attempts = 0
        let store = ShortDramaProgressStore(directory: directory) { data, url in
            attempts += 1
            if failWrite { throw FixtureFailure.refresh }
            try data.write(to: url, options: .atomic)
        }
        let fixture = PlaybackFixture(progressStore: store)
        let model = fixture.model()
        await model.load()
        let id = try record(model, position: 30)
        let episode = try #require(model.selectedEpisodeID)
        #expect(attempts == 1)
        #expect(model.progressWarning != nil)
        #expect(try store.load(for: fixture.progressKey).episodes[episode]?.position == 30)
        model.recordProgress(id: id, position: 30, duration: 100)
        #expect(attempts == 1)
        failWrite = false
        model.flushProgress()
        #expect(attempts == 2)
        #expect(try ShortDramaProgressStore(directory: directory).load(for: fixture.progressKey).episodes[episode]?.position == 30)
        model.flushProgress()
        #expect(attempts == 2)
    }

    @Test("a corrupt shared record is retained while hosts report the storage failure")
    func corruptStoreDoesNotGetOverwritten() async throws {
        let fixture = PlaybackFixture()
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let file = fixture.directory.appendingPathComponent(fixture.progressKey.filename)
        let damaged = Data("{invalid".utf8)
        try damaged.write(to: file)
        let model = fixture.model()
        await model.load()
        #expect(model.progressWarning != nil)
        _ = try record(model, position: 25)
        model.cancel()
        #expect(try Data(contentsOf: file) == damaged)
        #expect(throws: (any Error).self) {
            try fixture.progressStore.updateEpisode(
                ShortDramaEpisodeProgress(position: 1, duration: 100, completed: false, updatedAt: .now),
                episodeID: "first", for: fixture.progressKey
            )
        }
        #expect(try Data(contentsOf: file) == damaged)
    }

    @Test("history begins only after readiness and repeated callbacks cannot reset progress or unhide it")
    func historyRequiresNewSuccessfulPlayback() async throws {
        let fixture = PlaybackFixture()
        let model = fixture.model()
        await model.load()
        let id = try #require(model.playback?.id)
        #expect(fixture.progressStore.historyEntries.isEmpty)
        model.playbackReady(id: id, duration: 0)
        #expect(fixture.progressStore.historyEntries.isEmpty)
        model.playbackReady(id: id, duration: 100)
        #expect(fixture.progressStore.historyEntries.count == 1)
        #expect(fixture.progressStore.historyEntries.first?.position == 0)
        model.recordProgress(id: id, position: 34, duration: 100)
        model.playbackReady(id: id, duration: 100)
        #expect(fixture.progressStore.historyEntries.first?.position == 34)
        try fixture.progressStore.removeHistory(for: fixture.progressKey)
        model.recordProgress(id: id, position: 35, duration: 100)
        model.playbackReady(id: id, duration: 100)
        await model.restorationCompleted(id: id, position: 0, duration: 100,
                                         succeeded: true, resumePlayback: true)
        #expect(fixture.progressStore.historyEntries.isEmpty)
        model.cancel()
        let reentry = fixture.model()
        await reentry.load()
        let firstRestoreID = try #require(reentry.playback?.id)
        #expect(reentry.playback?.resumePosition == 35)
        reentry.playbackReady(id: firstRestoreID, duration: 100)
        #expect(fixture.progressStore.historyEntries.isEmpty)
        await reentry.restorationCompleted(id: firstRestoreID, position: 35, duration: 100,
                                           succeeded: false, resumePlayback: true)
        #expect(fixture.progressStore.historyEntries.isEmpty)
        let episode = try #require(reentry.selectedEpisodeID)
        await reentry.selectEpisode(id: episode)
        let successfulID = try #require(reentry.playback?.id)
        await reentry.restorationCompleted(id: successfulID, position: 35, duration: 100,
                                           succeeded: true, resumePlayback: true)
        let history = try #require(fixture.progressStore.historyEntries.first)
        #expect(history.title == "Fixture drama")
        #expect(history.episodeNumber == 1)
        #expect(history.position == 35)
        #expect(history.duration == 100)
        #expect(history.key == fixture.progressKey)
        #expect(history.completed == false)
    }

    private func record(_ model: ShortDramaPlaybackModel, position: Double) throws -> UUID {
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 100)
        model.recordProgress(id: id, position: position, duration: 100)
        return id
    }
}

private enum FixtureFailure: LocalizedError {
    case refresh
    var errorDescription: String? { "Fixture refresh failed" }
}

@MainActor
private final class PlaybackFixture {
    let numbers: [Int]
    let directory: URL
    let progressStore: ShortDramaProgressStore
    let progressKey = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "room")
    var heldNumbers = Set<Int>()
    var failNextNumbers = Set<Int>()
    private(set) var preparedNumbers: [Int] = []
    private(set) var preparedQualities: [LiveQualityDetail] = []
    private var pending: [Int: CheckedContinuation<LiveQualityDetail, any Error>] = [:]
    private var started: [Int: CheckedContinuation<Void, Never>] = [:]

    init(numbers: [Int] = [1, 2, 4], progressStore: ShortDramaProgressStore? = nil) {
        self.numbers = numbers
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.progressStore = progressStore ?? ShortDramaProgressStore(directory: directory)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func model() -> ShortDramaPlaybackModel {
        let room = LiveModel(userName: "Fixture", roomTitle: "Fixture drama", roomCover: "",
                             userHeadImg: "", liveType: "fixture.plugin", liveState: nil,
                             userId: "user", roomId: "room", liveWatchedCount: nil)
        return ShortDramaPlaybackModel(room: room, dependencies: ShortDramaPlaybackDependencies(
            resolvePlatform: { _ in LiveParseJSPlatform(pluginId: "fixture.plugin", liveTypes: ["fixture.plugin"]) },
            loadArguments: { [self] _, _ in
                [LiveQualityModel(cdn: "source-a", qualitys: numbers.map { quality($0, resolved: false) })]
            },
            prepare: { [self] _, _, episode in
                preparedNumbers.append(episode.number)
                preparedQualities.append(episode.quality)
                if failNextNumbers.remove(episode.number) != nil { throw FixtureFailure.refresh }
                if heldNumbers.contains(episode.number) {
                    // Intentionally ignores Task cancellation to exercise generation/identity ownership.
                    return try await withCheckedThrowingContinuation { continuation in
                        pending[episode.number] = continuation
                        started.removeValue(forKey: episode.number)?.resume()
                    }
                }
                return quality(episode.number, resolved: true)
            }
        ), progressStore: progressStore)
    }

    func waitForPreparation(_ number: Int) async {
        if pending[number] != nil { return }
        await withCheckedContinuation { started[number] = $0 }
    }

    func complete(_ number: Int, error: (any Error)? = nil) {
        guard let continuation = pending.removeValue(forKey: number) else {
            Issue.record("No pending preparation for episode \(number)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: quality(number, resolved: true))
        }
    }

    private func quality(_ number: Int, resolved: Bool) -> LiveQualityDetail {
        LiveQualityDetail(
            roomId: "room", title: "Episode \(number)", qn: number,
            url: "https://media.example.invalid/\(resolved ? "resolved" : "catalog")/\(number).m3u8",
            liveCodeType: .hls, liveType: "fixture.plugin",
            playbackHints: LivePlaybackHints(isLive: false, selectionBehavior: resolved ? nil : .refreshOnSelect)
        )
    }
}
