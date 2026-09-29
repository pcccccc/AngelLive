import Foundation

private actor TranslationPermitPool {
    private let limit: Int
    private var active = 0
    private var order: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire(_ id: UUID) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if active < limit {
                    active += 1
                    continuation.resume()
                } else {
                    order.append(id)
                    waiters[id] = continuation
                }
            }
        }, onCancel: {
            Task { await self.cancel(id) }
        })
    }

    func release() {
        while let id = order.first {
            order.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume()
            return
        }
        active = max(0, active - 1)
    }

    private func cancel(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }
}

actor TranslationWorkCoordinator {
    struct Lease: Sendable {
        let flightID: UUID
        let consumerID: UUID
        let task: Task<String, any Error>
    }

    enum Acquisition: Sendable {
        case cached(String)
        case lease(Lease)
    }

    private struct Flight {
        let id: UUID
        let task: Task<String, any Error>
        var consumers: Set<UUID>
    }

    private let cacheCapacity: Int
    private let maximumFlights: Int
    private let permits: TranslationPermitPool
    private var cache: [RoomTranslationCacheKey: String] = [:]
    private var cacheOrder: [RoomTranslationCacheKey] = []
    private var flights: [RoomTranslationCacheKey: Flight] = [:]

    init(cacheCapacity: Int = 200, maximumFlights: Int = 64, maximumConcurrent: Int = 3) {
        self.cacheCapacity = max(1, cacheCapacity)
        self.maximumFlights = max(1, maximumFlights)
        permits = TranslationPermitPool(limit: maximumConcurrent)
    }

    func acquire(
        key: RoomTranslationCacheKey,
        operation: @escaping @Sendable () async throws -> String
    ) throws -> Acquisition {
        if let cached = cache[key] {
            touch(key)
            return .cached(cached)
        }

        let consumerID = UUID()
        if var flight = flights[key] {
            flight.consumers.insert(consumerID)
            flights[key] = flight
            return .lease(.init(flightID: flight.id, consumerID: consumerID, task: flight.task))
        }
        guard flights.count < maximumFlights else { throw RoomTranslationError.busy }

        let permitID = UUID()
        let flightID = UUID()
        let permits = permits
        let task = Task<String, any Error> {
            try await permits.acquire(permitID)
            do {
                try Task.checkCancellation()
                let result = try await operation()
                await permits.release()
                return result
            } catch {
                await permits.release()
                throw error
            }
        }
        flights[key] = Flight(id: flightID, task: task, consumers: [consumerID])
        return .lease(.init(flightID: flightID, consumerID: consumerID, task: task))
    }

    func complete(key: RoomTranslationCacheKey, flightID: UUID, value: String) {
        guard flights[key]?.id == flightID else { return }
        flights.removeValue(forKey: key)
        cache[key] = value
        touch(key)
        while cacheOrder.count > cacheCapacity, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    func release(key: RoomTranslationCacheKey, flightID: UUID, consumerID: UUID) {
        guard var flight = flights[key], flight.id == flightID else { return }
        flight.consumers.remove(consumerID)
        if flight.consumers.isEmpty {
            flight.task.cancel()
            flights.removeValue(forKey: key)
        } else {
            flights[key] = flight
        }
    }

    func removeAll() {
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        cache.removeAll()
        cacheOrder.removeAll()
    }

    private func touch(_ key: RoomTranslationCacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }
}
