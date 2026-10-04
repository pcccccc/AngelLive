import Foundation

/// Connection intent survives outages and suspension; transport status does not.
public struct DanmakuConnectionIntent: Sendable {
    private var wanted = false
    private var suspended = false

    public init() {}

    public mutating func request() -> Bool {
        wanted = true
        return !suspended
    }

    public mutating func suspend() { suspended = true }

    public mutating func resume() -> Bool {
        suspended = false
        return wanted
    }

    public mutating func stop() {
        wanted = false
        suspended = false
    }
}

/// All callbacks and cancellation live on the connection's main actor.
typealias DanmakuSchedule = @MainActor (
    TimeInterval, Bool, @escaping @MainActor () -> Void
) -> (@MainActor () -> Void)

@MainActor
func scheduleDanmakuWork(
    after interval: TimeInterval,
    repeats: Bool,
    action: @escaping @MainActor () -> Void
) -> @MainActor () -> Void {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    if repeats {
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
    } else {
        timer.schedule(deadline: .now() + interval)
    }
    timer.setEventHandler { MainActor.assumeIsolated { action() } }
    timer.resume()
    return { timer.cancel() }
}

/// Missing timer means no change; only an explicit off stops it. Repeated
/// identical plans must not postpone the next heartbeat on every inbound frame.
@MainActor
final class DanmakuConnectionTimer {
    private let schedule: DanmakuSchedule
    private var cancel: (@MainActor () -> Void)?
    private var plan: LiveParseDanmakuTimerPlan?
    private var generation = UUID()

    init(schedule: @escaping DanmakuSchedule = scheduleDanmakuWork) {
        self.schedule = schedule
    }

    isolated deinit { cancel?() }

    func update(_ next: LiveParseDanmakuTimerPlan?, action: @escaping @MainActor () -> Void) {
        guard let next else { return }
        guard next.mode != .off else { stop(); return }
        let normalized = LiveParseDanmakuTimerPlan(mode: next.mode, intervalMs: max(next.intervalMs ?? 0, 1_000))
        guard normalized != plan else { return }
        stop()
        plan = normalized
        let token = generation
        cancel = schedule(Double(normalized.intervalMs ?? 1_000) / 1_000, true) { [weak self] in
            guard self?.generation == token else { return }
            action()
        }
    }

    func stop() {
        generation = UUID()
        cancel?()
        cancel = nil
        plan = nil
    }
}

/// Retries remain bounded in frequency, not in lifetime. A long outage must not
/// permanently disable a room that the user is still watching.
struct DanmakuReconnectPolicy {
    private(set) var attempts = 0

    var delay: TimeInterval {
        attempts < 8 ? min(2 * pow(2, Double(attempts)), 30) : 60
    }

    mutating func beginAttempt() {
        if attempts < Int.max { attempts += 1 }
    }

    mutating func connected() { attempts = 0 }
}

/// FIFO execution includes each async plugin call and its result application.
/// Cancellation alone is insufficient: a late result must also match the epoch.
@MainActor
final class DanmakuConnectionWorkQueue {
    private let schedule: DanmakuSchedule
    private let timeout: TimeInterval
    private(set) var generation = UUID()
    private(set) var tail: Task<Void, Never>?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var keys: Set<String> = []

    init(timeout: TimeInterval = 30, schedule: @escaping DanmakuSchedule = scheduleDanmakuWork) {
        self.timeout = timeout
        self.schedule = schedule
    }

    isolated deinit {
        for task in tasks.values { task.cancel() }
    }

    func invalidate() {
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        keys.removeAll()
        tail = nil
    }

    func drain() async { await tail?.value }

    func enqueue(
        key: String? = nil,
        operation: @escaping @Sendable () async throws -> LiveParseDanmakuDriverResult,
        completion: @escaping @MainActor (Result<LiveParseDanmakuDriverResult, Error>) -> Void
    ) {
        if let key, !keys.insert(key).inserted { return }
        let id = UUID()
        let token = generation
        let predecessor = tail
        let task = Task { [weak self] in
            await predecessor?.value
            guard let self, self.generation == token, !Task.isCancelled else { return }
            let cancelDeadline = self.schedule(self.timeout, false) { [weak self] in
                self?.finish(id: id, token: token, key: key, result: .failure(URLError(.timedOut)), completion: completion)
            }
            defer { cancelDeadline() }
            do {
                let result = try await operation()
                self.finish(id: id, token: token, key: key, result: .success(result), completion: completion)
            } catch {
                self.finish(id: id, token: token, key: key, result: .failure(error), completion: completion)
            }
        }
        tasks[id] = task
        tail = task
    }

    private func finish(
        id: UUID, token: UUID, key: String?,
        result: Result<LiveParseDanmakuDriverResult, Error>,
        completion: @MainActor (Result<LiveParseDanmakuDriverResult, Error>) -> Void
    ) {
        guard generation == token, let task = tasks.removeValue(forKey: id) else { return }
        if let key { keys.remove(key) }
        task.cancel()
        completion(result)
    }
}

/// Owns cleanup for the most recently retired driver without making a new
/// connection wait for JavaScript cleanup. Replacing or timing out cleanup
/// cancels the underlying plugin call; `JSRuntime` then removes any pending
/// Promise continuation through its task-cancellation handler.
@MainActor
final class DanmakuDriverRetirement {
    private let schedule: DanmakuSchedule
    private let timeout: TimeInterval
    private var token: UUID?
    private var task: Task<Void, Never>?
    private var cancelDeadline: (@MainActor () -> Void)?
    // The transport can be released immediately after disconnect. Keep this
    // bounded cleanup owner alive until destroy completes or its deadline fires.
    private var cleanupLease: DanmakuDriverRetirement?

    init(timeout: TimeInterval = 30, schedule: @escaping DanmakuSchedule = scheduleDanmakuWork) {
        self.timeout = timeout
        self.schedule = schedule
    }

    isolated deinit { cancel() }

    var hasPendingRetirement: Bool { task != nil }

    func retire(_ driver: any DanmakuRuntimeDriving, reason: PluginJSDanmakuDriver.DestroyReason) {
        cancel()
        let nextToken = UUID()
        token = nextToken
        let nextTask = Task { [weak self] in
            await driver.destroy(reason: reason)
            guard !Task.isCancelled else { return }
            self?.finish(token: nextToken)
        }
        task = nextTask
        cancelDeadline = schedule(timeout, false) { [weak self] in
            self?.cancel(token: nextToken)
        }
        cleanupLease = self
    }

    func cancel() {
        token = nil
        task?.cancel()
        task = nil
        cancelDeadline?()
        cancelDeadline = nil
        cleanupLease = nil
    }

    private func cancel(token expected: UUID) {
        guard token == expected else { return }
        cancel()
    }

    private func finish(token expected: UUID) {
        guard token == expected else { return }
        token = nil
        task = nil
        cancelDeadline?()
        cancelDeadline = nil
        cleanupLease = nil
    }
}
