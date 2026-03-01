//
//  VLCVideoPlayerView.swift
//  AngelLive
//

import SwiftUI
import Combine
import AngelLiveCore
import AngelLiveDependencies
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(VLCKit)
import VLCKit
#endif

enum VLCPlaybackBridgeState {
    case buffering
    case playing
    case paused
    case stopped
    case error

    var isBuffering: Bool {
        self == .buffering
    }
}

@MainActor
final class VLCPlaybackController: ObservableObject {
    @Published private(set) var state: VLCPlaybackBridgeState = .buffering
    @Published private(set) var isPictureInPictureSupported = false
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var isSessionActive = false

    fileprivate var playHandler: (() -> Void)?
    fileprivate var pauseHandler: (() -> Void)?
    fileprivate var togglePlayPauseHandler: (() -> Void)?
    fileprivate var stopHandler: (() -> Void)?
    fileprivate var enterBackgroundHandler: (() -> Void)?
    fileprivate var becomeActiveHandler: (() -> Void)?

    func play() {
        Logger.debug("[VLCBridge] controller.play(), sessionActive=\(isSessionActive)", category: .player)
        playHandler?()
    }

    func pause() {
        Logger.debug("[VLCBridge] controller.pause(), sessionActive=\(isSessionActive)", category: .player)
        pauseHandler?()
    }

    func togglePlayPause() {
        Logger.debug("[VLCBridge] controller.togglePlayPause(), sessionActive=\(isSessionActive)", category: .player)
        togglePlayPauseHandler?()
    }

    func stop() {
        Logger.debug("[VLCBridge] controller.stop(), sessionActive=\(isSessionActive)", category: .player)
        stopHandler?()
    }

    func enterBackground() {
        Logger.debug("[VLCBridge] controller.enterBackground(), sessionActive=\(isSessionActive)", category: .player)
        enterBackgroundHandler?()
    }

    func becomeActive() {
        Logger.debug("[VLCBridge] controller.becomeActive(), sessionActive=\(isSessionActive)", category: .player)
        becomeActiveHandler?()
    }

    func togglePictureInPicture() {
        // Temporary no-op: current VLC PiP adapter can block live room enter.
    }

    func activateSession() {
        isSessionActive = true
        Logger.debug("[VLCBridge] session activated", category: .player)
    }

    func deactivateSession() {
        isSessionActive = false
        Logger.debug("[VLCBridge] session deactivated", category: .player)
    }

    fileprivate func updateState(_ state: VLCPlaybackBridgeState) {
        self.state = state
    }

    fileprivate func updatePictureInPictureState(isSupported: Bool, isActive: Bool) {
        self.isPictureInPictureSupported = isSupported
        self.isPictureInPictureActive = isActive
    }
}

#if canImport(VLCKitSPM) || canImport(VLCKit)
struct VLCVideoPlayerView: UIViewRepresentable {
    let url: URL
    let options: KSOptions
    var controller: VLCPlaybackController?
    var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onStateChanged: onStateChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = context.coordinator.containerView
        view.backgroundColor = .black
        Logger.debug("[VLCBridge] makeUIView, url=\(compactURL(url))", category: .player)
        // Defer session activation and initial playback to avoid publishing
        // changes from within a view update (which causes undefined behavior).
        let url = self.url
        let options = self.options
        DispatchQueue.main.async {
            controller?.activateSession()
            context.coordinator.playIfNeeded(url: url, options: options)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.containerView !== uiView {
            context.coordinator.attach(to: uiView)
        }
        context.coordinator.attach(controller: controller)
        context.coordinator.onStateChanged = onStateChanged
        Logger.debug("[VLCBridge] updateUIView, url=\(compactURL(url)), sessionActive=\(controller?.isSessionActive ?? false)", category: .player)
        context.coordinator.playIfNeeded(url: url, options: options)
    }

    private func compactURL(_ url: URL) -> String {
        let host = url.host ?? "unknown-host"
        return "\(host)\(url.path)"
    }

    final class Coordinator: NSObject {
        private let mediaPlayer = VLCMediaPlayer()
        private weak var controller: VLCPlaybackController?
        fileprivate var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

        fileprivate private(set) var containerView: UIView
        private var currentRequestFingerprint: String?
        private var notificationTokens: [NSObjectProtocol] = []
        private var shouldResumeAfterForeground = false
        private var lastNotifiedState: VLCPlaybackBridgeState?
        private var lastObservedPlayerState: VLCMediaPlayerState?
        private let traceID = String(UUID().uuidString.prefix(8))

