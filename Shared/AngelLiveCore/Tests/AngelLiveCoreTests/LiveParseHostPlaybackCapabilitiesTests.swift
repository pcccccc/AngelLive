import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Host playback capability registration")
struct LiveParseHostPlaybackCapabilitiesTests {
    @Test("An already-created runtime sees registration and cannot overwrite the version")
    func registrationIsLiveAndReadOnly() async throws {
        let registry = LiveParseHostPlaybackCapabilityRegistry()
        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: .shared,
            nativeStream: nil,
            loginTransactionStore: .shared,
            credentialDomains: [],
            platformSessionOverride: nil,
            logHandler: nil,
            mediaTransformVersionProvider: { registry.mediaTransformVersion }
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async inspect() {
                Host.capabilities.mediaTransform = 99;
                var deleted = delete Host.capabilities.mediaTransform;
                var replaced = false;
                try {
                  Object.defineProperty(Host.capabilities, "mediaTransform", { value: 99 });
                  replaced = true;
                } catch (_) {}
                return { version: Host.capabilities.mediaTransform, deleted: deleted, replaced: replaced };
              }
            };
            """)
        let before = try #require(try await runtime.callPluginFunction(name: "inspect") as? [String: Any])
        #expect(before["version"] as? Int == 0)
        #expect(before["deleted"] as? Bool == false)
        #expect(before["replaced"] as? Bool == false)
        registry.enableMediaTransformV1()
        registry.enableMediaTransformV1()
        let after = try #require(try await runtime.callPluginFunction(name: "inspect") as? [String: Any])
        #expect(after["version"] as? Int == 1)
        #expect(after["deleted"] as? Bool == false)
        #expect(after["replaced"] as? Bool == false)
        // A separately constructed host starts unavailable, independent of test order.
        #expect(LiveParseHostPlaybackCapabilityRegistry().mediaTransformVersion == 0)
    }
}
