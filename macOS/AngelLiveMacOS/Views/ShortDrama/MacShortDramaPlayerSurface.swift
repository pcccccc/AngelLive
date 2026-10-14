#if canImport(KSPlayer)
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer

@MainActor
@Observable
final class MacShortDramaPlayerController {
    private(set) var coordinator: KSVideoPlayer.Coordinator?
    private(set) var playbackID: UUID?

    func attach(_ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID) {
        self.coordinator = coordinator
        self.playbackID = playbackID
    }

    private(set) var wantsPlayback = true

    func setDesiredPlayback(_ wantsPlayback: Bool, applyImmediately: Bool = true) {
        self.wantsPlayback = wantsPlayback
        guard applyImmediately else { return }
        if wantsPlayback { play() } else { pause() }
    }

    func detach(playbackID: UUID) {
        guard self.playbackID == playbackID else { return }
        coordinator = nil
        self.playbackID = nil
    }

    func pause() {
        wantsPlayback = false
        coordinator?.playerLayer?.pause()
    }

    func play() {
        wantsPlayback = true
        coordinator?.playerLayer?.play()
    }

    private var releasedPlaybackIDs = Set<UUID>()

    func release(_ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID) {
        guard releasedPlaybackIDs.insert(playbackID).inserted else { return }
        // resetPlayer is the sole owner of stop; a second stop triggers a Metal assertion.
        coordinator.resetPlayer()
        detach(playbackID: playbackID)
    }

    func stop() {
        wantsPlayback = false
        if let coordinator, let playbackID { release(coordinator, playbackID: playbackID) }
    }

    func setRate(_ rate: Float) {
        coordinator?.playbackRate = rate
    }

    func seek(to time: Double, autoPlay: Bool) {
        guard let layer = coordinator?.playerLayer,
              layer.player.duration.isFinite,
              layer.player.duration > 0,
              layer.player.seekable else { return }
        layer.seek(
            time: min(max(time, 0), layer.player.duration),
            autoPlay: autoPlay
        )
    }

    func isSeekable(for playbackID: UUID?) -> Bool {
        guard let playbackID,
              playbackID == self.playbackID,
              let player = coordinator?.playerLayer?.player else { return false }
        return player.seekable && player.duration.isFinite && player.duration > 0
    }

    func synchronize(layer: KSPlayerLayer, state: KSPlayerState) {
        if wantsPlayback {
            if (state == .readyToPlay || state == .paused), !layer.player.isPlaying {
                layer.play()
            }
        } else if layer.player.isPlaying {
            layer.pause()
        }
    }

    func timeSample(for playbackID: UUID?) -> (current: Double, duration: Double)? {
        guard let playbackID,
              playbackID == self.playbackID,
              let player = coordinator?.playerLayer?.player else { return nil }
        return (player.currentPlaybackTime, player.duration)
    }
}

struct MacShortDramaPlayerSurface: View {
    let playback: ShortDramaPlayback
    let playbackRate: Float
    let volume: Float
    let model: ShortDramaPlaybackModel
    let controller: MacShortDramaPlayerController
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
        model: ShortDramaPlaybackModel,
        controller: MacShortDramaPlayerController,
        playbackSession: KSPlayerPlaybackSession,
        onReady: @escaping (UUID) -> Void,
        onPlayingChanged: @escaping (UUID, Bool) -> Void
    ) {
        self.playback = playback
        self.playbackRate = playbackRate
        self.volume = volume
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        self.onPlayingChanged = onPlayingChanged

        let options = PlayerOptions()
        options.isAutoPlay = controller.wantsPlayback
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
            controller.attach(coordinator, playbackID: playback.id)
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
        if !model.hasFinished { controller.synchronize(layer: layer, state: state) }
        if !didReportReady && (
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
        let willAdvance = error == nil && model.selectedEpisodeID.flatMap {
            ShortDramaCompletionPolicy.nextEpisode(in: model.episodes, after: $0, autoplay: model.autoplay)
        } != nil
        // An immediate continuation retains playback intent. A modal keeps its pause until
        // the host restores the saved intent before releasing the deferred completion.
        controller.setDesiredPlayback(willAdvance && controller.wantsPlayback, applyImmediately: false)
        onPlayingChanged(playback.id, false)
        Task { @MainActor in
            await model.playbackFinished(id: playback.id, error: error)
        }
    }
}

#endif
