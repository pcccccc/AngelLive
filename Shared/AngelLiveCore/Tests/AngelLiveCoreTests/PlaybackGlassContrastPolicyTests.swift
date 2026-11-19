import Foundation
import Testing
@testable import AngelLiveCore

struct PlaybackGlassContrastPolicyTests {
    @Test func fourBrightCellsDoNotQualifyAndFiveRequireTwoSamples() throws {
        var run = try SamplingRun()
        #expect(run.record(.brightCells(4), at: 3000) == nil)
        #expect(run.record(.brightCells(4), at: 3400) == nil)
        #expect(run.record(.brightCells(5), at: 3800) == nil)
        #expect(run.record(.brightCells(5), at: 4200) == true)
    }

    @Test func darknessMustLastTwoAndAHalfSeconds() throws {
        var run = try SamplingRun()
        #expect(run.record(.brightCells(5), at: 2600) == nil)
        #expect(run.record(.brightCells(5), at: 3000) == true)
        #expect(run.record(.brightCells(2), at: 4000) == nil)
        #expect(run.record(.brightCells(2), at: 6400) == nil)
        #expect(run.record(.brightCells(2), at: 6500) == false)
    }

    @Test func clearAndRegularEachHoldForAtLeastThreeSeconds() throws {
        var run = try SamplingRun()
        #expect(run.record(.brightCells(5), at: 2600) == nil)
        #expect(run.record(.brightCells(5), at: 2999) == nil)
        #expect(run.record(.brightCells(5), at: 3000) == true)
        #expect(run.record(.brightCells(2), at: 3400) == nil)
        #expect(run.record(.brightCells(2), at: 5900) == nil)
        #expect(run.record(.brightCells(2), at: 6000) == false)
        #expect(run.record(.brightCells(5), at: 6400) == nil)
        #expect(run.record(.brightCells(5), at: 8999) == nil)
        #expect(run.record(.brightCells(5), at: 9000) == true)
    }

    @Test func alternatingBrightAndDarkSamplesBreakBothStreaks() throws {
        var run = try SamplingRun()
        #expect(run.record(.brightCells(5), at: 3000) == nil)
        #expect(run.record(.brightCells(2), at: 3400) == nil)
        #expect(run.record(.brightCells(5), at: 3800) == nil)
        #expect(run.record(.brightCells(5), at: 4200) == true)
        #expect(run.record(.brightCells(2), at: 4600) == nil)
        #expect(run.record(.brightCells(5), at: 6600) == nil)
        #expect(run.record(.brightCells(2), at: 7200) == nil)
        #expect(run.record(.brightCells(2), at: 9700) == false)
    }

    @Test func intermediateAndUnreadableSamplesInterruptDarkness() throws {
        var run = try SamplingRun()
        _ = run.record(.brightCells(5), at: 3000)
        #expect(run.record(.brightCells(5), at: 3400) == true)
        #expect(run.record(.brightCells(2), at: 3800) == nil)
        #expect(run.record(.brightCells(3), at: 5800) == nil)
        #expect(run.record(.brightCells(2), at: 6400) == nil)
        #expect(run.record(.unreadable(isDecoderReady: true), at: 8400) == nil)
        #expect(run.record(.brightCells(2), at: 9000) == nil)
        #expect(run.record(.brightCells(2), at: 11500) == false)
    }

    @Test func fallbackRequiresThreeConsecutiveUnreadableSamplesWithReadyDecoder() throws {
        var run = try SamplingRun()
        let ready = PlaybackGlassContrastPolicy.Sample.unreadable(isDecoderReady: true)
        let unready = PlaybackGlassContrastPolicy.Sample.unreadable(isDecoderReady: false)

        #expect(run.record(ready, at: 3000) == nil)
        #expect(run.record(ready, at: 3400) == nil)
        #expect(run.record(unready, at: 3800) == nil)
        #expect(run.record(unready, at: 4200) == nil)
        #expect(run.record(unready, at: 4600) == nil)
        #expect(run.record(ready, at: 5000) == nil)
        #expect(run.record(.brightCells(4), at: 5400) == nil)
        #expect(run.record(ready, at: 5800) == nil)
        #expect(run.record(ready, at: 6200) == nil)
        #expect(run.record(ready, at: 6600) == true)
    }

    @Test func decoderFallbackAlsoWaitsForTheMinimumDwell() throws {
        var run = try SamplingRun()
        let ready = PlaybackGlassContrastPolicy.Sample.unreadable(isDecoderReady: true)
        #expect(run.record(ready, at: 2000) == nil)
        #expect(run.record(ready, at: 2400) == nil)
        #expect(run.record(ready, at: 2800) == nil)
        #expect(run.record(ready, at: 3200) == true)
    }

