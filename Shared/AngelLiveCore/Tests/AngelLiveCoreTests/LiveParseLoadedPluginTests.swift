import Foundation
import Dispatch
import Testing

@testable import AngelLiveCore

@Suite("Loaded plugin initialization")
struct LiveParseLoadedPluginTests {
    @Test("concurrent loads evaluate each script once")
    func concurrentLoadsEvaluateEachScriptOnce() async throws {
        let fixture = try LoadedPluginFixture(preloadScript: """
            const fixturePreloadDeclaration = 1;
            globalThis.fixturePreloadCount = (globalThis.fixturePreloadCount || 0) + 1;
            console.log("fixture.load-gate");
            """)
        defer { fixture.remove() }
        let starts = AsyncStream<Void>.makeStream()
        var startIterator = starts.stream.makeAsyncIterator()

        let loads = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        try await fixture.plugin.loadReportingStart(to: starts.continuation)
                    }
                }
                try await group.waitForAll()
            }
        }
        for _ in 0..<20 { await startIterator.next() }
        await fixture.waitUntilLoadIsGated()
        fixture.releaseLoadGate()

        try await loads.value

        let counts = try await fixture.loadCounts()
        #expect(counts == [1, 1])
    }

    @Test("loads after initialization are no-ops")
    func laterLoadsAreNoOps() async throws {
        let fixture = try LoadedPluginFixture()
        defer { fixture.remove() }

        try await fixture.plugin.load()
        try await fixture.plugin.load()

        let counts = try await fixture.loadCounts()
        #expect(counts == [1, 1])
    }

    @Test("failed initialization can be retried")
    func failedInitializationCanRetry() async throws {
        let fixture = try LoadedPluginFixture(createPreload: false)
        defer { fixture.remove() }

        await #expect(throws: LiveParsePluginError.self) {
            try await fixture.plugin.load()
        }
        try fixture.writePreload("globalThis.fixturePreloadCount = 1;")

        try await fixture.plugin.load()
        let counts = try await fixture.loadCounts()
        #expect(counts == [1, 1])
    }

    @Test("cancelling one waiter does not cancel shared initialization")
    func cancelledWaiterDoesNotCancelSharedInitialization() async throws {
        let fixture = try LoadedPluginFixture(preloadScript: """
            globalThis.fixturePreloadCount = (globalThis.fixturePreloadCount || 0) + 1;
            console.log("fixture.load-gate");
            """)
        defer { fixture.remove() }
        let starts = AsyncStream<Void>.makeStream()
        var startIterator = starts.stream.makeAsyncIterator()

        let cancelledWaiter = Task {
            try await fixture.plugin.loadReportingStart(to: starts.continuation)
        }
        await startIterator.next()
        await fixture.waitUntilLoadIsGated()
        let survivingWaiter = Task {
            try await fixture.plugin.loadReportingStart(to: starts.continuation)
        }
        await startIterator.next()
        cancelledWaiter.cancel()
        fixture.releaseLoadGate()

        try await survivingWaiter.value
        _ = try? await cancelledWaiter.value
        let counts = try await fixture.loadCounts()
        #expect(counts == [1, 1])
    }
}

private extension LiveParseLoadedPlugin {
    func loadReportingStart(to starts: AsyncStream<Void>.Continuation) async throws {
        // Yield while isolated to the loader, then enter load without leaving
        // this actor. The test can hold script evaluation until all calls enter.
        starts.yield(())
        try await load()
    }
}

private final class ScriptLoadGate: Sendable {
    // Only the runtime's GCD queue blocks; the async test waits via a continuation.
    // Both synchronization objects are immutable, thread-safe references.
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func handleLog(_ message: String) {
        guard message == "fixture.load-gate" else { return }
        entered.signal()
        release.wait()
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.entered.wait()
                continuation.resume()
            }
        }
    }

    func open() {
        release.signal()
    }
}

private struct LoadedPluginFixture {
    let root: URL
    let plugin: LiveParseLoadedPlugin
    private let preloadURL: URL
    private let scriptGate: ScriptLoadGate

    init(
        preloadScript: String = "globalThis.fixturePreloadCount = (globalThis.fixturePreloadCount || 0) + 1;",
        createPreload: Bool = true
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scriptGate = ScriptLoadGate()
        self.root = root
        self.scriptGate = scriptGate
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        preloadURL = root.appendingPathComponent("preload.js")
        if createPreload {
            try Data(preloadScript.utf8).write(to: preloadURL)
        }
        try Data("""
            globalThis.fixtureEntryCount = (globalThis.fixtureEntryCount || 0) + 1;
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              loadCounts() {
                return [globalThis.fixturePreloadCount || 0, globalThis.fixtureEntryCount || 0];
              }
            };
            """.utf8).write(to: root.appendingPathComponent("index.js"))

        let manifest = LiveParsePluginManifest(
            pluginId: "fixture.plugin",
            version: "1.0.0",
            apiVersion: 1,
            displayName: "Fixture",
            liveTypes: ["fixture.plugin"],
            entry: "index.js",
            preloadScripts: ["preload.js"]
        )
        plugin = LiveParseLoadedPlugin(
            manifest: manifest,
            rootDirectory: root,
            location: .sandbox,
            runtime: JSRuntime(pluginId: manifest.pluginId) { message in
                scriptGate.handleLog(message)
            }
        )
    }

    func writePreload(_ script: String) throws {
        try Data(script.utf8).write(to: preloadURL)
    }

    func waitUntilLoadIsGated() async {
        await scriptGate.waitUntilEntered()
    }

    func releaseLoadGate() {
        scriptGate.open()
    }

    func loadCounts() async throws -> [Int] {
        let value = try await plugin.runtime.callPluginFunction(name: "loadCounts")
        return (value as? [NSNumber])?.map(\.intValue) ?? []
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