        init(controller: VLCPlaybackController?, onStateChanged: ((VLCPlaybackBridgeState) -> Void)?) {
            self.controller = controller
            self.onStateChanged = onStateChanged
            self.containerView = UIView(frame: .zero)
            super.init()

            mediaPlayer.drawable = containerView
            bindControlHandlers()
            observeStateChanges()
            Logger.debug("[VLCBridge][\(traceID)] coordinator init", category: .player)
        }

        deinit {
            Logger.debug("[VLCBridge][\(traceID)] coordinator deinit", category: .player)
            mediaPlayer.stop()
            mediaPlayer.drawable = nil
            mediaPlayer.media = nil
            notificationTokens.forEach(NotificationCenter.default.removeObserver)
        }

        fileprivate func attach(to view: UIView) {
            Logger.debug("[VLCBridge][\(traceID)] attach drawable", category: .player)
            containerView = view
            mediaPlayer.drawable = view
        }

        fileprivate func attach(controller: VLCPlaybackController?) {
            guard self.controller !== controller else { return }
            Logger.debug("[VLCBridge][\(traceID)] attach new controller", category: .player)
            self.controller = controller
            bindControlHandlers()
        }

        fileprivate func playIfNeeded(url: URL, options: KSOptions) {
            // During room dismiss/switch we explicitly close the session to prevent auto-reopen.
            if controller?.isSessionActive == false {
                Logger.debug("[VLCBridge][\(traceID)] playIfNeeded skipped, inactive session, url=\(compactURL(url))", category: .player)
                return
            }
            let fingerprint = requestFingerprint(url: url, options: options)
            let shouldReplaceMedia = currentRequestFingerprint != fingerprint
            Logger.debug(
                "[VLCBridge][\(traceID)] playIfNeeded, replace=\(shouldReplaceMedia), playerState=\(describe(mediaPlayer.state)), url=\(compactURL(url))",
                category: .player
            )
            if shouldReplaceMedia {
                guard let media = VLCMedia(url: url) else {
                    notifyState(.error)
                    return
                }
                applyRequestOptions(options, to: media)
                mediaPlayer.media = media
                currentRequestFingerprint = fingerprint
                notifyState(.buffering)
                Logger.debug("[VLCBridge][\(traceID)] start play new media", category: .player)
                mediaPlayer.play()
                return
            }

            // Avoid repeatedly calling play() while opening/buffering, which can reset the stream.
            switch mediaPlayer.state {
            case .paused, .stopped, .stopping, .error:
                notifyState(.buffering)
                Logger.debug("[VLCBridge][\(traceID)] resume play from \(describe(mediaPlayer.state))", category: .player)
                mediaPlayer.play()
            case .opening, .buffering, .playing:
                break
            @unknown default:
                Logger.warning("[VLCBridge][\(traceID)] unknown player state in playIfNeeded", category: .player)
                break
            }
        }

        private func applyRequestOptions(_ options: KSOptions, to media: VLCMedia) {
            if !(options.userAgent ?? "").isEmpty {
                media.addOption(":http-user-agent=\(options.userAgent ?? "")")
            }

            guard let headers = options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] else {
                return
            }

            if let referer = headers["Referer"] ?? headers["referer"] {
                media.addOption(":http-referrer=\(referer)")
            }

            if let userAgent = headers["User-Agent"] ?? headers["user-agent"], !userAgent.isEmpty {
                media.addOption(":http-user-agent=\(userAgent)")
            }

            // Pass through extra headers for platforms that require auth/cookie/origin checks.
            for (key, value) in headers {
                let lower = key.lowercased()
                if lower == "user-agent" || lower == "referer" {
                    continue
                }
                media.addOption(":http-header=\(key): \(value)")
            }
        }

