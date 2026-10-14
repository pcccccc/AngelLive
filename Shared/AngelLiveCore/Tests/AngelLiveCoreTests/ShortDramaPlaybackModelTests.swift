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
}

private enum FixtureFailure: LocalizedError {
    case refresh
    var errorDescription: String? { "Fixture refresh failed" }
}

@MainActor
private final class PlaybackFixture {
    let numbers: [Int]
    var heldNumbers = Set<Int>()
    var failNextNumbers = Set<Int>()
    private(set) var preparedNumbers: [Int] = []
    private(set) var preparedQualities: [LiveQualityDetail] = []
    private var pending: [Int: CheckedContinuation<LiveQualityDetail, any Error>] = [:]
    private var started: [Int: CheckedContinuation<Void, Never>] = [:]

    init(numbers: [Int] = [1, 2, 4]) {
        self.numbers = numbers
    }

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
        ))
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
