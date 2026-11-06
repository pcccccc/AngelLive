#if canImport(KSPlayer)
import AngelLiveCore
import AVFoundation
import AVKit
import Foundation
import KSPlayer
import os
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One logical player, with video as the timeline and the optional audio as a follower.
/// KSPlayerLayer owns the synchronous legacy API on MainActor. Seeking also has a
/// nonisolated callback entry because MediaPlayback's async extension leaves that actor.
@MainActor
public final class DualStreamPlayer: NSObject, @preconcurrency MediaPlayerProtocol, MediaPlayerDelegate {
    typealias PlayerFactory = @MainActor (URL, KSOptions) -> any MediaPlayerProtocol
    private let primaryFactory: PlayerFactory
    private let audioFactory: PlayerFactory
    private let container = UIView(frame: .zero)
    private let renderClock: DualStreamRenderClock
    private var primary: any MediaPlayerProtocol
    private var primaryNeedsStop = true
    private var audio: (any MediaPlayerProtocol)?
    private var options: PlayerOptions?
    private var inputError: DualStreamPlayerError?
    private var generation: UInt64 = 0
    private var alignmentGeneration: UInt64 = 0
    private var seekGeneration: UInt64 = 0
    private struct PendingSeek {
        let token: UInt64
        let completion: @MainActor @Sendable (Bool) -> Void
    }
    private var pendingSeek: PendingSeek?
    private var isPreparing = false
    private var acceptingCallbacks = true
    private var isSeeking = false
    private var wantsPlayback = false
    private var hasFinished = false
    private var aligning = false
    private var aligned = false
    private var muted = false
    private var volume: Float = 1
    private var mode: UIViewContentMode = .scaleAspectFit
    private var rate: Float
    private var audioFailed = false
    private var audioHasEnded = false
    private var notifiedInputError = false
    private var reportedAudioReady = false
    private var reportedFirstAlignment = false
    private static let logger = Logger(subsystem: "AngelLiveDependencies", category: "DualStream")
    public weak var delegate: MediaPlayerDelegate?
    private lazy var coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)

    // Internal, read-only observations for deterministic regression tests and local probes.
    var audioCurrentPlaybackTime: TimeInterval? { audio?.currentPlaybackTime }
    var audioPlaybackState: MediaPlaybackState? { audio?.playbackState }
    var audioLoadState: MediaLoadState? { audio?.loadState }
    var audioIsAligned: Bool { aligned }
    private(set) var audioAlignmentCount = 0
    private(set) var audioFailureCount = 0
    enum AudioStopReason: String { case ended, inputFailure, seekFailure, unseekable }
    private(set) var audioStopReason: AudioStopReason?
    var audioDrift: TimeInterval? {
        guard let audio else { return nil }
        let drift = audio.currentPlaybackTime - primary.currentPlaybackTime
        return drift.isFinite ? drift : nil
    }

    public required convenience init(url: URL, options: KSOptions, formatContext: FormatContext?) {
        self.init(url: url, options: options, primaryFactory: { url, options in
            if (options as? PlayerOptions)?.mediaTransform != nil {
                return MediaTransformPlayer(url: url, options: options)
            }
            return KSMEPlayer(url: url, options: options)
        }, audioFactory: { KSMEPlayer(url: $0, options: $1) })
        if let formatContext {
            // This input never belongs to either child player.
            formatContext.close()
            inputError = .unsupportedInput
        }
    }

    init(url: URL, options: KSOptions, primaryFactory: @escaping PlayerFactory, audioFactory: @escaping PlayerFactory) {
        self.primaryFactory = primaryFactory
        self.audioFactory = audioFactory
        let snapshot = (options as? PlayerOptions)?.dualStreamVideoSessionSnapshot()
        let clock = DualStreamRenderClock()
        renderClock = clock
        snapshot?.dualStreamClock = { [weak clock] in clock?.time }
        self.options = snapshot
        rate = options.startPlayRate
        primary = primaryFactory(url, snapshot ?? options)
        super.init()
        installPrimaryView()
        primary.delegate = self
        primary.isMuted = true
        if snapshot?.dualStreamAudio == nil { inputError = .missingAudioOptions }
        installAudio()
    }

    // The layer must stop players before release, matching MediaPlayerProtocol's contract.
    isolated deinit {
        let cancelledSeek = pendingSeek
        pendingSeek = nil
        primary.delegate = nil
        audio?.delegate = nil
        audio?.isMuted = true
        audio?.stop()
        if primaryNeedsStop { primary.stop() }
        cancelledSeek?.completion(false)
    }


    private func installAudio() {
        guard let options, let configuration = options.dualStreamAudio, inputError == nil else { return }
        // No KSPlayerLayer is created for audio: remote commands and Now Playing remain
        // owned by the host layer. The pinned KSMEPlayer still configures its shared
        // AVAudioSession and route observers during init; this is not a second session.
        let follower = audioFactory(configuration.url, configuration.options(from: options))
        audio = follower
        renderClock.follower = follower
        follower.delegate = self
        follower.isMuted = true
        follower.playbackVolume = volume
        follower.playbackRate = rate
    }

    private func installPrimaryView() {
        let surface = primary.view
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func diagnose(_ event: String) {
        guard UserDefaults.shared.bool(forKey: GeneralSettingModel.globalDeveloperMode) else { return }
        let driftMilliseconds = (audioDrift ?? 0) * 1_000
        Self.logger.info("event=\(event, privacy: .public) alignment=\(self.audioAlignmentCount) driftMilliseconds=\(driftMilliseconds)")
    }

    public var view: UIView { container }
    public var duration: TimeInterval { primary.duration }
    public var fileSize: Int64 { primary.fileSize }
    public var naturalSize: CGSize { primary.naturalSize }
    public var chapters: [Chapter] { primary.chapters }
    public var currentPlaybackTime: TimeInterval { primary.currentPlaybackTime }
    public var dynamicInfo: DynamicInfo { primary.dynamicInfo }
    public var ioContext: AbstractAVIOContext? { primary.ioContext }
    public var playableTime: TimeInterval { primary.playableTime }
    public var isReadyToPlay: Bool { primary.isReadyToPlay }
    public var playbackState: MediaPlaybackState { primary.playbackState }
    public var loadState: MediaLoadState { primary.loadState }
    public var isPlaying: Bool { primary.isPlaying }
    public var seekable: Bool { primary.seekable }
    public var subtitleDataSource: (any ConstantSubtitleDataSource)? { primary.subtitleDataSource }
    public var playbackCoordinator: AVPlaybackCoordinator { coordinator }
    public var contentMode: UIViewContentMode {
        get { mode }
        set { mode = newValue; primary.contentMode = newValue }
    }
    public var playbackRate: Float {
        get { rate }
        set {
            suspendAudio()
            rate = newValue
            primary.playbackRate = newValue
            audio?.playbackRate = newValue
            synchronizeAudio()
        }
    }
    public var playbackVolume: Float {
        get { volume }
        set { volume = newValue; audio?.playbackVolume = newValue }
    }
    public var isMuted: Bool {
        get { muted }
        set { muted = newValue; audio?.isMuted = newValue || !aligned || !primary.isPlaying }
    }
    // A video-only route/PiP would bypass the logical command owner. These optional
    // presentations remain unavailable for separate audio until both streams can move.
    public var allowsExternalPlayback: Bool { get { false } set {} }
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool { get { false } set {} }
    public var isExternalPlaybackActive: Bool { false }
    public var pipController: KSPictureInPictureProtocol? { get { nil } set {} }
    public func configPIP() {}

    public func prepareToPlay() {
        guard !isPreparing else { return }
        guard let inputError else {
            guard primaryNeedsStop else { return }
            isPreparing = true
            acceptingCallbacks = true
            hasFinished = false
            primary.prepareToPlay()
            audio?.prepareToPlay()
            return
        }
        guard !notifiedInputError else { return }
        notifiedInputError = true
        delegate?.finish(player: self, error: inputError)
    }

    public func play() {
        guard primaryNeedsStop else { return }
        wantsPlayback = true
        hasFinished = false
        primary.play()
        synchronizeAudio()
    }

    public func pause() {
        wantsPlayback = false
        suspendAudio()
        primary.pause()
    }

    private func suspendAudio() {
        renderClock.isAligned = false
        alignmentGeneration &+= 1
        aligning = false
        aligned = false
        audio?.isMuted = true
        audio?.pause()
    }

    private func synchronizeAudio() {
        guard let audio, !audioFailed, !audioHasEnded, !hasFinished else { return }
        guard wantsPlayback, !isSeeking, primary.isPlaying,
              primary.isReadyToPlay, primary.loadState == .playable else {
            if aligned || aligning || audio.playbackState == .playing { suspendAudio() }
            return
        }
        guard audio.isReadyToPlay, audio.loadState == .playable else { return }
        if aligned {
            audio.playbackRate = rate
            audio.isMuted = muted
            if !audio.isPlaying { audio.play() }
            renderClock.isAligned = audio.isPlaying
            return
        }
        guard !aligning else { return }
        guard audio.seekable, primary.currentPlaybackTime.isFinite else { stopAudio(reason: .unseekable); return }
        aligning = true
        let itemToken = generation
        let seekToken = alignmentGeneration
        let target = primary.currentPlaybackTime
        audioAlignmentCount += 1
        audio.isMuted = true
        audio.pause()
        audio.seek(time: target) { [weak self, weak audio] succeeded in
            guard let self, let audio, self.generation == itemToken,
                  self.alignmentGeneration == seekToken, self.audio === audio else { return }
            self.aligning = false
            guard succeeded else { self.stopAudio(reason: .seekFailure); return }
            self.aligned = true
            if !self.reportedFirstAlignment {
                self.reportedFirstAlignment = true
                self.diagnose("aligned")
            }
            // The primary may have paused or started buffering during this seek.
            self.synchronizeAudio()
        }
    }

    private func stopAudio(reason: AudioStopReason) {
        guard !audioFailed, !(reason == .ended && audioHasEnded) else { return }
        audioStopReason = reason
        diagnose(reason.rawValue)
        if reason == .ended {
            audioHasEnded = true
            suspendAudio()
            return
        }
        audioFailed = true
        audioFailureCount += 1
        suspendAudio()
        let previous = audio
        audio = nil
        renderClock.follower = nil
        previous?.delegate = nil
        previous?.stop()
    }

    public nonisolated func seek(time: TimeInterval, completion: @MainActor @escaping @Sendable (Bool) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.seekPrimary(time: time, completion: completion) }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { completion(false); return }
            self.seekPrimary(time: time, completion: completion)
        }
    }

    public func seek(time: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            seekPrimary(time: time) { continuation.resume(returning: $0) }
        }
    }

    private func seekPrimary(time: TimeInterval, completion: @MainActor @escaping @Sendable (Bool) -> Void) {
        guard time.isFinite, acceptingCallbacks, primaryNeedsStop else { completion(false); return }
        let cancelledSeek = pendingSeek
        suspendAudio()
        isSeeking = true
        seekGeneration &+= 1
        let token = generation
        let seekToken = seekGeneration
        pendingSeek = PendingSeek(token: seekToken, completion: completion)
        // The pinned item keeps one completion and can overwrite it while seeking.
        // The logical owner settles superseded callers even if the child never calls back.
        cancelledSeek?.completion(false)
        guard pendingSeek?.token == seekToken, generation == token else { return }
        primary.seek(time: time) { [weak self] succeeded in
            guard let self, self.generation == token, self.seekGeneration == seekToken,
                  let pending = self.pendingSeek, pending.token == seekToken else { return }
            self.pendingSeek = nil
            self.isSeeking = false
            if succeeded, self.audioHasEnded, let audio = self.audio, time < audio.duration {
                self.audioHasEnded = false
                self.audioStopReason = nil
            }
            // Seek completion remains the primary's result. The host explicitly decides
            // whether to resume; audio cannot resume a failed or paused video seek.
            pending.completion(succeeded)
            guard self.generation == token else { return }
            self.synchronizeAudio()
        }
    }

    private func clear(stopped: Bool) {
        let cancelledSeek = pendingSeek
        pendingSeek = nil
        let notifyClear = acceptingCallbacks
        acceptingCallbacks = false
        generation &+= 1
        seekGeneration &+= 1
        suspendAudio()
        wantsPlayback = false
        isPreparing = false
        isSeeking = false
        hasFinished = false
        let previous = audio
        audio = nil
        renderClock.follower = nil
        previous?.delegate = nil
        previous?.stop()
        if stopped {
            if primaryNeedsStop { primary.stop(); primaryNeedsStop = false }
        } else { primary.reset() }
        if notifyClear { delegate?.playerDidClear(player: self) }
        cancelledSeek?.completion(false)
    }
    public func reset() { clear(stopped: false) }
    public func stop() { clear(stopped: true) }

    public func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {
        primary.delegate = nil
        clear(stopped: true)
        primary.view.removeFromSuperview()
        self.options = (options as? PlayerOptions)?.dualStreamVideoSessionSnapshot()
        optionsSnapshotClock()
        audioFailed = false
        audioHasEnded = false
        audioFailureCount = 0
        audioAlignmentCount = 0
        audioStopReason = nil
        reportedAudioReady = false
        reportedFirstAlignment = false
        notifiedInputError = false
        inputError = self.options?.dualStreamAudio == nil ? .missingAudioOptions : nil
        rate = options.startPlayRate
        switch io {
        case let .left(url):
            primary = primaryFactory(url, self.options ?? options)
            primaryNeedsStop = true
            acceptingCallbacks = true
            primary.delegate = self
            primary.isMuted = true
            primary.playbackRate = rate
            primary.contentMode = mode
            installPrimaryView()
            installAudio()
        case let .right(context):
            context.close()
            inputError = .unsupportedInput
        }
    }

    private func optionsSnapshotClock() {
        options?.dualStreamClock = { [weak renderClock] in renderClock?.time }
    }

    public func startRecord(url: URL) { primary.startRecord(url: url) }
    public func stopRecord() { primary.stopRecord() }
    public func tracks(mediaType: AVMediaType) -> [MediaPlayerTrack] {
        mediaType == .audio ? (audio?.tracks(mediaType: mediaType) ?? []) : primary.tracks(mediaType: mediaType)
    }
    public func select(track: some MediaPlayerTrack) {
        if track.mediaType == .audio {
            suspendAudio()
            audio?.select(track: track)
            synchronizeAudio()
        } else { primary.select(track: track) }
    }
    public func enterBackground() {
        // KSPlayerLayer already pauses when background playback is disallowed.
        // If it calls this hook while still playing, audio follows that same intent.
        primary.enterBackground()
        audio?.enterBackground()
        synchronizeAudio()
    }
    public func enterForeground() {
        primary.enterForeground()
        // The follower has video disabled. KSMEPlayer's foreground video refresh
        // performs its own seek; the logical owner aligns audio explicitly instead.
        suspendAudio()
        synchronizeAudio()
    }
    public func thumbnailImageAtCurrentTime() async -> CGImage? { await primary.thumbnailImageAtCurrentTime() }

    public func readyToPlay(player: some MediaPlayerProtocol) {
        guard acceptingCallbacks, primary === player || audio === player else { return }
        if primary === player { delegate?.readyToPlay(player: self) }
        else if !reportedAudioReady {
            reportedAudioReady = true
            diagnose("ready")
        }
        synchronizeAudio()
    }
    public func changeLoadState(player: some MediaPlayerProtocol) {
        guard acceptingCallbacks, primary === player || audio === player else { return }
        if primary === player { delegate?.changeLoadState(player: self) }
        else if aligned, player.loadState != .playable { suspendAudio() }
        synchronizeAudio()
    }
    public func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) {
        if acceptingCallbacks, primary === player { delegate?.changeBuffering(player: self, progress: progress) }
    }
    public func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) {
        if acceptingCallbacks, primary === player {
            synchronizeAudio()
            delegate?.changePlaybackTime(player: self, time: time)
        }
    }
    public func playBack(player: some MediaPlayerProtocol, loopCount: Int) {
        if acceptingCallbacks, primary === player { suspendAudio(); delegate?.playBack(player: self, loopCount: loopCount) }
    }
    public func reachEndOfStream(player: some MediaPlayerProtocol) {
        if acceptingCallbacks, primary === player {
            // Demux EOF can precede presentation EOF. Do not cut off buffered audio.
            delegate?.reachEndOfStream(player: self)
        }
    }
    public func finish(player: some MediaPlayerProtocol, error: Error?) {
        guard acceptingCallbacks else { return }
        if primary === player {
            hasFinished = true
            wantsPlayback = false
            suspendAudio()
            delegate?.finish(player: self, error: error)
        } else if audio === player { stopAudio(reason: error == nil ? .ended : .inputFailure) }
    }
    public func playerDidClear(player: some MediaPlayerProtocol) {
        if acceptingCallbacks, primary === player { suspendAudio(); delegate?.playerDidClear(player: self) }
    }
}

extension DualStreamPlayer: AVPlaybackCoordinatorPlaybackControlDelegate {
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPlayCommand) async {
        guard command.expectedCurrentItemIdentifier == coordinator.currentItemIdentifier else { return }
        play()
    }
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPauseCommand) async {
        guard command.expectedCurrentItemIdentifier == coordinator.currentItemIdentifier else { return }
        pause()
    }
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorSeekCommand) async {
        guard command.expectedCurrentItemIdentifier == coordinator.currentItemIdentifier else { return }
        // AVFoundation requires a coordinated seek to stay paused until a new PlayCommand.
        pause()
        _ = await seek(time: command.itemTime.seconds)
    }
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue _: AVDelegatingPlaybackCoordinatorBufferingCommand) async {}
}
#endif
