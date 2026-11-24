import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
struct VodPlaybackModelTests {
    @Test func eofWithoutMarkersDoesNotAdvanceWhenAutoplayIsDisabled() async throws {
        let fixture = try Fixture(autoplay: false)
        let model = await fixture.open()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 100)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.playback?.id == id && model.creditsOffer == nil)
        #expect(model.progressSnapshot?.episodes[fixture.episodes[0].id]?.completed == true)
        #expect(fixture.requests.count == 1)
    }
    @Test func creditsWriteImmediatelyAndOfferNextAcrossSeasons() async throws {
        let fixture = try Fixture(markers: true)
        let model = await fixture.open()
        let playback = try #require(model.playback)
        model.playbackReady(id: playback.id, duration: 100)
        model.recordProgress(id: playback.id, position: 5, duration: 100)
        #expect(model.skipIntro(playbackID: playback.id) == 10)
        model.recordProgress(id: playback.id, position: 7, duration: 100)
        #expect(model.activeIntroSkipTarget == nil)
        model.recordProgress(id: playback.id, position: 89, duration: 100)
        #expect(model.creditsOffer == nil)
        model.recordProgress(id: playback.id, position: 91, duration: 100)
        let snapshot = try VodProgressStore(directory: fixture.directory).load(for: fixture.key)
        #expect(snapshot.episodes[playback.episodeID]?.completed == true)
        #expect(snapshot.episodes[playback.episodeID]?.position == 91)
        #expect(model.preferredEpisode == fixture.episodes[1])
        #expect(model.creditsOffer?.nextEpisode == fixture.episodes[1])
        await model.advanceToNextEpisode()
        #expect(model.selectedSeasonID == "season-b")
        #expect(model.playback?.episodeID == fixture.episodes[1].id)
        model.recordProgress(id: playback.id, position: 99, duration: 100)
        #expect(model.progressSnapshot?.episodes[playback.episodeID]?.position == 91)
    }

    @Test func dismissingCreditsSuppressesAutoplayButKeepsCompletionUntilReplay() async throws {
        let fixture = try Fixture(markers: true)
        let model = await fixture.open()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 100)
        model.recordProgress(id: id, position: 90, duration: 100)
        model.dismissCreditsOffer(playbackID: id)
        model.recordProgress(id: id, position: 95, duration: 100)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.hasFinished && model.creditsOffer == nil)
        #expect(model.playback?.id == id)
        await model.selectEpisode(id: fixture.episodes[0].id)
        let replay = try #require(model.playback)
        #expect(replay.id != id && replay.resumePosition == nil)
        model.playbackReady(id: replay.id, duration: 100)
        #expect(model.progressSnapshot?.episodes[replay.episodeID]?.completed == false)
    }

    @Test(arguments: [VodWorkKind.movie, .series])
    func creditsWithoutAutoplayAreStillComplete(kind: VodWorkKind) async throws {
        let fixture = try Fixture(kind: kind, markers: true, autoplay: kind == .movie)
        let model = await fixture.open()
        let playback = try #require(model.playback)
        model.playbackReady(id: playback.id, duration: 100)
        model.recordProgress(id: playback.id, position: 90, duration: 100)
        #expect(model.creditsOffer == nil)
        #expect(model.progressSnapshot?.episodes[playback.episodeID]?.completed == true)
    }

    @Test func eofWithoutMarkersWaitsForOverlayAndAdvancesOnce() async throws {
        let fixture = try Fixture()
        let model = await fixture.open()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 100)
        await model.setOverlayHoldPresented(true)
        await model.playbackFinished(id: id, error: nil)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.playback?.id == id)
        await model.setOverlayHoldPresented(false)
        #expect(model.playback?.episodeID == fixture.episodes[1].id)
        #expect(model.progressSnapshot?.episodes[fixture.episodes[0].id]?.completed == true)
        #expect(fixture.requests.count == 2)
    }

    @Test func confirmedInteriorSeekDiscardsEOFForTheOldPosition() async throws {
        let fixture = try Fixture()
        let model = await fixture.open()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 100)
        #expect(model.beginScrubbing(playbackID: id))
        await model.playbackFinished(id: id, error: nil)
        await model.completeScrubbing(playbackID: id, targetTime: 25, duration: 100,
                                      seekSucceeded: true, resumePlayback: true)
        #expect(model.playback?.id == id && !model.hasFinished)
        #expect(model.progressSnapshot?.episodes[fixture.episodes[0].id]?.position == 25)
        #expect(model.progressSnapshot?.episodes[fixture.episodes[0].id]?.completed == false)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.playback?.episodeID == fixture.episodes[1].id)
    }

    @Test(arguments: [true, false])
    func confirmedSeekAfterCompletionPersistsAndRearmsPrompts(markers: Bool) async throws {
        let fixture = try Fixture(markers: markers, autoplay: markers)
        let model = await fixture.open()
        let playback = try #require(model.playback)
        let id = playback.id
        model.playbackReady(id: id, duration: 100)
        model.recordProgress(id: id, position: 5, duration: 100)
        model.dismissIntroPrompt(playbackID: id)
        model.recordProgress(id: id, position: 90, duration: 100)
        model.dismissCreditsOffer(playbackID: id)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.hasFinished)
        #expect(model.progressSnapshot?.episodes[playback.episodeID]?.completed == true)

        #expect(model.beginScrubbing(playbackID: id))
        await model.completeScrubbing(playbackID: id, targetTime: 5, duration: 100,
                                      seekSucceeded: true, resumePlayback: false)
        let saved = try VodProgressStore(directory: fixture.directory).load(for: fixture.key)
        #expect(saved.episodes[playback.episodeID]?.completed == false)
        #expect(saved.episodes[playback.episodeID]?.position == 5)
        #expect(model.preferredEpisode == fixture.episodes[0])
        #expect(model.activeIntroSkipTarget == (markers ? 10 : nil))
        #expect(model.creditsOffer == nil)

        model.recordProgress(id: id, position: 20, duration: 100)
        #expect(model.progressSnapshot?.episodes[playback.episodeID]?.position == 20)
        model.recordProgress(id: id, position: 90, duration: 100)
        #expect(model.creditsOffer?.nextEpisode == (markers ? fixture.episodes[1] : nil))
    }

    @Test func refreshingSelectionUsesTheReturnedSourceAndRetryStaysOnTheEpisode() async throws {
        let fixture = try Fixture(refresh: true)
        fixture.failRequestNumber = 2
        let model = await fixture.open()
        #expect(model.playback == nil && model.errorMessage != nil)
        #expect(model.selectedEpisodeID == fixture.episodes[0].id)
        #expect(fixture.requests.map(\.source) == [nil, "source-a"])
        await model.retry()
        #expect(model.playback?.sourceID == "source-a")
        #expect(fixture.requests.map(\.episodeID) == Array(repeating: fixture.episodes[0].id, count: 4))
        #expect(fixture.requests.map(\.source) == [nil, "source-a", "source-a", "source-a"])
    }

    @Test func switchingDuringResolutionRejectsLateResultsAndStaleCallbacks() async throws {
        let fixture = try Fixture()
        var requested: AsyncStream<Void>.Continuation?
        let requests = AsyncStream<Void> { requested = $0 }
        let signal = try #require(requested)
        var gate: CheckedContinuation<Void, Never>?
        let model = fixture.makeModel { episode in
            if episode.id == fixture.episodes[0].id {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    signal.yield(())
                }
            }
        }
        await model.load()
        let pending = Task { await model.selectEpisode(id: fixture.episodes[0].id) }
        for await _ in requests { break }
        await model.selectEpisode(id: fixture.episodes[1].id)
        let selected = try #require(model.playback)
        gate?.resume()
        await pending.value
        #expect(model.playback == selected)
        #expect(!model.isLoadingPlayback)
        await model.playbackFinished(id: UUID(), error: Fixture.Error.fixture)
        #expect(model.errorMessage == nil && model.playback == selected)
        model.cancel()
        model.playbackReady(id: selected.id, duration: 100)
        #expect(model.playback == nil && model.progressSnapshot?.lastEpisodeID == nil)
    }
}

