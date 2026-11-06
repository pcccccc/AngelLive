import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Dual-stream playback contract")
struct DualStreamProtocolTests {
    private let key = "00112233445566778899aabbccddeeff"

    @Test("Capability is live, read-only, and independent of media transform")
    func capabilityRegistration() async throws {
        let registry = LiveParseHostPlaybackCapabilityRegistry()
        let runtime = JSRuntime(
            pluginId: "fixture.plugin", session: .shared, nativeStream: nil,
            loginTransactionStore: .shared, credentialDomains: [], platformSessionOverride: nil,
            logHandler: nil, mediaTransformVersionProvider: { registry.mediaTransformVersion },
            dualStreamProvider: { registry.dualStream }
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async inspect() {
                Host.capabilities.dualStream = true;
                const deleted = delete Host.capabilities.dualStream;
                let replaced = false;
                try { Object.defineProperty(Host.capabilities, "dualStream", { value: true }); replaced = true; } catch (_) {}
                return { dual: Host.capabilities.dualStream, transform: Host.capabilities.mediaTransform, deleted, replaced };
              }
            };
            """)
        let before = try #require(try await runtime.callPluginFunction(name: "inspect") as? [String: Any])
        #expect(before["dual"] as? Bool == false)
        #expect(before["transform"] as? Int == 0)
        #expect(before["deleted"] as? Bool == false)
        #expect(before["replaced"] as? Bool == false)
        registry.enableDualStream()
        registry.enableDualStream()
        let after = try #require(try await runtime.callPluginFunction(name: "inspect") as? [String: Any])
        #expect(after["dual"] as? Bool == true)
        #expect(after["transform"] as? Int == 0)
        #expect(after["deleted"] as? Bool == false)
        #expect(after["replaced"] as? Bool == false)
        let separate = LiveParseHostPlaybackCapabilityRegistry()
        separate.enableMediaTransformV1()
        #expect(separate.mediaTransformVersion == 1)
        #expect(!separate.dualStream)
    }

    private func quality(_ fields: [String: Any] = [:]) throws -> LiveQualityDetail {
        var object: [String: Any] = [
            "roomId": "room", "title": "quality", "qn": 0,
            "url": "https://media.example.invalid/video.m3u8",
            "liveCodeType": "m3u8", "liveType": "fixture.plugin"
        ]
        object.merge(fields) { _, new in new }
        return try JSONDecoder().decode(LiveQualityDetail.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("Missing and null audio fields preserve legacy playback")
    func legacyAndNull() throws {
        for fields: [String: Any] in [[:], ["audioUrl": NSNull(), "audioUserAgent": NSNull(), "audioHeaders": NSNull()]] {
            let value = try quality(fields)
            #expect(value.audioUrl == nil)
            #expect(value.audioUserAgent == nil)
            #expect(value.audioHeaders == nil)
            #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: value).audioURL == nil)
        }
    }

    @Test("Audio metadata round trips independently of video request metadata")
    func roundTrip() throws {
        let original = try quality([
            "audioUrl": "https://media.example.invalid/audio.m4a",
            "audioUserAgent": "audio-agent", "audioHeaders": ["X-Audio": "audio-value"],
            "userAgent": "video-agent", "headers": ["X-Video": "video-value"]
        ])
        let decoded = try JSONDecoder().decode(LiveQualityDetail.self, from: JSONEncoder().encode(original))
        #expect(decoded.audioUrl == original.audioUrl)
        #expect(decoded.audioUserAgent == "audio-agent")
        #expect(decoded.audioHeaders == ["X-Audio": "audio-value"])
        #expect(decoded.headers == ["X-Video": "video-value"])
    }

    @Test("Wrong audio field types reject the response without exposing supplied values")
    func invalidTypes() throws {
        let secret = "sensitive-fixture-value"
        for fields: [String: Any] in [
            ["audioUrl": [secret]], ["audioUserAgent": [secret]],
            ["audioHeaders": ["X-Audio": [secret]]], ["audioHeaders": [secret]]
        ] {
            #expect {
                try quality(fields)
            } throws: { error in
                error is DecodingError && !(String(reflecting: error) + error.localizedDescription).contains(secret)
            }
        }
    }

    @Test("Malformed audio metadata cannot conceal a required invalid decryption declaration")
    func invalidDecryptionStillRejects() throws {
        #expect(throws: (any Error).self) {
            try quality(["audioUrl": NSNull(), "decryption": ["method": "cenc", "key": "invalid"]])
        }
    }

    @Test("Only absolute HTTP(S) audio URLs with a host are eligible", arguments: [
        "", "/relative/audio.m4a", "audio.m4a", "file:///tmp/audio.m4a", "ftp://media.example.invalid/a", "https:///audio.m4a"
    ])
    func invalidAudioURL(_ audioURL: String) throws {
        let value = try quality(["audioUrl": audioURL, "playbackHints": ["isLive": false]])
        #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: value).audioURL == nil)
    }

    @Test("VOD audio forces ME while live audio is ignored")
    func routing() throws {
        for scheme in ["http", "https"] {
            let url = "\(scheme)://media.example.invalid/audio.m4a"
            let value = try quality([
                "audioUrl": url,
                "playbackHints": ["isLive": false, "preferredEngines": ["avPlayer"]]
            ])
            let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: value)
            #expect(plan.audioURL?.absoluteString == url)
            #expect(plan.playerKinds == [.mePlayer])
        }
        let encrypted = try quality([
            "audioUrl": "https://media.example.invalid/audio.m4a",
            "playbackHints": ["isLive": false], "decryption": ["method": "cenc", "key": key]
        ])
        #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: encrypted).audioURL != nil)
        #expect(encrypted.decryption?.key == key)
        for hints: [String: Any] in [[:], ["isLive": true]] {
            let value = try quality(["audioUrl": "https://media.example.invalid/audio.m4a", "playbackHints": hints])
            #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: value).audioURL == nil)
        }
        let inferred = try quality([
            "audioUrl": "https://media.example.invalid/audio.m4a",
            "playbackHints": ["streamFormat": "hlsVod"]
        ])
        #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: inferred).audioURL != nil)
    }

    @Test("Audio requests use audio, video, then fallback agent without video headers")
    func audioRequestIsolation() throws {
        let value = try quality([
            "userAgent": "video-agent", "headers": ["X-Video": "private-video"],
            "audioUserAgent": "audio-agent", "audioHeaders": ["X-Audio": "audio-value"]
        ])
        let options = RoomPlaybackResolver.audioRequestOptions(for: value, fallbackUserAgent: "fallback-agent")
        #expect(options.userAgent == "audio-agent")
        #expect(options.headers["X-Audio"] == "audio-value")
        #expect(options.headers["X-Video"] == nil)
        let videoFallback = try quality(["userAgent": "video-agent"])
        let videoOptions = RoomPlaybackResolver.audioRequestOptions(for: videoFallback, fallbackUserAgent: "fallback-agent")
        #expect(videoOptions.userAgent == "video-agent")
        #expect(videoOptions.headers.keys.allSatisfy { $0.lowercased() == "user-agent" })
        let fallback = RoomPlaybackResolver.audioRequestOptions(for: try quality(), fallbackUserAgent: "fallback-agent")
        #expect(fallback.userAgent == "fallback-agent")
    }

    @Test("Existing audio User-Agent header is not duplicated by casing")
    func audioHeaderCase() throws {
        let value = try quality(["audioHeaders": ["UsEr-AgEnT": "header-agent"]])
        let options = RoomPlaybackResolver.audioRequestOptions(for: value, fallbackUserAgent: "fallback-agent")
        #expect(options.headers.filter { $0.key.lowercased() == "user-agent" }.count == 1)
        #expect(options.headers["UsEr-AgEnT"] == "header-agent")
    }

    @Test("Refreshing a selection replaces audio and decryption as one quality")
    func replacement() throws {
        let previous = try quality([
            "audioUrl": "https://media.example.invalid/old.m4a",
            "decryption": ["method": "cenc", "key": key]
        ])
        let updated = try quality(["audioUrl": "https://media.example.invalid/new.m4a"])
        let line = LiveQualityModel(cdn: "source-a", qualitys: [updated])
        let selection = try #require(RoomPlaybackResolver.matchingSelection(in: [line], preferredQuality: previous))
        #expect(selection.quality.audioUrl == "https://media.example.invalid/new.m4a")
        #expect(selection.quality.decryption == nil)
    }
}
