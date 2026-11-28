#if os(tvOS) || (os(macOS) && DEBUG)
import Foundation
import Testing
@testable import AngelLiveCore

@Suite("TV back command sequence")
struct TVBackCommandSequenceTests {
    /// Record every phase, including those consumed without performing a return.
    private func returns(_ events: [(Int, TVBackCommandSequence.Event)]) -> [Bool] {
        let start = ContinuousClock.now
        var sequence = TVBackCommandSequence()
        let source = UUID()
        return events.map { milliseconds, event in
            sequence.shouldReturn(for: event, source: source, at: start.advanced(by: .milliseconds(milliseconds)))
        }
    }

    @Test("Menu and a nearby Escape produce one return in either order")
    func crossSourceDuplicate() {
        let menuFirst = returns([(0, .menu), (99, .escapeDown), (110, .escapeUp)])
        #expect(menuFirst == [true, false, false])

        let menuLast = returns([(0, .escapeDown), (10, .escapeUp), (109, .menu)])
        #expect(menuLast == [false, true, false])
    }

    @Test("Menu and repeated key events while Escape is held wait for key-up")
    func heldEscape() {
        let result = returns([(0, .escapeDown), (200, .escapeRepeat), (300, .escapeDown),
                              (400, .menu), (500, .escapeUp)])
        #expect(result == [false, false, false, false, true])
    }

    @Test("Successive Menu commands remain independent")
    func sameSourceMenuCommands() {
        let result = returns([(0, .menu), (50, .menu)])
        #expect(result == [true, true])
    }

    @Test("Separate Escape presses each return on release")
    func sameSourceEscapePresses() {
        let result = returns([(0, .escapeDown), (20, .escapeUp), (50, .escapeDown), (70, .escapeUp)])
        #expect(result == [false, true, false, true])
    }

    @Test("A Menu and an Escape starting outside the duplicate window both return")
    func crossSourceOutsideWindow() {
        let result = returns([(0, .menu), (100, .escapeDown), (120, .escapeUp)])
        #expect(result == [true, false, true])
    }

    @Test("An unmatched Escape release does not return or suppress the next Menu")
    func orphanedEscapeRelease() {
        let result = returns([(0, .escapeUp), (10, .menu)])
        #expect(result == [false, true])
    }

    @Test("A repeated Escape release does not create another return")
    func repeatedEscapeRelease() {
        let result = returns([(0, .escapeDown), (10, .escapeUp), (20, .escapeUp), (109, .menu)])
        #expect(result == [false, true, false, false])
    }

    @Test("An unmatched release preserves a preceding Menu pairing")
    func orphanedReleasePreservesMenuPairing() {
        let result = returns([(0, .menu), (10, .escapeUp), (99, .escapeDown), (110, .escapeUp)])
        #expect(result == [true, false, false, false])
    }

