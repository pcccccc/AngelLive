import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Favorite refresh request policy")
struct FavoriteRefreshRequestPolicyTests {
    @Test("default policy owns one 20 second total budget")
    func defaultBudgetIsTwentySeconds() {
        #expect(FavoriteRefreshRequestPolicy.default.totalBudget == .seconds(20))
        #expect(FavoriteRefreshRequestPolicy.default.notFoundRetryDelay == .milliseconds(400))
    }

    @Test("fast success performs one attempt")
    func fastSuccessUsesOneAttempt() async throws {
        let old = favoriteRoom(liveState: "0")
        let refreshed = favoriteRoom(liveState: "1")
        let fetcher = ScriptedFavoriteFetcher([.success(refreshed)])
        let timing = DeterministicFavoriteTiming()
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        let result = try await executor.fetch(liveModel: old, pluginId: "test-plugin")

        #expect(result.liveState == "1")
        #expect(await fetcher.callCount == 1)
        #expect(await timing.timeoutBudgets == [.seconds(20)])
    }

    @Test("NOT_FOUND retries once and the second attempt only receives remaining budget")
    func notFoundUsesOneShortRetryWithinSharedBudget() async throws {
        let old = favoriteRoom(liveState: "1")
        let refreshed = favoriteRoom(liveState: "0")
        let fetcher = ScriptedFavoriteFetcher([
            .standard(.notFound),
            .success(refreshed)
        ])
        let timing = DeterministicFavoriteTiming(operationDurations: [.seconds(12), .zero])
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        let result = try await executor.fetch(liveModel: old, pluginId: "test-plugin")

        #expect(result.liveState == "0")
        #expect(await fetcher.callCount == 2)
        #expect(await timing.sleeps == [.milliseconds(400)])
        #expect(await timing.timeoutBudgets == [.seconds(20), .seconds(7) + .milliseconds(600)])
    }

