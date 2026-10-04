import Testing
@testable import AngelLiveCore

@Suite("Search request ownership")
@MainActor
struct SearchRequestModelTests {
    @Test func newerSuccessAndErrorWinOverOlderCompletions() async {
        let gate = SearchRequestGate()
        var accepted: [String] = []
        let model = SearchRequestModel(fetch: gate.fetch) { request, _ in
            accepted.append(request.input)
        }
        model.submit(input: "a", kind: .keyword)
        let first = model.pendingTask
        await gate.waitForStarted(1)
        model.submit(input: "b", kind: .keyword)
        let second = model.pendingTask
        await gate.waitForStarted(2)
        gate.finish(1, .success([room("b")]))
        await second?.value
        gate.finish(0, .failure(FixtureSearchError.failed))
        await first?.value
        #expect(model.rooms == [room("b")])
        #expect(model.error == nil)
        #expect(!model.isLoading)
        #expect(accepted == ["b"])
    }

    @Test func clearAndKindChangeRejectLateResults() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "old", kind: .keyword)
        let old = model.pendingTask
        await gate.waitForStarted(1)
        model.clear()
        gate.finish(0, .success([room("old")]))
        await old?.value
        #expect(model.rooms.isEmpty)
        #expect(!model.hasSearched)

        model.submit(input: "keyword", kind: .keyword)
        let keyword = model.pendingTask
        await gate.waitForStarted(2)
        model.submit(input: "share", kind: .share)
        let share = model.pendingTask
        await gate.waitForStarted(3)
        gate.finish(2, .success([room("share")]))
        await share?.value
        gate.finish(1, .success([room("keyword")]))
        await keyword?.value
        #expect(model.rooms == [room("share")])
        #expect(!model.hasMore)
    }

    @Test func cancelPreservesCommittedDataAndRejectsInflightResult() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "kept", kind: .keyword)
        let initial = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success([room("kept")]))
        await initial?.value
        model.loadMore()
        let late = model.pendingTask
        await gate.waitForStarted(2)
        model.cancel()
        gate.finish(1, .success([room("late")]))
        await late?.value
        #expect(model.rooms == [room("kept")])
        #expect(!model.isLoading)
    }

    @Test func failedPageDoesNotAdvanceAndRetryMergesOnce() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "query", kind: .keyword)
        let first = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success([room("one")]))
        await first?.value
        model.loadMore()
        model.loadMore()
        await gate.waitForStarted(2)
        let failedPage = model.pendingTask
        #expect(gate.requests.map(\.page) == [1, 2])
        gate.finish(1, .failure(FixtureSearchError.failed))
        await failedPage?.value
        model.loadMore()
        let retry = model.pendingTask
        await gate.waitForStarted(3)
        #expect(gate.requests.map(\.page) == [1, 2, 2])
        gate.finish(2, .success([room("one"), room("two")]))
        await retry?.value
        #expect(model.rooms == [room("one"), room("two")])
    }

    @Test func underlyingCancellationReturnsToIdleAndAllowsNextSubmit() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "cancelled", kind: .keyword)
        let cancelled = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .failure(CancellationError()))
        await cancelled?.value
        #expect(!model.isLoading)
        #expect(model.error == nil)

        model.submit(input: "next", kind: .keyword)
        let next = model.pendingTask
        await gate.waitForStarted(2)
        gate.finish(1, .success([room("next")]))
        await next?.value
        #expect(model.rooms == [room("next")])
        #expect(!model.isLoading)
    }

    @Test func oldPageCannotAppendToNewQuery() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "old", kind: .keyword)
        let oldFirst = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success([room("old-1")]))
        await oldFirst?.value
        model.loadMore()
        let oldPage = model.pendingTask
        await gate.waitForStarted(2)
        model.submit(input: "new", kind: .keyword)
        let newFirst = model.pendingTask
        await gate.waitForStarted(3)
        gate.finish(2, .success([room("new-1")]))
        await newFirst?.value
        gate.finish(1, .success([room("old-2")]))
        await oldPage?.value
        #expect(model.rooms == [room("new-1")])
    }

    @Test func shareAndBlankInputsNeverPaginateOrFetchBlank() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        model.submit(input: "   ", kind: .keyword)
        #expect(gate.requests.isEmpty)
        model.submit(input: "share", kind: .share)
        let share = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success([room("share")]))
        await share?.value
        model.loadMore()
        #expect(gate.requests.count == 1)
        #expect(!model.hasMore)
    }

    @Test func liveStateUpdateUsesNamespacedIdentityAndIgnoresRemovedRoom() async {
        let gate = SearchRequestGate()
        let model = SearchRequestModel(fetch: gate.fetch)
        let firstPlugin = room("same", plugin: "fixture.one")
        let secondPlugin = room("same", plugin: "fixture.two")
        model.submit(input: "query", kind: .keyword)
        let task = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success([firstPlugin, secondPlugin]))
        await task?.value

        model.updateRoomLiveState(id: firstPlugin.id, state: "1")
        #expect(model.rooms[0].liveState == "1")
        #expect(model.rooms[1].liveState == nil)
        model.updateRoomLiveState(id: "fixture.missing-same", state: "1")
        #expect(model.rooms.count == 2)
        model.clear()
        model.updateRoomLiveState(id: firstPlugin.id, state: "0")
        #expect(model.rooms.isEmpty)
    }

    @Test func lateAuthenticationCannotPolluteNewQuery() async {
        let gate = SearchOutcomeGate()
        let model = SearchRequestModel(fetchOutcome: gate.fetch)
        model.submit(input: "old", kind: .keyword)
        let old = model.pendingTask
        await gate.waitForStarted(1)
        model.submit(input: "new", kind: .keyword)
        let new = model.pendingTask
        await gate.waitForStarted(2)
        gate.finish(1, .success(RoomSearchOutcome(rooms: [room("new")])))
        await new?.value
        gate.finish(0, .success(RoomSearchOutcome(
            rooms: [],
            authenticationRequiredPluginIDs: ["fixture.old"]
        )))
        await old?.value
        #expect(model.rooms == [room("new")])
        #expect(model.authenticationRequiredPluginIDs.isEmpty)
        #expect(model.error == nil)
    }

    @Test func authenticationOutcomeIsBlockingOnlyWhenItHasNoRooms() async {
        let gate = SearchOutcomeGate()
        let model = SearchRequestModel(fetchOutcome: gate.fetch)
        model.submit(input: "partial", kind: .keyword)
        let partial = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success(RoomSearchOutcome(
            rooms: [room("visible")],
            authenticationRequiredPluginIDs: ["fixture.gated"]
        )))
        await partial?.value
        #expect(model.rooms == [room("visible")])
        #expect(model.error == nil)
        #expect(model.authenticationRequiredPluginIDs == ["fixture.gated"])

        model.submit(input: "blocked", kind: .keyword)
        let blocked = model.pendingTask
        await gate.waitForStarted(2)
        gate.finish(1, .success(RoomSearchOutcome(
            rooms: [],
            authenticationRequiredPluginIDs: ["fixture.gated"]
        )))
        await blocked?.value
        #expect(model.error?.isAuthRequired == true)
        #expect(model.error?.authRequiredPluginIDs == ["fixture.gated"])
    }

    @Test func paginationAuthenticationKeepsVisibleFirstPageNonBlocking() async {
        let gate = SearchOutcomeGate()
        let model = SearchRequestModel(fetchOutcome: gate.fetch)
        model.submit(input: "query", kind: .keyword)
        let first = model.pendingTask
        await gate.waitForStarted(1)
        gate.finish(0, .success(RoomSearchOutcome(rooms: [room("page-one")])))
        await first?.value
        model.loadMore()
        let second = model.pendingTask
        await gate.waitForStarted(2)
        gate.finish(1, .success(RoomSearchOutcome(
            rooms: [],
            authenticationRequiredPluginIDs: ["fixture.gated"]
        )))
        await second?.value
        #expect(model.rooms == [room("page-one")])
        #expect(model.error == nil)
        #expect(model.authenticationRequiredPluginIDs == ["fixture.gated"])
        #expect(!model.hasMore)
    }

    private func room(_ id: String, plugin: String = "fixture.plugin") -> LiveModel {
        LiveModel(userName: "fixture", roomTitle: id, roomCover: "", userHeadImg: "",
                  liveType: LiveType(rawValue: plugin)!, liveState: nil,
                  userId: id, roomId: id, liveWatchedCount: nil)
    }

}

