import CoreGraphics

enum PlayerVideoSizeResolver {
    static func resolve(trackSize: CGSize, rotation: UInt16, presentationSize: CGSize?) -> CGSize? {
        guard isValid(trackSize) else { return nil }
        // Presentation dimensions already include the display transform.
        if let presentationSize, isValid(presentationSize) {
            return presentationSize
        }
        let angle = Int(rotation)
        if abs(angle - 90) <= 1 || abs(angle - 270) <= 1 {
            return CGSize(width: trackSize.height, height: trackSize.width)
        }
        return trackSize
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
    }
}

#if canImport(KSPlayer)
import KSPlayer
import KSPlayerUI
internal import AVFoundation

@MainActor
enum PlayerVideoGeometry {
    static func readyNaturalSize(of layer: KSPlayerLayer) -> CGSize? {
        let player = layer.player
        guard player.isReadyToPlay,
              let videoTrack = player.tracks(mediaType: .video).first(where: { $0.isEnabled }) else {
            return nil
        }

        let presentationSize = (player as? KSAVPlayer)?.player.currentItem?.presentationSize
        // Track naturalSize already accounts for pixel aspect ratio in the player adapter.
        return PlayerVideoSizeResolver.resolve(
            trackSize: videoTrack.naturalSize,
            rotation: videoTrack.rotation,
            presentationSize: presentationSize
        )
    }
}
#endif
