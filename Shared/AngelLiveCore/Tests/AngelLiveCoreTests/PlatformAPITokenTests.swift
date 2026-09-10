import Foundation
import Testing
@testable import AngelLiveCore

@Suite("API credential isolation")
struct PlatformAPITokenTests {
    @Test func clientCredentialModesAreOfferedOnIOS() async throws {
        let fixture = try TokenFixture(credentialKinds: ["client_credentials"])
        defer { fixture.remove() }
        let entries = await PlatformLoginRegistry(pluginManager: fixture.manager).availablePlatforms(for: .iOS)
        let entry = try #require(entries.first { $0.pluginId == fixture.pluginId })
        #expect(entry.methods(for: .iOS) == [.clientCredentials])
        #expect(entry.methods(for: .macOS).isEmpty)
        #expect(entry.methods(for: .tvOS).isEmpty)
    }

    @Test @MainActor func clientCredentialsValidatePersistRefreshAndSwitchAtomically() async throws {
        let fixture = try TokenFixture(credentialKinds: ["client_credentials", "token"])
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("previous-token")
        let service = PlatformAPITokenService(manager: fixture.manager)
        for secret in ["invalid", "network", "mismatch"] {
            do {
                try await service.validateAndSave(pluginId: fixture.pluginId, clientId: "fixture-client", clientSecret: secret)
                Issue.record("An invalid candidate must not replace the committed credential")
            } catch { }
            #expect(try await fixture.vault.record(pluginId: fixture.pluginId)?.token == "previous-token")
        }
        try await service.validateAndSave(pluginId: fixture.pluginId, clientId: " fixture-client ", clientSecret: " fixture-secret ")
        let saved = try #require(try await fixture.vault.record(pluginId: fixture.pluginId))
        #expect(saved.kind == .clientCredentials)
        #expect(saved.clientId == "fixture-client")
        #expect(saved.clientSecret == "fixture-secret")
        #expect(saved.token == nil)
        #expect(service.statuses[fixture.pluginId]?.credentialKind == "client_credentials")
        let restored = PlatformAPITokenService(manager: fixture.manager)
        await restored.load(pluginId: fixture.pluginId)
        await restored.refresh(pluginId: fixture.pluginId)
        #expect(restored.statuses[fixture.pluginId]?.state == "valid")
        #expect(try await fixture.vault.record(pluginId: fixture.pluginId)?.clientSecret == "fixture-secret")
        try await service.validateAndSave(pluginId: fixture.pluginId, token: "replacement-token")
        #expect(try await fixture.vault.record(pluginId: fixture.pluginId)?.clientSecret == nil)
        #expect(try await fixture.vault.record(pluginId: fixture.pluginId)?.token == "replacement-token")
        try await service.clear(pluginId: fixture.pluginId)
        #expect(try await fixture.vault.record(pluginId: fixture.pluginId) == nil)
    }

