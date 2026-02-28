#if !canImport(KSPlayer) && (canImport(VLCKitSPM) || canImport(VLCKit))

import CoreMedia
import Foundation
import SwiftUI
#if canImport(VLCKitSPM)
import VLCKitSPM
#else
import VLCKit
#endif

#if os(iOS) || os(tvOS)
@preconcurrency import UIKit
public typealias KSPlatformVideoView = UIView
#elseif os(macOS)
@preconcurrency import AppKit
public typealias KSPlatformVideoView = NSView
#endif

public protocol MediaPlayerProtocol: AnyObject {}

public final class KSAVPlayer: NSObject, MediaPlayerProtocol {}
public final class KSMEPlayer: NSObject, MediaPlayerProtocol {}

public enum KSDecodeType: String, Sendable {
    case software
}

public enum KSDynamicRange: CustomStringConvertible, Sendable {
    case sdr

    public var description: String {
        switch self {
        case .sdr:
            return "SDR"
        }
    }
}

public enum KSMediaType: Sendable {
    case video
    case audio
    case subtitle
}

public struct DynamicInfo: Sendable {
    public var displayFPS: Double = 0
    public var droppedVideoFrameCount: Int = 0
    public var droppedVideoPacketCount: Int = 0
    public var audioVideoSyncDiff: Double = 0
    public var networkSpeed: Double = 0
    public var videoBitrate: Double = 0
    public var audioBitrate: Double = 0

    public init() {}
}

public struct MediaPlayerTrack: Identifiable, Sendable {
    public let id = UUID()
    public var subtitleID: String = UUID().uuidString
    public var name: String = ""
    public var isEnabled: Bool = true
    public var dynamicRange: KSDynamicRange? = .sdr

    public init(subtitleID: String = UUID().uuidString, name: String = "", isEnabled: Bool = true, dynamicRange: KSDynamicRange? = .sdr) {
        self.subtitleID = subtitleID
        self.name = name
        self.isEnabled = isEnabled
        self.dynamicRange = dynamicRange
    }
}

public protocol SubtitleDataSource {}

public final class SubtitleModel {
    public var subtitleInfos: [MediaPlayerTrack] = []
    public var selectedSubtitleInfo: MediaPlayerTrack?

    public init() {}

    public func addSubtitle(dataSource _: SubtitleDataSource?) {}
}

public enum KSPlaybackState: Sendable {
    case stopped
    case playing
    case paused
    case seeking

    public var isPlaying: Bool {
        self == .playing
    }
}

public enum KSPlayerStateBase: Sendable {
    case initialized
    case buffering
    case readyToPlay
    case paused
    case playedToTheEnd
    case error
    case stopped

    public var isPlaying: Bool {
        switch self {
        case .readyToPlay:
            return true
        default:
            return false
        }
    }
}

public typealias KSPlayerState = KSPlayerStateBase

public enum KSPlayer {
    public typealias KSPlayerLayer = KSPlayerLayerBase
    public typealias KSPlayerState = KSPlayerStateBase
}

public protocol KSPlayerLayerDelegate: AnyObject {
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState)
    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval)
    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?)
    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval)
}

public extension KSPlayerLayerDelegate {
    func player(layer _: KSPlayer.KSPlayerLayer, state _: KSPlayer.KSPlayerState) {}
    func player(layer _: KSPlayer.KSPlayerLayer, currentTime _: TimeInterval, totalTime _: TimeInterval) {}
    func player(layer _: KSPlayer.KSPlayerLayer, finish _: Error?) {}
    func player(layer _: KSPlayer.KSPlayerLayer, bufferedCount _: Int, consumeTime _: TimeInterval) {}
}

open class KSOptions {
    public nonisolated(unsafe) static var isAutoPlay: Bool = true
    public nonisolated(unsafe) static var isSecondOpen: Bool = false
    public nonisolated(unsafe) static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    public nonisolated(unsafe) static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self
    public nonisolated(unsafe) static var canBackgroundPlay: Bool = false
    public nonisolated(unsafe) static var hudLog: Bool = false
    public nonisolated(unsafe) static var subtitleDynamicRange: String = ""

    #if os(iOS)
    public nonisolated(unsafe) static var supportedInterfaceOrientations: UIInterfaceOrientationMask? = .all
    #else
    public nonisolated(unsafe) static var supportedInterfaceOrientations: Int? = nil
    #endif

    public var userAgent: String = "libmpv"
    public var avOptions: [String: Any] = [:]
    public var formatContextOptions: [String: Any] = [:]
    public var decodeType: KSDecodeType = .software
    public var canStartPictureInPictureAutomaticallyFromInline: Bool = false

