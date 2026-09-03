import Foundation

struct PluginHTTPFlightKey: Hashable, Sendable {
    let pluginId: String
    let sessionRevision: String
    let method: String
    let singleFlightKey: String
}

struct PluginHTTPFlightSnapshot: Sendable, Equatable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]
    let responseURL: String
    let setCookies: [String]
    let requestContainsCookieHeader: Bool
    let requestCookieDiagnostics: String

    init(
        data: Data,
        statusCode: Int,
        headers: [String: String],
        responseURL: String,
        setCookies: [String] = [],
        requestContainsCookieHeader: Bool = false,
        requestCookieDiagnostics: String = "missing"
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.responseURL = responseURL
        self.setCookies = setCookies
        self.requestContainsCookieHeader = requestContainsCookieHeader
        self.requestCookieDiagnostics = requestCookieDiagnostics
    }
}

struct PluginHTTPFlightFailure: Error, LocalizedError, Sendable, Equatable {
    let domain: String
    let code: Int
    let receivedHTTPResponse: Bool
    let message: String

    init(
        domain: String,
        code: Int,
        receivedHTTPResponse: Bool,
        message: String
    ) {
        self.domain = domain
        self.code = code
        self.receivedHTTPResponse = receivedHTTPResponse
        self.message = message
    }

    init(error: any Error, receivedHTTPResponse: Bool = false) {
        let nsError = error as NSError
        self.init(
            domain: nsError.domain,
            code: nsError.code,
            receivedHTTPResponse: receivedHTTPResponse,
            message: error.localizedDescription
        )
    }

    var errorDescription: String? { message }
}

struct PluginHTTPFlightMetrics: Sendable, Equatable {
    var realRequests = 0
    var joinedFlights = 0
    var successCacheHits = 0
    var failureCacheHits = 0
}

