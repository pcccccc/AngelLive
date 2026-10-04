import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Effective plugin login registry", .serialized)
struct PlatformLoginRegistryTests {
    @Test("registry follows pinned effective version and never infers QR support")
    func pinnedVersionControlsLoginMetadata() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "registry-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(pluginId: pluginId, version: "1.0.0", supportsQRCode: false)
        try fixture.install(pluginId: pluginId, version: "2.0.0", supportsQRCode: true)
        try fixture.storage.saveState(.init(plugins: [
            pluginId: .init(pinnedVersion: "1.0.0")
        ]))

        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        let registry = PlatformLoginRegistry(pluginManager: manager)
        let pinned = try #require(await registry.entry(pluginId: pluginId))
        #expect(pinned.version == "1.0.0")
        #expect(pinned.loginChallenge == nil)

        try manager.unpin(pluginId: pluginId)
        let latest = try #require(await registry.entry(pluginId: pluginId))
        #expect(latest.version == "2.0.0")
        #expect(latest.loginChallenge?.isSupportedByCurrentHost == true)
    }

    @Test("disabled effective plugins are omitted from login registry")
    func disabledPluginIsOmitted() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "disabled-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(pluginId: pluginId, version: "1.0.0", supportsQRCode: true)
        try fixture.storage.saveState(.init(plugins: [
            pluginId: .init(enabled: false)
        ]))

        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        let registry = PlatformLoginRegistry(pluginManager: manager)
        #expect(await registry.entry(pluginId: pluginId) == nil)
    }

    @Test("trusted plugin ids resolve in request order without a default")
    func trustedPluginIDsResolveInOrder() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let first = "first-\(UUID().uuidString.lowercased()).plugin"
        let second = "second-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(pluginId: first, version: "1.0.0", supportsQRCode: true)
        try fixture.install(pluginId: second, version: "1.0.0", supportsQRCode: true)
        let registry = PlatformLoginRegistry(
            pluginManager: LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        )

        let entries = await registry.entries(
            pluginIDs: [second, "fixture.unknown", first, second],
            for: .iOS
        )
        #expect(entries.map(\.pluginId) == [second, first])
        let empty = await registry.entries(pluginIDs: [], for: .iOS)
        #expect(empty.isEmpty)
    }

    @Test("concurrent first resolve shares one runtime lease")
    func concurrentResolveSharesRuntime() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "concurrent-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(pluginId: pluginId, version: "1.0.0", supportsQRCode: true)
        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)

        let runtimes = try await withThrowingTaskGroup(of: JSRuntime.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try manager.resolve(pluginId: pluginId).runtime
                }
            }
            var values: [JSRuntime] = []
            for try await runtime in group { values.append(runtime) }
            return values
        }

        #expect(Set(runtimes.map(ObjectIdentifier.init)).count == 1)
    }

    @Test("credential payload stays host-managed while the current plugin can read its Cookie header")
    func credentialPayloadStaysHostManagedWithScopedCookieGetter() async throws {
        struct Status: Decodable { let state: String }

        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "credential-boundary-\(UUID().uuidString.lowercased()).plugin"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: pluginId)
        defer { LiveParsePlatformSessionVault.restore(platformId: pluginId, session: vaultSnapshot) }
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: true,
            script: """
            globalThis.receivedCredentialMutator = false;
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              setCredential(input) {
                globalThis.receivedCredentialMutator = !!input;
                return { ok: true };
              },
              validateCredential(input) {
                var cookieHeader = Host.session.getCookieHeader("\(pluginId)");
                var receivedCookie = !!(input && input.credential && input.credential.cookie);
                return {
                  state: input.credentialAvailable === true && !receivedCookie && cookieHeader.length > 0
                    ? "valid"
                    : "invalid"
                };
              },
              probe() { return { mutatorRan: globalThis.receivedCredentialMutator }; }
            };
            """
        )
        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        let secret = "session=must-remain-native"

        let receipt = try await manager.call(
            pluginId: pluginId,
            function: "setCredential",
            payload: ["credential": ["cookie": secret]]
        )
        #expect((receipt as? [String: Any])?["managedByHost"] as? Bool == true)
        #expect(LiveParsePlatformSessionVault.session(for: pluginId)?.cookie == secret)

        let status: Status = try await manager.callDecodableUsingIsolatedCredential(
            pluginId: pluginId,
            function: "validateCredential",
            payload: ["credentialAvailable": true],
            cookie: secret,
            uid: nil
        )
        #expect(status.state == "valid")

        let probe = try await manager.call(pluginId: pluginId, function: "probe")
        #expect((probe as? [String: Any])?["mutatorRan"] as? Bool == false)
    }

    @Test("runtime lease keeps an active login challenge on one plugin version")
    func runtimeLeaseSurvivesPluginSelectionChange() async throws {
        struct Probe: Decodable { let version: String; let count: Int? }

        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "lease-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: true,
            script: "globalThis.leaseCount = 0; globalThis.LiveParsePlugin = { apiVersion: 1, probe() { globalThis.leaseCount += 1; return { version: '1.0.0', count: globalThis.leaseCount }; } };"
        )
        try fixture.install(
            pluginId: pluginId,
            version: "2.0.0",
            supportsQRCode: true,
            script: "globalThis.LiveParsePlugin = { apiVersion: 1, probe() { return { version: '2.0.0' }; } };"
        )
        try fixture.storage.saveState(.init(plugins: [
            pluginId: .init(pinnedVersion: "1.0.0")
        ]))
        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        let lease = try manager.runtimeLease(pluginId: pluginId)
        #expect(LiveParsePluginVersionLeaseRegistry.protectedVersions(pluginId: pluginId).contains("1.0.0"))

        try manager.unpin(pluginId: pluginId)
        let leased: Probe = try await manager.callDecodable(
            using: lease,
            function: "probe",
            payload: [:],
            sensitive: true
        )
        let leasedAgain: Probe = try await manager.callDecodable(
            using: lease,
            function: "probe",
            payload: [:],
            sensitive: true
        )
        let current: Probe = try await manager.callDecodable(
            pluginId: pluginId,
            function: "probe"
        )

        #expect(lease.version == "1.0.0")
        #expect(leased.version == "1.0.0")
        #expect(leased.count == 1)
        #expect(leasedAgain.count == 2)
        #expect(current.version == "2.0.0")
    }

    @Test("reload cancels a pending ordinary call from the retired runtime", .timeLimit(.minutes(1)))
    func reloadRejectsLateOrdinaryResult() async throws {
        struct Receipt: Decodable, Sendable {}
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "late-runtime-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: false,
            script: "globalThis.LiveParsePlugin = { apiVersion: 1, probe() { return new Promise(function () {}); } };"
        )
        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        let runtime = try manager.resolve(pluginId: pluginId).runtime
        let call = Task<Void, Error> {
            let _: Receipt = try await manager.callDecodable(pluginId: pluginId, function: "probe")
        }
        while await runtime.pendingPromiseCallCountForTesting() == 0 { await Task.yield() }

        try manager.reload()

        await #expect(throws: CancellationError.self) { try await call.value }
    }

    @Test("selection changes for one plugin do not cancel another plugin", .timeLimit(.minutes(1)))
    func perPluginRuntimeGate() async throws {
        struct ProbeResponse: Decodable, Sendable { let ok: Bool }
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginA = "scope-a-\(UUID().uuidString.lowercased()).plugin"
        let pluginB = "scope-b-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(pluginId: pluginA, version: "1.0.0", supportsQRCode: false)
        try fixture.install(
            pluginId: pluginB,
            version: "1.0.0",
            supportsQRCode: false,
            script: """
            globalThis.releaseProbe = null;
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              probe() { return new Promise(function(resolve) { globalThis.releaseProbe = resolve; }); }
            };
            """
        )
        let manager = LiveParsePluginManager(storage: fixture.storage, bundle: .main)
        _ = try manager.resolve(pluginId: pluginA)
        let runtimeB = try manager.resolve(pluginId: pluginB).runtime
        let call = Task<Bool, Error> {
            let value: ProbeResponse = try await manager.callDecodable(pluginId: pluginB, function: "probe")
            return value.ok
        }
        while await runtimeB.pendingPromiseCallCountForTesting() == 0 { await Task.yield() }

        try manager.setLastGoodVersion(pluginId: pluginA, version: "1.0.0")
        try manager.pin(pluginId: pluginA, version: "1.0.0")
        try manager.unpin(pluginId: pluginA)
        try await runtimeB.evaluate(script: "globalThis.releaseProbe({ ok: true });")
        #expect(try await call.value)
    }

    @Test("concurrent plugin loads evaluate the entry script once")
    func concurrentLoadIsSingleFlight() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "load-flight-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: false,
            script: "globalThis.entryLoads = (globalThis.entryLoads || 0) + 1; globalThis.LiveParsePlugin = { apiVersion: 1, probe() { return { count: globalThis.entryLoads }; } };"
        )
        let plugin = try LiveParsePluginManager(storage: fixture.storage, bundle: .main).resolve(pluginId: pluginId)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 { group.addTask { try await plugin.load() } }
            try await group.waitForAll()
        }

        let result = try #require(try await plugin.runtime.callPluginFunction(name: "probe") as? [String: Any])
        #expect(result["count"] as? Int == 1)
    }

    @Test("a failed plugin load can be retried")
    func failedLoadCanRetry() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "load-retry-\(UUID().uuidString.lowercased()).plugin"
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: false,
            script: "globalThis.LiveParsePlugin = { apiVersion: 99 };"
        )
        let plugin = try LiveParsePluginManager(storage: fixture.storage, bundle: .main).resolve(pluginId: pluginId)
        await #expect(throws: LiveParsePluginError.self) { try await plugin.load() }

        let entryFileURL = await plugin.entryFileURL
        try Data("globalThis.LiveParsePlugin = { apiVersion: 1, probe() { return { ok: true }; } };".utf8)
            .write(to: entryFileURL, options: .atomic)
        try await plugin.load()
        let result = try #require(try await plugin.runtime.callPluginFunction(name: "probe") as? [String: Any])
        #expect(result["ok"] as? Bool == true)
    }

    @Test(
        "cancelled sensitive Promise permanently mutes and evicts its abandoned runtime",
        .timeLimit(.minutes(1))
    )
    func cancelledSensitiveCallTaintsRuntime() async throws {
        let fixture = try PluginResolutionFixture()
        defer { fixture.remove() }
        let pluginId = "tainted-\(UUID().uuidString.lowercased()).plugin"
        let secret = "late-secret-\(UUID().uuidString)"
        try fixture.install(
            pluginId: pluginId,
            version: "1.0.0",
            supportsQRCode: true,
            script: """
            globalThis.releaseAbandonedCall = null;
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              never(input) {
                return new Promise(function (resolve) {
                  globalThis.releaseAbandonedCall = function () {
                    console.log("late:" + input.secret);
                    resolve({ ok: true });
                  };
                });
              }
            };
            """
        )
        let messages = LockedStringList()
        let manager = LiveParsePluginManager(
            storage: fixture.storage,
            bundle: .main,
            logHandler: { messages.append($0) }
        )
        let abandonedRuntime = try manager.resolve(pluginId: pluginId).runtime
        let call = Task<Void, Error> {
            _ = try await manager.call(
                pluginId: pluginId,
                function: "never",
                payload: ["secret": secret],
                sensitive: true
            )
        }
        await abandonedRuntime.waitForPendingPromiseCallForTesting()
        #expect(await abandonedRuntime.pendingPromiseCallCountForTesting() == 1)

        call.cancel()
        guard case .failure(let error) = await call.result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error is CancellationError)
        let replacementRuntime = try manager.resolve(pluginId: pluginId).runtime
        #expect(replacementRuntime !== abandonedRuntime)

        await #expect(throws: CancellationError.self) {
            try await abandonedRuntime.evaluate(script: "globalThis.releaseAbandonedCall();")
        }
        await Task.yield()
        #expect(!messages.values.contains { $0.contains(secret) })
    }

}

private struct PluginResolutionFixture {
    let root: URL
    let storage: LiveParsePluginStorage

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AngelLiveRegistryTests-\(UUID().uuidString)", isDirectory: true)
        storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
    }

    func install(
        pluginId: String,
        version: String,
        supportsQRCode: Bool,
        script: String = "globalThis.LiveParsePlugin = { apiVersion: 1 };"
    ) throws {
        let directory = storage.pluginVersionDirectory(pluginId: pluginId, version: version)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = LiveParsePluginManifest(
            pluginId: pluginId,
            version: version,
            apiVersion: 1,
            displayName: "Fixture \(version)",
            liveTypes: ["fixture"],
            entry: "index.js",
            loginFlow: .init(
                loginURL: "https://example.invalid/login",
                cookieDomains: ["example.invalid"],
                authSignalCookies: ["session"]
            ),
            loginChallenge: supportsQRCode ? .init(kind: .qrcode) : nil
        )
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try Data(script.utf8).write(
            to: directory.appendingPathComponent("index.js"),
            options: .atomic
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockedStringList: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}
