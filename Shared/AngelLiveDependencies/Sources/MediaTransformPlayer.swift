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

public enum MediaTransformPlayerError: Error, LocalizedError, Sendable, Equatable {
    case missingTransformOptions
    case unsupportedInput

    public var errorDescription: String? {
        switch self {
        case .missingTransformOptions: "Media transform requires resource-specific PlayerOptions."
        case .unsupportedInput: "Media transform requires a URL opened by its resource loader."
        }
    }
}

/// One cancellable open. The flag is shared with FFmpeg's synchronous interrupt callback.
/// Options are a private snapshot; nobody mutates them while the IO queue is opening.
private final class MediaTransformOpen: @unchecked Sendable {
    let url: URL
    let options: KSOptions
    let transform: LiveMediaTransform
    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    lazy var interrupt = IOInterruptContext { [cancelled] in cancelled.withLock { $0 } }

    @MainActor init(url: URL, options: PlayerOptions, transform: LiveMediaTransform) {
        self.url = url
        self.transform = transform
        self.options = options.mediaTransformSessionSnapshot()
    }

    func cancel() { cancelled.withLock { $0 = true } }
}

/// A synchronous legacy-protocol bridge, not shared mutable storage. Its value is
/// produced and consumed in the same synchronous call while UIKit stays on main.
private struct MediaTransformMainResult<Value>: @unchecked Sendable {
    let value: Value
}

/// FormatContext is created on IO and then transferred exactly once to KSMEPlayer.
/// A rejected result is closed on IO. The lock only protects this ownership handoff.
private final class MediaTransformContextHandoff: @unchecked Sendable {
    private let context: OSAllocatedUnfairLock<FormatContext?>
    init(_ context: FormatContext) { self.context = .init(initialState: context) }
    func take() -> FormatContext? { context.withLock { value in defer { value = nil }; return value } }
    func close() { take()?.close() }
    deinit { close() }
}

/// Keeps the host's player identity and view stable while opening transformed input.
/// All player/UI state is MainActor-owned. Nonisolated legacy protocol calls use a
/// synchronous main-queue bridge; only the private open/handoff cross the IO queue.
public final class MediaTransformPlayer: NSObject, MediaPlayerProtocol, MediaPlayerDelegate, @unchecked Sendable {
    typealias ContextFactory = @Sendable (URL, KSOptions, LiveMediaTransform, IOInterruptContext) throws -> FormatContext
    private let ioQueue = DispatchQueue(label: "AngelLive.media-transform.open", qos: .userInitiated)
    private let factory: ContextFactory
    private struct Lifetime: Sendable {
        var resource: MediaTransformOpen?
        var player: KSMEPlayer?
    }
    // An ownership record for nonisolated deinit only; normal access remains main-owned.
    private let lifetime = OSAllocatedUnfairLock(initialState: Lifetime())
    @MainActor private var inner: KSMEPlayer?
    @MainActor private var container: UIView
    @MainActor private weak var hostDelegate: MediaPlayerDelegate?
    @MainActor private var url: URL
    @MainActor private var options: KSOptions
    @MainActor private var inputError: MediaTransformPlayerError?
    @MainActor private var opening: MediaTransformOpen?
    @MainActor private var inputFailure: (@Sendable () -> Error?)?
    @MainActor private var reportedInputFailure = false
    @MainActor private var generation: UInt64 = 0
    @MainActor private var requestedState: MediaPlaybackState = .idle
    @MainActor private var openingLoadState: MediaLoadState = .idle
    @MainActor private var volume: Float = 1
    @MainActor private var muted = false
    @MainActor private var externalPlayback = false
    @MainActor private var externalScreenPlayback = false
    @MainActor private var rate: Float = 1
    @MainActor private var mode: UIViewContentMode = .scaleAspectFit
    @MainActor private var pendingPIP: KSPictureInPictureProtocol?
    @MainActor private let fallbackCoordinatorPlayer = AVPlayer()
    private let emptyInfo = DynamicInfo(metadata: { [:] }, bytesRead: { 0 }, audioBitrate: { 0 }, videoBitrate: { 0 })

    @MainActor public required convenience init(url: URL, options: KSOptions, formatContext: FormatContext?) {
        self.init(url: url, options: options, factory: MediaTransformContextFactory.make)
        if let formatContext {
            inputError = .unsupportedInput
            let handoff = MediaTransformContextHandoff(formatContext)
            ioQueue.async { handoff.close() }
        }
    }

    @MainActor init(url: URL, options: KSOptions, factory: @escaping ContextFactory) {
        self.url = url
        self.options = (options as? PlayerOptions)?.mediaTransformSessionSnapshot() ?? options
        self.factory = factory
        rate = options.startPlayRate
        container = UIView(frame: .zero)
        super.init()
    }

    deinit {
        let owned = lifetime.withLock { state in defer { state = Lifetime() }; return state }
        owned.resource?.cancel()
        if let player = owned.player {
            DispatchQueue.main.async {
                player.delegate = nil
                player.stop()
                player.view.removeFromSuperview()
            }
        }
    }

