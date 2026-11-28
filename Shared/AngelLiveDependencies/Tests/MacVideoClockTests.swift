#if os(macOS) && canImport(KSPlayer)
import Testing
@testable import KSPlayer
@testable import AngelLiveDependencies

@MainActor
struct MacVideoClockTests {
    @Test func preferredDisplayLinkFrameRate() {
        let options = PlayerOptions()
        #expect(!options.preferredFrame(fps: 30))
        #expect(!options.preferredFrame(fps: 60))
        #expect(options.preferredFrame(fps: 120))

        options.enablesMacOSHighFrameRateClockTolerance = true
        for fps: Float in [15, 24, 29.97, 30, 50, 59.94, 60, 120, 240] {
            #expect(options.preferredFrame(fps: fps))
        }
        for fps: Float in [-1, 0, Float(15).nextDown, Float(240).nextUp, 1000, .nan, .infinity] {
            #expect(!options.preferredFrame(fps: fps))
        }
    }

    @Test func highFrameRateTolerance() {
        var clock = KSClock()
        clock.rate = 0 // A fixed media clock makes adjacent floating-point boundary values deterministic.
        let options = PlayerOptions()
        func sync(_ time: Double, fps: Double = 60) -> ClockProcessType {
            options.videoClockSync(main: clock, nextVideoTime: time, fps: fps, frameCount: 3)
        }
        let halfFrame = 1.0 / 120
        let tick = 1.0 / 60
        guard case .remain = sync(halfFrame.nextUp) else {
            Issue.record("The default clock should wait for an early frame")
            return
        }
        options.enablesMacOSHighFrameRateClockTolerance = true
        for lead in [halfFrame, halfFrame.nextUp, tick] {
            guard case .next = sync(lead) else {
                Issue.record("Expected presentation at lead \(lead)")
                return
            }
        }
        guard case .remain = sync(tick.nextUp),
              case .next = sync(tick, fps: 50),
              case .remain = sync(tick, fps: 49),
              case .next = sync(tick, fps: 30),
              case .remain = sync(tick.nextUp, fps: 30),
              case .dropFrame(count: 1) = sync(-0.2),
              case .next = sync(tick),
              case .dropFrame(count: 1) = sync(-0.2) else {
            Issue.record("Unexpected clock decision or consecutive-delay count")
            return
        }
    }

    @Test(arguments: [false, true])
    func snapshotsKeepClockPolicy(enabled: Bool) {
        let options = PlayerOptions()
        options.enablesMacOSHighFrameRateClockTolerance = enabled
        #expect(options.mediaTransformSessionSnapshot().enablesMacOSHighFrameRateClockTolerance == enabled)
        #expect(options.dualStreamVideoSessionSnapshot().enablesMacOSHighFrameRateClockTolerance == enabled)
    }
}
#endif
