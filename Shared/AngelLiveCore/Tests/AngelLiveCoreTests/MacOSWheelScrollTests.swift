#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import AngelLiveCore

@Suite("macOS wheel scroll routing", .serialized)
@MainActor
struct MacOSWheelScrollTests {
    @Test("Routes the dominant wheel delta only while a region is active")
    func routesDominantWheelDelta() {
        let router = MacHorizontalWheelRouter.shared
        let token = UUID()
        var receivedDelta: CGFloat?

        router.activate(token: token) { delta, _ in
            receivedDelta = delta
            return true
        }

        let consumed = router.route(
            deltaX: 2,
            deltaY: 6,
            hasPreciseScrollingDeltas: false
        )

        #expect(consumed)
        #expect(receivedDelta == 6)

        router.deactivate(token: token)
        #expect(!router.route(
            deltaX: 2,
            deltaY: 6,
            hasPreciseScrollingDeltas: false
        ))
    }
}
#endif
