#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI
import UIKit

enum TVVodPictureMode: String, CaseIterable {
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

struct TVVodPlayerSurface: View {
    let playback: VodResolvedPlayback
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let rate: Float
    let pictureMode: TVVodPictureMode
    let subtitleBottomOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hidesSubtitles: Bool
    let shouldPlay: Bool
    let onState: () -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(playback: VodResolvedPlayback, model: VodPlaybackModel, controller: KSOnDemandPlayerController,
         playbackSession: KSPlayerPlaybackSession, rate: Float, pictureMode: TVVodPictureMode,
         hidesSubtitles: Bool, subtitleBottomOffset: CGFloat, shouldPlay: Bool, onState: @escaping () -> Void) {
        self.playback = playback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.rate = rate
        self.pictureMode = pictureMode
        self.hidesSubtitles = hidesSubtitles
        self.subtitleBottomOffset = subtitleBottomOffset
        self.shouldPlay = shouldPlay
        self.onState = onState
        let options = PlayerOptions()
        options.isAutoPlay = shouldPlay && playback.resumePosition == nil
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
            .onStateChanged(updateState)
            .onFinish(finish)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard model.playback?.id == playback.id else { return }
                coordinator.playbackRate = rate
                controller.attach(coordinator, playbackID: playback.id, url: playback.url,
                                  subtitles: playback.subtitles, userAgent: options.userAgent,
                                  resumePosition: playback.resumePosition, desiredPlayback: shouldPlay)
                if let layer = coordinator.playerLayer { updateState(layer, layer.state) }
            }
            .onChange(of: rate) { _, rate in coordinator.playbackRate = rate }
            .onChange(of: pictureMode) { _, _ in applyPresentation() }
            .onChange(of: hidesSubtitles) { _, _ in applyPresentation() }
            .onChange(of: subtitleBottomOffset) { _, _ in applyPresentation() }
            .onDisappear { controller.release(coordinator, playbackID: playback.id) }
    }

    private func applyPresentation() {
        guard let layer = coordinator.playerLayer, controller.playbackID == playback.id else { return }
        layer.player.contentMode = pictureMode.contentMode
        layer.subtitleView.contentMode = pictureMode.contentMode
        layer.subtitleView.isHidden = hidesSubtitles
        let view = layer.subtitleView
        let transform = CGAffineTransform(translationX: 0, y: hidesSubtitles ? 0 : -subtitleBottomOffset)
        guard view.transform != transform else { return }
        UIView.animate(withDuration: reduceMotion ? 0 : 0.22, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            view.transform = transform
        }
    }

    private func updateState(_ layer: KSPlayerLayer, _ state: KSPlayerState) {
        guard model.playback?.id == playback.id, controller.playbackID == playback.id,
              coordinator.playerLayer === layer else { return }
        applyPresentation()
        playbackSession.attach(playerLayer: layer)
        playbackSession.activate()
        controller.synchronize(layer: layer, state: state, playbackID: playback.id)
        controller.restoreIfPossible(model: model) { _ in
            guard self.coordinator.playerLayer === layer else { return }
            updateState(layer, layer.state)
        }
        if !controller.isRestoring(for: playback.id), layer.player.loadState == .playable {
            model.playbackReady(id: playback.id, duration: layer.player.duration)
        }
        onState()
    }

    private func finish(_ layer: KSPlayerLayer, _ error: Error?) {
        guard model.playback?.id == playback.id, controller.playbackID == playback.id,
              coordinator.playerLayer === layer,
              case .forward(let playbackError) = controller.handlePlaybackFinished(
                layer: layer, playbackID: playback.id, error: error
              ) else { return }
        if let sample = controller.timeSample(for: playback.id) {
            model.recordProgress(id: playback.id, position: sample.current, duration: sample.duration)
        }
        Task { @MainActor in
            await model.playbackFinished(id: playback.id, error: playbackError)
            guard model.playback?.id == playback.id, controller.playbackID == playback.id,
                  model.hasFinished else { return }
            controller.pause()
        }
    }
}
#endif
