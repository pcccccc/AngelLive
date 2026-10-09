#if canImport(KSPlayer)
import CoreGraphics
import KSPlayer
internal import AVFoundation

@MainActor
enum PlayerVideoGeometry {
    static func readyNaturalSize(of layer: KSPlayerLayer) -> CGSize? {
        let player = layer.player
        guard player.isReadyToPlay,
              let videoTrack = player.tracks(mediaType: .video).first(where: { $0.isEnabled }) else {
            return nil
        }

        let trackSize = videoTrack.naturalSize
        let naturalSize = player.naturalSize
        guard trackSize.width.isFinite, trackSize.height.isFinite,
              trackSize.width > 1, trackSize.height > 1,
              naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 1, naturalSize.height > 1 else {
            return nil
        }

        return naturalSize
    }
}
#endif