    @Test func revealingControlsKeepsMaterialAndDwellButStartsFreshEvidence() throws {
        var run = try SamplingRun()
        #expect(run.record(.brightCells(5), at: 3000) == nil)
        run.samples = .init()
        let changedOnFirstReveal = run.policy.select(run.source, at: run.instant(4000))
        #expect(!changedOnFirstReveal)
        #expect(run.record(.brightCells(5), at: 4000) == nil)
        #expect(run.record(.brightCells(5), at: 4400) == true)

        #expect(run.record(.brightCells(2), at: 4800) == nil)
        run.samples = .init()
        let changedOnSecondReveal = run.policy.select(run.source, at: run.instant(8000))
        #expect(!changedOnSecondReveal)
        #expect(run.policy.usesRegularGlass(for: run.source))
        #expect(run.record(.brightCells(2), at: 8000) == nil)
        let changedOnReselection = run.policy.select(run.source, at: run.instant(10000))
        #expect(!changedOnReselection)
        #expect(run.record(.brightCells(2), at: 10500) == false)
    }

    @Test func temporarilyMissingURLKeepsTheLastPlayableSource() throws {
        var run = try SamplingRun()
        _ = run.record(.brightCells(5), at: 3000)
        #expect(run.record(.brightCells(5), at: 3400) == true)

        let unavailable = PlaybackGlassContrastSource(roomID: "source-a", url: nil, kernel: .ksplayer)
        #expect(unavailable == nil)
        let changedWhileUnavailable = run.policy.select(unavailable, at: run.instant(3800))
        #expect(!changedWhileUnavailable)
        #expect(!run.policy.usesRegularGlass(for: unavailable))
        let changedAfterRecovery = run.policy.select(run.source, at: run.instant(4200))
        #expect(!changedAfterRecovery)
        #expect(run.policy.usesRegularGlass(for: run.source))
    }

    @Test func changedSourceStartsClearAndRejectsSamplesFromPreviousSource() throws {
        var run = try SamplingRun()
        _ = run.record(.brightCells(5), at: 3000)
        #expect(run.record(.brightCells(5), at: 3400) == true)

        let next = try #require(PlaybackGlassContrastSource(roomID: "source-b", url: run.source.url, kernel: .ksplayer))
        let changedToNext = run.policy.select(next, at: run.instant(4000))
        #expect(changedToNext)
        #expect(!run.policy.usesRegularGlass(for: next))
        #expect(!run.policy.usesRegularGlass(for: run.source))
        #expect(run.record(.brightCells(48), at: 7400) == nil)
        #expect(!run.policy.usesRegularGlass(for: next))
        let changedToOriginal = run.policy.select(run.source, at: run.instant(7800))
        #expect(changedToOriginal)
        #expect(!run.policy.usesRegularGlass(for: run.source))
    }

    @Test func sourceIdentityIncludesURLKernelAndEpisode() throws {
        let run = try SamplingRun()
        let url = try #require(URL(string: "https://video.example.invalid/source-b"))
        let distinctSources = try [
            #require(PlaybackGlassContrastSource(roomID: "source-a", url: url, kernel: .ksplayer)),
            #require(PlaybackGlassContrastSource(roomID: "source-a", url: run.source.url, kernel: .vlc4)),
            #require(PlaybackGlassContrastSource(roomID: "source-a", url: run.source.url, kernel: .ksplayer,
                                               episodeID: "episode-b"))
        ]
        for source in distinctSources {
            var policy = run.policy
            let changed = policy.select(source, at: run.instant(4000))
            #expect(changed)
        }
    }

    private struct SamplingRun {
        let source: PlaybackGlassContrastSource
        private let origin = ContinuousClock.now
        var policy = PlaybackGlassContrastPolicy()
        var samples = PlaybackGlassContrastPolicy.Samples()

        init() throws {
            source = try #require(PlaybackGlassContrastSource(roomID: "source-a",
                                                             url: URL(string: "https://video.example.invalid/source-a"),
                                                             kernel: .ksplayer))
            policy.select(source, at: origin)
        }

        func instant(_ milliseconds: Int) -> ContinuousClock.Instant {
            origin + .milliseconds(milliseconds)
        }

        mutating func record(_ sample: PlaybackGlassContrastPolicy.Sample, at milliseconds: Int) -> Bool? {
            let now = instant(milliseconds)
            return policy.record(sample, for: source, at: now, samples: &samples)
        }
    }
}
