import XCTest

/// Each test owns a fresh synthetic namespace; relaunches deliberately reuse that namespace.
@MainActor
final class HistorySmokeTests: XCTestCase {
    private let liveA = "history.live.fixture.live.live-a"
    private let liveB = "history.live.fixture.live.live-b"
    private let dramaA = "history.drama.fixture.plugin.drama-a"
    private let dramaB = "history.drama.fixture.plugin.drama-b"

    func testSwitchBetweenLiveAndDramaHistory() {
        let app = launch()
        defer { finish(app) }
        assertVisible(liveA, in: app)
        assertVisible(liveB, in: app)
        selectDrama(in: app)
        assertVisible(dramaA, in: app)
        assertVisible(dramaB, in: app)
        assertAbsent(liveA, in: app)
        capture("Synthetic drama history", in: app)
        selectLive(in: app)
        assertVisible(liveA, in: app)
        assertAbsent(dramaA, in: app)
    }

    func testLiveContextMenuCancelAndDelete() {
        let app = launch()
        defer { finish(app) }
        cancelContextMenu(for: liveA, in: app)
        assertVisible(liveA, in: app)
        remove(liveA, in: app)
        assertVisible(liveB, in: app)
        selectDrama(in: app)
        assertVisible(dramaA, in: app)
        assertVisible(dramaB, in: app)
    }

    func testDramaContextMenuCancelAndDeleteLastItem() {
        let app = launch()
        defer { finish(app) }
        selectDrama(in: app)
        cancelContextMenu(for: dramaA, in: app)
        assertVisible(dramaA, in: app)
        remove(dramaA, in: app)
        assertVisible(dramaB, in: app)
        remove(dramaB, in: app)
        assertVisible("history.empty.drama", in: app)
        assertAbsent("history.clear", in: app)
        capture("Synthetic drama empty state", in: app)
        selectLive(in: app)
        assertVisible(liveA, in: app)
        assertVisible(liveB, in: app)
    }

    func testDeletingLastLiveItemPreservesDrama() {
        let app = launch()
        defer { finish(app) }
        remove(liveA, in: app)
        remove(liveB, in: app)
        assertVisible("history.empty.live", in: app)
        assertAbsent("history.clear", in: app)
        capture("Synthetic live empty state", in: app)
        selectDrama(in: app)
        assertVisible(dramaA, in: app)
        assertVisible(dramaB, in: app)
    }

    func testClearConfirmationAndCategoryScope() {
        let app = launch()
        defer { finish(app) }
        click("history.clear", in: app)
        click("history.clear.cancel", in: app)
        assertVisible(liveA, in: app)
        clearCurrentType(in: app)
        assertVisible("history.empty.live", in: app)
        selectDrama(in: app)
        assertVisible(dramaA, in: app)
        assertVisible(dramaB, in: app)
        clearCurrentType(in: app)
        assertVisible("history.empty.drama", in: app)
        selectLive(in: app)
        assertVisible("history.empty.live", in: app)
        capture("Both history categories cleared", in: app)
    }

    func testDeletionAndClearPersistAcrossRelaunch() {
        // Three real launches plus deletion/clear assertions take longer than
        // the plan's one-minute default on the desktop UI automation runner.
        executionTimeAllowance = 120
        let runID = UUID()
        let app = launch(runID: runID)
        defer { finish(app) }
        remove(liveA, in: app)
        selectDrama(in: app)
        remove(dramaA, in: app)
        app.terminate()
        configure(app, runID: runID, reset: false)
        launchAndWait(app)
        assertVisible(liveB, in: app)
        assertAbsent(liveA, in: app)
        selectDrama(in: app)
        assertVisible(dramaB, in: app)
        assertAbsent(dramaA, in: app)
        clearCurrentType(in: app)
        assertVisible("history.empty.drama", in: app)
        app.terminate()
        launchAndWait(app)
        assertVisible(liveB, in: app)
        selectDrama(in: app)
        assertVisible("history.empty.drama", in: app)
        capture("Persisted drama clear after relaunch", in: app)
    }

