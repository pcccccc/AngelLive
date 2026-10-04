import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Platform session metadata revisions")
struct PlatformSessionMetadataRevisionTests {
    @Test("a second logout cannot match a download captured while already logged out")
    func missingSessionABA() throws {
        let suite = "fixture.session-revisions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlatformSessionMetadataRevisionStore(defaults: defaults)
        let captured = store.revision(pluginId: "fixture.plugin")
        let firstLogout = store.recordMutation(pluginId: "fixture.plugin")
        let secondLogout = store.recordMutation(pluginId: "fixture.plugin")
        #expect(captured != firstLogout)
        #expect(firstLogout != secondLogout)
        #expect(store.revision(pluginId: "fixture.plugin") == secondLogout)
    }

    @Test("reconstructing the store preserves generations and separates plugins")
    func restorationAndNamespace() throws {
        let suite = "fixture.session-revisions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PlatformSessionMetadataRevisionStore(defaults: defaults)
        let revision = first.recordMutation(pluginId: "source-a")
        let restored = PlatformSessionMetadataRevisionStore(defaults: defaults)
        #expect(restored.revision(pluginId: "source-a") == revision)
        #expect(restored.revision(pluginId: "source-b") == "unmodified")
        #expect(restored.revision(pluginId: "source-a") == revision)
    }
}
