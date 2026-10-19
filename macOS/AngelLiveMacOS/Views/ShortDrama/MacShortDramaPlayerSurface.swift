#if canImport(KSPlayer)
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer

struct MacShortDramaPlayerSurface: View {
    let playback: ShortDramaPlayback
    let playbackRate: Float
    let volume: Float
    let desiredPlayback: Bool
    let model: ShortDramaPlaybackModel
    let controller: KSShortDramaPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let onReady: (UUID) -> Void
    let onPlayingChanged: (UUID, Bool) -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions
    @State private var didReportReady = false

    init(
        playback: ShortDramaPlayback,
        playbackRate: Float,
        volume: Float,
        desiredPlayback: Bool,
        model: ShortDramaPlaybackModel,
        controller: KSShortDramaPlayerController,
        playbackSession: KSPlayerPlaybackSession,
        onReady: @escaping (UUID) -> Void,
        onPlayingChanged: @escaping (UUID, Bool) -> Void
    ) {
        self.playback = playback
        self.playbackRate = playbackRate
        self.volume = volume
        self.desiredPlayback = desiredPlayback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        self.onPlayingChanged = onPlayingChanged

        let options = PlayerOptions()
        options.isAutoPlay = desiredPlayback && playback.resumePosition == nil
        options.isLoopPlay = false
        options.registerRemoteControll = false
        options.automaticWindowResize = false
        options.startPlayRate = playbackRate
        _options = State(initialValue: options)
        _ = KSPlayerSessionConfigurator.apply(
            quality: playback.quality,
            to: options,
            fallbackUserAgent: "libmpv",
            liveReconnectPolicy: .applicationManaged
        )
    }

    var body: some View {
        MacFullUIVideoPlayer(coordinator: coordinator, url: playback.url, options: options)
        .onStateChanged { layer, state in handlePlayerState(layer, state) }
        .onFinish { layer, error in handlePlaybackFinished(layer, error) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.black)
        .onAppear {
            coordinator.playbackRate = playbackRate
            controller.attach(
                coordinator, playbackID: playback.id, url: playback.url,
                resumePosition: playback.resumePosition, desiredPlayback: desiredPlayback
            )
        }
        .onChange(of: playbackRate) { _, newValue in
            coordinator.playbackRate = newValue
        }
        .onChange(of: volume) { _, newValue in
            coordinator.playerLayer?.player.playbackVolume = newValue
        }
        .onDisappear {
            if controller.playbackID == playback.id { playbackSession.attach(playerLayer: nil) }
            controller.release(coordinator, playbackID: playback.id)
        }
    }

    private func handlePlayerState(_ layer: KSPlayerLayer, _ state: KSPlayerState) {
        guard model.playback?.id == playback.id,
              controller.playbackID == playback.id,
              layer === coordinator.playerLayer else { return }
        layer.player.contentMode = .scaleAspectFit
        playbackSession.attach(playerLayer: layer)
        playbackSession.activate()
        layer.player.playbackRate = playbackRate
        layer.player.playbackVolume = volume
        controller.synchronize(layer: layer, state: state)
        controller.restoreIfPossible(model: model, onReady: onReady)
        if !didReportReady && !controller.isRestoring(for: playback.id) && (
            state == .bufferFinished
                || (state == .paused && layer.player.loadState == .playable)
        ) {
            didReportReady = true
            onReady(playback.id)
        }
        onPlayingChanged(playback.id, layer.player.isPlaying)
    }

    private func handlePlaybackFinished(_ layer: KSPlayerLayer, _ error: Error?) {
        guard model.playback?.id == playback.id,
              controller.playbackID == playback.id,
              layer === coordinator.playerLayer else { return }
        switch controller.handlePlaybackFinished(layer: layer, playbackID: playback.id, error: error) {
        case .ignored:
            return
        case .forward(let playbackError):
            if let sample = controller.timeSample(for: playback.id) {
                model.recordProgress(id: playback.id, position: sample.current, duration: sample.duration)
            }
            let willAdvance = playbackError == nil && model.selectedEpisodeID.flatMap {
                ShortDramaCompletionPolicy.nextEpisode(in: model.episodes, after: $0, autoplay: model.autoplay)
            } != nil
            // Keep the host's existing continuation intent after consuming restore-related EOF.
            controller.setDesiredPlayback(willAdvance && controller.wantsPlayback, applyImmediately: false)
            onPlayingChanged(playback.id, false)
            Task { @MainActor in
                await model.playbackFinished(id: playback.id, error: playbackError)
            }
        }
    }
}

#endif
