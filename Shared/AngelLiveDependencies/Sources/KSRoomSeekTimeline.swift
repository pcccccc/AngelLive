#if canImport(KSPlayer)
import AngelLiveCore
import Foundation
import KSPlayer
import Observation

/// The timeline for a room whose playback plan identifies it as on demand.
/// Its seek request and preview belong to the current room and source.
@MainActor
@Observable
public final class KSRoomSeekTimeline {
    public private(set) var elapsed = 0.0
    public private(set) var duration = 0.0
    public private(set) var target: Double?
    public private(set) var canSeek = false
    public private(set) var isCommitting = false
    public let preview = SeekPreviewModel()

    @ObservationIgnored private var sourceID = UUID()
    @ObservationIgnored private var requestID: UUID?

    public init() {}

    public func sample(_ layer: KSPlayerLayer?) {
        guard target == nil, !isCommitting else { return }
        guard let player = layer?.player, player.isReadyToPlay else {
            canSeek = false
            return
        }
        let maximum = player.duration
        duration = maximum.isFinite ? max(0, maximum) : 0
        elapsed = bounded(player.currentPlaybackTime)
        canSeek = duration > 0 && player.seekable
    }

    public func beginScrubbing() {
        guard canSeek, !isCommitting, target == nil else { return }
        target = elapsed
    }

    public func updateScrub(to time: Double, url: URL?, quality: LiveQualityDetail?) {
        guard target != nil else { return }
        let time = bounded(time)
        target = time
        if let url, let quality {
            preview.update(id: sourceID, url: url, quality: quality, targetTime: time)
        }
    }

    public func cancelScrubbing() {
        target = nil
        preview.endScrubbing()
    }

    public func seek(to time: Double, on layer: KSPlayerLayer?) {
        cancelScrubbing()
        guard canSeek, !isCommitting, let layer, layer.player.isReadyToPlay, layer.player.seekable else { return }
        let time = bounded(time)
        let wasPlaying = layer.player.isPlaying
        let url = layer.url
        let playerID = ObjectIdentifier(layer.player)
        let request = UUID()
        requestID = request
        isCommitting = true
        layer.seek(time: time, autoPlay: false) { [weak self, weak layer] succeeded in
            guard let self, self.requestID == request else { return }
            self.requestID = nil
            self.isCommitting = false
            guard let layer, layer.url == url, ObjectIdentifier(layer.player) == playerID else { return }
            if succeeded { self.elapsed = time }
            if wasPlaying { layer.play() } else { layer.pause() }
        }
    }

    public func reset() {
        sourceID = UUID()
        requestID = nil
        elapsed = 0
        duration = 0
        target = nil
        canSeek = false
        isCommitting = false
        preview.cancel()
    }

    private func bounded(_ time: Double) -> Double {
        time.isFinite ? min(duration, max(0, time)) : 0
    }
}
#endif
