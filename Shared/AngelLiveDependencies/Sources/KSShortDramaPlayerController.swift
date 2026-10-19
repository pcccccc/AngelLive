#if canImport(KSPlayer)
import Foundation
import Observation
import AngelLiveCore
import KSPlayer

/// Shared short-drama player ownership, confirmed seeking, and progress restoration.
@MainActor
@Observable
public final class KSShortDramaPlayerController {
    public private(set) var coordinator: KSVideoPlayer.Coordinator?
    public private(set) var playbackID: UUID?
    @ObservationIgnored private var resolvedURL: URL?
    @ObservationIgnored private var pendingRestart: PendingRestart?
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    private var pendingRestore: PendingRestore?
    private var failedPlaybackID: UUID?

    private struct PendingRestore {
        let playbackID: UUID
        let position: Double
        var started = false
    }

    private struct PendingRestart {
        let token: UUID
        let playbackID: UUID
        let layer: KSPlayerLayer
        let continuation: CheckedContinuation<Bool, Never>
        var didBecomeReady = false
    }

    public enum PlaybackFinishDisposition {
        case ignored
        case forward(Error?)
    }

    public init() {}

    public func attach(
        _ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID, url: URL,
        resumePosition: Double?, desiredPlayback: Bool
    ) {
        if self.playbackID != playbackID || self.coordinator !== coordinator {
            restorationTask?.cancel()
            restorationTask = nil
            pendingRestore = resumePosition.map { PendingRestore(playbackID: playbackID, position: $0) }
            completeRestart(succeeded: false)
            failedPlaybackID = nil
        }
        self.coordinator = coordinator
        self.playbackID = playbackID
        wantsPlayback = desiredPlayback
        resolvedURL = url
        if let layer = coordinator.playerLayer, layer.state == .initialized {
            // KSPlayer does not prepare when initialized with isAutoPlay=false.
            // Prepare explicitly while the independent restore hold keeps decoding paused.
            if pendingRestore != nil || !wantsPlayback { layer.pause() }
            layer.prepareToPlay()
        }
    }

    public private(set) var wantsPlayback = true

    public func setDesiredPlayback(_ wantsPlayback: Bool, applyImmediately: Bool = true) {
        self.wantsPlayback = wantsPlayback
        guard applyImmediately else { return }
        if wantsPlayback { play() } else { pause() }
    }

    public func release(_ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID) {
        // An outgoing surface can disappear after the next coordinator has attached.
        // Release only its own layer; clear current state only for the matching owner.
        if self.coordinator === coordinator, self.playbackID == playbackID {
            completeRestart(succeeded: false)
            restorationTask?.cancel()
            restorationTask = nil
            pendingRestore = nil
            self.coordinator = nil
            self.playbackID = nil
            resolvedURL = nil
            failedPlaybackID = nil
        }
        // resetPlayer releases its layer once; an extra stop can assert in Metal.
        if coordinator.playerLayer != nil { coordinator.resetPlayer() }
    }

    public func pause() {
        wantsPlayback = false
        coordinator?.playerLayer?.pause()
    }

    public func play() {
        guard failedPlaybackID == nil else { return }
        wantsPlayback = true
        guard pendingRestart == nil, pendingRestore == nil else { return }
        coordinator?.playerLayer?.play()
    }

    public func stop() {
        wantsPlayback = false
        if let coordinator, let playbackID {
            release(coordinator, playbackID: playbackID)
        }
    }

    public func setRate(_ rate: Float) {
        coordinator?.playbackRate = rate
    }

