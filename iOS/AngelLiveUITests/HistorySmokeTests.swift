import XCTest

/// Runs against the production FullUI history page with a per-test synthetic store.
/// The test plan is serial: Xcode must not clone the simulator for these tests.
@MainActor
final class HistorySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = UUID()

    private func startNewRun() {
        continueAfterFailure = false
        runID = UUID()
        app = XCUIApplication()
        launch(reset: true)
    }

    private func finish() {
        guard app != nil else { return }
        if let testRun, testRun.totalFailureCount > 0 {
            attachEvidence(named: "failure")
        }
        app?.terminate()
        app = nil
    }

    func testTypesSwitchByTapAndHorizontalSwipe() {
        defer { finish() }
        startNewRun()
        assertVisible(item(.live, "live-a"))
        select(.drama)
        assertVisible(item(.drama, "drama-a"))
        app.collectionViews["history.list.drama"].swipeRight()
        assertVisible(item(.live, "live-a"))
        assertSelectedType(.live)
        app.collectionViews["history.list.live"].swipeLeft()
        assertVisible(item(.drama, "drama-a"))
        assertSelectedType(.drama)
        select(.live)
        assertVisible(item(.live, "live-b"))
        attachEvidence(named: "types-returned-to-live")
    }

    func testDeleteSingleAndLastLiveRecord() {
        defer { finish() }
        startNewRun()
        delete(.live, "live-a")
        assertVisible(item(.live, "live-b"))
        delete(.live, "live-b")
        assertEmpty(.live)
        select(.drama)
        assertVisible(item(.drama, "drama-a"))
        assertVisible(item(.drama, "drama-b"))
    }

    func testDeleteSingleAndLastDramaRecord() {
        defer { finish() }
        startNewRun()
        select(.drama)
        delete(.drama, "drama-a")
        assertVisible(item(.drama, "drama-b"))
        delete(.drama, "drama-b")
        assertEmpty(.drama)
        select(.live)
        assertVisible(item(.live, "live-a"))
        assertVisible(item(.live, "live-b"))
    }

    func testClearOnlyLiveHistory() {
        defer { finish() }
        startNewRun()
        clearCurrentType()
        assertEmpty(.live)
        select(.drama)
        assertVisible(item(.drama, "drama-a"))
        assertVisible(item(.drama, "drama-b"))
    }

    func testClearOnlyDramaHistory() {
        defer { finish() }
        startNewRun()
        select(.drama)
        clearCurrentType()
        assertEmpty(.drama)
        select(.live)
        assertVisible(item(.live, "live-a"))
        assertVisible(item(.live, "live-b"))
    }

    func testDeletedRecordsStayDeletedAfterRelaunch() {
        defer { finish() }
        startNewRun()
        delete(.live, "live-a")
        select(.drama)
        delete(.drama, "drama-a")
        app.terminate()
        launch(reset: false)
        assertVisible(item(.live, "live-b"))
        XCTAssertFalse(item(.live, "live-a").exists)
        select(.drama)
        assertVisible(item(.drama, "drama-b"))
        XCTAssertFalse(item(.drama, "drama-a").exists)
        attachEvidence(named: "relaunch-persisted-drama-deletion")
    }

    func testClearCancelKeepsRecords() {
        defer { finish() }
        startNewRun()
        app.buttons["history.clear"].tap()
        let cancel = alertAction("history.clear.cancel")
        assertVisible(cancel)
        cancel.tap()
        assertVisible(item(.live, "live-a"))
        assertVisible(item(.live, "live-b"))
    }

    private enum Kind: String {
        case live, drama
    }

    private func launch(reset: Bool) {
        app.launchArguments = ["--ui-testing", "--ui-test-run-id", runID.uuidString]
        if reset { app.launchArguments.append("--ui-test-reset") }
        app.launch()
        assertVisible(app.descendants(matching: .any)["history.type.live"].firstMatch)
        assertVisible(item(.live, "live-b"))
        assertSelectedType(.live)
    }

    private func select(_ kind: Kind) {
        let tab = app.descendants(matching: .any)["history.type.\(kind.rawValue)"].firstMatch
        assertVisible(tab)
        tab.tap()
        assertSelectedType(kind)
    }

    private func assertSelectedType(_ selected: Kind, file: StaticString = #filePath, line: UInt = #line) {
        for kind in [Kind.live, .drama] {
            let tab = app.descendants(matching: .any)["history.type.\(kind.rawValue)"].firstMatch
            let matches = tab.wait(for: \.isSelected, toEqual: kind == selected, timeout: 5)
            if !matches { attachEvidence(named: "type-selection-mismatch") }
            XCTAssertTrue(matches, "Only \(selected.rawValue) should be selected", file: file, line: line)
        }
        XCTAssertTrue(app.descendants(matching: .any)["history.type.\(selected.rawValue)"].firstMatch.isSelected,
                      file: file, line: line)
        let other: Kind = selected == .live ? .drama : .live
        XCTAssertFalse(app.descendants(matching: .any)["history.type.\(other.rawValue)"].firstMatch.isSelected,
                       file: file, line: line)
    }

    private func alertAction(_ identifier: String) -> XCUIElement {
        // The current SwiftUI alert exposes a native action containing a second Button
        // with the same identifier. Target the outer action, whose child is in the snapshot.
        app.alerts.buttons.matching(identifier: identifier)
            .containing(.button, identifier: identifier).firstMatch
    }

    private func item(_ kind: Kind, _ roomID: String) -> XCUIElement {
        let source = kind == .live ? "fixture.live" : "fixture.plugin"
        return app.cells["history.item.\(kind.rawValue).\(source).\(roomID)"]
    }

    private func delete(_ kind: Kind, _ roomID: String) {
        let record = item(kind, roomID)
        assertVisible(record)
        record.press(forDuration: 1)
        // UIKit's native context-menu action has a stable product label.
        let action = app.buttons["删除记录"]
        assertVisible(action)
        action.tap()
        XCTAssertTrue(record.waitForNonExistence(timeout: 5), "Deleted identity should leave the list")
    }

    private func clearCurrentType() {
        let clear = app.buttons["history.clear"]
        assertVisible(clear)
        clear.tap()
        let confirm = alertAction("history.clear.confirm")
        assertVisible(confirm)
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
    }

    private func assertEmpty(_ kind: Kind, file: StaticString = #filePath, line: UInt = #line) {
        assertVisible(app.otherElements["history.empty.\(kind.rawValue)"], file: file, line: line)
        XCTAssertFalse(app.buttons["history.clear"].exists, file: file, line: line)
        attachEvidence(named: "empty-\(kind.rawValue)")
    }

    private func assertVisible(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: 5)
        if !exists { attachEvidence(named: "missing-element") }
        XCTAssertTrue(exists, "Missing \(element)", file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        if result != .completed { attachEvidence(named: "element-not-hittable") }
        XCTAssertEqual(result, .completed, "Not visible: \(element)", file: file, line: line)
    }

    private func attachEvidence(named name: String) {
        // A launch failure has no app window; preserve the screen and explicit process state.
        let isRunning = app.state != .notRunning
        let screenshot = XCTAttachment(screenshot: isRunning ? app.screenshot() : XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: isRunning ? app.debugDescription : "Synthetic UI test application is not running; run ID: \(runID)")
        hierarchy.name = "\(name)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
