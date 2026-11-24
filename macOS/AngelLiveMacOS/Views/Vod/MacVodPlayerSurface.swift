#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import KSPlayerUI
import SwiftUI

enum MacVodPictureMode: String, CaseIterable {
    case fit = "适应"
    case fill = "填充"
    case stretch = "拉伸"

    var contentMode: UIViewContentMode {
        switch self {
        case .fit: .scaleAspectFit
        case .fill: .scaleAspectFill
        case .stretch: .scaleToFill
        }
    }
}

struct MacVodPlayerSurface: View {
    let playback: VodResolvedPlayback
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let rate: Float
    let volume: Float
    let pictureMode: MacVodPictureMode
    let subtitleBottomOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hidesSubtitles: Bool
    let onState: () -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(playback: VodResolvedPlayback, model: VodPlaybackModel, controller: KSOnDemandPlayerController,
         playbackSession: KSPlayerPlaybackSession, rate: Float, volume: Float,
         pictureMode: MacVodPictureMode, hidesSubtitles: Bool, subtitleBottomOffset: CGFloat,
         onState: @escaping () -> Void) {
        self.playback = playback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.rate = rate
        self.volume = volume
        self.pictureMode = pictureMode
        self.hidesSubtitles = hidesSubtitles
        self.subtitleBottomOffset = subtitleBottomOffset
        self.onState = onState

        let options = PlayerOptions()
        options.isAutoPlay = playback.resumePosition == nil
        options.isLoopPlay = false
        options.registerRemoteControll = false
        options.automaticWindowResize = false
        options.isAccurateSeek = true
        options.startPlayRate = rate
        _ = KSPlayerSessionConfigurator.apply(quality: playback.quality, to: options, fallbackUserAgent: "libmpv",
                                              liveReconnectPolicy: .applicationManaged)
        _options = State(initialValue: options)
    }

    var body: some View {
        MacFullUIVideoPlayer(coordinator: coordinator, url: playback.url, options: options)
            .onStateChanged(handleState)
            .onFinish(handleFinish)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                coordinator.playbackRate = rate
                controller.attach(coordinator, playbackID: playback.id, url: playback.url,
                                  subtitles: playback.subtitles, userAgent: options.userAgent,
                                  resumePosition: playback.resumePosition, desiredPlayback: true)
                if let layer = coordinator.playerLayer { handleState(layer, layer.state) }
            }
            .onChange(of: rate) { coordinator.playbackRate = rate }
            .onChange(of: volume) { coordinator.playerLayer?.player.playbackVolume = volume }
            .onChange(of: pictureMode) { updatePresentation() }
            .onChange(of: hidesSubtitles) { updatePresentation() }
            .onChange(of: subtitleBottomOffset) { updatePresentation() }
            .onDisappear {
                if controller.playbackID == playback.id { playbackSession.attach(playerLayer: nil) }
                controller.release(coordinator, playbackID: playback.id)
            }
    }

    private func updatePresentation() {
        guard let layer = coordinator.playerLayer else { return }
        layer.player.contentMode = pictureMode.contentMode
        layer.subtitleView.contentMode = pictureMode.contentMode
        layer.subtitleView.isHidden = hidesSubtitles
        let view = layer.subtitleView
        guard let parent = view.superview,
              let center = parent.constraints.first(where: {
                  $0.firstItem === view && $0.firstAttribute == .centerY && $0.secondItem === parent
              }) else { return }
        // AppKit centerYAnchor constants increase toward the bottom in either coordinate system.
        let offset = hidesSubtitles ? 0 : -subtitleBottomOffset
        guard center.constant != offset else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.22
            center.animator().constant = offset
        }
    }

    private func owns(_ layer: KSPlayerLayer) -> Bool {
        model.playback?.id == playback.id && controller.playbackID == playback.id && coordinator.playerLayer === layer
    }

    private func handleState(_ layer: KSPlayerLayer, _ state: KSPlayerState) {
        guard owns(layer) else { return }
        updatePresentation()
        layer.player.playbackRate = rate
        layer.player.playbackVolume = volume
        playbackSession.attach(playerLayer: layer)
        playbackSession.activate()
        controller.synchronize(layer: layer, state: state, playbackID: playback.id)
        if !controller.isRestoring(for: playback.id), layer.player.loadState == .playable {
            model.playbackReady(id: playback.id, duration: layer.player.duration)
        }
        onState()
    }

    private func handleFinish(_ layer: KSPlayerLayer, _ error: Error?) {
        guard owns(layer), case .forward(let playbackError) = controller.handlePlaybackFinished(
            layer: layer, playbackID: playback.id, error: error
        ) else { return }
        if let sample = controller.timeSample(for: playback.id) {
            model.recordProgress(id: playback.id, position: sample.current, duration: sample.duration)
        }
        onState()
        Task { @MainActor in
            await model.playbackFinished(id: playback.id, error: playbackError)
            if owns(layer), model.hasFinished { controller.pause() }
        }
    }
}
#endif
