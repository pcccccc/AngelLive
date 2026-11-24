#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import KSPlayerUI
import SwiftUI
import UIKit

enum VodPictureMode: String, CaseIterable {
    case fit = "适应"
    case fill = "填充"
    case stretch = "拉伸"

    var contentMode: UIView.ContentMode {
        switch self {
        case .fit: .scaleAspectFit
        case .fill: .scaleAspectFill
        case .stretch: .scaleToFill
        }
    }
}

struct VodPlayerSurface: View {
    let playback: VodResolvedPlayback
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let rate: Float
    let pictureMode: VodPictureMode
    let subtitleBottomOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hidesSubtitles: Bool
    let onState: () -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(playback: VodResolvedPlayback, model: VodPlaybackModel, controller: KSOnDemandPlayerController,
         playbackSession: KSPlayerPlaybackSession, rate: Float, pictureMode: VodPictureMode,
         hidesSubtitles: Bool, subtitleBottomOffset: CGFloat, onState: @escaping () -> Void) {
        self.playback = playback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.rate = rate
        self.pictureMode = pictureMode
        self.hidesSubtitles = hidesSubtitles
        self.subtitleBottomOffset = subtitleBottomOffset
        self.onState = onState
        let options = PlayerOptions()
        options.isAutoPlay = playback.resumePosition == nil
        options.isLoopPlay = false
        options.registerRemoteControll = false
        options.isAccurateSeek = true
        options.startPlayRate = rate
        _ = KSPlayerSessionConfigurator.apply(quality: playback.quality, to: options, fallbackUserAgent: "libmpv",
                                              liveReconnectPolicy: .applicationManaged)
        _options = State(initialValue: options)
    }

    var body: some View {
        KSVideoPlayer(coordinator: coordinator, url: playback.url, options: options)
            .onStateChanged(onPlayerState)
            .onFinish(onFinish)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                coordinator.playbackRate = rate
                controller.attach(coordinator, playbackID: playback.id, url: playback.url,
                                  subtitles: playback.subtitles, userAgent: options.userAgent,
                                  resumePosition: playback.resumePosition, desiredPlayback: true)
                if let layer = coordinator.playerLayer { onPlayerState(layer, layer.state) }
            }
            .onChange(of: rate) { _, value in coordinator.playbackRate = value }
            .onChange(of: pictureMode) { _, _ in updatePresentation() }
            .onChange(of: hidesSubtitles) { _, _ in updatePresentation() }
            .onChange(of: subtitleBottomOffset) { _, _ in updatePresentation() }
            .onDisappear { controller.release(coordinator, playbackID: playback.id) }
    }

    private func updatePresentation() {
        guard let layer = coordinator.playerLayer else { return }
        layer.player.contentMode = pictureMode.contentMode
        layer.subtitleView.contentMode = pictureMode.contentMode
        layer.subtitleView.alpha = hidesSubtitles ? 0 : 1
        let view = layer.subtitleView
        let transform = CGAffineTransform(translationX: 0, y: hidesSubtitles ? 0 : -subtitleBottomOffset)
        guard view.transform != transform else { return }
        UIView.animate(withDuration: reduceMotion ? 0 : 0.22, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            view.transform = transform
        }
    }

    private func onPlayerState(_ layer: KSPlayerLayer, _ state: KSPlayerState) {
        guard model.playback?.id == playback.id, controller.playbackID == playback.id,
              coordinator.playerLayer === layer else { return }
        updatePresentation()
        playbackSession.attach(playerLayer: layer)
        playbackSession.activate()
        controller.synchronize(layer: layer, state: state, playbackID: playback.id)
        controller.restoreIfPossible(model: model) { _ in onPlayerState(layer, layer.state) }
        if !controller.isRestoring(for: playback.id), layer.player.loadState == .playable {
            model.playbackReady(id: playback.id, duration: layer.player.duration)
        }
        onState()
    }

    private func onFinish(_ layer: KSPlayerLayer, _ error: Error?) {
        guard model.playback?.id == playback.id, controller.playbackID == playback.id,
              coordinator.playerLayer === layer else { return }
        guard case .forward(let playbackError) = controller.handlePlaybackFinished(
            layer: layer, playbackID: playback.id, error: error
        ) else { return }
        if let sample = controller.timeSample(for: playback.id) {
            model.recordProgress(id: playback.id, position: sample.current, duration: sample.duration)
        }
        Task { @MainActor in
            await model.playbackFinished(id: playback.id, error: playbackError)
            guard model.playback?.id == playback.id, controller.playbackID == playback.id, model.hasFinished else {
                return
            }
            controller.pause()
        }
    }
}
#endif
