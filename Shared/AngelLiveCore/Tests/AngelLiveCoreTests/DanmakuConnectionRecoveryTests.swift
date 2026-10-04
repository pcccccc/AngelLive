import Foundation
import Testing
@preconcurrency import Starscream
@testable import AngelLiveCore

@Suite("Danmaku connection recovery")
@MainActor
struct DanmakuConnectionRecoveryTests {
    @Test func inboundFramesDoNotPostponeHeartbeat() {
        let clock = ManualDanmakuClock()
        let timer = DanmakuConnectionTimer(schedule: clock.schedule)
        var ticks = 0
        let plan = LiveParseDanmakuTimerPlan(mode: .heartbeat, intervalMs: 30_000)
        timer.update(plan) { ticks += 1 }
        for _ in 0..<6 {
            clock.advance(5)
            timer.update(plan) { ticks += 1 }
            timer.update(nil) { ticks += 1 }
        }
        #expect(ticks == 1)
        clock.advance(30)
        #expect(ticks == 2)
        timer.stop()
    }

    @Test func explicitOffStopsAndSamePlanCanRestart() {
        let clock = ManualDanmakuClock()
        let timer = DanmakuConnectionTimer(schedule: clock.schedule)
        var ticks = 0
        let plan = LiveParseDanmakuTimerPlan(mode: .heartbeat, intervalMs: 1_000)
        timer.update(plan) { ticks += 1 }
        timer.update(.init(mode: .off, intervalMs: nil)) { ticks += 1 }
        clock.advance(10)
        #expect(ticks == 0)
        timer.update(plan) { ticks += 1 }
        clock.advance(1)
        #expect(ticks == 1)
        timer.stop()
    }

    @Test func changedPlanReschedulesButRetiredCallbackIsIgnored() throws {
        let clock = ManualDanmakuClock()
        let timer = DanmakuConnectionTimer(schedule: clock.schedule)
        var ticks = 0
        timer.update(.init(mode: .heartbeat, intervalMs: 30_000)) { ticks += 1 }
        let retired = try #require(clock.entries.values.first).action
        timer.update(.init(mode: .heartbeat, intervalMs: 10_000)) { ticks += 1 }
        retired()
        #expect(ticks == 0)
        clock.advance(10)
        #expect(ticks == 1)
        timer.stop()
    }

    @Test func outageLongerThanEightAttemptsStillRetriesAtBoundedRate() {
        var policy = DanmakuReconnectPolicy()
        #expect(policy.delay == 2)
        for _ in 0..<100 {
            #expect((2...60).contains(policy.delay))
            policy.beginAttempt()
        }
        #expect(policy.attempts == 100)
        #expect(policy.delay == 60)
        policy.connected()
        #expect(policy.attempts == 0)
        #expect(policy.delay == 2)
    }

    @Test func connectionIntentSurvivesOutageAndRepeatedSuspension() {
        var intent = DanmakuConnectionIntent()
        let requested = intent.request()
        #expect(requested)
        intent.suspend()
        intent.suspend()
        let requestedWhileSuspended = intent.request()
        #expect(!requestedWhileSuspended)
        let resumed = intent.resume()
        #expect(resumed)
        intent.stop()
        intent.suspend()
        let resumedAfterStop = intent.resume()
        #expect(!resumedAfterStop)
    }

    @Test func framesAndTicksApplyInOrderAndTicksCoalesce() async throws {
        let queue = DanmakuConnectionWorkQueue()
        let gate = DeferredDanmakuResult()
        var applied: [Int] = []
        queue.enqueue(operation: { await gate.value() }) { _ in applied.append(1) }
        await gate.waitUntilStarted()
        queue.enqueue(key: "tick", operation: { try emptyResult() }) { _ in applied.append(2) }
        queue.enqueue(key: "tick", operation: { try emptyResult() }) { _ in applied.append(99) }
        queue.enqueue(operation: { try emptyResult() }) { _ in applied.append(3) }
        #expect(applied.isEmpty)
        await gate.resolve(try emptyResult())
        await queue.drain()
        #expect(applied == [1, 2, 3])
    }

