import Foundation
import Testing
@testable import AngelLiveCore

@Suite("RoomPlaybackResolver plugin-first routing")
struct RoomPlaybackResolverTests {
    private func quality(
        url: String,
        codeType: LiveCodeType,
        hints: LivePlaybackHints? = nil
    ) -> LiveQualityDetail {
        LiveQualityDetail(
            roomId: "room",
            title: "source",
            qn: 0,
            url: url,
            liveCodeType: codeType,
            liveType: LiveType(rawValue: "test") ?? .placeholder,
            playbackHints: hints
        )
    }

    @Test("old playback hints remain decodable")
    func oldHintsDecode() throws {
        let data = Data(#"{"streamFormat":"hlsLive","requiresCustomSegmentLoader":false}"#.utf8)
        let hints = try JSONDecoder().decode(LivePlaybackHints.self, from: data)

        #expect(hints.streamFormat == .hlsLive)
        #expect(hints.latencyMode == nil)
        #expect(hints.preferredEngines == nil)
        #expect(hints.isLive == nil)
    }

    @Test("new plugin hints decode without host-specific Swift types")
    func newHintsDecode() throws {
        let data = Data(#"{"streamFormat":"hlsLive","latencyMode":"lowLatency","preferredEngines":["avPlayer","mePlayer"],"isLive":true}"#.utf8)
        let hints = try JSONDecoder().decode(LivePlaybackHints.self, from: data)

        #expect(hints.latencyMode == .lowLatency)
        #expect(hints.preferredEngines == [.avPlayer, .mePlayer])
        #expect(hints.isLive == true)
    }

    @Test("unknown future hint values do not reject playback JSON")
    func unknownHintsAreAdvisory() throws {
        let data = Data(#"{"streamFormat":"futureFormat","latencyMode":"futureLatency","preferredEngines":["futurePlayer","mePlayer"]}"#.utf8)
        let hints = try JSONDecoder().decode(LivePlaybackHints.self, from: data)

        #expect(hints.streamFormat == nil)
        #expect(hints.latencyMode == nil)
        #expect(hints.preferredEngines == [.unknown, .mePlayer])

        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/live.flv", codeType: .flv, hints: hints)
        )
        #expect(plan.playerKinds == [.mePlayer])
    }

    @Test("explicit engine order overrides standard HLS default")
    func explicitEngineOrderWins() {
        let hints = LivePlaybackHints(
            streamFormat: .hlsLive,
            preferredEngines: [.avPlayer, .mePlayer]
        )
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/live.m3u8", codeType: .hls, hints: hints)
        )

        #expect(plan.playerKinds == [.avPlayer, .mePlayer])
        #expect(plan.isHLS)
        #expect(plan.isLive)
    }

    @Test("explicit low latency works without an LL-HLS filename")
    func explicitLowLatencyWins() {
        let hints = LivePlaybackHints(streamFormat: .hlsLive, latencyMode: .lowLatency)
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/master.m3u8", codeType: .hls, hints: hints)
        )
        #expect(plan.playerKinds == [.avPlayer, .mePlayer])
    }

    @Test("explicit standard latency suppresses URL LL-HLS inference")
    func explicitStandardSuppressesInference() {
        let hints = LivePlaybackHints(streamFormat: .hlsLive, latencyMode: .standard)
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/llhls.m3u8", codeType: .hls, hints: hints)
        )
        #expect(plan.playerKinds == [.mePlayer, .avPlayer])
    }

    @Test("unusable AV preference for FLV falls back to ME")
    func incompatiblePreferenceFallsBack() {
        let hints = LivePlaybackHints(streamFormat: .flv, preferredEngines: [.avPlayer])
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/live.flv", codeType: .flv, hints: hints)
        )
        #expect(plan.playerKinds == [.mePlayer])
        #expect(plan.isLive)
    }

    @Test("custom loader capability forces ME")
    func customLoaderForcesME() {
        let hints = LivePlaybackHints(
            streamFormat: .hlsLive,
            preferredEngines: [.avPlayer, .mePlayer],
            requiresCustomSegmentLoader: true
        )
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/live.m3u8", codeType: .hls, hints: hints)
        )
        #expect(plan.playerKinds == [.mePlayer])
    }

    @Test("plugin live semantic overrides format inference")
    func explicitLiveSemanticWins() {
        let hints = LivePlaybackHints(streamFormat: .hlsVod, isLive: true)
        let plan = RoomPlaybackResolver.resolvePlan(
            selectedQuality: quality(url: "https://example.com/archive.m3u8", codeType: .hls, hints: hints)
        )
        #expect(plan.isHLS)
        #expect(plan.isLive)
        #expect(plan.streamFormat == .hlsVod)
    }
}
