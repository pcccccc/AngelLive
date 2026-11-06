import Foundation
import Synchronization
import Testing
@testable import AngelLiveCore

@Suite("Separate audio logging protection")
struct DualStreamLoggingTests {
    @Test("Structured console values redact nested audio address and headers")
    func nestedValuesRedacted() throws {
        let address = "https://media.example.invalid/audio?signature=fixture-signed-value"
        let credential = "fixture-header-value"
        let value: [String: Any] = ["response": [["AudioUrl": address, "AudioHeaders": ["X-Fixture": credential], "title": "quality"]]]
        #expect(LiveParsePluginManager.containsSensitiveConsoleValue(value))
        let redacted = LiveParsePluginManager.redactedLoginTransactionConsoleValue(value)
        let text = try #require(String(data: JSONSerialization.data(withJSONObject: redacted), encoding: .utf8))
        #expect(!text.contains(address))
        #expect(!text.contains(credential))
        #expect(text.contains("<redacted>"))
        #expect(text.contains("quality"))
    }

    @Test("Playback calls suppress audio addresses and headers even when decoding fails", arguments: ["getPlayback", "refreshPlayback"])
    func playbackLogs(_ function: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DualStreamLogging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginId = "fixture.plugin.\(UUID().uuidString.lowercased())"
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
        let directory = storage.pluginVersionDirectory(pluginId: pluginId, version: "1.0.0")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = LiveParsePluginManifest(pluginId: pluginId, version: "1.0.0", apiVersion: 1,
                                               displayName: "Fixture", liveTypes: ["fixture.plugin"], entry: "index.js")
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        let signedValue = "fixture-signed-value"
        let headerValue = "fixture-header-value"
        try Data("""
            function playback() {
              const address = "https://media.example.invalid/audio?signature=\(signedValue)";
              const credential = "\(headerValue)";
              console.log(address); console.error(credential);
              return [{cdn:"source-a", qualitys:[{roomId:"room", title:"quality", qn:0,
                url:"https://media.example.invalid/video", liveCodeType:"m3u8", liveType:"fixture.plugin",
                audioUrl: address, audioHeaders: {"X-Fixture": credential}}]}];
            }
            function malformed() {
              let result = playback(); result[0].qualitys[0].audioHeaders = {"X-Fixture": ["\(headerValue)"]}; return result;
            }
            globalThis.LiveParsePlugin = {apiVersion:1, getPlayback:playback, refreshPlayback:malformed,
              probe:function() { console.log("fixture.probe"); return {ok:true}; }};
            """.utf8).write(to: directory.appendingPathComponent("index.js"))
        let messages = AudioLogRecorder()
        let manager = LiveParsePluginManager(storage: storage, bundle: .main, logHandler: { messages.append($0) })
        do {
            let values: [LiveQualityModel] = try await manager.callDecodable(pluginId: pluginId, function: function)
            #expect(function == "getPlayback")
            #expect(values.first?.qualitys.first?.audioHeaders?["X-Fixture"] == headerValue)
        } catch {
            #expect(function == "refreshPlayback")
            let text = String(reflecting: error) + error.localizedDescription
            #expect(!text.contains(signedValue))
            #expect(!text.contains(headerValue))
        }
        #expect(messages.values.isEmpty)
        _ = try await manager.call(pluginId: pluginId, function: "probe")
        #expect(messages.values == ["fixture.probe"])
    }
}

private final class AudioLogRecorder: Sendable {
    private let messages = Mutex<[String]>([])
    var values: [String] { messages.withLock { $0 } }
    func append(_ value: String) { messages.withLock { $0.append(value) } }
}
