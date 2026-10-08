import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Playback decryption contract")
struct LivePlaybackDecryptionTests {
    private let key = "00112233445566778899aabbccddeeff"

    private func response(decryption: Any? = nil, hints: [String: Any]? = nil) throws -> Data {
        var quality: [String: Any] = [
            "roomId": "room", "title": "quality", "qn": 0,
            "url": "https://example.invalid/llhls.m3u8",
            "liveCodeType": "m3u8", "liveType": "fixture.plugin"
        ]
        quality["decryption"] = decryption
        quality["playbackHints"] = hints
        return try JSONSerialization.data(withJSONObject: [["cdn": "source-a", "qualitys": [quality]]])
    }

    private func qualities(decryption: Any? = nil, hints: [String: Any]? = nil) throws -> [LiveQualityModel] {
        try JSONDecoder().decode([LiveQualityModel].self, from: response(decryption: decryption, hints: hints))
    }

    @Test("Plugin quality JSON decodes and round trips a canonical key")
    func jsonRoundTrip() throws {
        let decoded = try qualities(decryption: ["method": "cenc", "key": key.uppercased()])
        let declaration = try #require(decoded.first?.qualitys.first?.decryption)
        #expect(declaration.method == .cenc)
        #expect(declaration.key == key)
        let encoded = try JSONEncoder().encode(decoded)
        let roundTrip = try JSONDecoder().decode([LiveQualityModel].self, from: encoded)
        #expect(roundTrip.first?.qualitys.first?.decryption == declaration)
    }

    @Test("Legacy quality JSON and construction default to unencrypted playback")
    func legacyQuality() throws {
        #expect(try qualities().first?.qualitys.first?.decryption == nil)
        let quality = LiveQualityDetail(
            roomId: "room", title: "quality", qn: 0,
            url: "https://example.invalid/live.m3u8", liveCodeType: .hls, liveType: "fixture.plugin"
        )
        #expect(quality.decryption == nil)
    }

    @Test("Keys reject alternate encodings and malformed values", arguments: [
        "", "00112233445566778899aabbccddeef", "00112233445566778899aabbccddeeff00",
        " 00112233445566778899aabbccddeeff", "00112233445566778899aabbccddeeff\n",
        "0x00112233445566778899aabbccddeeff", "ABEiM0RVZneImaq7zN3u/w==",
        "gg112233445566778899aabbccddeeff", "００112233445566778899aabbccddeeff"
    ])
    func malformedKeys(_ malformedKey: String) throws {
        #expect(throws: LivePlaybackDecryption.ValidationError.invalidKey) {
            try LivePlaybackDecryption(method: .cenc, key: malformedKey)
        }
        #expect {
            try qualities(decryption: ["method": "cenc", "key": malformedKey])
        } throws: { error in
            let text = String(reflecting: error) + error.localizedDescription
            return error is DecodingError && (malformedKey.isEmpty || !text.contains(malformedKey))
        }
    }

    @Test("Unknown methods, missing fields and invalid field types reject without exposing values")
    func invalidDeclarations() throws {
        let declarations: [Any] = [
            ["method": key, "key": key], ["method": "cenc"], ["key": key],
            ["method": "cenc", "key": [key]], ["method": [key], "key": key], key
        ]
        for declaration in declarations {
            #expect {
                try qualities(decryption: declaration)
            } throws: { error in
                error is DecodingError && !(String(reflecting: error) + error.localizedDescription).contains(key)
            }
        }
    }

    @Test("Generic object descriptions redact the key")
    func descriptionsRedactKey() throws {
        let models = try qualities(decryption: ["method": "cenc", "key": key])
        let declaration = try #require(models.first?.qualitys.first?.decryption)
        #expect(!String(describing: declaration).contains(key))
        #expect(!String(reflecting: declaration).contains(key))
        #expect(!String(reflecting: models).contains(key))
    }

    @Test("Required decryption overrides advisory AV preference and LL-HLS routing")
    func decryptionForcesME() throws {
        for hints: [String: Any] in [
            ["streamFormat": "hlsLive", "preferredEngines": ["avPlayer"], "latencyMode": "lowLatency", "isLive": false],
            ["streamFormat": "hlsLive", "latencyMode": "lowLatency"],
            ["streamFormat": "hlsVod", "preferredEngines": ["avPlayer"], "isLive": true],
            ["streamFormat": "dash", "isLive": false]
        ] {
            let models = try qualities(decryption: ["method": "cenc", "key": key], hints: hints)
            let quality = try #require(models.first?.qualitys.first)
            let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: quality)
            #expect(plan.playerKinds == [.mePlayer])
            #expect(plan.streamFormat == RoomPlaybackResolver.streamFormat(for: quality))
            #expect(plan.isHLS == (plan.streamFormat == .hlsLive || plan.streamFormat == .hlsVod))
            #expect(plan.isLive == (hints["isLive"] as? Bool ?? true))
        }
    }

    @Test("Matching refreshed playback qualities retains the newly supplied key")
    func refreshedSelectionUpdatesKey() throws {
        let previous = try qualities(decryption: ["method": "cenc", "key": key])
        let updatedKey = "ffeeddccbbaa99887766554433221100"
        let updated = try qualities(decryption: ["method": "cenc", "key": updatedKey])
        let preferred = try #require(previous.first?.qualitys.first)
        let selected = try #require(RoomPlaybackResolver.matchingSelection(in: updated, preferredQuality: preferred))
        #expect(selected.quality.decryption?.key == updatedKey)
    }
}
