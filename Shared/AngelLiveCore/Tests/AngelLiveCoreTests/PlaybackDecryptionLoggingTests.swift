import Foundation
import Synchronization
import Testing
@testable import AngelLiveCore

@Suite("Playback decryption logging protection")
struct PlaybackDecryptionLoggingTests {
    private let key = "00112233445566778899aabbccddeeff"

    @Test("Nested playback declarations and FFmpeg keys are redacted in console values")
    func nestedValuesAreRedacted() throws {
        let value: [String: Any] = ["response": [
            ["qualitys": [["title": "quality", "decryption": ["method": "cenc", "key": key]]]],
            ["options": ["Decryption_Key": key]]
        ]]
        #expect(LiveParsePluginManager.containsSensitiveConsoleValue(value))
        #expect(!LiveParsePluginManager.containsSensitiveConsoleValue(["title": "quality"]))
        let redacted = LiveParsePluginManager.redactedLoginTransactionConsoleValue(value)
        let text = try #require(String(data: JSONSerialization.data(withJSONObject: redacted), encoding: .utf8))
        #expect(!text.contains(key))
        #expect(text.contains("<redacted>"))
        #expect(text.contains("quality"))
        #expect(text.contains("Decryption_Key"))
    }

    @Test("Playback retrieval suppresses plugin logs while preserving typed key results", arguments: [
        "getPlayback", "getPlayArgs", "refreshPlayback"
    ])
    func retrievalSuppressesAndRestoresLogging(_ function: String) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AngelLiveDecryptionLogging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginId = "fixture.plugin.\(UUID().uuidString.lowercased())"
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
            function playback() {
              var key = "\(key)";
              console.log("key:" + key);
              console.error("key:" + key);
              return [{cdn:"source-a", qualitys:[{
                roomId:"room", title:"quality", qn:0,
                url:"https://example.invalid/live.m3u8",
                liveCodeType:"m3u8", liveType:"fixture.plugin",
                decryption:{method:"cenc", key:key}
              }]}];
            }
            globalThis.LiveParsePlugin = {
              apiVersion:1,
              getPlayback:playback, getPlayArgs:playback, refreshPlayback:playback,
              probe:function() { console.log("fixture.probe"); return {ok:true}; }
            };
            """.utf8).write(to: directory.appendingPathComponent("index.js"))
        let messages = DecryptionLogRecorder()
        let manager = LiveParsePluginManager(storage: storage, bundle: .main, logHandler: { messages.append($0) })
        let models: [LiveQualityModel] = try await manager.callDecodable(pluginId: pluginId, function: function)
        #expect(models.first?.qualitys.first?.decryption?.key == key)
        #expect(messages.values.isEmpty)
        _ = try await manager.call(pluginId: pluginId, function: "probe")
        #expect(messages.values == ["fixture.probe"])
    }
}

private final class DecryptionLogRecorder: Sendable {
    private let messages = Mutex<[String]>([])
    var values: [String] { messages.withLock { $0 } }
    func append(_ value: String) { messages.withLock { $0.append(value) } }
}
