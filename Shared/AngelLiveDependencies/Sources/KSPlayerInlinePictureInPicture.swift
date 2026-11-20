import AVKit

#if canImport(KSPlayer)
import KSPlayer

@MainActor
protocol InlinePictureInPictureController: AnyObject {
    var canStartPictureInPictureAutomaticallyFromInline: Bool { get set }
    var isPictureInPictureActive: Bool { get }
}

@MainActor
public enum KSPlayerInlinePictureInPicture {
    static func updateEligibility(
        _ enabled: Bool,
        for controller: some InlinePictureInPictureController
    ) -> Bool {
        // Revoke eligibility even during active PiP. Keep the controller alive
        // in that case so KSPlayer can finish restoring the inline player.
        controller.canStartPictureInPictureAutomaticallyFromInline = enabled
        return enabled || controller.isPictureInPictureActive
    }

    #if os(iOS)
    public static func update(_ enabled: Bool, on layer: KSComplexPlayerLayer) {
        let player = layer.player
        layer.options.canStartPictureInPictureAutomaticallyFromInline = enabled
        if enabled, player.isReadyToPlay, player.pipController == nil {
            player.configPIP()
        }

        guard let controller = player.pipController as? AVPictureInPictureController else { return }
        if updateEligibility(enabled, for: controller) {
            controller.delegate = layer
        } else {
            player.pipController = nil
        }
    }
    #endif
}

#if os(iOS)
extension AVPictureInPictureController: InlinePictureInPictureController {}
#endif
#endif