    @Test("Cross-source Menu is suppressed until the 400 millisecond boundary")
    func crossSourceMenuCooldown() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let first = sequence.shouldReturn(for: .menu, source: a, at: start)
        let suppressed = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(399)))
        let allowed = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(400)))
        #expect([first, suppressed, allowed] == [true, false, true])
    }

    @Test("A same-source Menu remains independent at 100 milliseconds")
    func sameSourceAtBoundary() {
        let start = ContinuousClock.now
        let source = UUID()
        var sequence = TVBackCommandSequence()
        let first = sequence.shouldReturn(for: .menu, source: source, at: start)
        let second = sequence.shouldReturn(for: .menu, source: source, at: start.advanced(by: .milliseconds(100)))
        #expect([first, second] == [true, true])
    }

    @Test("Cancellation consumes a late release and protects the next source during cooldown")
    func cancelledPress() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let down = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        sequence.cancelSource(a, at: start.advanced(by: .milliseconds(10)))
        let up = sequence.shouldReturn(for: .escapeUp, source: a, at: start.advanced(by: .milliseconds(20)))
        let blocked = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(409)))
        let allowed = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(410)))
        #expect([down, up, blocked, allowed] == [false, false, false, true])
    }

    @Test("A mismatched release clears the original press and starts its source cooldown")
    func mismatchedRelease() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let down = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        let foreignDown = sequence.shouldReturn(for: .escapeDown, source: b, at: start.advanced(by: .milliseconds(10)))
        let foreignUp = sequence.shouldReturn(for: .escapeUp, source: b, at: start.advanced(by: .milliseconds(20)))
        let oldUp = sequence.shouldReturn(for: .escapeUp, source: a, at: start.advanced(by: .milliseconds(30)))
        let blocked = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(419)))
        let allowed = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(420)))
        #expect([down, foreignDown, foreignUp, oldUp, blocked, allowed] == [false, false, false, false, false, true])
    }

    @Test("A lost release expires at five seconds and late releases remain inert")
    func stalePressExpires() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let down = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        let earlyMenu = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(4999)))
        let menu = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .seconds(5)))
        let lateUp = sequence.shouldReturn(for: .escapeUp, source: a, at: start.advanced(by: .milliseconds(5001)))
        #expect([down, earlyMenu, menu, lateUp] == [false, false, true, false])
    }

    @Test("A fresh Escape press returns after a cancelled source cooldown")
    func freshPressAfterCancellation() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let oldDown = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        sequence.cancelSource(a, at: start.advanced(by: .milliseconds(10)))
        let newDown = sequence.shouldReturn(for: .escapeDown, source: b, at: start.advanced(by: .milliseconds(410)))
        let newUp = sequence.shouldReturn(for: .escapeUp, source: b, at: start.advanced(by: .milliseconds(420)))
        #expect([oldDown, newDown, newUp] == [false, false, true])
    }

    @Test("An Escape release from a different source is suppressed during cooldown")
    func crossSourceEscapeCooldown() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let menu = sequence.shouldReturn(for: .menu, source: a, at: start)
        let down = sequence.shouldReturn(for: .escapeDown, source: b, at: start.advanced(by: .milliseconds(200)))
        let up = sequence.shouldReturn(for: .escapeUp, source: b, at: start.advanced(by: .milliseconds(399)))
        #expect([menu, down, up] == [true, false, false])
    }

    @Test("A new Escape press can replace a lost press after five seconds")
    func newPressAfterTimeout() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let oldDown = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        let newDown = sequence.shouldReturn(for: .escapeDown, source: b, at: start.advanced(by: .seconds(5)))
        let newUp = sequence.shouldReturn(for: .escapeUp, source: b, at: start.advanced(by: .milliseconds(5020)))
        #expect([oldDown, newDown, newUp] == [false, false, true])
    }

    @Test("Cancelling a second source preserves the first source cooldown")
    func overlappingCooldowns() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let first = sequence.shouldReturn(for: .menu, source: a, at: start)
        let down = sequence.shouldReturn(for: .escapeDown, source: b, at: start.advanced(by: .milliseconds(100)))
        sequence.cancelSource(b, at: start.advanced(by: .milliseconds(150)))
        let blocked = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(399)))
        let allowed = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .milliseconds(400)))
        #expect([first, down, blocked, allowed] == [true, false, false, true])
    }

    @Test("Cancelling a timed-out press does not start a new cooldown")
    func cancellingExpiredPress() {
        let start = ContinuousClock.now
        let a = UUID(), b = UUID()
        var sequence = TVBackCommandSequence()
        let down = sequence.shouldReturn(for: .escapeDown, source: a, at: start)
        sequence.cancelSource(a, at: start.advanced(by: .seconds(5)))
        let menu = sequence.shouldReturn(for: .menu, source: b, at: start.advanced(by: .seconds(5)))
        let lateUp = sequence.shouldReturn(for: .escapeUp, source: a, at: start.advanced(by: .milliseconds(5001)))
        #expect([down, menu, lateUp] == [false, true, false])
    }

    @Test("A Menu followed by a long Escape press in the parent returns only once")
    func menuThenCrossViewLongPress() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        var sequence = TVBackCommandSequence()
        let menu = sequence.shouldReturn(for: .menu, source: modal, at: start)
        let down = sequence.shouldReturn(for: .escapeDown, source: parent, at: start.advanced(by: .milliseconds(20)))
        let up = sequence.shouldReturn(for: .escapeUp, source: parent, at: start.advanced(by: .milliseconds(500)))
        let nextDown = sequence.shouldReturn(for: .escapeDown, source: parent, at: start.advanced(by: .milliseconds(600)))
        let nextUp = sequence.shouldReturn(for: .escapeUp, source: parent, at: start.advanced(by: .milliseconds(620)))
        #expect([menu, down, up, nextDown, nextUp] == [true, false, false, false, true])
    }

    @Test("Parent Escape routes one action to the active modal", arguments: [63, 1150])
    @MainActor
    func parentEscapeClosesModal(duration: Int) {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.handle(.escapeDown, from: parent, at: start) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .milliseconds(duration))) { parentCalls += 1 }
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(duration + 1))) { parentCalls += 1 }
        #expect(modalCalls == 1)
        #expect(parentCalls == 0)
    }

    @Test("A Menu from any source closes only the top modal and silences closing input")
    @MainActor
    func menuRoutesToTopModal() {
        let start = ContinuousClock.now
        let parent = UUID(), lower = UUID(), upper = UUID()
        let router = TVBackCommandRouter()
        var parentCalls = 0, lowerCalls = 0, upperCalls = 0
        router.beginModal(lower) { lowerCalls += 1 }
        router.beginModal(upper) { upperCalls += 1 }
        router.handle(.menu, from: parent, at: start) { parentCalls += 1 }
        router.handle(.menu, from: upper, at: start.advanced(by: .milliseconds(1))) { parentCalls += 1 }
        router.handle(.escapeDown, from: lower, at: start.advanced(by: .milliseconds(2))) { parentCalls += 1 }
        router.handle(.escapeRepeat, from: lower, at: start.advanced(by: .milliseconds(3))) { parentCalls += 1 }
        router.handle(.escapeUp, from: lower, at: start.advanced(by: .milliseconds(4))) { parentCalls += 1 }
        #expect(parentCalls == 0 && lowerCalls == 0 && upperCalls == 1)
    }

    @Test("Sequence returns the top modal destination and enters closing state")
    func sequenceModalDestination() {
        let start = ContinuousClock.now
        let parent = UUID(), lower = UUID(), upper = UUID()
        var sequence = TVBackCommandSequence()
        sequence.beginModal(lower)
        sequence.beginModal(upper)
        let destination = sequence.route(for: .menu, source: parent, at: start)
        let quiet = sequence.route(for: .menu, source: upper, at: start.advanced(by: .milliseconds(1)))
        #expect(destination == .modal(upper))
        #expect(quiet == nil)
    }

    @Test("Programmatic closing stays silent and duplicate begin cannot reopen")
    @MainActor
    func programmaticClosingAndReentry() {
        let start = ContinuousClock.now
        let parent = UUID(), modal = UUID()
        let router = TVBackCommandRouter()
        var calls = 0, replacementCalls = 0, parentCalls = 0
        router.beginModal(modal) { calls += 1 }
        router.markModalClosing(modal, at: start)
        router.beginModal(modal) { replacementCalls += 1 }
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1))) { parentCalls += 1 }
        router.handle(.escapeDown, from: parent, at: start.advanced(by: .milliseconds(2))) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .milliseconds(3))) { parentCalls += 1 }
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1000))) { parentCalls += 1 }
        #expect(calls == 0 && replacementCalls == 0 && parentCalls == 0)
    }

    @Test("Ended modal prevents parent actions until the cooldown boundary")
    @MainActor
    func modalEndCooldown() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.markModalClosing(modal, at: start)
        router.endModal(modal, at: start)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(399))) { parentCalls += 1 }
        #expect(parentCalls == 0)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(400))) { parentCalls += 1 }
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(450))) { parentCalls += 1 }
        #expect(parentCalls == 2)
        #expect(modalCalls == 0)
    }

    @Test("Nested modal removal keeps the top and duplicate end does not extend cooldown")
    @MainActor
    func nestedAndDuplicateEnd() {
        let start = ContinuousClock.now
        let parent = UUID(), lower = UUID(), upper = UUID()
        let router = TVBackCommandRouter()
        var parentCalls = 0, lowerCalls = 0, upperCalls = 0
        router.beginModal(lower) { lowerCalls += 1 }
        router.beginModal(upper) { upperCalls += 1 }
        router.endModal(lower, at: start)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(500))) { parentCalls += 1 }
        #expect(parentCalls == 0 && lowerCalls == 0 && upperCalls == 1)
        router.endModal(upper, at: start.advanced(by: .milliseconds(600)))
        router.endModal(upper, at: start.advanced(by: .milliseconds(900)))
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1000))) { parentCalls += 1 }
        #expect(parentCalls == 1)
    }

    @Test("Closing nested modals restores the lower layer then the parent")
    @MainActor
    func nestedStackOrder() {
        let start = ContinuousClock.now
        let parent = UUID(), lower = UUID(), upper = UUID()
        let router = TVBackCommandRouter()
        var parentCalls = 0, lowerCalls = 0, upperCalls = 0
        router.beginModal(lower) { lowerCalls += 1 }
        router.beginModal(upper) { upperCalls += 1 }
        router.endModal(upper, at: start)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(400))) { parentCalls += 1 }
        #expect(parentCalls == 0 && lowerCalls == 1 && upperCalls == 0)
        router.endModal(lower, at: start.advanced(by: .milliseconds(500)))
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(900))) { parentCalls += 1 }
        #expect(parentCalls == 1)
    }

    @Test("A five-second held press expires and a new long press closes the modal")
    @MainActor
    func modalPressTimeoutAndNewPress() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.handle(.escapeDown, from: parent, at: start) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .seconds(5))) { parentCalls += 1 }
        #expect(modalCalls == 0 && parentCalls == 0)
        router.handle(.escapeDown, from: parent, at: start.advanced(by: .milliseconds(5010))) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .milliseconds(6160))) { parentCalls += 1 }
        #expect(modalCalls == 1 && parentCalls == 0)
    }

    @Test("Modal end restarts cooldown after a long closing period")
    @MainActor
    func closingAndEndCooldown() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.markModalClosing(modal, at: start)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1000))) { parentCalls += 1 }
        router.endModal(modal, at: start.advanced(by: .milliseconds(1000)))
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1399))) { parentCalls += 1 }
        #expect(modalCalls == 0 && parentCalls == 0)
        router.handle(.menu, from: parent, at: start.advanced(by: .milliseconds(1400))) { parentCalls += 1 }
        #expect(parentCalls == 1)
    }

    @Test("A press begun during cooldown stays suppressed after it ends")
    @MainActor
    func pressStraddlingCooldown() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.endModal(modal, at: start)
        router.handle(.escapeDown, from: parent, at: start.advanced(by: .milliseconds(399))) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .milliseconds(450))) { parentCalls += 1 }
        #expect(parentCalls == 0 && modalCalls == 0)
        router.handle(.escapeDown, from: parent, at: start.advanced(by: .milliseconds(500))) { parentCalls += 1 }
        router.handle(.escapeUp, from: parent, at: start.advanced(by: .milliseconds(520))) { parentCalls += 1 }
        #expect(parentCalls == 1 && modalCalls == 0)
    }

    @Test("A press split between parent and modal routes only to the modal")
    @MainActor
    func splitSourcePress() {
        let start = ContinuousClock.now
        let modal = UUID(), parent = UUID()
        let router = TVBackCommandRouter()
        var modalCalls = 0, parentCalls = 0
        router.beginModal(modal) { modalCalls += 1 }
        router.handle(.escapeDown, from: parent, at: start) { parentCalls += 1 }
        router.handle(.escapeUp, from: modal, at: start.advanced(by: .milliseconds(63))) { parentCalls += 1 }
        #expect(parentCalls == 0 && modalCalls == 1)
    }

}

private extension TVBackCommandSequence {
    mutating func shouldReturn(for event: Event, source: UUID, at now: ContinuousClock.Instant) -> Bool {
        route(for: event, source: source, at: now) != nil
    }
}
#endif
