import Foundation
import Testing
import AngelLiveCore
import AngelLiveDependencies
#if canImport(KSPlayer)
import KSPlayer

@Suite("KSPlayer playback decryption options")
@MainActor
struct KSPlayerDecryptionTests {
    private func quality(key: String?, header: String) throws -> LiveQualityDetail {
        var json: [String: Any] = [
            "roomId": "room", "title": "quality", "qn": 0,
            "url": "https://example.invalid/live.m3u8",
            "liveCodeType": "m3u8", "liveType": "fixture.plugin",
            "userAgent": "fixture-agent", "headers": ["X-Fixture": header],
            "playbackHints": ["streamFormat": "hlsLive", "preferredEngines": ["avPlayer"]]
        ]
        if let key { json["decryption"] = ["method": "cenc", "key": key] }
        return try JSONDecoder().decode(LiveQualityDetail.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("Reused session options replace keys and clear them for an unencrypted quality")
    func reusedOptionsReplaceAndClearKey() throws {
        let options = KSOptions()
        options.formatContextOptions["fixture_option"] = "preserved"
        options.avOptions["fixture_option"] = "preserved"
        let keyA = "00112233445566778899aabbccddeeff"
        let keyB = "ffeeddccbbaa99887766554433221100"
        for (key, header) in [(keyA as String?, "first"), (keyB as String?, "second"), (nil, "clear")] {
            let configuration = KSPlayerSessionConfigurator.apply(
                quality: try quality(key: key, header: header), to: options,
                fallbackUserAgent: "fallback-agent", liveReconnectPolicy: .playerManaged
            )
            #expect(options.formatContextOptions["decryption_key"] as? String == key)
            #expect(options.avOptions["decryption_key"] == nil)
            #expect(options.formatContextOptions["fixture_option"] as? String == "preserved")
            #expect(options.avOptions["fixture_option"] as? String == "preserved")
            #expect(options.userAgent == "fixture-agent")
            #expect(options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String]
                == ["X-Fixture": header, "user-agent": "fixture-agent"])
            let headers = options.formatContextOptions["headers"] as? String ?? ""
            #expect(headers.contains("X-Fixture:\(header)"))
            #expect(!headers.contains(keyA) && !headers.contains(keyB))
            if header != "first" { #expect(!headers.contains("X-Fixture:first")) }
            #expect(configuration.plan.playerKinds == (key == nil ? [.avPlayer] : [.mePlayer]))
            #expect(configuration.effectiveIsLive)
        }
    }
}
#endif
