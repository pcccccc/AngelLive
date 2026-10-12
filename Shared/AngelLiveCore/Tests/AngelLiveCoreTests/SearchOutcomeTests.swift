import Testing
@testable import AngelLiveCore

@Suite("Search authentication outcomes")
struct SearchOutcomeTests {
    @Test func keywordDefaultSearchesEveryAvailablePlatform() async throws {
        let platforms = [Self.platform("source-a"), Self.platform("source-b")]
        let calls = SearchPlatformCalls()
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: platforms, keyword: "query", page: 1
        ) { platform, _, _ in
            await calls.record(platform.pluginId)
            return [Self.room(platform.pluginId, pluginID: platform.pluginId)]
        }
        #expect(await calls.pluginIDs.sorted() == ["source-a", "source-b"])
        #expect(outcome.rooms.map(\.roomId).sorted() == ["source-a", "source-b"])
    }

    @Test func keywordSelectionCallsOnlySelectedAvailablePlatform() async throws {
        let calls = SearchPlatformCalls()
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: [Self.platform("source-a"), Self.platform("source-b")],
            keyword: "query", page: 2, pluginID: "source-b"
        ) { platform, keyword, page in
            await calls.record(platform.pluginId)
            #expect(keyword == "query")
            #expect(page == 2)
            throw Self.authError(claimedPluginID: "fixture.forged")
        }
        #expect(await calls.pluginIDs == ["source-b"])
        #expect(outcome.rooms.isEmpty)
        #expect(outcome.authenticationRequiredPluginIDs == ["source-b"])
    }

    @Test func keywordUnavailableSelectionDoesNotFallBack() async throws {
        let calls = SearchPlatformCalls()
        let outcome = try await LiveService.searchRoomsWithOutcome(
            platforms: [Self.platform("source-a")],
            keyword: "query", page: 1, pluginID: "source-b"
        ) { platform, _, _ in
            await calls.record(platform.pluginId)
            return []
        }
        #expect(await calls.pluginIDs.isEmpty)
        #expect(outcome.rooms.isEmpty)
        #expect(outcome.authenticationRequiredPluginIDs.isEmpty)
    }

    @Test func shareSelectionKeepsOnlySelectedCandidateAndItsAuthenticationOwner() async throws {
        var calls: [String] = []
        let outcome = try await ApiManager.fetchSearchWithShareCodeOutcome(
            shareCode: "fixture",
            platforms: [Self.platform("source-a"), Self.platform("source-b")],
            pluginID: "source-b"
        ) { platform, _ in
            calls.append(platform.pluginId)
            throw Self.authError(claimedPluginID: "fixture.forged")
        }
        #expect(calls == ["source-b"])
        #expect(outcome.authenticationRequiredPluginIDs == ["source-b"])
    }

    @Test func shareSelectionOutsideMatchedCandidatesDoesNotFallBack() async {
        var calls: [String] = []
        await #expect(throws: (any Error).self) {
            _ = try await ApiManager.fetchSearchWithShareCodeOutcome(
                shareCode: "fixture",
                platforms: [Self.platform("source-a")],
                pluginID: "source-b"
            ) { platform, _ in
                calls.append(platform.pluginId)
                return Self.room("resolved", pluginID: platform.pluginId)
            }
        }
        #expect(calls.isEmpty)
    }

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

private actor SearchPlatformCalls {
    private(set) var pluginIDs: [String] = []

    func record(_ pluginID: String) {
        pluginIDs.append(pluginID)
    }
}
