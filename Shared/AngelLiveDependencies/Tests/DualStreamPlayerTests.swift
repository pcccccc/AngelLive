#if canImport(KSPlayer)
import AngelLiveCore
import AVFoundation
import AVKit
import Foundation
import KSPlayer
import Testing
@testable import AngelLiveDependencies

@Suite("Separate audio player coordination")
@MainActor
struct DualStreamPlayerTests {
    private func setup() -> (DualStreamPlayer, FakePlayer, FakePlayer, Probe) {
        let video = FakePlayer()
        let audio = FakePlayer()
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        let player = DualStreamPlayer(url: URL(string: "https://media.example.invalid/video")!, options: options,
                                      primaryFactory: { _, _ in video }, audioFactory: { _, _ in audio })
        let probe = Probe()
        player.delegate = probe
        return (player, video, audio, probe)
    }

    private func combinedSetup(decryption: LivePlaybackDecryption? = nil)
        -> (DualStreamPlayer, [(URL, KSOptions)], () -> [FakePlayer], FakePlayer, Probe) {
        var created: [FakePlayer] = []
        var requests: [(URL, KSOptions)] = []
        let audio = FakePlayer()
        let options = PlayerOptions()
        options.formatContextOptions["decryption_key"] = decryption?.key
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio?sig=a&b=1")!, userAgent: "agent", headers: [:],
            decryption: decryption, sharesVideoRequest: true
        )
        let player = DualStreamPlayer(
            url: URL(string: "https://media.example.invalid/video")!, options: options,
            primaryFactory: { url, options in
                requests.append((url, options))
                let fake = FakePlayer()
                created.append(fake)
                return fake
            },
            audioFactory: { _, _ in audio }
        )
        let probe = Probe()
        player.delegate = probe
        return (player, requests, { created }, audio, probe)
    }

    @Test("A shared request opens video and audio through one combined manifest")
    func combinedInput() throws {
        let key = try LivePlaybackDecryption(method: .cenc, key: "00112233445566778899aabbccddeeff")
        let (player, requests, _, audio, _) = combinedSetup(decryption: key)
        #expect(player.usesCombinedInput)
        let (url, options) = try #require(requests.first)
        #expect(url.isFileURL && url.pathExtension == "mpd")
        let manifest = try String(contentsOf: url, encoding: .utf8)
        #expect(manifest.contains("https://media.example.invalid/video"))
        #expect(manifest.contains("audio?sig=a&amp;b=1"))
        #expect(options.formatContextOptions["cenc_decryption_key"] as? String == key.key)
        #expect(options.formatContextOptions["decryption_key"] == nil)
        #expect((options.formatContextOptions["protocol_whitelist"] as? String)?.contains("http") == true)
        // No follower player: a single demuxer owns the audio clock.
        player.prepareToPlay(); player.play()
        #expect(audio.seeks.isEmpty)
        player.isMuted = true
        player.playbackVolume = 0.3
        #expect(player.tracks(mediaType: .audio).isEmpty)
        player.stop()
    }

    @Test("A manifest open failure falls back to the two-player path for the same item")
    func combinedFallback() throws {
        let (player, _, created, audio, probe) = combinedSetup()
        player.prepareToPlay(); player.play()
        let combined = try #require(created().first)
        player.finish(player: combined, error: NSError(domain: "fixture", code: 1))
        #expect(!player.usesCombinedInput)
        #expect(probe.finishCount == 0)
        #expect(created().count == 2)
        // The rebuilt item aligns the follower as before.
        #expect(audio.seeks == [0])
        player.stop()
    }

    @Test("Errors after the combined input became ready are reported, not retried")
    func combinedLateError() throws {
        let (player, _, created, _, probe) = combinedSetup()
        player.prepareToPlay(); player.play()
        let combined = try #require(created().first)
        player.readyToPlay(player: combined)
        player.finish(player: combined, error: NSError(domain: "fixture", code: 1))
        #expect(player.usesCombinedInput)
        #expect(probe.finishCount == 1)
        player.stop()
    }

    @Test("Audio starts only after successful alignment and follows pause and buffering")
    func playbackAndBuffering() {
        let (player, video, audio, _) = setup()
        player.prepareToPlay()
        player.play()
        #expect(audio.seeks == [0])
        #expect(audio.isMuted)
        #expect(audio.playbackState != .playing)
        audio.completeSeek(true)
        #expect(player.audioIsAligned)
        #expect(audio.playbackState == .playing)
        #expect(!audio.isMuted)
        video.loadState = .loading
        player.changeLoadState(player: video)
        #expect(audio.isMuted)
        #expect(audio.playbackState == .paused)
        video.loadState = .playable
        video.currentPlaybackTime = 4
        player.changeLoadState(player: video)
        #expect(audio.seeks.last == 4)
        audio.completeSeek(true)
        player.pause()
        #expect(audio.isMuted)
        #expect(audio.playbackState == .paused)
        player.stop()
    }

    @Test("Seek follows confirmed video position; rate, volume and mute reach audio")
    func controls() {
        let (player, video, audio, _) = setup()
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        player.playbackVolume = 0.4
        player.isMuted = true
        #expect(audio.playbackVolume == 0.4)
        #expect(audio.isMuted)
        player.seek(time: 12) { _ in }
        #expect(audio.isMuted)
        video.currentPlaybackTime = 12
        video.completeSeek(true)
        #expect(audio.seeks.last == 12)
        audio.completeSeek(true)
        player.isMuted = false
        #expect(!audio.isMuted)
        player.playbackRate = 1.5
        #expect(video.playbackRate == 1.5)
        #expect(audio.playbackRate == 1.5)
        #expect(audio.isMuted)
        audio.completeSeek(true)
        #expect(!audio.isMuted)
        player.stop()
    }

    @Test("A confirmed seek to exactly zero aligns audio to zero")
    func seekToZero() {
        let (player, video, audio, _) = setup()
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        video.currentPlaybackTime = 8
        player.seek(time: 0) { _ in }
        video.currentPlaybackTime = 0
        video.completeSeek(true)
        #expect(audio.seeks.last == 0)
        audio.completeSeek(true)
        #expect(player.audioIsAligned)
        player.stop()
    }

    @Test("Audio failure and EOF never forward video finish or end events")
    func audioFailureIsIsolated() {
        for failure in [true, false] {
            let (player, _, audio, probe) = setup()
            player.prepareToPlay(); player.play(); audio.completeSeek(true)
            if failure {
                player.finish(player: audio, error: FixtureError.failed)
                #expect(player.audioFailureCount == 1)
            } else {
                player.reachEndOfStream(player: audio)
                player.finish(player: audio, error: nil)
            }
            #expect(probe.finishCount == 0)
            #expect(probe.endCount == 0)
            #expect(audio.isMuted)
            player.stop()
        }
    }

    @Test("Audio EOF followed by a backward seek realigns and resumes audio")
    func replayAfterAudioEOF() {
        let video = FakePlayer(), audio = FakePlayer()
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        let player = DualStreamPlayer(url: URL(string: "https://media.example.invalid/video")!, options: options,
            primaryFactory: { _, _ in video }, audioFactory: { _, _ in audio })
        let probe = Probe()
        player.delegate = probe
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        player.finish(player: audio, error: nil)
        #expect(player.audioFailureCount == 0)
        #expect(probe.finishCount == 0)
        video.currentPlaybackTime = 10
        player.seek(time: 4) { _ in }
        video.currentPlaybackTime = 4
        video.completeSeek(true)
        #expect(audio.seeks.last == 4)
        audio.completeSeek(true)
        #expect(audio.playbackState == .playing)
        #expect(!audio.isMuted)
        player.stop()
    }

    @Test("A late audio seek cannot restart sound after pause")
    func lateSeekAfterPause() {
        let (player, _, audio, _) = setup()
        player.prepareToPlay(); player.play()
        player.pause()
        audio.completeSeek(true)
        #expect(!player.audioIsAligned)
        #expect(audio.isMuted)
        #expect(audio.playbackState != .playing)
        player.stop()
    }

    @Test("Replacing an item rejects old seek and delegate callbacks")
    func replacementInvalidatesOldCallbacks() {
        let oldVideo = FakePlayer(), newVideo = FakePlayer()
        let oldAudio = FakePlayer(), newAudio = FakePlayer()
        var videoCount = 0, audioCount = 0
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        let player = DualStreamPlayer(url: URL(string: "https://media.example.invalid/old")!, options: options,
            primaryFactory: { _, _ in videoCount += 1; return videoCount == 1 ? oldVideo : newVideo },
            audioFactory: { _, _ in audioCount += 1; return audioCount == 1 ? oldAudio : newAudio })
        let probe = Probe()
        player.delegate = probe
        player.prepareToPlay(); player.play()
        player.replace(io: .left(URL(string: "https://media.example.invalid/new")!), options: options)
        player.prepareToPlay(); player.play()
        oldAudio.completeSeek(true)
        player.finish(player: oldAudio, error: FixtureError.failed)
        player.finish(player: oldVideo, error: FixtureError.failed)
        #expect(!player.audioIsAligned)
        #expect(newAudio.isMuted)
        #expect(probe.finishCount == 0)
        newAudio.completeSeek(true)
        #expect(player.audioIsAligned)
        #expect(newAudio.playbackState == .playing)
        player.stop()
    }

    @Test("Replacing a resource preserves the selected video content mode")
    func replacementPreservesContentMode() {
        let oldVideo = FakePlayer(), newVideo = FakePlayer(), audio = FakePlayer()
        var videoCount = 0
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        let player = DualStreamPlayer(url: URL(string: "https://media.example.invalid/old")!, options: options,
            primaryFactory: { _, _ in videoCount += 1; return videoCount == 1 ? oldVideo : newVideo },
            audioFactory: { _, _ in audio })
        player.contentMode = .scaleAspectFill
        #expect(oldVideo.contentMode == .scaleAspectFill)
        player.replace(io: .left(URL(string: "https://media.example.invalid/new")!), options: options)
        #expect(newVideo.contentMode == .scaleAspectFill)
        #expect(player.contentMode == .scaleAspectFill)
        player.stop()
    }

    @Test("Audio buffering pauses output until realignment")
    func audioBuffering() {
        let (player, video, audio, _) = setup()
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        audio.loadState = .loading
        player.changeLoadState(player: audio)
        #expect(audio.isMuted)
        #expect(audio.playbackState == .paused)
        video.currentPlaybackTime = 6
        audio.loadState = .playable
        player.changeLoadState(player: audio)
        #expect(audio.seeks.last == 6)
        audio.completeSeek(true)
        #expect(audio.playbackState == .playing)
        player.stop()
    }

    @Test("Stopped primary callbacks cannot reach the host")
    func lateCallbacksAfterStop() {
        let (player, video, _, probe) = setup()
        player.prepareToPlay(); player.play(); player.stop()
        player.finish(player: video, error: FixtureError.failed)
        player.reachEndOfStream(player: video)
        player.changeLoadState(player: video)
        #expect(probe.finishCount == 0)
        #expect(probe.endCount == 0)
        #expect(probe.loadCount == 0)
    }

    @Test("Older seek completion cannot resume audio while a newer seek is pending")
    func overlappingSeeks() {
        let (player, video, audio, _) = setup()
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        var results: [Bool] = []
        player.seek(time: 3) { results.append($0) }
        player.seek(time: 8) { results.append($0) }
        #expect(results == [false])
        video.completeSeek(true)
        #expect(results == [false])
        #expect(audio.isMuted)
        video.currentPlaybackTime = 8
        video.completeSeek(true)
        #expect(results == [false, true])
        #expect(audio.seeks.last == 8)
        audio.completeSeek(true)
        #expect(player.audioIsAligned)
        player.stop()
    }

    @Test("Stopping resolves a pending seek even if the underlying player never calls back")
    func stopResolvesPendingSeek() {
        let (player, video, _, _) = setup()
        player.prepareToPlay(); player.play()
        var results: [Bool] = []
        player.seek(time: 4) { results.append($0) }
        player.stop()
        #expect(results == [false])
        video.completeSeek(true)
        #expect(results == [false])
    }

    @Test("Replacing an item resolves a pending seek exactly once")
    func replacementResolvesPendingSeek() {
        let (player, video, _, _) = setup()
        player.prepareToPlay(); player.play()
        var results: [Bool] = []
        player.seek(time: 4) { results.append($0) }
        let options = PlayerOptions()
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/new-audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        player.replace(io: .left(URL(string: "https://media.example.invalid/new-video")!), options: options)
        #expect(results == [false])
        video.completeSeek(true)
        #expect(results == [false])
        player.stop()
    }

    @Test("Background hook preserves active playback until host pauses")
    func backgroundPlayback() {
        let (player, _, audio, _) = setup()
        player.prepareToPlay(); player.play(); audio.completeSeek(true)
        player.enterBackground()
        #expect(audio.playbackState == .playing)
        #expect(!audio.isMuted)
        player.pause()
        #expect(audio.playbackState == .paused)
        #expect(audio.isMuted)
        player.stop()
    }

    @Test("Frozen, reversed, and unavailable audio clocks release video pacing")
    func renderClockFallback() {
        let audio = FakePlayer()
        let clock = DualStreamRenderClock()
        clock.follower = audio
        clock.isAligned = true
        audio.play()
        audio.currentPlaybackTime = 1
        #expect(clock.time == nil)
        audio.currentPlaybackTime = 1.1
        #expect(clock.time == 1.1)
        #expect(clock.time == nil)
        audio.currentPlaybackTime = 0.9
        #expect(clock.time == nil)
        audio.currentPlaybackTime = .nan
        #expect(clock.time == nil)
        audio.currentPlaybackTime = 2
        #expect(clock.time == nil)
        audio.currentPlaybackTime = 2.1
        #expect(clock.time == 2.1)
        audio.loadState = .loading
        #expect(clock.time == nil)
        audio.loadState = .playable
        #expect(clock.time == nil)
        audio.pause()
        #expect(clock.time == nil)
    }

    @Test("Only video options receive the dual-stream render clock and accurate seek")
    func isolatedOptions() throws {
        let video = FakePlayer(), audio = FakePlayer()
        var videoOptions: PlayerOptions?
        var audioOptions: PlayerOptions?
        let options = PlayerOptions()
        options.isAccurateSeek = false
        options.isSeekedAutoPlay = true
        options.dualStreamAudio = DualStreamAudioConfiguration(
            url: URL(string: "https://media.example.invalid/audio")!, userAgent: "audio-agent", headers: [:], decryption: nil
        )
        let player = DualStreamPlayer(url: URL(string: "https://media.example.invalid/video")!, options: options,
            primaryFactory: { _, options in videoOptions = options as? PlayerOptions; return video },
            audioFactory: { _, options in audioOptions = options as? PlayerOptions; return audio })
        let primary = try #require(videoOptions)
        let follower = try #require(audioOptions)
        #expect(primary is DualStreamVideoOptions)
        #expect(primary.isAccurateSeek)
        #expect(!primary.isSeekedAutoPlay)
        #expect(primary.dualStreamClock != nil)
        let copied = primary.mediaTransformSessionSnapshot()
        #expect(copied is DualStreamVideoOptions)
        #expect(copied.dualStreamClock != nil)
        #expect(!(follower is DualStreamVideoOptions))
        #expect(follower.dualStreamClock == nil)
        #expect(!options.isAccurateSeek)
        #expect(options.isSeekedAutoPlay)
        player.stop()
    }

    private enum FixtureError: Error { case failed }

    @MainActor private final class Probe: MediaPlayerDelegate {
        var finishCount = 0
        var endCount = 0
        var loadCount = 0
        func readyToPlay(player: some MediaPlayerProtocol) {}
        func changeLoadState(player: some MediaPlayerProtocol) { loadCount += 1 }
        func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {}
        func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) {}
        func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
        func reachEndOfStream(player: some MediaPlayerProtocol) { endCount += 1 }
        func finish(player: some MediaPlayerProtocol, error: Error?) { finishCount += 1 }
        func playerDidClear(player: some MediaPlayerProtocol) {}
    }

    @MainActor private final class FakePlayer: NSObject, @preconcurrency MediaPlayerProtocol {
        weak var delegate: MediaPlayerDelegate?
        let view = UIView()
        var duration: TimeInterval = 45
        var fileSize: Int64 = 0
        var naturalSize: CGSize = .zero
        var chapters: [Chapter] = []
        var currentPlaybackTime: TimeInterval = 0
        var playbackRate: Float = 1
        let dynamicInfo = DynamicInfo(metadata: { [:] }, bytesRead: { 0 }, audioBitrate: { 0 }, videoBitrate: { 0 })
        var ioContext: AbstractAVIOContext? { nil }
        var playableTime: TimeInterval = 45
        var isReadyToPlay = true
        var playbackState: MediaPlaybackState = .idle
        var loadState: MediaLoadState = .playable
        var seekable = true
        var isMuted = false
        var allowsExternalPlayback = false
        var usesExternalPlaybackWhileExternalScreenIsActive = false
        var playbackVolume: Float = 1
        var subtitleDataSource: (any ConstantSubtitleDataSource)? { nil }
        private let coordinatorPlayer = AVPlayer()
        var playbackCoordinator: AVPlaybackCoordinator { coordinatorPlayer.playbackCoordinator }
        var pipController: KSPictureInPictureProtocol?
        var seeks: [TimeInterval] = []
        var pendingSeeks: [@MainActor @Sendable (Bool) -> Void] = []
        override init() { super.init() }
        required init(url: URL, options: KSOptions, formatContext: FormatContext?) { super.init() }
        func prepareToPlay() {}
        func seek(time: TimeInterval, completion: @MainActor @escaping @Sendable (Bool) -> Void) { seeks.append(time); pendingSeeks.append(completion) }
        func completeSeek(_ result: Bool) { guard !pendingSeeks.isEmpty else { return }; pendingSeeks.removeFirst()(result) }
        func play() { playbackState = .playing }
        func pause() { playbackState = .paused }
        func stop() { playbackState = .stopped }
        func reset() { playbackState = .idle }
        func replace(playerItem _: PlayerItem, options _: KSOptions) {}
        func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {}
        func startRecord(url: URL) {}
        func stopRecord() {}
        func enterBackground() {}
        func enterForeground() {}
        func thumbnailImageAtCurrentTime() async -> CGImage? { nil }
        func tracks(mediaType: AVMediaType) -> [MediaPlayerTrack] { [] }
        func select(track: some MediaPlayerTrack) {}
        func configPIP() {}
    }
}
#endif
