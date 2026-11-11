#if canImport(KSPlayer)
import AngelLiveCore
import Foundation
import ImageIO
import KSPlayer
import Metal
import Testing
@testable import AngelLiveDependencies

/// Explicit probe: set COMBINED_PROBE_BASE_URL to a server hosting the synthetic CENC
/// `video.mp4` + `audio.mp4` pair (key 00112233445566778899aabbccddeeff).
/// Optional COMBINED_PROBE_FRAME_PATH saves a decoded frame for visual inspection.
@Suite("Combined separate audio runtime probe")
@MainActor
struct CombinedSeparateAudioProbeTests {
    @Test("Encrypted video and audio play through one combined manifest",
          .enabled(if: ProcessInfo.processInfo.environment["COMBINED_PROBE_BASE_URL"] != nil))
    func syntheticPlayback() async throws {
        let environment = ProcessInfo.processInfo.environment
        let base = try #require(environment["COMBINED_PROBE_BASE_URL"].flatMap(URL.init(string:)))
        try #require(MTLCreateSystemDefaultDevice() != nil)
        let key = try LivePlaybackDecryption(method: .cenc, key: "00112233445566778899aabbccddeeff")
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: base.appendingPathComponent("audio.mp4"), userAgent: "fixture-agent", headers: [:],
            decryption: key, sharesVideoRequest: true
        )
        options.formatContextOptions["decryption_key"] = key.key
        options.videoDecodeType = .software
        options.renderUseDispatchSourceTimer = true
        options.registerRemoteControll = false
        options.automaticWindowResize = false
        options.isLoopPlay = false
        let player = DualStreamPlayer(url: base.appendingPathComponent("video.mp4"), options: options)
        let probe = Probe()
        player.delegate = probe
        defer { player.stop() }
        player.view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        player.prepareToPlay()
        player.play()

        try await waitUntil(seconds: 15) { player.isReadyToPlay || probe.finished }
        try #require(player.usesCombinedInput, "Fell back to two players")
        try #require(!probe.finished && player.isReadyToPlay)
        let audioTracks = player.tracks(mediaType: .audio)
        #expect(!audioTracks.isEmpty)
        print("[combined-probe] audio=\(audioTracks.map(\.description))")

        try await waitUntil(seconds: 15) { player.currentPlaybackTime > 3 || probe.finished }
        #expect(!probe.finished)
        if let path = environment["COMBINED_PROBE_FRAME_PATH"],
           let image = await player.thumbnailImageAtCurrentTime(),
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }

        for (position, rate): (TimeInterval, Float) in [(0, 1), (120, 1.5), (60, 2)] {
            let ok = await (player as any MediaPlayerProtocol).seek(time: position)
            #expect(ok)
            player.playbackRate = rate
            player.play()
            let start = player.currentPlaybackTime
            try await Task.sleep(for: .seconds(2))
            print("[combined-probe] seek=\(position) rate=\(rate) start=\(start) advanced=\(player.currentPlaybackTime - start) state=\(player.playbackState) load=\(player.loadState) playing=\(player.isPlaying)")
            #expect(player.currentPlaybackTime > start)
        }
        let endOK = await (player as any MediaPlayerProtocol).seek(time: max(player.duration - 3, 0))
        #expect(endOK)
        player.playbackRate = 1
        player.play()
        try await waitUntil(seconds: 20) { probe.finished || probe.reachedEnd }
        print("[combined-probe] end t=\(player.currentPlaybackTime) duration=\(player.duration) finished=\(probe.finished) reachedEnd=\(probe.reachedEnd) state=\(player.playbackState)")
        #expect((probe.finished || probe.reachedEnd) && probe.error == nil)
        // After the demuxer has consumed both files, seeking back must still play.
        probe.finished = false
        let backOK = await (player as any MediaPlayerProtocol).seek(time: 10)
        player.play()
        let resume = player.currentPlaybackTime
        try await Task.sleep(for: .seconds(3))
        print("[combined-probe] after-eof seekOK=\(backOK) start=\(resume) advanced=\(player.currentPlaybackTime - resume) state=\(player.playbackState) finished=\(probe.finished)")
        #expect(player.currentPlaybackTime > resume)
    }

    private func waitUntil(seconds: Int, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<(seconds * 10) where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor
    final class Probe: MediaPlayerDelegate {
        var finished = false
        var reachedEnd = false
        var error: Error?
        func readyToPlay(player: some MediaPlayerProtocol) {}
        func changeLoadState(player: some MediaPlayerProtocol) {}
        func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {}
        func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) {}
        func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
        func reachEndOfStream(player: some MediaPlayerProtocol) { reachedEnd = true }
        func finish(player: some MediaPlayerProtocol, error: Error?) { finished = true; self.error = error }
        func playerDidClear(player: some MediaPlayerProtocol) {}
    }
}
#endif
