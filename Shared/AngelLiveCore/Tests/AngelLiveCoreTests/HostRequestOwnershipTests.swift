import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Host request ownership")
@MainActor
struct HostRequestOwnershipTests {
    @Test("category requests completing out of order retain their own results and loading state")
    func categoryResponsesStayWithTheirOwner() async {
        let firstGate = RequestGate<[LiveModel]>()
        let secondGate = RequestGate<[LiveModel]>()
        let first = CategoryRoomListModel { _ in try await firstGate.request() }
        let second = CategoryRoomListModel { _ in try await secondGate.request() }
        let firstTask = Task { await first.load() }
        await firstGate.waitForStarted(1)
        let secondTask = Task { await second.load() }
        await secondGate.waitForStarted(1)
        secondGate.finish(.success([room("new-category")]))
        await secondTask.value
        #expect(!second.isLoading)
        #expect(first.isLoading)
        firstGate.finish(.success([room("old-category")]))
        await firstTask.value
        #expect(first.rooms.map(\.roomId) == ["old-category"])
        #expect(second.rooms.map(\.roomId) == ["new-category"])
    }

    @Test("failed or cancelled pagination retries the same page and ignores late cancelled results")
    func pageCommitsOnlyAfterSuccess() async {
        let gate = RequestGate<[LiveModel]>()
        var requestedPages: [Int] = []
        let model = CategoryRoomListModel { page in
            requestedPages.append(page)
            return try await gate.request()
        }
        let first = Task { await model.load() }
        await gate.waitForStarted(1)
        gate.finish(.success([room("page-one")]))
        await first.value

        let failure = Task { await model.loadMore() }
        await gate.waitForStarted(2)
        gate.finish(.failure(FixtureError.offline))
        await failure.value
        #expect(model.error != nil)

        let cancelled = Task { await model.loadMore() }
        await gate.waitForStarted(3)
        cancelled.cancel()
        gate.finish(.success([room("cancelled-page")]))
        await cancelled.value
        #expect(model.rooms.map(\.roomId) == ["page-one"])

        let retry = Task { await model.loadMore() }
        await gate.waitForStarted(4)
        gate.finish(.success([room("page-two")]))
        await retry.value
        #expect(requestedPages == [1, 2, 2, 2])
        #expect(model.rooms.map(\.roomId) == ["page-one", "page-two"])
        #expect(model.error == nil)
    }

    @Test("a repeated category load does not start a second request")
    func categoryRequestsDoNotOverlap() async {
        let gate = RequestGate<[LiveModel]>()
        let model = CategoryRoomListModel { _ in try await gate.request() }
        let load = Task { await model.load() }
        await gate.waitForStarted(1)
        await model.loadMore()
        await model.load()
        #expect(gate.started == 1)
        gate.finish(.success([]))
        await load.value
        #expect(!model.hasMore)
        await model.loadMore()
        #expect(gate.started == 1)
    }

    @Test("slow live status polling merges timer ticks and emits current-room end only once")
    func pollingCoalescesAndEndsOnce() async throws {
        let gate = RequestGate<LiveState>()
        var ended = 0
        let session = LiveStatusPollingSession(check: { try await gate.request() }, onEnded: { ended += 1 })
        session.poll()
        let pending = try #require(session.task)
        await gate.waitForStarted(1)
        session.poll()
        session.poll()
        #expect(gate.started == 1)
        gate.finish(.success(.close))
        await pending.value
        #expect(ended == 1)
        session.poll()
        #expect(gate.started == 1)
    }

    @Test("a stopped room cannot end its replacement even when its request ignores cancellation",
          arguments: [LiveState.close, .unknow])
    func retiredRoomCannotCloseNewRoom(_ lateState: LiveState) async throws {
        let oldGate = RequestGate<LiveState>()
        let newGate = RequestGate<LiveState>()
        var ended = 0
        let old = LiveStatusPollingSession(check: { try await oldGate.request() }, onEnded: { ended += 1 })
        old.poll()
        let oldTask = try #require(old.task)
        await oldGate.waitForStarted(1)
        old.stop()
        let current = LiveStatusPollingSession(check: { try await newGate.request() }, onEnded: { ended += 1 })
        current.poll()
        let currentTask = try #require(current.task)
        await newGate.waitForStarted(1)
        oldGate.finish(.success(lateState))
        await oldTask.value
        #expect(ended == 0)
        newGate.finish(.success(.live))
        await currentTask.value
        #expect(ended == 0)
        current.stop()
    }

    @Test("a failed poll releases its slot for the next timer tick")
    func pollingRecoversAfterRequestError() async throws {
        let gate = RequestGate<LiveState>()
        var failures = 0
        var ended = 0
        let session = LiveStatusPollingSession(
            check: { try await gate.request() }, onEnded: { ended += 1 }, onFailure: { _ in failures += 1 }
        )
        session.poll()
        let first = try #require(session.task)
        await gate.waitForStarted(1)
        gate.finish(.failure(FixtureError.offline))
        await first.value
        session.poll()
        let retry = try #require(session.task)
        await gate.waitForStarted(2)
        gate.finish(.success(.live))
        await retry.value
        #expect(failures == 1)
        #expect(ended == 0)
        session.stop()
    }

    private func room(_ id: String) -> LiveModel {
        LiveModel(userName: "fixture", roomTitle: id, roomCover: "", userHeadImg: "",
                  liveType: LiveType(rawValue: "fixture.plugin")!, liveState: nil,
                  userId: id, roomId: id, liveWatchedCount: nil)
    }
}

private enum FixtureError: Error { case offline }

/// Intentionally ignores task cancellation so tests exercise late-result guards.
@MainActor
private final class RequestGate<Value: Sendable> {
    private(set) var started = 0
    private var response: CheckedContinuation<Value, any Error>?
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func request() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            precondition(response == nil)
            response = continuation
            started += 1
            let ready = observers.filter { $0.0 <= started }
            observers.removeAll { $0.0 <= started }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForStarted(_ count: Int) async {
        if started >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func finish(_ result: Result<Value, any Error>) {
        let continuation = response
        response = nil
        continuation?.resume(with: result)
    }
}