private enum FixtureSearchError: Error { case failed }

@MainActor
private final class SearchRequestGate {
    private(set) var requests: [RoomSearchRequest] = []
    private var continuations: [Int: CheckedContinuation<[LiveModel], any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetch(_ request: RoomSearchRequest) async throws -> [LiveModel] {
        let index = requests.count
        requests.append(request)
        let ready = waiters.filter { $0.0 <= requests.count }
        waiters.removeAll { $0.0 <= requests.count }
        ready.forEach { $0.1.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[index] = $0 }
        } onCancel: {
            // Deliberately ignore cancellation to prove the model's generation guard.
        }
    }

    func waitForStarted(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int, _ result: Result<[LiveModel], any Error>) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        continuation.resume(with: result)
    }
}

@MainActor
private final class SearchOutcomeGate {
    private var started = 0
    private var continuations: [Int: CheckedContinuation<RoomSearchOutcome, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetch(_ request: RoomSearchRequest) async throws -> RoomSearchOutcome {
        _ = request
        let index = started
        started += 1
        let ready = waiters.filter { $0.0 <= started }
        waiters.removeAll { $0.0 <= started }
        ready.forEach { $0.1.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[index] = $0 }
        } onCancel: {}
    }

    func waitForStarted(_ count: Int) async {
        if started >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int, _ result: Result<RoomSearchOutcome, any Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}
