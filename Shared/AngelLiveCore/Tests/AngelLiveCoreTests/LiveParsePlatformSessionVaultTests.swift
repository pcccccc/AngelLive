import Foundation
import Testing

@testable import AngelLiveCore

@Suite("LiveParse platform session vault", .serialized)
struct LiveParsePlatformSessionVaultTests {
    @Test("republishing an unchanged persisted credential preserves its revision")
    func unchangedCredentialKeepsRevision() throws {
        let pluginId = "vault-revision-\(UUID().uuidString.lowercased()).plugin"
        let snapshot = LiveParsePlatformSessionVault.session(for: pluginId)
        defer { LiveParsePlatformSessionVault.restore(platformId: pluginId, session: snapshot) }

        LiveParsePlatformSessionVault.update(
            platformId: pluginId,
            cookie: "session=committed",
            uid: "user-1"
        )
        let committed = try #require(LiveParsePlatformSessionVault.session(for: pluginId))
        let committedRevision = LiveParsePlatformSessionVault.revision(for: pluginId)

        // This is the same publication performed by a queued credential-status
        // check while another credential operation is waiting on the per-plugin barrier.
        LiveParsePlatformSessionVault.update(
            platformId: pluginId,
            cookie: "session=committed",
            uid: "user-1"
        )

        let republished = try #require(LiveParsePlatformSessionVault.session(for: pluginId))
        #expect(republished.updatedAt == committed.updatedAt)
        #expect(republished.uid == "user-1")
        #expect(LiveParsePlatformSessionVault.revision(for: pluginId) == committedRevision)
    }

    @Test("a changed credential still advances the revision")
    func changedCredentialAdvancesRevision() throws {
        let pluginId = "vault-change-\(UUID().uuidString.lowercased()).plugin"
        let snapshot = LiveParsePlatformSessionVault.session(for: pluginId)
        defer { LiveParsePlatformSessionVault.restore(platformId: pluginId, session: snapshot) }

        LiveParsePlatformSessionVault.update(
            platformId: pluginId,
            cookie: "session=old",
            uid: "user-1"
        )
        let oldSession = try #require(LiveParsePlatformSessionVault.session(for: pluginId))
        let oldRevision = LiveParsePlatformSessionVault.revision(for: pluginId)

        LiveParsePlatformSessionVault.update(
            platformId: pluginId,
            cookie: "session=new",
            uid: "user-1"
        )
        let newSession = try #require(LiveParsePlatformSessionVault.session(for: pluginId))

        #expect(newSession.cookie == "session=new")
        #expect(newSession.revision != oldSession.revision)
        #expect(LiveParsePlatformSessionVault.revision(for: pluginId) != oldRevision)
    }
}