    @Test("a full-budget timeout never starts a second request")
    func timeoutDoesNotRetry() async throws {
        let fetcher = ScriptedFavoriteFetcher([.urlError(.timedOut)])
        let timing = DeterministicFavoriteTiming(operationDurations: [.seconds(20)])
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        let failure = try await capturedFailure {
            try await executor.fetch(liveModel: favoriteRoom(liveState: "1"), pluginId: "slow-plugin")
        }

        #expect(failure.kind == .timeout)
        #expect(failure.attempts == 1)
        #expect(failure.elapsed == .seconds(20))
        #expect(failure.underlyingError == FavoriteRefreshUnderlyingError(
            domain: NSURLErrorDomain,
            code: URLError.Code.timedOut.rawValue
        ))
        #expect(await fetcher.callCount == 1)
        #expect(await timing.timeoutBudgets == [.seconds(20)])
    }

    @Test("business errors do not use the ordinary three-attempt detail retry")
    func businessErrorDoesNotRetry() async throws {
        let fetcher = ScriptedFavoriteFetcher([.standard(.authRequired)])
        let timing = DeterministicFavoriteTiming()
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        let failure = try await capturedFailure {
            try await executor.fetch(liveModel: favoriteRoom(), pluginId: "auth-plugin")
        }

        #expect(failure.kind == .authenticationRequired)
        #expect(failure.standardCode == .authRequired)
        #expect(failure.attempts == 1)
        #expect(await fetcher.callCount == 1)
        #expect(await timing.sleeps.isEmpty)
    }

    @Test("host network envelope preserves domain code and HTTP-response flag")
    func structuredNetworkErrorSurvivesPluginBoundary() async throws {
        let context = [
            "underlyingDomain": NSURLErrorDomain,
            "underlyingCode": String(URLError.Code.cannotFindHost.rawValue),
            "receivedHTTPResponse": "false"
        ]
        let fetcher = ScriptedFavoriteFetcher([.standard(.network, context: context)])
        let timing = DeterministicFavoriteTiming()
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        let failure = try await capturedFailure {
            try await executor.fetch(liveModel: favoriteRoom(), pluginId: "dns-plugin")
        }

        #expect(failure.kind == .fastUnreachable(.dns))
        #expect(failure.underlyingError == FavoriteRefreshUnderlyingError(
            domain: NSURLErrorDomain,
            code: URLError.Code.cannotFindHost.rawValue
        ))
        #expect(!failure.receivedHTTPResponse)
        #expect(failure.pluginId == "dns-plugin")
    }

    @Test("Host HTTP transports URL errors through JavaScript as structured plugin errors")
    func hostHTTPBridgePreservesStructuredURLError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteRefreshFailingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let runtime = JSRuntime(pluginId: "bridge-test", session: session)
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                return await Host.http.request({ url: "https://favorite-refresh.invalid/status" });
              }
            };
            """)

        do {
            _ = try await runtime.callPluginFunction(name: "probe")
            Issue.record("expected structured Host HTTP failure")
        } catch let error as LiveParsePluginError {
            guard case .standardized(let standard) = error else {
                Issue.record("expected standardized plugin error, got \(error)")
                return
            }
            #expect(standard.code == .network)
            #expect(standard.context["underlyingDomain"] == NSURLErrorDomain)
            #expect(standard.context["underlyingCode"] == String(URLError.Code.cannotFindHost.rawValue))
            #expect(standard.context["receivedHTTPResponse"] == "false")
            #expect(!standard.context.keys.contains("url"))
        }
    }

    @Test("generic NETWORK text is not guessed as timeout or unreachable")
    func genericNetworkErrorDoesNotUseMessageHeuristics() async throws {
        let fetcher = ScriptedFavoriteFetcher([
            .standard(.network, message: "network timed out while parsing")
        ])
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: DeterministicFavoriteTiming(),
            policy: .default
        )

        let failure = try await capturedFailure {
            try await executor.fetch(liveModel: favoriteRoom(), pluginId: "opaque-plugin")
        }

        #expect(failure.kind == .unknown)
        #expect(failure.standardCode == .network)
        #expect(failure.underlyingError == nil)
    }

    @Test("cancellation is propagated and is never retried")
    func cancellationDoesNotRetry() async {
        let fetcher = ScriptedFavoriteFetcher([.cancelled])
        let timing = DeterministicFavoriteTiming()
        let executor = FavoriteLiveInfoRequestExecutor(
            fetcher: fetcher,
            timing: timing,
            policy: .default
        )

        await #expect(throws: CancellationError.self) {
            try await executor.fetch(liveModel: favoriteRoom(), pluginId: "cancelled-plugin")
        }
        #expect(await fetcher.callCount == 1)
        #expect(await timing.sleeps.isEmpty)
    }

    @Test("failed refresh preserves the prior live state and identity")
    func failedRefreshKeepsOldRoomSnapshot() async throws {
        let old = favoriteRoom(liveState: "1")
        let fetcher = ScriptedFavoriteFetcher([.standard(.timeout)])
        let model = FavoriteStateModel(fetcher: fetcher)

        let result = try await model.syncStreamerLiveStates(members: [old])
        let room = try #require(result.rooms.first)

        #expect(room.liveState == "1")
        #expect(room.roomId == old.roomId)
        #expect(room.userId == old.userId)
        #expect(result.identityChanges.isEmpty)
        #expect(await fetcher.callCount == 1)
    }
}

private actor ScriptedFavoriteFetcher: FavoriteLiveInfoFetching {
    enum Step: Sendable {
        case success(LiveModel)
        case standard(
            LiveParsePluginStandardErrorCode,
            message: String = "test failure",
            context: [String: String] = [:]
        )
        case urlError(URLError.Code)
        case cancelled
    }

    private var steps: [Step]
    private(set) var callCount = 0

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func fetchLatestLiveInfo(for liveModel: LiveModel) async throws -> LiveModel {
        callCount += 1
        guard !steps.isEmpty else {
            throw LiveParsePluginError.standardized(.init(code: .unknown, message: "missing test step"))
        }
        let step = steps.removeFirst()
        switch step {
        case .success(let room):
            return room
        case .standard(let code, let message, let context):
            throw LiveParsePluginError.standardized(.init(code: code, message: message, context: context))
        case .urlError(let code):
            throw URLError(code)
        case .cancelled:
            throw CancellationError()
        }
    }
}

private actor DeterministicFavoriteTiming: FavoriteRefreshTiming {
    private var current: Duration = .zero
    private var operationDurations: [Duration]
    private(set) var timeoutBudgets: [Duration] = []
    private(set) var sleeps: [Duration] = []

    init(operationDurations: [Duration] = []) {
        self.operationDurations = operationDurations
    }

    func now() async -> Duration {
        current
    }

    func sleep(for duration: Duration) async throws {
        sleeps.append(duration)
        current += duration
    }

    func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        timeoutBudgets.append(duration)
        if !operationDurations.isEmpty {
            current += operationDurations.removeFirst()
        }
        return try await operation()
    }
}

private func capturedFailure(
    _ operation: () async throws -> LiveModel
) async throws -> FavoriteRefreshFailure {
    do {
        _ = try await operation()
        Issue.record("expected FavoriteRefreshFailure")
        throw TestFailure.missingExpectedError
    } catch let failure as FavoriteRefreshFailure {
        return failure
    }
}

private enum TestFailure: Error {
    case missingExpectedError
}

private final class FavoriteRefreshFailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "favorite-refresh.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
    }

    override func stopLoading() {}
}

private func favoriteRoom(liveState: String? = "0") -> LiveModel {
    LiveModel(
        userName: "Streamer",
        roomTitle: "Room",
        roomCover: "cover",
        userHeadImg: "avatar",
        liveType: LiveType(rawValue: "3")!,
        liveState: liveState,
        userId: "user-1",
        roomId: "room-1",
        liveWatchedCount: nil
    )
}