    public func seek(to time: Double, playbackID: UUID) async -> Bool {
        guard self.playbackID == playbackID, pendingRestart == nil, failedPlaybackID == nil,
              let layer = coordinator?.playerLayer,
              layer.player.duration.isFinite,
              layer.player.duration > 0,
              layer.player.seekable else { return false }
        layer.options.isAccurateSeek = true
        // KSPlayerLayer skips seeks under one second. Exact endpoint requests must
        // reach the player, including a seek from 00:00.5 back to zero.
        let target = min(max(time, 0), layer.player.duration)
        let succeeded = await withCheckedContinuation { continuation in
            layer.player.seek(time: target) { finished in
                continuation.resume(returning: finished)
            }
        }
        guard !Task.isCancelled, self.playbackID == playbackID,
              coordinator?.playerLayer === layer else { return false }
        if succeeded { return true }
        guard target == 0, layer.player is KSMEPlayer, let resolvedURL else { return false }

        // The pinned ME seek path truncates subsecond timestamps before scaling them. A
        // failed exact-zero seek can land before a valid HLS start; reopen this same resolved
        // resource once, without changing its UUID, surface, options or episode selection.
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, self.playbackID == playbackID,
                      coordinator?.playerLayer === layer else {
                    continuation.resume(returning: false)
                    return
                }
                pendingRestart = PendingRestart(
                    token: token, playbackID: playbackID, layer: layer, continuation: continuation
                )
                layer.pause()
                layer.options.startPlayTime = 0
                layer.options.startPlayTimePercentage = 0
                layer.replace(playerItem: MEPlayerItem(io: .left(resolvedURL), options: layer.options))
                // replace resets the player's playback state; keep decoding paused from the
                // new beginning until this request's ready + playable state has been observed.
                layer.pause()
                layer.prepareToPlay()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.completeRestart(token: token, succeeded: false)
            }
        }
    }

    public func isSeekable(for playbackID: UUID?) -> Bool {
        guard let playbackID,
              playbackID == self.playbackID,
              failedPlaybackID == nil, pendingRestart == nil, pendingRestore == nil,
              let player = coordinator?.playerLayer?.player else { return false }
        return player.seekable && player.duration.isFinite && player.duration > 0
    }

    public func synchronize(layer: KSPlayerLayer, state: KSPlayerState) {
        guard coordinator?.playerLayer === layer else { return }
        if pendingRestore?.playbackID == playbackID {
            layer.pause()
            return
        }
        if let pending = pendingRestart, pending.layer === layer, pending.playbackID == playbackID {
            if state == .error {
                failedPlaybackID = pending.playbackID
                wantsPlayback = false
                completeRestart(token: pending.token, succeeded: false)
                layer.pause()
                return
            }
            if state == .readyToPlay {
                pendingRestart?.didBecomeReady = true
            }
            layer.pause()
            if let current = pendingRestart, current.token == pending.token,
               current.didBecomeReady, layer.player.loadState == .playable,
               layer.player.playbackState == .paused {
                completeRestart(token: current.token, succeeded: true)
            }
            return
        }
        guard failedPlaybackID == nil else { return }
        if wantsPlayback {
            if (state == .readyToPlay || state == .paused), !layer.player.isPlaying {
                layer.play()
            }
        } else if layer.player.isPlaying {
            layer.pause()
        }
    }

    public func playbackHasFailed(for playbackID: UUID) -> Bool {
        failedPlaybackID == playbackID
    }

    public func isRestoring(for playbackID: UUID) -> Bool {
        pendingRestore?.playbackID == playbackID
    }

    public func restoreIfPossible(model: ShortDramaPlaybackModel, onReady: @escaping (UUID) -> Void) {
        guard let restore = pendingRestore, !restore.started,
              playbackID == restore.playbackID, model.playback?.id == restore.playbackID,
              let layer = coordinator?.playerLayer, layer.player.isReadyToPlay,
              layer.player.loadState == .playable, layer.player.seekable,
              layer.player.duration.isFinite, layer.player.duration > 0 else { return }
        pendingRestore?.started = true
        let duration = layer.player.duration
        let target = min(restore.position, duration)
        restorationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await seek(to: target, playbackID: restore.playbackID)
            guard !Task.isCancelled, playbackID == restore.playbackID,
                  model.playback?.id == restore.playbackID,
                  coordinator?.playerLayer === layer,
                  pendingRestore?.playbackID == restore.playbackID else { return }
            layer.pause()
            restorationTask = nil
            await model.restorationCompleted(
                id: restore.playbackID, position: target, duration: duration,
                succeeded: succeeded, resumePlayback: wantsPlayback
            )
            guard succeeded, !Task.isCancelled, model.playback?.id == restore.playbackID,
                  playbackID == restore.playbackID, coordinator?.playerLayer === layer else { return }
            // A confirmed endpoint that did not advance is terminal for this instance.
            // Clear intent before releasing the restore hold so late paused/ready callbacks
            // cannot restart it; an already-selected next UUID keeps its inherited intent.
            if model.hasFinished { pause() }
            pendingRestore = nil
            onReady(restore.playbackID)
            if wantsPlayback, !model.hasFinished { layer.play() }
        }
    }

    public func handlePlaybackFinished(
        layer: KSPlayerLayer, playbackID: UUID, error: Error?
    ) -> PlaybackFinishDisposition {
        guard self.playbackID == playbackID, coordinator?.playerLayer === layer else { return .ignored }
        // Seek-related EOF is ambiguous until restoration confirms its target. A successful
        // endpoint restore is settled by the model once; an interior target discards old EOF.
        if pendingRestore?.playbackID == playbackID, error == nil {
            layer.pause()
            return .ignored
        }
        if let pending = pendingRestart, pending.layer === layer, pending.playbackID == playbackID {
            // The old item's EOF may already be queued when replace detaches its delegate.
            // A nil finish cannot identify a failure of the new item; keep waiting for its
            // own ready/playable state instead of failing or completing the episode.
            guard error != nil else {
                layer.pause()
                return .ignored
            }
            failedPlaybackID = playbackID
            wantsPlayback = false
            completeRestart(token: pending.token, succeeded: false)
            layer.pause()
        }
        if failedPlaybackID == playbackID, error == nil { return .ignored }
        return .forward(error)
    }

    private func completeRestart(token: UUID? = nil, succeeded: Bool) {
        guard let pending = pendingRestart, token == nil || pending.token == token else { return }
        pendingRestart = nil
        pending.continuation.resume(returning: succeeded)
    }

    public func timeSample(for playbackID: UUID?) -> (current: Double, duration: Double)? {
        guard let playbackID,
              playbackID == self.playbackID,
              pendingRestore == nil, pendingRestart == nil, failedPlaybackID == nil,
              let player = coordinator?.playerLayer?.player, player.isReadyToPlay,
              player.loadState == .playable else { return nil }
        return (player.currentPlaybackTime, player.duration)
    }
}
#endif