        private func requestFingerprint(url: URL, options: KSOptions) -> String {
            var parts: [String] = [url.absoluteString, options.userAgent ?? ""]
            if let headers = options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String], !headers.isEmpty {
                let sorted = headers.keys.sorted().map { "\($0)=\(headers[$0] ?? "")" }
                parts.append(sorted.joined(separator: "&"))
            }
            return parts.joined(separator: "|")
        }

        private func observeStateChanges() {
            let token = NotificationCenter.default.addObserver(
                forName: VLCMediaPlayer.stateChangedNotification,
                object: mediaPlayer,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let isActiveSession = currentRequestFingerprint != nil || mediaPlayer.media != nil
                let rawState = mediaPlayer.state
                if lastObservedPlayerState != rawState {
                    Logger.debug(
                        "[VLCBridge][\(traceID)] raw state changed: \(describe(lastObservedPlayerState)) -> \(describe(rawState)), sessionActive=\(isActiveSession)",
                        category: .player
                    )
                    lastObservedPlayerState = rawState
                }
                switch mediaPlayer.state {
                case .opening, .buffering:
                    if isActiveSession {
                        notifyState(.buffering)
                    }
                case .playing:
                    if isActiveSession {
                        notifyState(.playing)
                    }
                case .paused:
                    if isActiveSession {
                        notifyState(.paused)
                    }
                case .error:
                    Logger.warning("[VLCBridge][\(traceID)] VLC mediaPlayer entered error state", category: .player)
                    notifyState(.error)
                case .stopped, .stopping:
                    notifyState(.stopped)
                @unknown default:
                    Logger.warning("[VLCBridge][\(traceID)] VLC mediaPlayer entered unknown state", category: .player)
                    notifyState(.stopped)
                }
            }
            notificationTokens.append(token)
        }

        private func bindControlHandlers() {
            controller?.playHandler = { [weak self] in
                guard let self, controller?.isSessionActive == true else { return }
                Logger.debug("[VLCBridge][\(traceID)] handler play()", category: .player)
                mediaPlayer.play()
            }
            controller?.pauseHandler = { [weak self] in
                guard let self else { return }
                Logger.debug("[VLCBridge][\(self.traceID)] handler pause()", category: .player)
                self.mediaPlayer.pause()
            }
            controller?.togglePlayPauseHandler = { [weak self] in
                guard let self else { return }
                guard controller?.isSessionActive == true else { return }
                Logger.debug("[VLCBridge][\(traceID)] handler togglePlayPause(), current=\(describe(mediaPlayer.state))", category: .player)
                if mediaPlayer.state == .playing || mediaPlayer.state == .opening || mediaPlayer.state == .buffering {
                    mediaPlayer.pause()
                } else {
                    mediaPlayer.play()
                }
            }
            controller?.stopHandler = { [weak self] in
                guard let self else { return }
                Logger.debug("[VLCBridge][\(traceID)] handler stop()", category: .player)
                shouldResumeAfterForeground = false
                mediaPlayer.stop()
                mediaPlayer.media = nil
                currentRequestFingerprint = nil
                notifyState(.stopped)
            }
            controller?.enterBackgroundHandler = { [weak self] in
                guard let self else { return }
                guard controller?.isSessionActive == true else { return }
                shouldResumeAfterForeground = mediaPlayer.state == .playing || mediaPlayer.state == .opening || mediaPlayer.state == .buffering
                Logger.debug("[VLCBridge][\(traceID)] handler enterBackground(), shouldResume=\(shouldResumeAfterForeground)", category: .player)
                mediaPlayer.pause()
            }
            controller?.becomeActiveHandler = { [weak self] in
                guard let self else { return }
                guard controller?.isSessionActive == true else { return }
                Logger.debug("[VLCBridge][\(traceID)] handler becomeActive(), shouldResume=\(shouldResumeAfterForeground), hasMedia=\(mediaPlayer.media != nil)", category: .player)
                mediaPlayer.drawable = containerView
                if shouldResumeAfterForeground, mediaPlayer.media != nil {
                    notifyState(.buffering)
                    mediaPlayer.play()
                }
            }
            controller?.updatePictureInPictureState(isSupported: false, isActive: false)
        }

        private func notifyState(_ state: VLCPlaybackBridgeState) {
            if lastNotifiedState != state {
                Logger.debug("[VLCBridge][\(traceID)] bridge state: \(describe(lastNotifiedState)) -> \(describe(state))", category: .player)
                lastNotifiedState = state
            }
            // Defer @Published updates to avoid "Publishing changes from within
            // view updates" when called synchronously from updateUIView / playIfNeeded.
            DispatchQueue.main.async { [weak self] in
                self?.controller?.updateState(state)
                self?.onStateChanged?(state)
            }
        }

        private func describe(_ state: VLCPlaybackBridgeState?) -> String {
            switch state {
            case .buffering: return "buffering"
            case .playing: return "playing"
            case .paused: return "paused"
            case .stopped: return "stopped"
            case .error: return "error"
            case nil: return "nil"
            }
        }

        private func describe(_ state: VLCMediaPlayerState?) -> String {
            switch state {
            case .stopped: return "stopped"
            case .opening: return "opening"
            case .buffering: return "buffering"
            case .playing: return "playing"
            case .paused: return "paused"
            case .stopping: return "stopping"
            case .error: return "error"
            case nil: return "nil"
            @unknown default: return "unknown"
            }
        }

        private func compactURL(_ url: URL) -> String {
            let host = url.host ?? "unknown-host"
            return "\(host)\(url.path)"
        }
    }
}
#else
struct VLCVideoPlayerView: View {
    let url: URL
    let options: KSOptions
    var controller: VLCPlaybackController?
    var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

    var body: some View {
        Color.black
            .onAppear {
                onStateChanged?(.error)
            }
    }
}
#endif
