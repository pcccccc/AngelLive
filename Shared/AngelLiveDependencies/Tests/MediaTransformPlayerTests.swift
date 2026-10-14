#if canImport(KSPlayer)
import AngelLiveCore
import AVFoundation
import Foundation
import KSPlayer
import Metal
import Testing
import os
@testable import AngelLiveDependencies

@Suite("Transformed player session ownership")
@MainActor
struct MediaTransformPlayerTests {
    private enum FixtureError: Error, Equatable { case stoppedOpen, currentOpen }

    private func transform() throws -> LiveMediaTransform {
        try LiveMediaTransform(
            scope: LiveTransformScope(offsetInPeriod: 2, lengthPerPeriod: 4, periodBytes: 8, periodCount: 0),
            keygen: LiveKeygenSpec(seed: 1, saltBias: 2, saltMultiplier: 3,
                shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
                zeroState: 11, zeroKeyByte: 7, resetPerPeriod: true)
        )
    }

    private func quality(transform: LiveMediaTransform?) throws -> LiveQualityDetail {
        var hints: [String: Any] = ["streamFormat": "hlsLive", "preferredEngines": ["avPlayer"]]
        if let transform { hints["mediaTransform"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(transform)) }
        let json: [String: Any] = [
            "roomId": "room", "title": "quality", "qn": 0,
            "url": "https://example.invalid/live.m3u8", "liveCodeType": "m3u8", "liveType": "fixture.plugin",
            "playbackHints": hints
        ]
        return try JSONDecoder().decode(LiveQualityDetail.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("Conversion selects only its loader, then ordinary resources clear the old configuration")
    func configureAndClear() throws {
        let options = PlayerOptions()
        let transform = try transform()
        let transformed = KSPlayerSessionConfigurator.apply(quality: try quality(transform: transform), to: options,
            fallbackUserAgent: "fixture-agent", liveReconnectPolicy: .playerManaged)
        #expect(options.mediaTransform == transform)
        #expect(transformed.playerTypes.count == 1)
        #expect(transformed.playerTypes.first == MediaTransformPlayer.self)
        #expect(transformed.plan.isLive)
        #expect(!transformed.effectiveIsLive)
        #expect(options.isLive == false)
        let ordinary = KSPlayerSessionConfigurator.apply(quality: try quality(transform: nil), to: options,
            fallbackUserAgent: "fixture-agent", liveReconnectPolicy: .playerManaged)
        #expect(options.mediaTransform == nil)
        #expect(ordinary.playerTypes.first == KSAVPlayer.self)
        #expect(ordinary.effectiveIsLive)
    }

    @Test("Plain KSOptions cannot silently bypass a required transform")
    func unsupportedPlainOptions() throws {
        let options = KSOptions()
        let configuration = KSPlayerSessionConfigurator.apply(quality: try quality(transform: transform()), to: options,
            fallbackUserAgent: "fixture-agent", liveReconnectPolicy: .playerManaged)
        #expect(configuration.playerTypes.first == MediaTransformPlayer.self)
        let player = MediaTransformPlayer(url: URL(string: "https://example.invalid/live.m3u8")!, options: options)
        let delegate = DelegateProbe()
        player.delegate = delegate
        player.prepareToPlay()
        #expect(delegate.failedPlayers.count == 1)
        #expect(delegate.failedPlayers.first === player)
        #expect(delegate.errors.first as? MediaTransformPlayerError == .missingTransformOptions)
        player.stop()
    }

    @Test("An asynchronous open keeps the rate, seek position and headers from its own resource")
    func reusedOptionsCannotChangePendingResource() async throws {
        let options = PlayerOptions()
        options.mediaTransform = try transform()
        options.startPlayRate = 2
        options.startPlayTime = 17
        options.formatContextOptions["headers"] = "X-Fixture:original"
        let observed = OSAllocatedUnfairLock(initialState: (rate: Float(0), time: TimeInterval(0), headers: ""))
        let player = MediaTransformPlayer(url: URL(string: "https://example.invalid/live.m3u8")!, options: options) { _, openedOptions, _, _ in
            observed.withLock {
                $0 = (openedOptions.startPlayRate, openedOptions.startPlayTime,
                      openedOptions.formatContextOptions["headers"] as? String ?? "")
            }
            throw FixtureError.currentOpen
        }
        let delegate = DelegateProbe()
        player.delegate = delegate
        options.startPlayRate = 0.5
        options.startPlayTime = 0
        options.formatContextOptions["headers"] = "X-Fixture:replacement"
        options.mediaTransform = nil
        #expect(player.playbackRate == 2)
        player.prepareToPlay()
        try await waitUntil { delegate.failedPlayers.count == 1 }
        let opened = observed.withLock { $0 }
        #expect(opened.rate == 2)
        #expect(opened.time == 17)
        #expect(opened.headers == "X-Fixture:original")
        player.stop()
    }

    @Test("Real composed KSMEPlayer decodes transformed video and advances playback")
    func realPlayerDecodesAndAdvances() async throws {
        // This exercises the real renderer. An unavailable Metal environment is a
        // validation failure, rather than silently substituting a fake video clock.
        try #require(MTLCreateSystemDefaultDevice() != nil, "Real playback test requires a Metal device")
        let options = PlayerOptions()
        options.mediaTransform = try MediaTransformIntegrationTests.transform()
        options.audioOutputType = SilentFixtureAudioOutput.self
        options.videoDecodeType = .software
        options.renderUseDispatchSourceTimer = true
        options.preferredForwardBufferDuration = 0
        options.registerRemoteControll = false
        options.automaticWindowResize = false
        options.canStartPictureInPictureAutomaticallyFromInline = false
        options.isLoopPlay = false
        options.formatContextOptions["rw_timeout"] = 2_000_000
        let player = MediaTransformPlayer(
            url: try MediaTransformIntegrationTests.fixture("media-transform-master.m3u8"), options: options
        )
        defer { player.stop() }
        let delegate = DelegateProbe()
        player.delegate = delegate
        let surface = player.view
        surface.frame = CGRect(x: 0, y: 0, width: 160, height: 96)
        player.prepareToPlay()
        player.play()
        try await waitUntil(timeout: .seconds(10)) { !delegate.readyPlayers.isEmpty || !delegate.errors.isEmpty }
        try #require(delegate.errors.isEmpty, "Player opening failed: \(delegate.errors)")
        #expect(delegate.readyPlayers.count == 1)
        #expect(delegate.readyPlayers.first === player)
        #expect(player.isReadyToPlay)
        #expect(player.duration > 0)
        #expect(player.tracks(mediaType: .audio).isEmpty)
        #expect(player.tracks(mediaType: .video).contains { $0.isEnabled })
        #if os(macOS)
        surface.layoutSubtreeIfNeeded()
        #else
        surface.layoutIfNeeded()
        #endif
        try await waitUntil(timeout: .seconds(10)) {
            (player.currentPlaybackTime > 0.15 && delegate.playbackTimes.contains { $0 > 0.15 })
                || !delegate.errors.isEmpty
        }
        try #require(delegate.errors.isEmpty, "Player decoding failed: \(delegate.errors)")
        #expect(player.currentPlaybackTime > 0.15)
        #expect(delegate.playbackTimes.contains { $0 > 0.15 })
        let decodedFrame = try #require(await player.thumbnailImageAtCurrentTime())
        #expect(decodedFrame.width == 160)
        #expect(decodedFrame.height == 96)
        #expect(player.view === surface)
        player.stop()
        #expect(!player.isReadyToPlay)
        #expect(player.playbackState == .stopped)
        #expect(player.loadState == .idle)
        #expect(surface.subviews.isEmpty)
    }

    @Test("Stop interrupts background open; reset opens again and suppresses the cancelled generation")
    func cancelledOpenDoesNotReachDelegateAndResetReopens() async throws {
        let probe = OSAllocatedUnfairLock(initialState: (count: 0, finished: 0, background: false))
        let options = PlayerOptions()
        options.mediaTransform = try transform()
        let player = MediaTransformPlayer(url: URL(string: "https://example.invalid/live.m3u8")!, options: options) { _, _, _, interrupt in
            let count = probe.withLock { state in state.count += 1; state.background = !Thread.isMainThread; return state.count }
            defer { probe.withLock { $0.finished += 1 } }
            if count == 1 {
                // Runs only on the dedicated IO thread; never blocks the test's main actor.
                let deadline = Date().addingTimeInterval(3)
                while !interrupt.interrupt && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
                throw FixtureError.stoppedOpen
            }
            throw FixtureError.currentOpen
        }
        let delegate = DelegateProbe()
        player.delegate = delegate
        let view = player.view
        player.prepareToPlay()
        try await waitUntil { probe.withLock { $0.count == 1 } }
        #expect(probe.withLock { $0.background })
        player.stop()
        player.reset()
        player.prepareToPlay()
        try await waitUntil { delegate.failedPlayers.count == 1 }
        #expect(probe.withLock { $0.count == 2 && $0.finished == 2 })
        #expect(delegate.failedPlayers.first === player)
        #expect(delegate.errors.first as? FixtureError == .currentOpen)
        #expect(player.view === view)
        player.stop()
    }

    private func waitUntil(timeout: Duration = .seconds(4), _ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }

    @MainActor private final class DelegateProbe: MediaPlayerDelegate {
        var readyPlayers: [any MediaPlayerProtocol] = []
        var failedPlayers: [any MediaPlayerProtocol] = []
        var errors: [Error] = []
        var playbackTimes: [TimeInterval] = []
        func readyToPlay(player: some MediaPlayerProtocol) { readyPlayers.append(player) }
        func changeLoadState(player: some MediaPlayerProtocol) {}
        func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {}
        func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) { playbackTimes.append(time) }
        func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
        func reachEndOfStream(player: some MediaPlayerProtocol) {}
        func finish(player: some MediaPlayerProtocol, error: Error?) {
            failedPlayers.append(player)
            if let error { errors.append(error) }
        }
        func playerDidClear(player: some MediaPlayerProtocol) {}
    }

    /// The fixture has video only. Keep KSMEPlayer's required audio sink inert so
    /// this test never opens an audio engine or depends on an output device.
    private final class SilentFixtureAudioOutput: AudioOutput {
        weak var renderSource: AudioOutputRenderSourceDelegate?
        var playbackRate: Float = 1
        var volume: Float = 1
        var outputLatency: TimeInterval = 0
        var isMuted = true
        @MainActor init() {}
        @MainActor func prepare(audioFormat: AVAudioFormat) {}
        @MainActor func play() {}
        @MainActor func pause() {}
        func flush() {}
        func stop() {}
    }
}
#endif
