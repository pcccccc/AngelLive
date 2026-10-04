import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Conditional session login guards")
struct PlatformConditionalSessionLoginTests {
    @Test("stale authorization is rejected before credential input is processed")
    func staleRevisionPrecedesEmptyInput() async {
        // A fresh metadata-only namespace cannot refer to a user's session.
        // Empty input additionally guarantees no credential validation or store
        // access even if the stale guard regresses; the result still detects it.
        let pluginID = "fixture.conditional.\(UUID().uuidString.lowercased())"
        let manager = PlatformSessionManager.shared
        let before = await manager.metadataRevision(pluginId: pluginID)

        let result = await manager.loginWithCookieIfUnchanged(
            pluginId: pluginID,
            cookie: " \n ",
            expectedMetadataRevision: "stale.\(UUID().uuidString)"
        )

        guard case .stale = result else {
            Issue.record("Expected stale authorization to take precedence over invalid input")
            return
        }
        let after = await manager.metadataRevision(pluginId: pluginID)
        #expect(after == before)
    }

    @Test("invalid empty input does not mutate the captured metadata revision")
    func emptyInputLeavesRevisionUnchanged() async {
        let pluginID = "fixture.conditional.\(UUID().uuidString.lowercased())"
        let manager = PlatformSessionManager.shared
        let before = await manager.metadataRevision(pluginId: pluginID)

        let result = await manager.loginWithCookieIfUnchanged(
            pluginId: pluginID,
            cookie: "\t\n ",
            expectedMetadataRevision: before
        )

        guard case .completed(.invalid) = result else {
            Issue.record("Expected empty input to fail without committing a session")
            return
        }
        let after = await manager.metadataRevision(pluginId: pluginID)
        #expect(after == before)
    }
}
