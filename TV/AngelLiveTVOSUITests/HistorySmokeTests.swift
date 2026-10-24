import XCTest

/// Drives the real FullUI history page with Siri Remote events. Each test owns
/// one UUID-scoped fixture and relaunches that same scope to check persistence.
@MainActor
final class HistorySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var runID: UUID!
    private let remote = XCUIRemote.shared
    private let liveA = "history.card.live:fixture.live-live-a"
    private let liveB = "history.card.live:fixture.live-live-b"
    private let dramaA = "history.card.drama:14:fixture.plugin7:drama-a"
    private let dramaB = "history.card.drama:14:fixture.plugin7:drama-b"

    private func start() {
        continueAfterFailure = false
        app = XCUIApplication()
        runID = UUID()
        launch(reset: true)
    }

    private func finish() {
        if app != nil { record("Final state") }
        app?.terminate()
        app = nil
    }

    func testTypeSelectionDownAndContextMenuCancellation() {
        defer { finish() }
        start()
        focused("history.kind.live")
        remote.press(.right)
        focused("history.kind.drama")
        // Moving focus alone must not switch the selected history source.
        exists(liveA)
        verify(!element(dramaA).exists, "Moving type focus changed the history source")
        remote.press(.select)
        exists(dramaA)
        remote.press(.down)
        focused(dramaA)
        openDeleteMenu()
        remote.press(.menu)
        focused(dramaA)
        exists(dramaB)
        record("Context cancellation returns to source")
    }

    func testDeleteMovesToNeighborThenReturnsToTypeAfterLastRecord() {
        defer { finish() }
        start()
        selectDrama()
        remote.press(.down)
        focused(dramaA)
        deleteFocusedCard()
        absent(dramaA)
        focused(dramaB)
        record("Deletion moves to neighbor")
        deleteFocusedCard()
        absent(dramaB)
        exists("history.empty.drama")
        focused("history.kind.drama")
        remote.press(.left)
        focused("history.kind.live")
        remote.press(.select)
        exists(liveA)
        exists(liveB)
        record("Last deletion returns to selected type")
    }

    func testClearDramaPreservesLiveAcrossRelaunch() {
        defer { finish() }
        start()
        selectDrama()
        clearSelectedType()
        exists("history.empty.drama")
        focused("history.kind.drama")
        app.terminate()
        launch(reset: false)
        exists(liveA)
        exists(liveB)
        selectDrama()
        exists("history.empty.drama")
        verify(!element(dramaA).exists, "Cleared drama reappeared after relaunch")
        record("Cleared drama remains empty after relaunch")
    }

    func testClearLivePreservesDrama() {
        defer { finish() }
        start()
        clearSelectedType()
        exists("history.empty.live")
        focused("history.kind.live")
        selectDrama()
        exists(dramaA)
        exists(dramaB)
        record("Cleared live preserves drama")
    }

    func testLiveDeletionPersistsAcrossRelaunch() {
        defer { finish() }
        start()
        remote.press(.down)
        focused(liveA)
        deleteFocusedCard()
        absent(liveA)
        focused(liveB)
        app.terminate()
        launch(reset: false)
        absent(liveA)
        exists(liveB)
        selectDrama()
        exists(dramaA)
        exists(dramaB)
        record("Deleted live remains absent after relaunch")
    }

    private func launch(reset: Bool) {
        app.launchArguments = ["--ui-testing", "--ui-test-run-id", runID.uuidString]
        if reset { app.launchArguments.append("--ui-test-reset") }
        app.launch()
        focused("history.kind.live")
    }

    private func selectDrama() {
        focused("history.kind.live")
        remote.press(.right)
        focused("history.kind.drama")
        remote.press(.select)
        focused("history.kind.drama")
    }

    private func openDeleteMenu() {
        remote.press(.select, forDuration: 1.2)
        exists("history.delete")
    }

    private func deleteFocusedCard() {
        openDeleteMenu()
        // Live cards also have a favorite action; drama has deletion only.
        focusDeleteMenuCell()
        remote.press(.select)
        absent("history.delete")
    }

    private func clearSelectedType() {
        remote.press(.up)
        focused("history.clear")
        remote.press(.select)
        exists("history.clear.confirm")
        // The system alert has horizontal actions. Its outer Button owns focus;
        // the identified SwiftUI Button is a child with the same bounds.
        let confirm = app.alerts.buttons.containing(.button, identifier: "history.clear.confirm").firstMatch
        verify(confirm.waitForExistence(timeout: 5), "Missing outer clear confirmation action")
        if !confirm.hasFocus { remote.press(.right) }
        focused(confirm, named: "clear confirmation action")
        remote.press(.select)
        absent("history.clear.confirm")
    }

    private func focusDeleteMenuCell() {
        // The identifier is on an Other descendant; the system's enclosing Cell
        // owns focus. Live menus have favorite above delete, drama has delete only.
        let cell = app.cells.containing(.any, identifier: "history.delete").firstMatch
        verify(cell.waitForExistence(timeout: 5), "Missing system delete menu cell")
        if !cell.hasFocus { remote.press(.down) }
        focused(cell, named: "delete menu cell")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func exists(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        verify(element(id).waitForExistence(timeout: 5), "Missing \(id)", file: file, line: line)
    }

    private func absent(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(element(id), predicate: NSPredicate(format: "exists == false"), message: "Still present: \(id)", file: file, line: line)
    }

    private func focused(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        focused(element(id), named: id, file: file, line: line)
    }

    private func focused(_ target: XCUIElement, named name: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        verify(target.waitForExistence(timeout: 5), "Missing \(name)", file: file, line: line)
        wait(target, predicate: NSPredicate(format: "hasFocus == true"), message: "Focus did not reach \(name)", file: file, line: line)
    }

    private func wait(_ target: XCUIElement, predicate: NSPredicate, message: String,
                      file: StaticString, line: UInt) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: target)
        verify(XCTWaiter.wait(for: [expectation], timeout: 5) == .completed, message, file: file, line: line)
    }

    private func verify(_ condition: Bool, _ message: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        guard !condition else { return }
        // XCTest's stop-on-failure exception can bypass Swift defer. Capture and
        // clean up before recording the assertion so failed focus checks retain
        // both the screenshot and complete application hierarchy in xcresult.
        record("Failure: \(message)")
        app.terminate()
        app = nil
        XCTFail(message, file: file, line: line)
    }

    private func record(_ name: String) {
        let isRunning = app.state != .notRunning
        let screenshot = XCTAttachment(screenshot: isRunning ? app.screenshot() : XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: isRunning
            ? app.debugDescription
            : "Application state: notRunning. Application hierarchy is unavailable because the app did not launch or exited.")
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
