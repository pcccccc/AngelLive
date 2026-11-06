#if canImport(KSPlayer)
import AngelLiveCore
import AVFoundation
import Foundation
import KSPlayer
import Metal
import Testing
@testable import AngelLiveDependencies

@Suite("Separate audio runtime probe")
@MainActor
struct DualStreamRuntimeProbeTests {
    @Test("Synthetic encrypted audio and video exercise playback controls",
          .enabled(if: ProcessInfo.processInfo.environment["DUAL_STREAM_PROBE_BASE_URL"] != nil))
    func syntheticPlayback() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["DUAL_STREAM_PROBE_BASE_URL"].flatMap(URL.init(string:)))
        try #require(MTLCreateSystemDefaultDevice() != nil)
        let key = try LivePlaybackDecryption(method: .cenc, key: "00112233445566778899aabbccddeeff")
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: base.appendingPathComponent("audio.mp4"), userAgent: "fixture-agent", headers: [:], decryption: key
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
        try await waitUntil { player.audioIsAligned || probe.finished }
        try #require(!probe.finished && player.audioIsAligned, "Initial audio alignment failed")
        try await waitUntil { player.currentPlaybackTime > 1 || probe.finished }
        try #require(!probe.finished)
        try await sampleDrift(player, probe: probe, label: "1x", seconds: 10)
        player.pause()
        let pausedVideo = player.currentPlaybackTime
        let pausedAudio = try #require(player.audioCurrentPlaybackTime)
        try await Task.sleep(for: .milliseconds(300))
        print("DualStream probe pause videoDelta=\(player.currentPlaybackTime - pausedVideo) audioDelta=\((player.audioCurrentPlaybackTime ?? pausedAudio) - pausedAudio)")
        for (position, rate): (TimeInterval, Float) in [(0, 1), (10, 1.5), (20, 2)] {
            let seekOK: Bool
            if position == 0 {
                seekOK = await (player as any MediaPlayerProtocol).seek(time: position)
            } else {
                seekOK = await seek(player, to: position)
            }
            try #require(seekOK, "Primary seek failed")
            let confirmedPosition = player.currentPlaybackTime
            print("DualStream probe confirmed target=\(position) video=\(confirmedPosition)")
            player.playbackRate = rate
            player.play()
            try await waitUntil { player.audioIsAligned || probe.finished }
            try #require(!probe.finished && player.audioIsAligned, "Audio seek alignment failed")
            print("DualStream probe seek target=\(position) video=\(player.currentPlaybackTime) audio=\(player.audioCurrentPlaybackTime ?? -1) rate=\(player.playbackRate) alignments=\(player.audioAlignmentCount)")
            try await sampleDrift(player, probe: probe, label: "seek-\(position)-rate-\(rate)", seconds: 2)
        }
        let endSeekOK = await seek(player, to: 42)
        #expect(endSeekOK)
        player.play()
        try await waitUntil { probe.finished }
        #expect(probe.error == nil)
        print("DualStream probe EOF endEvents=\(probe.endEvents) finishEvents=\(probe.finishEvents) audioFailures=\(player.audioFailureCount)")
    }

    private func seek(_ player: DualStreamPlayer, to time: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            player.seek(time: time) { continuation.resume(returning: $0) }
        }
    }

    private func sampleDrift(_ player: DualStreamPlayer, probe: Probe, label: String, seconds: Int) async throws {
        let wallStart = ContinuousClock.now
        var samples: [Double] = []
        for index in 1...seconds {
            let target = wallStart.advanced(by: .seconds(index))
            try await waitUntil { ContinuousClock.now >= target || probe.finished }
            try #require(!probe.finished)
            let videoTime = player.currentPlaybackTime
            let audioTime = try #require(player.audioCurrentPlaybackTime)
            samples.append(audioTime - videoTime)
            print("DualStream probe \(label) sample=\(index) elapsed=\(wallStart.duration(to: .now)) video=\(videoTime) audio=\(audioTime) drift=\(audioTime - videoTime) primaryPlaying=\(player.isPlaying) primaryLoad=\(player.loadState) primaryState=\(player.playbackState) fps=\(player.dynamicInfo.displayFPS) droppedFrames=\(player.dynamicInfo.droppedVideoFrameCount) audioLoad=\(String(describing: player.audioLoadState)) audioState=\(String(describing: player.audioPlaybackState)) aligned=\(player.audioIsAligned) alignments=\(player.audioAlignmentCount)")
        }
        print("DualStream probe \(label) samples=\(samples.count) driftMin=\(samples.min()!) driftMax=\(samples.max()!)")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition(), "Timed out waiting for player state")
    }

    @MainActor private final class Probe: MediaPlayerDelegate {
        var endEvents = 0
        var finishEvents = 0
        var error: Error?
        var finished: Bool { finishEvents > 0 }
        func readyToPlay(player: some MediaPlayerProtocol) {}
        func changeLoadState(player: some MediaPlayerProtocol) {}
        func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {}
        func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) {}
        func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
        func reachEndOfStream(player: some MediaPlayerProtocol) { endEvents += 1 }
        func finish(player: some MediaPlayerProtocol, error: Error?) { finishEvents += 1; self.error = error }
        func playerDidClear(player: some MediaPlayerProtocol) {}
    }
}
#endif
