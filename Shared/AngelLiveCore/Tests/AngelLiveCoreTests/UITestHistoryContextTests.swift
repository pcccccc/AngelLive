#if DEBUG
import Foundation
import Testing
@testable import AngelLiveCore

@Suite("UI test history storage", .timeLimit(.minutes(1)))
@MainActor
struct UITestHistoryContextTests {
    @Test("test launch requires one valid explicit run identifier")
    func argumentsFailClosed() throws {
        #expect(try UITestLaunchConfiguration.current(arguments: ["App"]) == nil)
        #expect(try UITestLaunchConfiguration.current(arguments: ["App", "-AppleLanguages", "(zh-Hans)"]) == nil)
        for arguments in [
            ["--ui-testing"],
            ["--ui-test-typo"],
            ["--ui-testing", "--ui-test-run-id", UUID().uuidString, "--ui-test-typo"],
            ["--ui-testing", "--ui-test-run-id", "../real-data"],
            ["--ui-testing", "--ui-test-run-id", UUID().uuidString, "--ui-test-run-id", UUID().uuidString],
            ["--ui-test-reset"]
        ] {
            #expect(throws: UITestLaunchConfiguration.ConfigurationError.self) {
                try UITestLaunchConfiguration.current(arguments: arguments)
            }
        }
    }

    @Test("relaunch preserves deletions and hidden drama playback progress")
    func restartPreservesMutations() throws {
        let configuration = UITestLaunchConfiguration(runID: UUID(), resetsState: true)
        defer { clean(configuration) }
        let first = try UITestHistoryContext.prepare(configuration: configuration)
        #expect(first.history.watchList.map(\.roomId) == ["live-a", "live-b"])
        #expect(first.progress.historyEntries.map(\.title) == ["测试短剧 A", "测试短剧 B"])
        #expect(!first.favorite.favoriteICloudSyncEnabled)
        first.history.removeHistories(ids: [try #require(first.history.watchList.first).id])
        let removed = try #require(first.progress.historyEntries.first)
        try first.progress.removeHistory(for: removed.key)

        let relaunched = try UITestHistoryContext.prepare(configuration:
            .init(runID: configuration.runID, resetsState: false))
        #expect(relaunched.history.watchList.map(\.roomId) == ["live-b"])
        #expect(relaunched.progress.historyEntries.map(\.key.roomID) == ["drama-b"])
        #expect(try relaunched.progress.load(for: removed.key).episodes["episode-1"]?.position == 30)
    }

    @Test("reset only removes its own run state and restores its fixtures")
    func resetIsScoped() throws {
        let firstConfiguration = UITestLaunchConfiguration(runID: UUID(), resetsState: true)
        let secondConfiguration = UITestLaunchConfiguration(runID: UUID(), resetsState: true)
        defer { clean(firstConfiguration); clean(secondConfiguration) }
        let first = try UITestHistoryContext.prepare(configuration: firstConfiguration)
        let second = try UITestHistoryContext.prepare(configuration: secondConfiguration)
        first.history.clearAll()
        try first.progress.clearHistory()
        second.history.clearAll()
        let sentinel = second.directory.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: sentinel)

        let reset = try UITestHistoryContext.prepare(configuration: firstConfiguration)
        #expect(reset.history.watchList.count == 2)
        #expect(reset.progress.historyEntries.count == 2)
        let secondAgain = try UITestHistoryContext.prepare(configuration:
            .init(runID: secondConfiguration.runID, resetsState: false))
        #expect(secondAgain.history.watchList.isEmpty)
        #expect(secondAgain.progress.historyEntries.count == 2)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(firstConfiguration.defaultsSuiteName != secondConfiguration.defaultsSuiteName)
    }

    @Test("relaunch without seeded state cannot fall back or silently reseed")
    func missingStateFails() {
        let configuration = UITestLaunchConfiguration(runID: UUID(), resetsState: false)
        defer { clean(configuration) }
        #expect(throws: UITestLaunchConfiguration.ConfigurationError.missingState) {
            try UITestHistoryContext.prepare(configuration: configuration)
        }
        #expect(!FileManager.default.fileExists(atPath: configuration.directory.path))
    }

    @Test("reset refuses a symlink instead of deleting its destination")
    func symlinkFailsClosed() throws {
        let configuration = UITestLaunchConfiguration(runID: UUID(), resetsState: true)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(configuration); try? FileManager.default.removeItem(at: target) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let sentinel = target.appendingPathComponent("keep")
        try Data("safe".utf8).write(to: sentinel)
        try FileManager.default.createDirectory(at: configuration.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: configuration.directory, withDestinationURL: target)
        #expect(throws: UITestLaunchConfiguration.ConfigurationError.unsafeDirectory) {
            try UITestHistoryContext.prepare(configuration: configuration)
        }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "safe")
    }

    private func clean(_ configuration: UITestLaunchConfiguration) {
        configuration.defaults.removePersistentDomain(forName: configuration.defaultsSuiteName)
        try? FileManager.default.removeItem(at: configuration.directory)
    }
}
#endif
