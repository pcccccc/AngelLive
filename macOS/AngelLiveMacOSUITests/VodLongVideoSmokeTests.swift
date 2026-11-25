import XCTest

@MainActor
final class VodLongVideoSmokeTests: XCTestCase {
    func testLongVideoDirectPlayerEpisodeRefreshAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AngelLiveVodDemo", "-AngelLiveVodDemoWork", "longVideo"]
        defer {
            if app.state != .notRunning { app.terminate() }
        }

        app.launch()
        app.activate()
        let window = app.windows.firstMatch
        if !window.waitForExistence(timeout: 2) {
            app.typeKey("n", modifierFlags: .command)
        }
        verify(window.waitForExistence(timeout: 5), "Expected the demo window", in: app)
        let closePlayer = window.buttons["关闭播放器"]
        let selectEpisodes = window.buttons["选集"]
        verify(text(containing: "海岬列车", in: window).waitForExistence(timeout: 15),
               "Expected to open the long video directly", in: app)
        verify(text(containing: "第 1 集", in: window).exists, "Expected the normalized first episode title", in: app)
        verify(!text(containing: "第01集", in: window).exists, "Expected duplicate episode number prefix to be stripped", in: app)
        verify(closePlayer.exists && selectEpisodes.exists, "Expected direct player controls", in: app)
        verify(app.windows.count == 1, "Expected exactly one demo window", in: app)
        let pause = window.buttons["暂停"]
        verify(pause.wait(for: \.isEnabled, toEqual: true, timeout: 5),
               "Expected the first episode to start playing", in: app)
        window.hover()
        settle(0.35)
        capture("D1-macOS-direct-player", in: app)

        if !selectEpisodes.isHittable { window.hover() }
        verify(selectEpisodes.wait(for: \.isHittable, toEqual: true, timeout: 5),
               "Expected the episode selector to be hittable", in: app)
        selectEpisodes.click()
        let firstEpisode = button(containing: "第 1 集", in: window)
        let secondEpisode = button(containing: "山间停靠", in: window)
        let thirdEpisode = button(containing: "海岬终点", in: window)
        verify(secondEpisode.waitForExistence(timeout: 5), "Expected the second episode in the drawer", in: app)
        verify(firstEpisode.exists && thirdEpisode.exists, "Expected all three episodes in the drawer", in: app)
        verify(!text(containing: "第01集", in: window).exists, "Expected drawer first episode title to be normalized", in: app)
        settle(0.45)
        capture("D2a-macOS-episode-drawer", in: app)

        verify(secondEpisode.wait(for: \.isHittable, toEqual: true, timeout: 5),
               "Expected the second episode to be hittable", in: app)
        secondEpisode.click()
        settle(1.0)
        window.hover()
        verify(text(containing: "山间停靠", in: window).waitForExistence(timeout: 5),
               "Expected the player to select the second episode", in: app)
        verify(pause.wait(for: \.isEnabled, toEqual: true, timeout: 5),
               "Expected the deferred second episode to start playing", in: app)
        verify(!window.buttons["重试"].exists && !app.alerts.firstMatch.exists,
               "Expected playback without an error prompt", in: app)
        settle(0.35)
        capture("D2b-macOS-episode2-playing", in: app)

        window.hover()
        verify(closePlayer.wait(for: \.isHittable, toEqual: true, timeout: 5),
               "Expected the close control to be hittable", in: app)
        closePlayer.click()
        verify(text(containing: "精选演示", in: window).waitForExistence(timeout: 5),
               "Expected to return directly to the demo showcase", in: app)
        verify(!closePlayer.exists && app.windows.count == 1, "Expected one demo window without player controls", in: app)
        settle(0.45)
        capture("D3-macOS-returned-showcase", in: app)
    }

    private func text(containing snippet: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", snippet, snippet))
            .firstMatch
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func button(containing title: String, in window: XCUIElement) -> XCUIElement {
        window.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func verify(_ condition: Bool, _ message: String, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        guard !condition else { return }
        // Preserve the failure before XCTest aborts the test.
        capture("Failure: \(message)", in: app)
        if app.state != .notRunning { app.terminate() }
        XCTFail(message, file: file, line: line)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let isRunning = app.state != .notRunning
        let window = app.windows.firstMatch
        if isRunning, window.exists {
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let hierarchy = XCTAttachment(string: isRunning ? app.debugDescription : "Application state: notRunning")
        hierarchy.name = "\(name) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