    @Test(arguments: Array(APITokenCallPolicy.functions).sorted())
    func clientCredentialsAreInjectedWithoutCallerOverrides(function: String) async throws {
        let fixture = try TokenFixture(credentialKinds: ["client_credentials", "token"])
        defer { fixture.remove() }
        await fixture.enable()
        _ = try await fixture.vault.replace(pluginId: fixture.pluginId, record: .init(clientId: "fixture-client", clientSecret: "fixture-secret", status: .init(state: "valid")), manager: fixture.manager)
        let probe: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function,
            payload: ["clientId": "caller-client", "clientSecret": "caller-secret", "apiToken": "caller-token"])
        #expect(probe.received == nil)
        #expect(probe.receivedClientId == "fixture-client")
        #expect(probe.receivedClientSecret == "fixture-secret")
        let other: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.otherPluginId, function: function)
        #expect(other.receivedClientId == nil)
        #expect(other.receivedClientSecret == nil)
    }

    @Test(arguments: ["getPlayback", "getDanmaku", "createDanmakuSession", "onDanmakuEvent"])
    func mediaCallsNeverReceiveClientCredentials(function: String) async throws {
        let fixture = try TokenFixture(credentialKinds: ["client_credentials"])
        defer { fixture.remove() }
        await fixture.enable()
        _ = try await fixture.vault.replace(pluginId: fixture.pluginId, record: .init(clientId: "fixture-client", clientSecret: "fixture-secret", status: .init(state: "valid")), manager: fixture.manager)
        let probe: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function,
            payload: ["clientId": "caller-client", "clientSecret": "caller-secret", "apiToken": "caller-token"])
        #expect(probe.received == nil)
        #expect(probe.receivedClientId == nil)
        #expect(probe.receivedClientSecret == nil)
    }

    @Test func legacyTokenRecordAndClientCredentialDiagnostics() throws {
        let legacy = try JSONDecoder().decode(PlatformAPITokenVault.Record.self, from: Data(#"{"token":"legacy-token","status":{"state":"valid"}}"#.utf8))
        #expect(legacy.kind == .token)
        #expect(legacy.payload == ["apiToken": "legacy-token"])
        let malformed = Data(#"{"clientId":"partial-client","status":{"state":"valid"}}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PlatformAPITokenVault.Record.self, from: malformed) }
        let diagnostic = try #require(SensitivePluginHTTPConsoleSummary.loginFailureBody(statusCode: 401,
            body: #"{"message":"Invalid fixture-secret or generated-token","client_secret":"fixture-secret"}"#,
            secrets: ["fixture-secret", "Bearer generated-token"]))
        #expect(diagnostic.contains("Invalid"))
        #expect(!diagnostic.contains("fixture-secret"))
        #expect(!diagnostic.contains("generated-token"))
    }

    @Test func loginHTTPErrorRevealsReasonWithoutCredentials() throws {
        let body = #"{"status":401,"message":"Invalid fixture-secret-value","error":{"code":"AUTH_REQUIRED","description":"OAuth upstream-secret-value","token":"hidden-response-token"},"access_token":"hidden-response-token","user":{"name":"hidden-user"}}"#
        let summary = try #require(SensitivePluginHTTPConsoleSummary.loginFailureBody(
            statusCode: 401, body: body, token: "Bearer fixture-secret-value"
        ))
        #expect(summary.contains("401"))
        #expect(summary.contains("Invalid"))
        #expect(summary.contains("AUTH_REQUIRED"))
        #expect(summary.contains("<redacted>"))
        #expect(!summary.contains("fixture-secret-value"))
        #expect(!summary.contains("upstream-secret-value"))
        #expect(!summary.contains("hidden-response-token"))
        #expect(!summary.contains("hidden-user"))
    }

    @Test func loginHTTPDiagnosticsOmitSuccessAndArbitraryBodies() {
        #expect(SensitivePluginHTTPConsoleSummary.loginFailureBody(statusCode: 200, body: #"{"message":"credential-data"}"#, token: "fixture-secret") == nil)
        let invalidJSON = SensitivePluginHTTPConsoleSummary.loginFailureBody(statusCode: 401, body: "credential-data", token: "fixture-secret")
        #expect(invalidJSON?.contains("credential-data") == false)
        let oversized = SensitivePluginHTTPConsoleSummary.loginFailureBody(statusCode: 401, body: String(repeating: "sensitive-data", count: 10_000), token: "fixture-secret")
        #expect(oversized?.contains("sensitive-data") == false)
    }

    @Test func mixedMethodsRespectHostCapabilities() {
        let entry = LoginPlatformEntry(pluginId: "fixture.plugin", displayName: "Fixture", liveType: "source-a",
                                       loginFlow: .init(loginURL: "https://login.example.invalid", cookieDomains: [], authSignalCookies: []),
                                       loginChallenge: .init(kind: .qrcode), auth: .init(credentialKinds: ["token", "cookie"]), version: "1.0.0")
        #expect(entry.methods(for: .iOS) == [.apiToken, .qrCode, .web])
        #expect(entry.methods(for: .macOS) == [.apiToken, .qrCode, .web])
        #expect(entry.methods(for: .tvOS) == [.apiToken, .qrCode, .manualCookie])
        #expect(entry.preferredMethod(for: .tvOS, isLoggedIn: false) == .apiToken)
    }

    @Test func tokenOnlyRegistryAndMethods() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        let entry = try #require(await PlatformLoginRegistry(pluginManager: fixture.manager).entry(pluginId: fixture.pluginId))
        #expect(entry.loginFlow == nil)
        for platform in LoginChallengeHostPlatform.allCases {
            #expect(entry.methods(for: platform) == [.apiToken])
        }
    }

    @Test(arguments: Array(APITokenCallPolicy.functions).sorted())
    func injectsCurrentCredentialEveryTime(function: String) async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("fixture-secret-a")
        let first: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function, payload: ["apiToken": "caller-override"])
        #expect(first.received == "fixture-secret-a")
        try await fixture.store("fixture-secret-b")
        let second: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function)
        #expect(second.received == "fixture-secret-b")
        let other: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.otherPluginId, function: function)
        #expect(other.received == nil)
    }

    @Test(arguments: ["getPlayback", "getDanmaku", "createDanmakuSession", "onDanmakuEvent"])
    func mediaCallsNeverReceiveToken(function: String) async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("fixture-secret-a")
        let result: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function, payload: ["apiToken": "caller-secret"])
        #expect(result.received == nil)
    }

    @Test @MainActor func isolatedValidationPreservesCommittedCredentialOnFailure() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("fixture-secret-a")
        let service = PlatformAPITokenService(manager: fixture.manager)
        for rejected in ["invalid", "network", "expired", "malformed"] {
            await #expect(throws: (any Error).self) {
                try await service.validateAndSave(pluginId: fixture.pluginId, token: rejected)
            }
            #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).token == "fixture-secret-a")
        }
        try await service.validateAndSave(pluginId: fixture.pluginId, token: "Bearer fixture-secret-b")
        #expect(service.statusText(pluginId: fixture.pluginId) == "API 已连接")
        #expect(service.statuses[fixture.pluginId]?.clientId == "fixture-client")
        #expect(service.statuses[fixture.pluginId]?.userName == nil)
        #expect(LiveParsePlatformSessionVault.session(for: fixture.pluginId) == nil)
        try await service.clear(pluginId: fixture.pluginId)
        #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).token == nil)
        #expect(service.statusText(pluginId: fixture.pluginId) == "未配置")
    }

    @Test @MainActor func clearCancelsOldPromiseAndCandidateCannotRestoreIt() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("fixture-secret-a")
        let service = PlatformAPITokenService(manager: fixture.manager)
        let runtime = try fixture.manager.resolve(pluginId: fixture.pluginId).runtime
        let pending = Task { () throws -> TokenProbe in
            try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: "getRooms", payload: ["pending": true])
        }
        for _ in 0..<1_000 {
            if await runtime.pendingPromiseCallCountForTesting() > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await runtime.pendingPromiseCallCountForTesting() == 1)
        let baseline = try await fixture.vault.snapshot(pluginId: fixture.pluginId)
        try await service.clear(pluginId: fixture.pluginId)
        await #expect(throws: (any Error).self) { _ = try await pending.value }
        #expect(await runtime.pendingPromiseCallCountForTesting() == 0)
        await #expect(throws: APITokenError.self) {
            _ = try await fixture.vault.replace(pluginId: fixture.pluginId, record: .init(token: "old-candidate", status: .init(state: "valid")), expectedGeneration: baseline.generation, manager: fixture.manager)
        }
    }

    @Test func safeErrorsPreserveCategoryWithoutSecrets() {
        let error = LiveParsePluginError.standardized(.init(code: .upstream, message: "fixture-secret", context: ["reason": "integrity_required", "payload": "fixture-secret"]))
        let safe = APITokenCallPolicy.safeError(error)
        #expect(!safe.localizedDescription.contains("fixture-secret"))
        guard case let LiveParsePluginError.standardized(value) = safe else { Issue.record("Missing protocol error"); return }
        #expect(value.code == .upstream)
        #expect(value.context == ["reason": "integrity_required"])
    }

    @Test @MainActor func statusSurvivesServiceRecreationAndNetworkFailure() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("invalid")
        let service = PlatformAPITokenService(manager: fixture.manager)
        await service.refresh(pluginId: fixture.pluginId)
        let recreated = PlatformAPITokenService(manager: fixture.manager)
        await recreated.load(pluginId: fixture.pluginId)
        #expect(recreated.statusText(pluginId: fixture.pluginId) == "已失效")
        #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).token == "invalid")
        try await fixture.store("network")
        await recreated.load(pluginId: fixture.pluginId)
        await recreated.refresh(pluginId: fixture.pluginId)
        #expect(recreated.statusText(pluginId: fixture.pluginId) == "API 已连接")
        #expect(recreated.failures[fixture.pluginId] != nil)
        #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).token == "network")
    }

    @Test @MainActor func cancellationNeverCommitsCandidate() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store("fixture-secret-a")
        let service = PlatformAPITokenService(manager: fixture.manager)
        let task = Task { try await service.validateAndSave(pluginId: fixture.pluginId, token: "pending") }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).token == "fixture-secret-a")
    }

    @Test @MainActor func storageFailureDoesNotCommitOrEvict() async throws {
        let fixture = try TokenFixture(tokenStorage: FailingTokenStorage())
        defer { fixture.remove() }
        await fixture.enable()
        let baseline = try await fixture.vault.snapshot(pluginId: fixture.pluginId)
        let runtime = try fixture.manager.resolve(pluginId: fixture.pluginId).runtime
        let service = PlatformAPITokenService(manager: fixture.manager)
        await #expect(throws: (any Error).self) {
            try await service.validateAndSave(pluginId: fixture.pluginId, token: "fixture-secret-b")
        }
        #expect(try await fixture.vault.snapshot(pluginId: fixture.pluginId).generation == baseline.generation)
        #expect(try fixture.manager.resolve(pluginId: fixture.pluginId).runtime === runtime)
    }

    @Test func fullUIOptInProtectsShellMode() async throws {
        let fixture = try TokenFixture()
        defer { fixture.remove() }
        try await fixture.store("fixture-secret-a")
        let result: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: "getRooms")
        #expect(result.received == nil)
    }

    @Test("first FullUI request uses persisted credentials before any view lifecycle task")
    @MainActor
    func hostPolicyProtectsFirstRequest() async throws {
        let policy = PlatformAPICredentialHostPolicy()
        policy.initializeIfNeeded(hasInstalledPlugins: true)
        // Recreating a root view must not replace the already configured policy.
        policy.initializeIfNeeded(hasInstalledPlugins: false)
        let fixture = try TokenFixture(hostPolicy: { policy.isFullUI })
        defer { fixture.remove() }
        try await fixture.store("fixture-secret-a")

        // No activate() call: rendering cached UI must not be a prerequisite.
        let result: TokenProbe = try await fixture.manager.callDecodable(
            pluginId: fixture.pluginId, function: "getRooms", payload: ["apiToken": "caller-token"]
        )
        #expect(result.received == "fixture-secret-a")
    }

    @Test("ShellUI policy never reads API credentials")
    @MainActor
    func shellHostPolicyDoesNotReadStorage() async throws {
        let policy = PlatformAPICredentialHostPolicy()
        let fixture = try TokenFixture(tokenStorage: UnavailableTokenStorage(), hostPolicy: { policy.isFullUI })
        defer { fixture.remove() }
        let result: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: "getRooms")
        #expect(result.received == nil)
    }

    @Test("catalog mode changes apply without mounting or removing a window")
    @MainActor
    func catalogPolicyTracksModeChanges() async throws {
        let policy = PlatformAPICredentialHostPolicy()
        let fixture = try TokenFixture(hostPolicy: { policy.isFullUI })
        defer { fixture.remove() }
        try await fixture.store("fixture-secret-a")
        for enabled in [false, true, false, true] {
            policy.update(hasInstalledPlugins: enabled)
            let result: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: "getRooms")
            #expect(result.received == (enabled ? "fixture-secret-a" : nil))
        }
    }

    @Test(arguments: ["getPlayback", "getDanmaku"])
    func anonymousMediaDoesNotReadKeychain(function: String) async throws {
        let fixture = try TokenFixture(tokenStorage: UnavailableTokenStorage())
        defer { fixture.remove() }
        await fixture.enable()
        let result: TokenProbe = try await fixture.manager.callDecodable(pluginId: fixture.pluginId, function: function)
        #expect(result.received == nil)
    }
}