actor PluginHTTPFlightCoordinator {
    private enum CachedResult: Sendable {
        case success(PluginHTTPFlightSnapshot)
        case failure(PluginHTTPFlightFailure)
    }

    private struct CacheEntry: Sendable {
        let result: CachedResult
        let expiresAt: Date
    }

    private struct Flight: Sendable {
        let id: UUID
        let task: Task<PluginHTTPFlightSnapshot, Error>
    }

    private let maximumSuccessTTL: TimeInterval
    private let maximumFailureTTL: TimeInterval
    private var inFlight: [PluginHTTPFlightKey: Flight] = [:]
    private var cache: [PluginHTTPFlightKey: CacheEntry] = [:]
    private var counters = PluginHTTPFlightMetrics()

    init(
        maximumSuccessTTL: TimeInterval = 60,
        maximumFailureTTL: TimeInterval = 30
    ) {
        self.maximumSuccessTTL = max(0, maximumSuccessTTL)
        self.maximumFailureTTL = max(0, maximumFailureTTL)
    }

    func execute(
        key: PluginHTTPFlightKey,
        successTTL: TimeInterval,
        failureTTL: TimeInterval,
        bypassCache: Bool = false,
        operation: @escaping @Sendable () async throws -> PluginHTTPFlightSnapshot
    ) async throws -> PluginHTTPFlightSnapshot {
        try Task.checkCancellation()
        pruneExpiredEntries(now: .now)

        if !bypassCache, let cached = cache[key] {
            switch cached.result {
            case .success(let snapshot):
                counters.successCacheHits += 1
                Logger.debug(
                    "[HostHTTPFlight] pluginId=\(key.pluginId) method=\(key.method) hit=success-cache",
                    category: .plugin
                )
                return snapshot
            case .failure(let failure):
                counters.failureCacheHits += 1
                Logger.debug(
                    "[HostHTTPFlight] pluginId=\(key.pluginId) method=\(key.method) hit=failure-cache",
                    category: .plugin
                )
                throw failure
            }
        }

        if let flight = inFlight[key] {
            counters.joinedFlights += 1
            Logger.debug(
                "[HostHTTPFlight] pluginId=\(key.pluginId) method=\(key.method) hit=in-flight",
                category: .plugin
            )
            return try await waitForSharedTask(flight.task)
        }

        counters.realRequests += 1
        let task = Task<PluginHTTPFlightSnapshot, Error> {
            do {
                return try await operation()
            } catch let failure as PluginHTTPFlightFailure {
                throw failure
            } catch {
                throw PluginHTTPFlightFailure(error: error)
            }
        }
        let flightID = UUID()
        inFlight[key] = Flight(id: flightID, task: task)

        do {
            let snapshot = try await waitForSharedTask(task)
            if inFlight[key]?.id == flightID {
                inFlight.removeValue(forKey: key)
            }
            let ttl = min(max(0, successTTL), maximumSuccessTTL)
            if ttl > 0 {
                cache[key] = CacheEntry(
                    result: .success(snapshot),
                    expiresAt: .now.addingTimeInterval(ttl)
                )
            }
            return snapshot
        } catch is CancellationError {
            // 等待者取消不能取消同 key 的共享网络任务；完成者负责写缓存和移除 flight。
            Task { [weak self] in
                await self?.harvest(
                    task: task,
                    flightID: flightID,
                    key: key,
                    successTTL: successTTL,
                    failureTTL: failureTTL
                )
            }
            throw CancellationError()
        } catch {
            inFlight.removeValue(forKey: key)
            let failure = (error as? PluginHTTPFlightFailure)
                ?? PluginHTTPFlightFailure(error: error)
            let ttl = min(max(0, failureTTL), maximumFailureTTL)
            if ttl > 0 {
                cache[key] = CacheEntry(
                    result: .failure(failure),
                    expiresAt: .now.addingTimeInterval(ttl)
                )
            }
            throw failure
        }
    }

    func invalidateFailures() {
        cache = cache.filter { _, entry in
            if case .failure = entry.result { return false }
            return true
        }
    }

    func invalidateAll() {
        cache.removeAll(keepingCapacity: false)
    }

    /// Runtime abandonment is stronger than invalidation: no caller can
    /// legitimately consume these flights again, so stop their network work.
    func cancelAll() {
        for flight in inFlight.values {
            flight.task.cancel()
        }
        inFlight.removeAll(keepingCapacity: false)
        cache.removeAll(keepingCapacity: false)
    }

    func metrics() -> PluginHTTPFlightMetrics {
        counters
    }

    private func harvest(
        task: Task<PluginHTTPFlightSnapshot, Error>,
        flightID: UUID,
        key: PluginHTTPFlightKey,
        successTTL: TimeInterval,
        failureTTL: TimeInterval
    ) async {
        guard inFlight[key]?.id == flightID else { return }
        do {
            let snapshot = try await task.value
            guard inFlight[key]?.id == flightID else { return }
            inFlight.removeValue(forKey: key)
            let ttl = min(max(0, successTTL), maximumSuccessTTL)
            if ttl > 0 {
                cache[key] = CacheEntry(
                    result: .success(snapshot),
                    expiresAt: .now.addingTimeInterval(ttl)
                )
            }
        } catch is CancellationError {
            guard inFlight[key]?.id == flightID else { return }
            inFlight.removeValue(forKey: key)
        } catch {
            guard inFlight[key]?.id == flightID else { return }
            inFlight.removeValue(forKey: key)
            let failure = (error as? PluginHTTPFlightFailure)
                ?? PluginHTTPFlightFailure(error: error)
            let ttl = min(max(0, failureTTL), maximumFailureTTL)
            if ttl > 0 {
                cache[key] = CacheEntry(
                    result: .failure(failure),
                    expiresAt: .now.addingTimeInterval(ttl)
                )
            }
        }
    }

    private func pruneExpiredEntries(now: Date) {
        cache = cache.filter { $0.value.expiresAt > now }
    }
}

private enum PluginHTTPFlightWaitOutcome: Sendable {
    case success(PluginHTTPFlightSnapshot)
    case failure(PluginHTTPFlightFailure)
    case cancelled
}

private func waitForSharedTask(
    _ task: Task<PluginHTTPFlightSnapshot, Error>
) async throws -> PluginHTTPFlightSnapshot {
    let (stream, continuation) = AsyncStream.makeStream(
        of: PluginHTTPFlightWaitOutcome.self,
        bufferingPolicy: .bufferingOldest(1)
    )
    let waiter = Task {
        do {
            continuation.yield(.success(try await task.value))
        } catch let failure as PluginHTTPFlightFailure {
            continuation.yield(.failure(failure))
        } catch {
            continuation.yield(.failure(PluginHTTPFlightFailure(error: error)))
        }
    }
    defer {
        waiter.cancel()
        continuation.finish()
    }

    return try await withTaskCancellationHandler {
        var iterator = stream.makeAsyncIterator()
        guard let outcome = await iterator.next() else { throw CancellationError() }
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let failure): throw failure
        case .cancelled: throw CancellationError()
        }
    } onCancel: {
        continuation.yield(.cancelled)
    }
}