    public init() {}

    open func updateVideo(refreshRate _: Float, isDovi _: Bool, formatDescription _: CMFormatDescription) {}

    public func appendHeader(_ header: [String: String]) {
        avOptions["AVURLAssetHTTPHeaderFieldsKey"] = header
    }
}

public final class KSPlayerItem {
    public var options: KSOptions

    public init(options: KSOptions) {
        self.options = options
    }
}

private final class KSVLCBackend: NSObject {
    let mediaPlayer = VLCMediaPlayer()
    let view = MainActor.assumeIsolated { KSPlatformVideoView(frame: .zero) }
    var playbackState: KSPlaybackState = .stopped
    var playbackVolume: Float = 1 {
        didSet {
            mediaPlayer.audio?.volume = Int32(max(0, min(1, playbackVolume)) * 100)
        }
    }
    var isMuted: Bool = false {
        didSet {
            mediaPlayer.audio?.isMuted = isMuted
        }
    }
    var allowsExternalPlayback: Bool = false
    var seekable: Bool = true
    var dynamicInfo = DynamicInfo()
    var onStateChanged: ((KSPlayerState) -> Void)?
    private var stateObserver: NSObjectProtocol?

    override init() {
        super.init()
        mediaPlayer.drawable = view
        observePlayerState()
    }

    deinit {
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
        }
    }

    var naturalSize: CGSize {
        mediaPlayer.videoSize
    }

    #if os(iOS) || os(tvOS)
    var contentMode: UIView.ContentMode {
        get { view.contentMode }
        set { view.contentMode = newValue }
    }
    #endif

    var isPlaying: Bool {
        mediaPlayer.isPlaying
    }

    func tracks(mediaType: KSMediaType) -> [MediaPlayerTrack] {
        switch mediaType {
        case .video:
            return [MediaPlayerTrack(name: "Video", isEnabled: true, dynamicRange: .sdr)]
        case .audio:
            return [MediaPlayerTrack(name: "Audio", isEnabled: true, dynamicRange: nil)]
        case .subtitle:
            return []
        }
    }

    func select(track _: MediaPlayerTrack) {}

    func play(url: URL, options: KSOptions) {
        guard let media = VLCMedia(url: url) else {
            playbackState = .stopped
            onStateChanged?(.error)
            return
        }
        if !options.userAgent.isEmpty {
            media.addOption(":http-user-agent=\(options.userAgent)")
        }
        if let headers = options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] {
            if let referer = headers["Referer"] ?? headers["referer"] {
                media.addOption(":http-referrer=\(referer)")
            }
            if let ua = headers["User-Agent"] ?? headers["user-agent"] {
                media.addOption(":http-user-agent=\(ua)")
            }
        }
        mediaPlayer.media = media
        playbackState = .seeking
        onStateChanged?(.buffering)
        mediaPlayer.play()
    }

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        mediaPlayer.pause()
    }

    func stop() {
        mediaPlayer.stop()
    }

    private func observePlayerState() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: VLCMediaPlayer.stateChangedNotification,
            object: mediaPlayer,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            switch mediaPlayer.state {
            case .opening, .buffering:
                playbackState = .seeking
                onStateChanged?(.buffering)
            case .playing:
                playbackState = .playing
                onStateChanged?(.readyToPlay)
            case .paused:
                playbackState = .paused
                onStateChanged?(.paused)
            case .error:
                playbackState = .stopped
                onStateChanged?(.error)
            case .stopped, .stopping:
                playbackState = .stopped
                onStateChanged?(.stopped)
            @unknown default:
                playbackState = .stopped
                onStateChanged?(.stopped)
            }
        }
    }
}

public class KSPlayerLayerBase: NSObject {
    public weak var delegate: KSPlayerLayerDelegate?
    public let player: KSCompatPlayer
    public var options: KSOptions
    public let subtitleModel = SubtitleModel()

    private let backend: KSVLCBackend

    public init(options: KSOptions = KSOptions()) {
        self.options = options
        self.backend = KSVLCBackend()
        self.player = KSCompatPlayer(backend: backend)
        super.init()

        backend.onStateChanged = { [weak self] state in
            guard let self else { return }
            delegate?.player(layer: self, state: state)
            if state == .readyToPlay {
                delegate?.player(layer: self, currentTime: 0, totalTime: 0)
            }
        }
    }

    public func set(url: URL, options: KSOptions) {
        self.options = options
        backend.play(url: url, options: options)
    }

    public func play() {
        backend.play()
        delegate?.player(layer: self, state: .readyToPlay)
    }