private struct TokenProbe: Decodable {
    let received: String?
    let receivedClientId: String?
    let receivedClientSecret: String?
}

private final class MemoryTokenStorage: APITokenStorage {
    private var values: [String: Data] = [:]
    func read(pluginId: String) -> Data? { values[pluginId] }
    func write(_ data: Data, pluginId: String) { values[pluginId] = data }
    func delete(pluginId: String) { values[pluginId] = nil }
}

private struct FailingTokenStorage: APITokenStorage {
    func read(pluginId: String) throws -> Data? {
        try JSONEncoder().encode(PlatformAPITokenVault.Record(token: "fixture-secret-a", status: .init(state: "valid")))
    }
    func write(_ data: Data, pluginId: String) throws { throw APITokenError.storage }
    func delete(pluginId: String) throws { throw APITokenError.storage }
}

private struct UnavailableTokenStorage: APITokenStorage {
    func read(pluginId: String) throws -> Data? { throw APITokenError.storage }
    func write(_ data: Data, pluginId: String) throws { throw APITokenError.storage }
    func delete(pluginId: String) throws { throw APITokenError.storage }
}

private struct TokenFixture {
    let root: URL
    let pluginId = "fixture-\(UUID().uuidString.lowercased()).plugin"
    let otherPluginId = "other-\(UUID().uuidString.lowercased()).plugin"
    let vault: PlatformAPITokenVault
    let manager: LiveParsePluginManager
    init(
        tokenStorage: sending any APITokenStorage = MemoryTokenStorage(),
        credentialKinds: [String] = ["token"],
        hostPolicy: @escaping @MainActor @Sendable () -> Bool = { false }
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
        vault = PlatformAPITokenVault(storage: tokenStorage, hostPolicy: hostPolicy)
        manager = LiveParsePluginManager(storage: storage, apiTokenVault: vault)
        for id in [pluginId, otherPluginId] {
            let directory = storage.pluginVersionDirectory(pluginId: id, version: "1.0.0")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = LiveParsePluginManifest(pluginId: id, version: "1.0.0", apiVersion: 1, displayName: "Fixture", liveTypes: ["source-a"], entry: "index.js", auth: .init(required: true, credentialKinds: credentialKinds))
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
            let script = """
            globalThis.LiveParsePlugin = { apiVersion: 1 };
            function probe(input) {
              const secret = input.clientSecret || input.apiToken;
              if (input.pending || secret === 'pending') return new Promise(function() {});
              if (secret === 'network') throw new Error('LP_PLUGIN_ERROR:' + JSON.stringify({code:'NETWORK',message:secret}));
              return {received:input.apiToken || null, receivedClientId:input.clientId || null, receivedClientSecret:input.clientSecret || null,
                state:secret === 'invalid' ? 'invalid' : 'valid', expireAt:secret === 'expired' ? 1 : 0,
                clientId:secret === 'mismatch' ? 'other-client' : input.clientId || 'fixture-client',
                credentialKind: secret === 'malformed' ? 'unknown' : input.clientSecret ? 'client_credentials' : 'token',
                authorizationType:'api', tokenType:'app_access_token'};
            }
            \(Array(APITokenCallPolicy.functions.union(["getPlayback", "getDanmaku", "createDanmakuSession", "onDanmakuEvent"])).map { "LiveParsePlugin.\($0) = probe;" }.joined(separator: "\n"))
            """
            try Data(script.utf8).write(to: directory.appendingPathComponent("index.js"))
        }
    }
    func enable() async { await vault.activate(UUID()) }
    func store(_ token: String) async throws {
        let old = try await vault.replace(pluginId: pluginId, record: .init(token: token, status: .init(state: "valid", credentialKind: "token", authorizationType: "api")), manager: manager)
        for runtime in old { await runtime.retireCredentialGeneration() }
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
