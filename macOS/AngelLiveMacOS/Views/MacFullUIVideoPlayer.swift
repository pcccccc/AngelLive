import SwiftUI
import AppKit
import AngelLiveDependencies

#if canImport(KSPlayer)
import KSPlayer

/// FullUI keeps window geometry under the host and user's control across player lifetimes.
/// This follows KSVideoPlayer's make/update/reset path without its teardown aspect-ratio write.
@MainActor
struct MacFullUIVideoPlayer: NSViewRepresentable {
    typealias Coordinator = KSVideoPlayer.Coordinator

    @ObservedObject var coordinator: Coordinator
    let url: URL
    let options: KSOptions

    func makeCoordinator() -> Coordinator { coordinator }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.makeView(url: url, options: options)
    }

    func updateNSView(_ view: NSView, context: Context) {
        coordinator.playerLayer?.updateUIView(view)
        if context.coordinator.playerLayer?.url != url {
            _ = context.coordinator.makeView(url: url, options: options)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }

    func onStateChanged(_ handler: @escaping (KSPlayerLayer, KSPlayerState) -> Void) -> Self {
        coordinator.onStateChanged = handler
        return self
    }

    func onFinish(_ handler: @escaping (KSPlayerLayer, Error?) -> Void) -> Self {
        coordinator.onFinish = handler
        return self
    }
}
#else
// Keep the dependencies package's existing VLC adapter and lifecycle unchanged.
typealias MacFullUIVideoPlayer = KSVideoPlayer
#endif