    @Test func retiredResultCannotAffectReplacementSession() async throws {
        let queue = DanmakuConnectionWorkQueue()
        let gate = DeferredDanmakuResult()
        var applied: [String] = []
        queue.enqueue(operation: { await gate.value() }) { _ in applied.append("old") }
        await gate.waitUntilStarted()
        let oldWork = queue.tail
        queue.invalidate()
        queue.enqueue(operation: { try emptyResult() }) { _ in applied.append("new") }
        await queue.drain()
        await gate.resolve(try emptyResult())
        await oldWork?.value
        #expect(applied == ["new"])
    }

    @Test func hungDriverTimesOutOnceAndCanBeReplaced() async throws {
        let clock = ManualDanmakuClock()
        let queue = DanmakuConnectionWorkQueue(timeout: 10, schedule: clock.schedule)
        let gate = DeferredDanmakuResult()
        var failures = 0
        queue.enqueue(operation: { await gate.value() }) { outcome in
            if case .failure = outcome { failures += 1 }
            queue.invalidate()
        }
        await gate.waitUntilStarted()
        let oldWork = queue.tail
        clock.advance(10)
        #expect(failures == 1)
        var replacementFinished = false
        queue.enqueue(operation: { try emptyResult() }) { _ in replacementFinished = true }
        await queue.drain()
        #expect(replacementFinished)
        await gate.resolve(try emptyResult())
        await oldWork?.value
        #expect(failures == 1)
    }

    @Test func disconnectDuringSessionCreationNeverOpensSocket() async throws {
        let gate = DeferredDanmakuResult()
        let connection = makeWebSocket()
        let engine = RecordingDanmakuEngine()
        let delegate = RecordingDanmakuDelegate()
        connection.delegate = delegate
        connection.makeDriver = { _, _, _, _ in FixtureDanmakuDriver(create: { await gate.value() }) }
        connection.makeSocket = { WebSocket(request: $0, engine: engine) }
        connection.connect()
        await gate.waitUntilStarted()
        let oldWork = connection.workQueue.tail
        connection.disconnect()
        #expect(!connection.hasPendingConsoleEntry)
        await gate.resolve(try emptyResult())
        await oldWork?.value
        #expect(engine.starts == 0)
        #expect(connection.socket == nil)
        #expect(delegate.disconnected == 0)
    }

    @Test func oldSocketEventsCannotDisconnectReplacement() async throws {
        let clock = ManualDanmakuClock()
        let connection = makeWebSocket()
        let delegate = RecordingDanmakuDelegate()
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.makeDriver = { _, _, _, _ in FixtureDanmakuDriver() }
        connection.makeSocket = { WebSocket(request: $0, engine: RecordingDanmakuEngine()) }
        connection.connect()
        await connection.workQueue.drain()
        let old = try #require(connection.socket)
        connection.didReceive(event: .connected([:]), client: old)
        await connection.workQueue.drain()
        connection.didReceive(event: .error(URLError(.networkConnectionLost)), client: old)
        clock.advance(3)
        await connection.workQueue.drain()
        let replacement = try #require(connection.socket)
        #expect(replacement !== old)
        connection.didReceive(event: .connected([:]), client: replacement)
        await connection.workQueue.drain()
        connection.didReceive(event: .disconnected("late close", 1000), client: old)
        connection.didReceive(event: .error(URLError(.cancelled)), client: old)
        #expect(connection.socket === replacement)
        #expect(delegate.connected == 2)
        #expect(delegate.disconnected == 1)
        #expect(clock.entries.values.allSatisfy { $0.interval != nil })
        connection.disconnect()
    }

    @Test func connectionWithoutPluginTimerStaysOpenWithoutPingPastNinetySeconds() async throws {
        let clock = ManualDanmakuClock()
        let connection = makeWebSocket()
        let engine = RecordingDanmakuEngine()
        let delegate = RecordingDanmakuDelegate()
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.makeDriver = { _, _, _, _ in FixtureDanmakuDriver() }
        connection.makeSocket = { WebSocket(request: $0, engine: engine) }
        connection.connect()
        await connection.workQueue.drain()
        let socket = try #require(connection.socket)
        connection.didReceive(event: .connected([:]), client: socket)
        await connection.workQueue.drain()
        clock.advance(91)
        #expect(delegate.disconnected == 0)
        #expect(connection.socket === socket)
        #expect(engine.pings.isEmpty)
        connection.disconnect()
    }

