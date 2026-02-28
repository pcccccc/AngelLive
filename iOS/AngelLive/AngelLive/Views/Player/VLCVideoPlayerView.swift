//
//  VLCVideoPlayerView.swift
//  AngelLive
//

import SwiftUI
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

#if canImport(VLCKitSPM) || canImport(VLCKit)
struct VLCVideoPlayerView: UIViewRepresentable {
    let url: URL
    let options: KSOptions
    var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChanged: onStateChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = context.coordinator.containerView
        view.backgroundColor = .black
        context.coordinator.playIfNeeded(url: url, options: options)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.containerView !== uiView {
            context.coordinator.attach(to: uiView)
        }
        context.coordinator.onStateChanged = onStateChanged
        context.coordinator.playIfNeeded(url: url, options: options)
    }

    final class Coordinator: NSObject {
        private let mediaPlayer = VLCMediaPlayer()
        fileprivate var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

        fileprivate private(set) var containerView: UIView
        private var currentURL: URL?
        private var currentRequestFingerprint: String?
        private var notificationTokens: [NSObjectProtocol] = []

        init(onStateChanged: ((VLCPlaybackBridgeState) -> Void)?) {
            self.onStateChanged = onStateChanged
            self.containerView = UIView(frame: .zero)
            super.init()

            mediaPlayer.drawable = containerView
            observeStateChanges()
        }

        deinit {
            notificationTokens.forEach(NotificationCenter.default.removeObserver)
        }

        fileprivate func attach(to view: UIView) {
            containerView = view
            mediaPlayer.drawable = view
        }

        fileprivate func playIfNeeded(url: URL, options: KSOptions) {
            let fingerprint = requestFingerprint(url: url, options: options)
            let shouldReplaceMedia = currentRequestFingerprint != fingerprint
            if shouldReplaceMedia {
                guard let media = VLCMedia(url: url) else {
                    onStateChanged?(.error)
                    return
                }
                applyRequestOptions(options, to: media)
                mediaPlayer.media = media
                currentURL = url
                currentRequestFingerprint = fingerprint
                onStateChanged?(.buffering)
                mediaPlayer.play()
                return
            }

            // Avoid repeatedly calling play() while opening/buffering, which can reset the stream.
            switch mediaPlayer.state {
            case .paused, .stopped, .stopping, .error:
                onStateChanged?(.buffering)
                mediaPlayer.play()
            case .opening, .buffering, .playing:
                break
            @unknown default:
                break
            }
        }

        private func applyRequestOptions(_ options: KSOptions, to media: VLCMedia) {
            if !options.userAgent.isEmpty {
                media.addOption(":http-user-agent=\(options.userAgent)")
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
            var parts: [String] = [url.absoluteString, options.userAgent]
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
                switch mediaPlayer.state {
                case .opening, .buffering:
                    onStateChanged?(.buffering)
                case .playing:
                    onStateChanged?(.playing)
                case .paused:
                    onStateChanged?(.paused)
                case .error:
                    onStateChanged?(.error)
                case .stopped, .stopping:
                    onStateChanged?(.stopped)
                @unknown default:
                    onStateChanged?(.stopped)
                }
            }
            notificationTokens.append(token)
        }
    }
}
#else
struct VLCVideoPlayerView: View {
    let url: URL
    let options: KSOptions
    var onStateChanged: ((VLCPlaybackBridgeState) -> Void)?

    var body: some View {
        Color.black
            .onAppear {
                onStateChanged?(.error)
            }
    }
}
#endif
