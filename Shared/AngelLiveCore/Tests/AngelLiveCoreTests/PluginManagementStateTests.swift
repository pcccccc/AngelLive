import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
private final class ControlledSleep {
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var returned: CheckedContinuation<Void, Never>?
    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { continuation in
            sleepers.append(continuation)
            entered?.resume()
            entered = nil
        }
        returned?.resume()
        returned = nil
    }

    func waitForCount(_ count: Int) async {
        while durations.count < count {
            await withCheckedContinuation { entered = $0 }
        }
    }

    func releaseFirst() async {
        await withCheckedContinuation { continuation in
            returned = continuation
            sleepers.removeFirst().resume()
        }
    }
}

@MainActor
@Suite("Deferred plugin uninstall")
struct PluginDeferredUninstallTests {
    @Test("commits only when the delay completes")
    func delayedCommit() async {
        let clock = ControlledSleep()
        var removed: [String] = []
        let state = PluginDeferredUninstall(canUninstall: { _ in true }, uninstall: { removed.append($0); return true }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        #expect(clock.durations == [.seconds(5)])
        #expect(removed.isEmpty)
        #expect(state.pendingUninstallPluginId == "source-a")
        #expect(state.pendingUninstallDeadline != nil)
        await clock.releaseFirst()
        #expect(removed == ["source-a"])
        #expect(state.pendingUninstallPluginId == nil)
        #expect(state.pendingUninstallDeadline == nil)
    }

    @Test("undo cancels without removing")
    func undo() async {
        let clock = ControlledSleep()
        var removed: [String] = []
        let state = PluginDeferredUninstall(canUninstall: { _ in true }, uninstall: { removed.append($0); return true }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        state.undoPendingUninstall()
        await clock.releaseFirst()
        #expect(removed.isEmpty)
        #expect(state.pendingUninstallPluginId == nil)
        #expect(state.pendingUninstallDeadline == nil)
    }

    @Test("a new intent commits the old one and ignores its resumed timer")
    func replacePending() async {
        let clock = ControlledSleep()
        var removed: [String] = []
        let state = PluginDeferredUninstall(canUninstall: { _ in true }, uninstall: { removed.append($0); return true }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        let deadline = state.pendingUninstallDeadline
        #expect(state.stageUninstall(pluginId: "source-a"))
        #expect(state.pendingUninstallDeadline == deadline)
        #expect(clock.durations.count == 1)
        #expect(state.stageUninstall(pluginId: "source-b"))
        #expect(removed == ["source-a"])
        await clock.waitForCount(2)
        await clock.releaseFirst()
        #expect(removed == ["source-a"])
        #expect(state.pendingUninstallPluginId == "source-b")
        await clock.releaseFirst()
        #expect(removed == ["source-a", "source-b"])
    }

    @Test("busy plugins are rejected without disturbing a pending intent")
    func busyRejected() async {
        let clock = ControlledSleep()
        var removed: [String] = []
        let state = PluginDeferredUninstall(canUninstall: { $0 != "source-b" }, uninstall: { removed.append($0); return true }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        #expect(!state.stageUninstall(pluginId: "source-b"))
        #expect(state.pendingUninstallPluginId == "source-a")
        #expect(removed.isEmpty)
        state.undoPendingUninstall()
        await clock.releaseFirst()
    }

    @Test("uninstalled plugins are rejected")
    func missingRejected() {
        var removed: [String] = []
        let installed: Set<String> = ["source-a"]
        let state = PluginDeferredUninstall(canUninstall: { installed.contains($0) }, uninstall: { removed.append($0); return true })
        #expect(!state.stageUninstall(pluginId: "source-b"))
        #expect(state.pendingUninstallPluginId == nil)
        #expect(state.pendingUninstallDeadline == nil)
        #expect(removed.isEmpty)
    }

    @Test("failed removal clears intent and permits another attempt")
    func failedRemoval() async {
        let clock = ControlledSleep()
        var attempts = 0
        let state = PluginDeferredUninstall(canUninstall: { _ in true }, uninstall: { _ in attempts += 1; return false }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        #expect(!state.commitPendingUninstall())
        #expect(state.pendingUninstallPluginId == nil)
        #expect(state.pendingUninstallDeadline == nil)
        #expect(state.commitPendingUninstall())
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(2)
        await clock.releaseFirst()
        #expect(attempts == 1)
        #expect(state.pendingUninstallPluginId == "source-a")
        state.undoPendingUninstall()
        await clock.releaseFirst()
    }

    @Test("manual commit cancels the timer without a duplicate removal")
    func manualCommit() async {
        let clock = ControlledSleep()
        var removed: [String] = []
        let state = PluginDeferredUninstall(canUninstall: { _ in true }, uninstall: { removed.append($0); return true }, sleep: { await clock.sleep($0) })
        #expect(state.stageUninstall(pluginId: "source-a"))
        await clock.waitForCount(1)
        #expect(state.commitPendingUninstall())
        await clock.releaseFirst()
        #expect(removed == ["source-a"])
        #expect(state.pendingUninstallPluginId == nil)
    }
}

@Suite("Plugin management presentation precedence")
struct PluginManagementPresentationStateTests {
    @Test("manifest capabilities distinguish supported, unavailable and unknown entries")
    func manifestCapabilities() {
        let manifest = Data(#"""
        {"capabilities":{
          "categories":"available",
          "rooms":{"status":"partial","reason":"limited"},
          "playback":"unavailable",
          "search":"unknown",
          "unknownFeature":"available"
        }}
        """#.utf8)
        #expect(PlatformCapability.declaredFeatures(from: manifest) == [.categories, .rooms])
        #expect(PlatformCapability.declaredFeatures(from: Data(#"{"capabilities":{"rooms":"unavailable"}}"#.utf8)) == [])
        #expect(PlatformCapability.declaredFeatures(from: Data(#"{"capabilities":{"rooms":"unknown"}}"#.utf8)) == nil)
        #expect(PlatformCapability.declaredFeatures(from: Data(#"{"capabilities":{}}"#.utf8)) == nil)
        #expect(PlatformCapability.declaredFeatures(from: Data(#"{"apiVersion":1}"#.utf8)) == nil)
    }

    @Test("summary prioritizes running, failure, updates, checking and verification")
    func summary() {
        func resolve(_ running: Bool, _ failed: Bool, _ count: Int, _ checking: Bool, _ current: Bool) -> PluginManagementSummaryState {
            .resolve(isRunning: running, hasFailures: failed, updateCount: count, isChecking: checking, isVerifiedCurrent: current)
        }
        #expect(resolve(true, true, 2, true, true) == .running)
        #expect(resolve(false, true, 2, true, true) == .failed)
        #expect(resolve(false, false, 2, true, true) == .updates(2))
        #expect(resolve(false, false, 0, true, true) == .checking)
        #expect(resolve(false, false, 0, false, true) == .current)
        #expect(resolve(false, false, 0, false, false) == .unchecked)
    }

    @Test("row prioritizes waiting, progress, failure, success and catalog action")
    func row() {
        func resolve(_ action: RemotePluginCatalogActionState, _ waiting: Bool = false, _ success: Bool = false) -> PluginManagementRowPhase {
            .resolve(actionState: action, isWaiting: waiting, isSuccessful: success)
        }
        #expect(resolve(.installing, true, true) == .queued)
        #expect(resolve(.updating, false, true) == .progress)
        #expect(resolve(.failed("error"), false, true) == .failed("error"))
        #expect(resolve(.update, false, true) == .success)
        #expect(resolve(.install) == .install)
        #expect(resolve(.update) == .update)
        #expect(resolve(.installed) == .idle)
    }
}