    private func onMain<Value>(_ body: @MainActor @Sendable () -> Value) -> Value {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { MediaTransformMainResult(value: body()) }.value
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { MediaTransformMainResult(value: body()) }
        }.value
    }

    public var delegate: MediaPlayerDelegate? {
        get { onMain { self.hostDelegate } }
        set {
            let result = MediaTransformMainResult(value: newValue)
            onMain { self.hostDelegate = result.value }
        }
    }
    public var view: UIView { onMain { self.container } }
    public var duration: TimeInterval { onMain { self.inner?.duration ?? 0 } }
    public var fileSize: Int64 { onMain { self.inner?.fileSize ?? 0 } }
    public var chapters: [Chapter] { onMain { self.inner?.chapters ?? [] } }
    public var currentPlaybackTime: TimeInterval { onMain { self.inner?.currentPlaybackTime ?? 0 } }
    public var dynamicInfo: DynamicInfo { onMain { self.inner?.dynamicInfo ?? self.emptyInfo } }
    public var ioContext: AbstractAVIOContext? { onMain { self.inner?.ioContext } }
    public var playableTime: TimeInterval { onMain { self.inner?.playableTime ?? 0 } }
    public var isReadyToPlay: Bool { onMain { self.inner?.isReadyToPlay ?? false } }
    public var playbackState: MediaPlaybackState { onMain { self.inner?.playbackState ?? self.requestedState } }
    public var loadState: MediaLoadState { onMain { self.inner?.loadState ?? self.openingLoadState } }
    public var isPlaying: Bool { playbackState == .playing && loadState == .playable }
    public var seekable: Bool { onMain { self.inner?.seekable ?? false } }
    public var isExternalPlaybackActive: Bool { onMain { self.inner?.isExternalPlaybackActive ?? false } }
    public var subtitleDataSource: (any ConstantSubtitleDataSource)? { onMain { self.inner?.subtitleDataSource } }
    @MainActor public var naturalSize: CGSize { inner?.naturalSize ?? .zero }
    @MainActor public var playbackCoordinator: AVPlaybackCoordinator { inner?.playbackCoordinator ?? fallbackCoordinatorPlayer.playbackCoordinator }
    @MainActor public var playbackRate: Float {
        get { inner?.playbackRate ?? rate }
        set { rate = newValue; inner?.playbackRate = newValue }
    }
    @MainActor public var contentMode: UIViewContentMode {
        get { mode }
        set { mode = newValue; inner?.contentMode = newValue }
    }
    @MainActor public var pipController: KSPictureInPictureProtocol? {
        get { inner?.pipController ?? pendingPIP }
        set { pendingPIP = newValue; inner?.pipController = newValue }
    }
    public var playbackVolume: Float {
        get { onMain { self.inner?.playbackVolume ?? self.volume } }
        set { onMain { self.volume = newValue; self.inner?.playbackVolume = newValue } }
    }
    public var isMuted: Bool {
        get { onMain { self.inner?.isMuted ?? self.muted } }
        set { onMain { self.muted = newValue; self.inner?.isMuted = newValue } }
    }
    public var allowsExternalPlayback: Bool {
        get { onMain { self.inner?.allowsExternalPlayback ?? self.externalPlayback } }
        set { onMain { self.externalPlayback = newValue; self.inner?.allowsExternalPlayback = newValue } }
    }
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool {
        get { onMain { self.inner?.usesExternalPlaybackWhileExternalScreenIsActive ?? self.externalScreenPlayback } }
        set { onMain { self.externalScreenPlayback = newValue; self.inner?.usesExternalPlaybackWhileExternalScreenIsActive = newValue } }
    }

    public func prepareToPlay() { onMain { self.beginOpen() } }

    @MainActor private func beginOpen() {
        guard opening == nil, inner == nil else { return }
        if let inputError { fail(inputError); return }
        guard let resourceOptions = options as? PlayerOptions, let transform = resourceOptions.mediaTransform else {
            fail(MediaTransformPlayerError.missingTransformOptions)
            return
        }
        options.isLive = false
        let open = MediaTransformOpen(url: url, options: resourceOptions, transform: transform)
        opening = open
        lifetime.withLock { $0.resource = open }
        openingLoadState = .loading
        let token = generation
        hostDelegate?.changeLoadState(player: self)
        ioQueue.async { [weak self, factory, ioQueue] in
            do {
                let context = try factory(open.url, open.options, open.transform, open.interrupt)
                let handoff = MediaTransformContextHandoff(context)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, self.opening === open else {
                        // The context never reached a player; its only owner closes it.
                        ioQueue.async { handoff.close() }
                        return
                    }
                    guard let context = handoff.take() else { return }
                    self.install(context: context, open: open)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, self.opening === open else { return }
                    self.opening = nil
                    self.lifetime.withLock { $0.resource = nil }
                    self.fail(error)
                }
            }
        }
    }

    @MainActor private func install(context: FormatContext, open: MediaTransformOpen) {
        inputFailure = MediaTransformContextFactory.failureReader(for: context)
        let player = KSMEPlayer(url: open.url, options: open.options, formatContext: context)
        inner = player
        lifetime.withLock { $0.resource = open; $0.player = player }
        // Lifetime keeps cancellation available after FFmpeg takes context ownership.
        opening = nil
        player.delegate = self
        player.playbackVolume = volume
        player.isMuted = muted
        player.playbackRate = rate
        player.contentMode = mode
        player.allowsExternalPlayback = externalPlayback
        player.usesExternalPlaybackWhileExternalScreenIsActive = externalScreenPlayback
        player.pipController = pendingPIP
        let surface = player.view
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        player.prepareToPlay()
        if requestedState == .playing { player.play() }
        else if requestedState == .paused { player.pause() }
    }

    @MainActor private func fail(_ error: Error) {
        openingLoadState = .idle
        requestedState = .finished
        hostDelegate?.finish(player: self, error: error)
    }

    @MainActor private func clear(stopped: Bool) {
        generation &+= 1
        let owned = lifetime.withLock { state in defer { state = Lifetime() }; return state }
        owned.resource?.cancel()
        opening = nil
        inputFailure = nil
        reportedInputFailure = false
        let previous = inner
        inner = nil
        previous?.delegate = nil
        previous?.stop()
        previous?.view.removeFromSuperview()
        pendingPIP = nil
        requestedState = stopped ? .stopped : .idle
        openingLoadState = .idle
        hostDelegate?.playerDidClear(player: self)
    }

    public func reset() { onMain { self.clear(stopped: false) } }
    public func stop() { onMain { self.clear(stopped: true) } }
    @MainActor public func replace(io: Either<URL, AbstractAVIOContext>, options: KSOptions) {
        clear(stopped: false)
        self.options = (options as? PlayerOptions)?.mediaTransformSessionSnapshot() ?? options
        rate = options.startPlayRate
        switch io {
        case let .left(url): self.url = url; inputError = nil
        case let .right(context):
            inputError = .unsupportedInput
            ioQueue.async { context.close() }
        }
    }
    @MainActor public func play() { requestedState = .playing; inner?.play() }
    @MainActor public func pause() { requestedState = .paused; inner?.pause() }
    public func seek(time: TimeInterval, completion: @MainActor @escaping @Sendable (Bool) -> Void) {
        onMain {
            guard let player = self.inner else { completion(false); return }
            player.seek(time: time, completion: completion)
        }
    }
    public func startRecord(url: URL) { onMain { self.inner?.startRecord(url: url) } }
    public func stopRecord() { onMain { self.inner?.stopRecord() } }
    public func tracks(mediaType: AVMediaType) -> [MediaPlayerTrack] { onMain { self.inner?.tracks(mediaType: mediaType) ?? [] } }
    @MainActor public func select(track: some MediaPlayerTrack) { inner?.select(track: track) }
    @MainActor public func enterBackground() { inner?.enterBackground() }
    @MainActor public func enterForeground() { inner?.enterForeground() }
    @MainActor public func thumbnailImageAtCurrentTime() async -> CGImage? { await inner?.thumbnailImageAtCurrentTime() }
    @MainActor public func configPIP() { inner?.configPIP() }

    @MainActor private func isCurrent(_ player: some MediaPlayerProtocol) -> Bool { inner === player }
    @MainActor public func readyToPlay(player: some MediaPlayerProtocol) { if isCurrent(player) { hostDelegate?.readyToPlay(player: self) } }
    @MainActor public func changeLoadState(player: some MediaPlayerProtocol) { if isCurrent(player) { hostDelegate?.changeLoadState(player: self) } }
    @MainActor public func changeBuffering(player: some MediaPlayerProtocol, progress: UInt8) { if isCurrent(player) { hostDelegate?.changeBuffering(player: self, progress: progress) } }
    @MainActor public func changePlaybackTime(player: some MediaPlayerProtocol, time: TimeInterval) { if isCurrent(player) { hostDelegate?.changePlaybackTime(player: self, time: time) } }
    @MainActor public func playBack(player: some MediaPlayerProtocol, loopCount: Int) { if isCurrent(player) { hostDelegate?.playBack(player: self, loopCount: loopCount) } }
    @MainActor public func reachEndOfStream(player: some MediaPlayerProtocol) {
        guard isCurrent(player), !reportInputFailure() else { return }
        hostDelegate?.reachEndOfStream(player: self)
    }
    @MainActor public func finish(player: some MediaPlayerProtocol, error: Error?) {
        guard isCurrent(player), !reportInputFailure() else { return }
        hostDelegate?.finish(player: self, error: error)
    }
    @MainActor private func reportInputFailure() -> Bool {
        if reportedInputFailure { return true }
        guard let error = inputFailure?() else { return false }
        reportedInputFailure = true
        fail(error)
        return true
    }
    @MainActor public func playerDidClear(player: some MediaPlayerProtocol) { if isCurrent(player) { hostDelegate?.playerDidClear(player: self) } }
}
#endif