@MainActor
private final class Fixture {
    enum Error: Swift.Error { case fixture }
    struct Request {
        let episodeID: String
        let source: String?
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = VodProgressKey(pluginID: "fixture.plugin", workID: "work-a")
    let detail: VodWorkDetail
    let markers: Bool
    let autoplay: Bool
    let refresh: Bool
    var requests: [Request] = []
    var failRequestNumber: Int?
    var episodes: [VodEpisode] { detail.episodes }

    init(kind: VodWorkKind = .series, markers: Bool = false, autoplay: Bool = true, refresh: Bool = false) throws {
        let json = """
        {"kind":"\(kind.rawValue)","title":"雾港回声",
         "seasons":[{"id":"season-a","number":1,"title":"雾港回声"},
                    {"id":"season-b","number":2,"title":"远山来信"}],
         "episodes":[{"id":"episode-a","seasonId":"season-a","number":1,"title":"雾港回声","durationHint":100},
                     {"id":"episode-b","seasonId":"season-b","number":1,"title":"远山来信","durationHint":100}]}
        """
        detail = try VodCatalog.detail(from: Data(json.utf8), pluginID: key.pluginID, workID: key.workID)
        self.markers = markers
        self.autoplay = autoplay
        self.refresh = refresh
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func makeModel(beforeResolve: (@MainActor (VodEpisode) async -> Void)? = nil) -> VodPlaybackModel {
        VodPlaybackModel(
            dependencies: .init(loadDetail: { self.detail }, resolvePlayback: { detail, episode, source in
                self.requests.append(.init(episodeID: episode.id, source: source))
                if self.requests.count == self.failRequestNumber { throw Error.fixture }
                await beforeResolve?(episode)
                let markers = self.markers
                    ? #"[{"kind":"intro","start":0,"end":10},{"kind":"credits","start":90,"end":100}]"#
                    : "[]"
                let json = """
                {"sourceId":"source-a","url":"https://fixture.example.invalid/media","isLive":false,
                 "refreshOnSelect":\(self.refresh),"markers":\(markers)}
                """
                return try VodCatalog.playback(from: Data(json.utf8), workID: detail.workID, episode: episode,
                                               liveType: "fixture.plugin", sourceID: source)
            }),
            progressStore: VodProgressStore(directory: directory),
            autoplayEnabled: { self.autoplay }
        )
    }

    func open() async -> VodPlaybackModel {
        let model = makeModel()
        await model.load()
        await model.selectEpisode(id: episodes[0].id)
        return model
    }
}
