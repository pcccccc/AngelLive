#if canImport(KSPlayer)
import Testing
@testable import AngelLiveDependencies

@MainActor
struct KSPlayerInlinePictureInPictureTests {
    @Test("Turning off automatic PiP revokes eligibility during an active PiP session")
    func disableDuringActivePictureInPicture() {
        let controller = Controller()
        #expect(KSPlayerInlinePictureInPicture.updateEligibility(true, for: controller))
        #expect(controller.canStartPictureInPictureAutomaticallyFromInline)

        controller.isPictureInPictureActive = true
        #expect(KSPlayerInlinePictureInPicture.updateEligibility(false, for: controller))
        #expect(!controller.canStartPictureInPictureAutomaticallyFromInline)

        controller.isPictureInPictureActive = false
        #expect(!KSPlayerInlinePictureInPicture.updateEligibility(false, for: controller))
    }

    private final class Controller: InlinePictureInPictureController {
        var canStartPictureInPictureAutomaticallyFromInline = false
        var isPictureInPictureActive = false
    }
}
#endif