    public func pause() {
        backend.pause()
        delegate?.player(layer: self, state: .paused)
    }

    public func stop() {
        backend.stop()
        delegate?.player(layer: self, state: .stopped)
    }

    public func resetPlayer() {
        stop()
    }

    public func select(subtitleInfo info: MediaPlayerTrack?) {
        subtitleModel.selectedSubtitleInfo = info
    }
}

public final class KSComplexPlayerLayer: KSPlayerLayerBase {
    public var isPictureInPictureActive: Bool = false

    public func pipStart() {
        isPictureInPictureActive = true
    }

    public func pipStop(restoreUserInterface _: Bool) {
        isPictureInPictureActive = false
    }
}

public final class KSCompatPlayer {
    private let backend: KSVLCBackend

    fileprivate init(backend: KSVLCBackend) {
        self.backend = backend
    }

    public var view: KSPlatformVideoView { backend.view }
    public var playbackState: KSPlaybackState { backend.playbackState }
    public var naturalSize: CGSize { backend.naturalSize }
    public var isMuted: Bool {
        get { backend.isMuted }
        set { backend.isMuted = newValue }
    }
    public var playbackVolume: Float {
        get { backend.playbackVolume }
        set { backend.playbackVolume = newValue }
    }
    public var allowsExternalPlayback: Bool {
        get { backend.allowsExternalPlayback }
        set { backend.allowsExternalPlayback = newValue }
    }
    public var seekable: Bool { backend.seekable }
    public var isPlaying: Bool { backend.isPlaying }
    public var dynamicInfo: DynamicInfo { backend.dynamicInfo }

    #if os(iOS) || os(tvOS)
    public var contentMode: UIView.ContentMode {
        get { backend.contentMode }
        set { backend.contentMode = newValue }
    }
    #endif

    public func tracks(mediaType: KSMediaType) -> [MediaPlayerTrack] {
        backend.tracks(mediaType: mediaType)
    }

    public func select(track: MediaPlayerTrack) {
        backend.select(track: track)
    }
}

public typealias KSPlayerLayer = KSPlayerLayerBase

public struct KSVideoPlayer: View {
    @ObservedObject private var coordinator: Coordinator
    private let url: URL
    private let options: KSOptions

    public init(coordinator: Coordinator, url: URL, options: KSOptions) {
        self.coordinator = coordinator
        self.url = url
        self.options = options
    }

    public var body: some View {
        KSFallbackPlayerView(coordinator: coordinator, url: url, options: options)
            .onAppear {
                coordinator.open(url: url, options: options)
            }
    }

    public final class Coordinator: ObservableObject {
        @Published public var state: KSPlayerState = .initialized
        @Published public var isMaskShow: Bool = false
        public var shouldAutoReplay = false
        public var isScaleAspectFill = false
        public var playerLayer: KSPlayerLayer?

        public init(playerLayer: KSPlayerLayer? = nil) {
            self.playerLayer = playerLayer
        }

        public func open(url: URL, options: KSOptions) {
            let layer = playerLayer ?? KSComplexPlayerLayer(options: options)
            layer.options = options
            layer.set(url: url, options: options)
            playerLayer = layer
            state = .buffering
        }

        public func set(url: URL, options: KSOptions) {
            open(url: url, options: options)
        }

        public func resetPlayer() {
            playerLayer?.resetPlayer()
            state = .stopped
        }

        public func stop() {
            playerLayer?.stop()
            state = .stopped
        }

        public func enterBackground() {}
    }
}

#if os(iOS) || os(tvOS)
private struct KSFallbackPlayerView: UIViewRepresentable {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let url: URL
    let options: KSOptions

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.clipsToBounds = true
        attachLayer(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        attachLayer(to: uiView)
        coordinator.open(url: url, options: options)
    }

    private func attachLayer(to container: UIView) {
        guard let playerView = coordinator.playerLayer?.player.view else { return }
        if playerView.superview !== container {
            playerView.removeFromSuperview()
            playerView.frame = container.bounds
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(playerView)
        }
    }
}
#elseif os(macOS)
private struct KSFallbackPlayerView: NSViewRepresentable {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let url: URL
    let options: KSOptions

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        attachLayer(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        attachLayer(to: nsView)
        coordinator.open(url: url, options: options)
    }

    private func attachLayer(to container: NSView) {
        guard let playerView = coordinator.playerLayer?.player.view else { return }
        if playerView.superview !== container {
            playerView.removeFromSuperview()
            playerView.frame = container.bounds
            playerView.autoresizingMask = [.width, .height]
            container.addSubview(playerView)
        }
    }
}
#endif

#endif