    private func finish(_ app: XCUIApplication) {
        if let run = testRun, run.totalFailureCount > 0, app.state != .notRunning {
            capture("Failure before termination", in: app)
        }
        app.terminate()
    }

    private func launch(runID: UUID = UUID()) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        configure(app, runID: runID, reset: true)
        launchAndWait(app)
        return app
    }

    private func launchAndWait(_ app: XCUIApplication) {
        app.launch()
        // Test launches suppress automatic scene presentation. Open the real
        // main WindowGroup through its native File > New Window command.
        app.activate()
        app.typeKey("n", modifierFlags: .command)
        verify(app.windows.firstMatch.waitForExistence(timeout: 5),
               "Expected the history window after launch", in: app)
        verify(app.windows.count == 1, "Expected exactly one history window after launch", in: app)
        assertVisible("history.type.live", in: app)
    }

    private func configure(_ app: XCUIApplication, runID: UUID, reset: Bool) {
        app.launchArguments = ["--ui-testing", "--ui-test-run-id", runID.uuidString]
        if reset { app.launchArguments.append("--ui-test-reset") }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertVisible(_ identifier: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        verify(element(identifier, in: app).waitForExistence(timeout: 5),
               "Expected \(identifier)", in: app, file: file, line: line)
    }

    private func assertAbsent(_ identifier: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                               object: element(identifier, in: app))
        verify(XCTWaiter.wait(for: [absent], timeout: 5) == .completed,
               "Unexpected \(identifier)", in: app, file: file, line: line)
    }

    private func click(_ identifier: String, in app: XCUIApplication) {
        app.activate()
        verify(app.wait(for: .runningForeground, timeout: 5),
               "Expected the history app in the foreground before clicking \(identifier)", in: app)
        let target = element(identifier, in: app)
        verify(target.waitForExistence(timeout: 5), "Expected \(identifier) before click", in: app)
        verify(target.wait(for: \.isHittable, toEqual: true, timeout: 5),
               "Expected \(identifier) to be hittable", in: app)
        target.click()
    }

    private func selectLive(in app: XCUIApplication) {
        click("history.type.live", in: app)
        assertSelectedType("history.type.live", other: "history.type.drama", in: app)
    }

    private func selectDrama(in app: XCUIApplication) {
        click("history.type.drama", in: app)
        assertSelectedType("history.type.drama", other: "history.type.live", in: app)
    }

    private func assertSelectedType(_ selected: String, other: String, in app: XCUIApplication) {
        verify(element(selected, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5),
               "Expected \(selected) to be selected", in: app)
        verify(element(other, in: app).wait(for: \.isSelected, toEqual: false, timeout: 5),
               "Expected \(other) not to be selected", in: app)
    }

    private func openContextMenu(for identifier: String, in app: XCUIApplication) {
        app.activate()
        assertVisible(identifier, in: app)
        element(identifier, in: app).rightClick()
        assertVisible("history.remove", in: app)
    }

    private func cancelContextMenu(for identifier: String, in app: XCUIApplication) {
        openContextMenu(for: identifier, in: app)
        app.typeKey(.escape, modifierFlags: [])
        assertAbsent("history.remove", in: app)
    }

    private func remove(_ identifier: String, in app: XCUIApplication) {
        openContextMenu(for: identifier, in: app)
        click("history.remove", in: app)
        assertAbsent(identifier, in: app)
    }

    private func clearCurrentType(in app: XCUIApplication) {
        click("history.clear", in: app)
        click("history.clear.confirm", in: app)
        assertAbsent("history.clear.confirm", in: app)
    }

    private func verify(_ condition: Bool, _ message: String, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        guard !condition else { return }
        // XCTest's stop-on-failure exception can bypass Swift defer. Preserve
        // the actual failure state and terminate before recording the assertion.
        capture("Failure: \(message)", in: app)
        app.terminate()
        XCTFail(message, file: file, line: line)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let isRunning = app.state != .notRunning
        let screenshot = XCTAttachment(screenshot: isRunning ? app.screenshot() : XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: isRunning
            ? app.debugDescription
            : "Application state: notRunning. Application hierarchy is unavailable because the app did not launch or exited.")
        hierarchy.name = "\(name) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
