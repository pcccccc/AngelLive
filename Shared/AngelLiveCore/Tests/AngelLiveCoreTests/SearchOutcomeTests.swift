import Testing
@testable import AngelLiveCore

@Suite("Search authentication outcomes")
struct SearchOutcomeTests {
    @Test func pluginContextCannotBecomeTrustedRecoveryIdentity() {
        let pluginError = Self.authError(claimedPluginID: "fixture.forged")
        #expect(pluginError.isAuthRequired)
        #expect(pluginError.authRequiredPluginIDs.isEmpty)
        let request = AuthenticationRecoveryRequest(
            pluginIDs: ["fixture.one", "fixture.one", "", "fixture.two"]
        )
        #expect(request.pluginIDs == ["fixture.one", "fixture.two"])
    }

    @Test func keywordKeepsPartialRoomsAndTrustedAuthenticationOwner() async throws {
        let open = Self.platform("fixture.open")
        let gated = Self.platform("fixture.gated")
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: [open, gated], keyword: "query", page: 1
        ) { platform, _, _ in
            if platform.pluginId == gated.pluginId {
                throw Self.authError(claimedPluginID: "fixture.forged")
            }
            return [Self.room("result", pluginID: open.pluginId)]
        }
        #expect(outcome.rooms.map(\.roomId) == ["result"])
        #expect(outcome.authenticationRequiredPluginIDs == [gated.pluginId])
    }

    @Test func keywordReturnsAuthenticationWhenNoPlatformHasRooms() async throws {
        let first = Self.platform("fixture.first")
        let second = Self.platform("fixture.second")
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: [first, second], keyword: "query", page: 1
        ) { platform, _, _ in
            if platform.pluginId == first.pluginId { throw FixtureOutcomeError.offline }
            throw Self.authError(claimedPluginID: "fixture.forged")
        }
        #expect(outcome.rooms.isEmpty)
        #expect(outcome.authenticationRequiredPluginIDs == [second.pluginId])
    }

    @Test func keywordKeepsLegacyEmptyResultForOrdinaryFailures() async throws {
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: [Self.platform("fixture.one"), Self.platform("fixture.two")],
            keyword: "query",
            page: 1
        ) { _, _, _ in
            throw FixtureOutcomeError.offline
        }
        #expect(outcome.rooms.isEmpty)
        #expect(outcome.authenticationRequiredPluginIDs.isEmpty)
    }

    @Test func keywordPropagatesCancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await LiveService.searchRoomsWithOutcome(
                platforms: [Self.platform("fixture.cancelled")], keyword: "query", page: 1
            ) { _, _, _ in
                throw CancellationError()
            }
        }
    }

    @Test func sharePrefersEarlierAuthenticationOverLaterOrdinaryFailure() async throws {
        let first = Self.platform("fixture.first")
        let second = Self.platform("fixture.second")
        let outcome = try await ApiManager.fetchSearchWithShareCodeOutcome(
            shareCode: "fixture",
            platforms: [first, second]
        ) { platform, _ in
            if platform.pluginId == first.pluginId {
                throw Self.authError(claimedPluginID: "fixture.forged")
            }
            throw FixtureOutcomeError.notFound
        }
        #expect(outcome.rooms.isEmpty)
        #expect(outcome.authenticationRequiredPluginIDs == [first.pluginId])
    }

    @Test func shareSuccessWinsOverEarlierAuthentication() async throws {
        let first = Self.platform("fixture.first")
        let second = Self.platform("fixture.second")
        let resolved = Self.room("resolved", pluginID: second.pluginId)
        let outcome = try await ApiManager.fetchSearchWithShareCodeOutcome(
            shareCode: "fixture",
            platforms: [first, second]
        ) { platform, _ in
            if platform.pluginId == first.pluginId {
                throw Self.authError(claimedPluginID: "fixture.forged")
            }
            return resolved
        }
        #expect(outcome.rooms == [resolved])
        #expect(outcome.authenticationRequiredPluginIDs.isEmpty)
    }

    @Test func shareKeepsMultipleAuthenticationOwnersInCandidateOrder() async throws {
        let first = Self.platform("fixture.first")
        let second = Self.platform("fixture.second")
        let outcome = try await ApiManager.fetchSearchWithShareCodeOutcome(
            shareCode: "fixture",
            platforms: [first, second]
        ) { _, _ in
            throw Self.authError(claimedPluginID: "fixture.forged")
        }
        #expect(outcome.authenticationRequiredPluginIDs == [first.pluginId, second.pluginId])
    }

    @Test func sharePropagatesCancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await ApiManager.fetchSearchWithShareCodeOutcome(
                shareCode: "fixture",
                platforms: [Self.platform("fixture.cancelled")]
            ) { _, _ in
                throw CancellationError()
            }
        }
    }

    private static func platform(_ pluginID: String) -> LiveParseJSPlatform {
        LiveParseJSPlatform(pluginId: pluginID, liveTypes: [LiveType(rawValue: pluginID)!])
    }

    private static func room(_ id: String, pluginID: String) -> LiveModel {
        LiveModel(userName: "fixture", roomTitle: id, roomCover: "", userHeadImg: "",
                  liveType: LiveType(rawValue: pluginID)!, liveState: nil,
                  userId: id, roomId: id, liveWatchedCount: nil)
    }

    private static func authError(claimedPluginID: String) -> LiveParsePluginError {
        .standardized(.init(
            code: .authRequired,
            message: "login required",
            context: ["pluginId": claimedPluginID]
        ))
    }
}

private enum FixtureOutcomeError: Error {
    case offline
    case notFound
}
