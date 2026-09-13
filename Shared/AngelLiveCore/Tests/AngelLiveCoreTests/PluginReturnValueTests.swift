import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Plugin return value decoding")
struct PluginReturnValueTests {
    enum EntryPoint: CaseIterable, Sendable {
        case current, leased, isolatedCredential
    }

    @Test("Missing plugin results throw a recoverable error", arguments: [
        "destroyDanmakuSession", "returnNull", "asyncUndefined", "asyncNull"
    ], EntryPoint.allCases)
    func missingResult(function: String, entryPoint: EntryPoint) async throws {
        let fixture = try ReturnValueFixture()
        defer { fixture.remove() }

        do {
            let _: LiveParseDanmakuDriverResult = try await fixture.decode(function, via: entryPoint)
            Issue.record("A missing result must not satisfy the required driver result")
        } catch let error as LiveParsePluginError {
            guard case .invalidReturnValue = error else { throw error }
        }

        // The same runtime remains usable after a malformed response.
        let result: LiveParseDanmakuDriverResult = try await fixture.decode("validResult", via: entryPoint)
        #expect(result.ok == true)
        #expect(result.messages?.isEmpty == true)
    }

    @Test("Optional results preserve null", arguments: EntryPoint.allCases)
    func optionalResult(entryPoint: EntryPoint) async throws {
        let fixture = try ReturnValueFixture()
        defer { fixture.remove() }
        let result: LiveParseDanmakuDriverResult? = try await fixture.decode("returnNull", via: entryPoint)
        #expect(result == nil)
    }

    @Test("Array results and custom decoding strategies remain supported", arguments: EntryPoint.allCases)
    func arrayResult(entryPoint: EntryPoint) async throws {
        struct Item: Decodable { let roomId: String }
        let fixture = try ReturnValueFixture()
        defer { fixture.remove() }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result: [Item] = try await fixture.decode("arrayResult", via: entryPoint, decoder: decoder)
        #expect(result.map(\.roomId) == ["room-a", "room-b"])
    }
}

private struct ReturnValueFixture {
    let root: URL
    let pluginId: String
    let manager: LiveParsePluginManager

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        pluginId = "return-value-\(UUID().uuidString.lowercased()).plugin"
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
        let directory = storage.pluginVersionDirectory(pluginId: pluginId, version: "1.0.0")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = LiveParsePluginManifest(
            pluginId: pluginId, version: "1.0.0", apiVersion: 1,
            displayName: "Fixture", liveTypes: ["fixture.plugin"], entry: "index.js"
        )
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data("""
        globalThis.LiveParsePlugin = {
          apiVersion: 1,
          destroyDanmakuSession() {},
          returnNull() { return null; },
          asyncUndefined() { return Promise.resolve(); },
          asyncNull() { return Promise.resolve(null); },
          validResult() { return { ok: true, messages: [] }; },
          arrayResult() { return [{ room_id: "room-a" }, { room_id: "room-b" }]; }
        };
        """.utf8).write(to: directory.appendingPathComponent("index.js"))
        manager = LiveParsePluginManager(storage: storage, bundle: .main)
    }

    func decode<T: Decodable>(
        _ function: String,
        via entryPoint: PluginReturnValueTests.EntryPoint,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        switch entryPoint {
        case .current:
            return try await manager.callDecodable(pluginId: pluginId, function: function, decoder: decoder)
        case .leased:
            return try await manager.callDecodable(
                using: manager.runtimeLease(pluginId: pluginId), function: function,
                payload: [:], sensitive: false, decoder: decoder
            )
        case .isolatedCredential:
            return try await manager.callDecodableUsingIsolatedCredential(
                pluginId: pluginId, function: function, payload: [:], cookie: "", uid: nil, decoder: decoder
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