    @Test func pluginHeartbeatWritesAcrossPeriodsWithoutPingAndStopsWhenDisabled() async throws {
        let clock = ManualDanmakuClock()
        let connection = makeWebSocket()
        let engine = RecordingDanmakuEngine()
        let delegate = RecordingDanmakuDelegate()
        let heartbeat = FixtureHeartbeatWrites()
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.makeDriver = { _, _, _, _ in
            FixtureDanmakuDriver(
                onOpen: { try decodeResult(#"{"timer":{"mode":"heartbeat","intervalMs":30000}}"#) },
                onTick: { _ in try await heartbeat.next() }
            )
        }
        connection.makeSocket = { WebSocket(request: $0, engine: engine) }
        connection.connect()
        await connection.workQueue.drain()
        let socket = try #require(connection.socket)
        connection.didReceive(event: .connected([:]), client: socket)
        await connection.workQueue.drain()

        for _ in 0..<3 {
            clock.advance(30)
            await connection.workQueue.drain()
        }

        #expect(engine.textWrites == ["heartbeat-1", "heartbeat-2", "heartbeat-3"])
        #expect(engine.binaryWrites == [Data([1]), Data([2]), Data([3])])
        #expect(engine.pings.isEmpty)
        #expect(delegate.disconnected == 0)
        #expect(connection.socket === socket)

        clock.advance(30)
        await connection.workQueue.drain()
        clock.advance(91)
        await connection.workQueue.drain()
        #expect(engine.textWrites == ["heartbeat-1", "heartbeat-2", "heartbeat-3"])
        #expect(engine.binaryWrites == [Data([1]), Data([2]), Data([3])])
        #expect(engine.pings.isEmpty)
        #expect(delegate.disconnected == 0)
        #expect(connection.socket === socket)
        connection.disconnect()
    }

    @Test func createWritesWaitForSocketOpenAndAreSentOnce() async throws {
        let connection = makeWebSocket()
        let engine = RecordingDanmakuEngine()
        connection.makeSocket = { WebSocket(request: $0, engine: engine) }
        connection.makeDriver = { _, _, _, _ in
            FixtureDanmakuDriver(create: { try decodeResult(#"{"writes":[{"kind":"text","text":"join"}]}"#) })
        }
        connection.connect()
        await connection.workQueue.drain()
        #expect(engine.textWrites.isEmpty)
        let socket = try #require(connection.socket)
        connection.didReceive(event: .connected([:]), client: socket)
        await connection.workQueue.drain()
        #expect(engine.textWrites == ["join"])
        connection.disconnect()
    }

    @Test func invalidEndpointStopsAttemptAndReportsFailure() async {
        let connection = makeWebSocket(url: "wss://socket.example.invalid:0")
        let clock = ManualDanmakuClock()
        let engine = RecordingDanmakuEngine()
        let delegate = RecordingDanmakuDelegate()
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.makeSocket = { WebSocket(request: $0, engine: engine) }
        connection.makeDriver = { _, _, _, _ in FixtureDanmakuDriver() }
        connection.connect()
        await connection.workQueue.drain()
        #expect(engine.starts == 0)
        #expect(connection.socket == nil)
        #expect(delegate.disconnected == 1)
        clock.advance(30)
        #expect(clock.entries.isEmpty)
        #expect(engine.starts == 0)
        #expect(delegate.disconnected == 1)
    }

    @Test func pollingSessionFailureRetriesAndExplicitDisconnectCancelsRetry() async {
        let clock = ManualDanmakuClock()
        let plan = LiveParseDanmakuPlan(args: [:], transport: .init(kind: .httpPolling, url: "https://poll.example.invalid", polling: .init(sendOnConnect: false)), runtime: .init(driver: .pluginJSV1))
        let connection = HTTPPollingDanmakuConnection(parameters: nil, headers: nil, liveType: "fixture.plugin", pluginId: "fixture.plugin", roomId: "room", userId: nil, danmakuPlan: plan)
        let delegate = RecordingDanmakuDelegate()
        connection.delegate = delegate
        connection.schedule = clock.schedule
        var creations = 0
        connection.makeDriver = { _, _, _, _ in
            creations += 1
            return FixtureDanmakuDriver(create: { throw URLError(.notConnectedToInternet) })
        }
        connection.connect()
        await connection.workQueue.drain()
        #expect(creations == 1)
        #expect(delegate.disconnected == 1)
        clock.advance(3)
        await connection.workQueue.drain()
        #expect(creations == 2)
        #expect(delegate.disconnected == 1)
        #expect(delegate.reconnecting == [1])
        connection.disconnect()
        clock.advance(600)
        #expect(creations == 2)
        #expect(clock.entries.isEmpty)
    }

    @Test func pollingDoesNotReportConnectedUntilHTTPResponseIsProcessed() async throws {
        let clock = ManualDanmakuClock()
        let requests = RecordingPollRequestExecutor()
        let plan = LiveParseDanmakuPlan(
            args: [:],
            transport: .init(
                kind: .httpPolling,
                url: "https://poll.example.invalid",
                polling: .init(sendOnConnect: true)
            ),
            runtime: .init(driver: .pluginJSV1)
        )
        let connection = HTTPPollingDanmakuConnection(
            parameters: nil,
            headers: nil,
            liveType: "fixture.plugin",
            pluginId: "fixture.plugin",
            roomId: "room",
            userId: nil,
            danmakuPlan: plan
        )
        let delegate = RecordingDanmakuDelegate()
        let initial = try decodeResult(#"{"poll":{"url":"https://poll.example.invalid"}}"#)
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.executeRequest = requests.execute
        connection.makeDriver = { _, _, _, _ in
            FixtureDanmakuDriver(create: { initial })
        }

        connection.connect()
        await connection.workQueue.drain()
        #expect(requests.pendingCount == 1)
        #expect(delegate.connected == 0)

        requests.failNext(URLError(.notConnectedToInternet))
        #expect(delegate.connected == 0)
        #expect(delegate.disconnected == 1)

        clock.advance(3)
        await connection.workQueue.drain()
        #expect(requests.pendingCount == 1)
        requests.failNext(URLError(.networkConnectionLost))
        #expect(delegate.connected == 0)
        #expect(delegate.disconnected == 1)

        clock.advance(5)
        await connection.workQueue.drain()
        #expect(requests.pendingCount == 1)
        requests.succeedNext(Data())
        await connection.workQueue.drain()
        #expect(delegate.connected == 1)
        #expect(delegate.disconnected == 1)
        connection.disconnect()
    }

    @Test func pollingDoesNotReportConnectedWhenFirstResponseParsingFails() async throws {
        let clock = ManualDanmakuClock()
        let requests = RecordingPollRequestExecutor()
        let plan = LiveParseDanmakuPlan(
            args: [:],
            transport: .init(
                kind: .httpPolling,
                url: "https://poll.example.invalid",
                polling: .init(sendOnConnect: true)
            ),
            runtime: .init(driver: .pluginJSV1)
        )
        let connection = HTTPPollingDanmakuConnection(
            parameters: nil,
            headers: nil,
            liveType: "fixture.plugin",
            pluginId: "fixture.plugin",
            roomId: "room",
            userId: nil,
            danmakuPlan: plan
        )
        let delegate = RecordingDanmakuDelegate()
        let initial = try decodeResult(#"{"poll":{"url":"https://poll.example.invalid"}}"#)
        connection.delegate = delegate
        connection.schedule = clock.schedule
        connection.executeRequest = requests.execute
        connection.makeDriver = { _, _, _, _ in
            FixtureDanmakuDriver(
                create: { initial },
                onFrameAction: { throw URLError(.cannotParseResponse) }
            )
        }

        connection.connect()
        await connection.workQueue.drain()
        requests.succeedNext(Data("invalid".utf8))
        await connection.workQueue.drain()

        #expect(delegate.connected == 0)
        #expect(delegate.disconnected == 1)
        connection.disconnect()
    }

    @Test func retiredDriverCleanupIsOwnedReplacedAndTimedOut() async {
        let clock = ManualDanmakuClock()
        let retirement = DanmakuDriverRetirement(timeout: 10, schedule: clock.schedule)
        let first = CancellableDestroyProbe()
        let second = CancellableDestroyProbe()

        retirement.retire(
            FixtureDanmakuDriver(destroyAction: { _ in await first.run() }),
            reason: .reconnect
        )
        await first.waitUntilStarted()
        #expect(retirement.hasPendingRetirement)

        retirement.retire(
            FixtureDanmakuDriver(destroyAction: { _ in await second.run() }),
            reason: .error
        )
        await first.waitUntilCancelled()
        await second.waitUntilStarted()
        #expect(retirement.hasPendingRetirement)

        clock.advance(10)
        await second.waitUntilCancelled()
        #expect(!retirement.hasPendingRetirement)
        let firstSnapshot = await first.snapshot()
        let secondSnapshot = await second.snapshot()
        #expect(firstSnapshot == .init(started: 1, cancelled: 1, active: 0))
        #expect(secondSnapshot == .init(started: 1, cancelled: 1, active: 0))
    }

    @Test func releasingConnectionDoesNotCancelDriverCleanupBeforeItStarts() async {
        let clock = ManualDanmakuClock()
        let destroy = CancellableDestroyProbe()
        var connection: WebSocketConnection? = makeWebSocket()
        weak let releasedConnection = connection
        connection?.schedule = clock.schedule
        connection?.makeDriver = { _, _, _, _ in
            FixtureDanmakuDriver(destroyAction: { _ in await destroy.run() })
        }
        connection?.makeSocket = { WebSocket(request: $0, engine: RecordingDanmakuEngine()) }

        connection?.connect()
        await connection?.workQueue.drain()
        connection?.disconnect()
        connection = nil

        #expect(releasedConnection == nil)
        await destroy.waitUntilStarted()
        clock.advance(30)
        await destroy.waitUntilCancelled()
        let snapshot = await destroy.snapshot()
        #expect(snapshot == .init(started: 1, cancelled: 1, active: 0))
    }

    private func makeWebSocket(url: String = "wss://socket.example.invalid") -> WebSocketConnection {
        let plan = LiveParseDanmakuPlan(args: [:], transport: .init(kind: .websocket, url: url), runtime: .init(driver: .pluginJSV1))
        return WebSocketConnection(parameters: nil, headers: nil, liveType: "fixture.plugin", pluginId: "fixture.plugin", roomId: "room", userId: nil, danmakuPlan: plan)
    }
}

private func decodeResult(_ json: String) throws -> LiveParseDanmakuDriverResult {
    try JSONDecoder().decode(LiveParseDanmakuDriverResult.self, from: Data(json.utf8))
}

private func emptyResult() throws -> LiveParseDanmakuDriverResult { try decodeResult("{}") }

private struct FixtureDanmakuDriver: DanmakuRuntimeDriving {
    var create: @Sendable () async throws -> LiveParseDanmakuDriverResult = { try emptyResult() }
    var onOpen: @Sendable () async throws -> LiveParseDanmakuDriverResult = { try emptyResult() }
    var onTick: @Sendable (PluginJSDanmakuDriver.TickReason) async throws -> LiveParseDanmakuDriverResult = { _ in try emptyResult() }
    var onFrameAction: @Sendable () async throws -> LiveParseDanmakuDriverResult = { try emptyResult() }
    var destroyAction: @Sendable (PluginJSDanmakuDriver.DestroyReason) async -> Void = { _ in }
    func createSession() async throws -> LiveParseDanmakuDriverResult { try await create() }
    func onOpen() async throws -> LiveParseDanmakuDriverResult { try await onOpen() }
    func onTick(reason: PluginJSDanmakuDriver.TickReason) async throws -> LiveParseDanmakuDriverResult { try await onTick(reason) }
    func onFrame(frameType: PluginJSDanmakuDriver.IncomingFrameType, text: String?, data: Data?, statusCode: Int?, responseHeaders: [String: String]?) async throws -> LiveParseDanmakuDriverResult { try await onFrameAction() }
    func destroy(reason: PluginJSDanmakuDriver.DestroyReason) async { await destroyAction(reason) }
}

@MainActor
private final class RecordingPollRequestExecutor {
    private var completions: [@MainActor (DanmakuHTTPResponse) -> Void] = []
    private(set) var cancellations = 0
    var pendingCount: Int { completions.count }

    func execute(
        _ request: URLRequest,
        completion: @escaping @MainActor (DanmakuHTTPResponse) -> Void
    ) -> @MainActor () -> Void {
        _ = request
        completions.append(completion)
        return { [weak self] in self?.cancellations += 1 }
    }

    func failNext(_ error: Error) {
        completions.removeFirst()(.failure(error))
    }

    func succeedNext(_ data: Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://poll.example.invalid")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        completions.removeFirst()(.success((data, response)))
    }
}

private actor CancellableDestroyProbe {
    struct Snapshot: Equatable {
        let started: Int
        let cancelled: Int
        let active: Int
    }

    private var started = 0
    private var cancelled = 0
    private var active = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
        started += 1
        active += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch is CancellationError {
            cancelled += 1
        } catch {}
        active -= 1
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
    }

    func waitUntilStarted() async {
        if started > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilCancelled() async {
        if cancelled > 0 { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func snapshot() -> Snapshot {
        Snapshot(started: started, cancelled: cancelled, active: active)
    }
}

private actor FixtureHeartbeatWrites {
    private var tick = 0

    func next() throws -> LiveParseDanmakuDriverResult {
        tick += 1
        guard tick <= 3 else {
            return try decodeResult(#"{"timer":{"mode":"off"}}"#)
        }
        return try decodeResult(
            #"{"writes":[{"kind":"text","text":"heartbeat-\#(tick)"},{"kind":"binary","bytesBase64":"\#(Data([UInt8(tick)]).base64EncodedString())"}]}"#
        )
    }
}

private actor DeferredDanmakuResult {
    private var pending: CheckedContinuation<LiveParseDanmakuDriverResult, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func value() async -> LiveParseDanmakuDriverResult {
        await withCheckedContinuation { continuation in
            pending = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(_ value: LiveParseDanmakuDriverResult) {
        pending?.resume(returning: value)
        pending = nil
    }
}

@MainActor
private final class ManualDanmakuClock {
    struct Entry {
        var deadline: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
    }
    var now: TimeInterval = 0
    var entries: [UUID: Entry] = [:]

    func schedule(_ interval: TimeInterval, _ repeats: Bool, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let id = UUID()
        entries[id] = Entry(deadline: now + interval, interval: repeats ? interval : nil, action: action)
        return { [weak self] in self?.entries.removeValue(forKey: id) }
    }

    func advance(_ interval: TimeInterval) {
        let end = now + interval
        while let next = entries.min(by: { $0.value.deadline < $1.value.deadline }), next.value.deadline <= end {
            now = next.value.deadline
            if let interval = next.value.interval { entries[next.key]?.deadline += interval }
            else { entries.removeValue(forKey: next.key) }
            next.value.action()
        }
        now = end
    }
}

@MainActor
private final class RecordingDanmakuEngine: @preconcurrency Engine {
    var starts = 0
    var textWrites: [String] = []
    var binaryWrites: [Data] = []
    var pings: [Data] = []
    func register(delegate: any EngineDelegate) {}
    func start(request: URLRequest) { starts += 1 }
    func stop(closeCode: UInt16) {}
    func forceStop() {}
    func write(data: Data, opcode: FrameOpCode, completion: (() -> Void)?) {
        if opcode == .ping { pings.append(data) }
        else { binaryWrites.append(data) }
        completion?()
    }
    func write(string: String, completion: (() -> Void)?) { textWrites.append(string); completion?() }
}

@MainActor
private final class RecordingDanmakuDelegate: WebSocketConnectionDelegate {
    var connected = 0
    var disconnected = 0
    var reconnecting: [Int] = []
    func webSocketDidConnect() { connected += 1 }
    func webSocketDidDisconnect(error: Error?) { disconnected += 1 }
    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int) { reconnecting.append(attempt) }
    func webSocketDidReceiveMessage(_ message: DanmakuDisplayMessage) {}
}
