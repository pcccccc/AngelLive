import Foundation
import Observation

struct RoomTranslationHostOwnership {
    private var generations: [UUID: UUID] = [:]

    mutating func install(owner: UUID, generation: UUID) { generations[owner] = generation }
    func isCurrent(owner: UUID, generation: UUID) -> Bool { generations[owner] == generation }
    mutating func remove(owner: UUID) { generations.removeValue(forKey: owner) }
}

struct RoomTranslationNativeExecutionState {
    struct Assignment: Equatable {
        let owner: UUID
        let executionID: UUID
    }

    private var assignments: [UUID: Assignment] = [:]

    mutating func assign(requestID: UUID, owner: UUID) -> UUID {
        let executionID = UUID()
        assignments[requestID] = Assignment(owner: owner, executionID: executionID)
        return executionID
    }

    func isCurrent(requestID: UUID, executionID: UUID) -> Bool {
        assignments[requestID]?.executionID == executionID
    }

    mutating func retire(owner: UUID) -> [UUID] {
        let requestIDs = assignments.compactMap { requestID, assignment in
            assignment.owner == owner ? requestID : nil
        }
        for requestID in requestIDs {
            assignments.removeValue(forKey: requestID)
        }
        return requestIDs
    }

    mutating func remove(requestID: UUID) {
        assignments.removeValue(forKey: requestID)
    }
}

@MainActor
func liveAppleRoomTranslationProvider() -> any RoomTranslationProvider {
#if os(tvOS)
    UnavailableAppleRoomTranslationProvider()
#else
    if #available(iOS 18.0, macOS 15.0, *) { AppleRoomTranslationProvider.shared }
    else { UnavailableAppleRoomTranslationProvider() }
#endif
}

private struct UnavailableAppleRoomTranslationProvider: RoomTranslationProvider {
    func translate(_ request: RoomTranslationRequest) async throws -> String {
        throw RoomTranslationError.unavailable
    }
}

#if !os(tvOS)
import Translation

@available(iOS 18.0, macOS 15.0, *)
@MainActor @Observable
final class AppleRoomTranslationProvider: RoomTranslationProvider, RoomTranslationRetrying {
    static let shared = AppleRoomTranslationProvider()

    private struct LanguagePair: Hashable, Sendable {
        let source: String
        let target: String
    }

    private struct Job: Sendable {
        let requestID: UUID
        let executionID: UUID
        let text: String
    }

    private struct Host {
        let id: UUID
        let pair: LanguagePair
        var waiter: CheckedContinuation<Job?, Never>?
    }

    private struct Pending {
        let request: RoomTranslationRequest
        let continuation: CheckedContinuation<String, any Error>
    }

    private struct Active {
        let owner: UUID
        let pair: LanguagePair
        let request: RoomTranslationRequest
        let continuation: CheckedContinuation<String, any Error>
    }

    private(set) var configurationRevision = 0
    private var expectedHosts: Set<UUID> = []
    private var desiredSources: [String: String] = [:]
    private var ownership = RoomTranslationHostOwnership()
    private var executions = RoomTranslationNativeExecutionState()
    private var hosts: [UUID: Host] = [:]
    private var suspendedPairs: Set<LanguagePair> = []
    private var pendingOrder: [UUID] = []
    private var pending: [UUID: Pending] = [:]
    private var active: [UUID: Active] = [:]

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        guard !expectedHosts.isEmpty else { throw RoomTranslationError.unavailable }
        let pair = LanguagePair(source: request.sourceLanguage, target: request.targetLanguage)
        guard !suspendedPairs.contains(pair) else { throw RoomTranslationError.unavailable }

        let requestID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingOrder.append(requestID)
                pending[requestID] = Pending(request: request, continuation: continuation)
                if desiredSources[pair.target] == nil {
                    desiredSources[pair.target] = pair.source
                    configurationRevision &+= 1
                }
                drain()
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancel(requestID) }
        })
    }

    func setHostExpected(owner: UUID, expected: Bool) {
        if expected {
            expectedHosts.insert(owner)
        } else {
            expectedHosts.remove(owner)
            let hasRemainingHost = !expectedHosts.isEmpty
            deactivate(owner: owner, requeueActive: hasRemainingHost)
            if !hasRemainingHost { failAllPending(with: RoomTranslationError.unavailable) }
        }
    }

    func preferredSourceLanguage(targetLanguage: String) -> String? {
        _ = configurationRevision
        return desiredSources[targetLanguage]
    }

    func prepareForExplicitRetry() async {
        guard !suspendedPairs.isEmpty else { return }
        suspendedPairs.removeAll()
        configurationRevision &+= 1
        drain()
    }

    nonisolated static func hostAction(
        owner: UUID,
        sourceLanguage: String,
        targetLanguage: String
    ) -> (TranslationSession) async -> Void {
        { session in
            let hostID = UUID()
            await shared.registerHost(
                owner: owner,
                hostID: hostID,
                source: sourceLanguage,
                target: targetLanguage
            )
            await withTaskCancellationHandler(operation: {
                while let job = await shared.nextJob(owner: owner, hostID: hostID) {
                    do {
                        try Task.checkCancellation()
                        let response = try await session.translate(job.text)
                        try Task.checkCancellation()
                        await shared.finish(
                            job.requestID,
                            executionID: job.executionID,
                            result: .success(response.targetText),
                            suspendPair: false
                        )
                    } catch is CancellationError {
                        if Task.isCancelled {
                            await shared.deactivate(owner: owner, matching: hostID)
                            break
                        }
                        await shared.finish(
                            job.requestID,
                            executionID: job.executionID,
                            result: .failure(RoomTranslationError.unavailable),
                            suspendPair: true
                        )
                    } catch {
                        await shared.finish(
                            job.requestID,
                            executionID: job.executionID,
                            result: .failure(RoomTranslationError.unavailable),
                            suspendPair: true
                        )
                    }
                }
            }, onCancel: {
                Task { @MainActor in
                    shared.deactivate(owner: owner, matching: hostID)
                }
            })
            await shared.deactivate(owner: owner, matching: hostID)
        }
    }

    private func registerHost(owner: UUID, hostID: UUID, source: String, target: String) {
        guard expectedHosts.contains(owner) else { return }
        deactivate(owner: owner, requeueActive: true)
        ownership.install(owner: owner, generation: hostID)
        hosts[owner] = Host(
            id: hostID,
            pair: LanguagePair(source: source, target: target),
            waiter: nil
        )
    }

    private func nextJob(owner: UUID, hostID: UUID) async -> Job? {
        guard ownership.isCurrent(owner: owner, generation: hostID), hosts[owner] != nil else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            guard var host = hosts[owner], host.id == hostID else {
                continuation.resume(returning: nil)
                return
            }
            host.waiter = continuation
            hosts[owner] = host
            drain()
        }
    }

    private func deactivate(owner: UUID, requeueActive: Bool) {
        guard let host = hosts.removeValue(forKey: owner) else { return }
        ownership.remove(owner: owner)
        host.waiter?.resume(returning: nil)
        let retiredRequestIDs = executions.retire(owner: owner)
        for requestID in retiredRequestIDs {
            guard let request = active.removeValue(forKey: requestID) else { continue }
            if requeueActive {
                pending[requestID] = Pending(
                    request: request.request,
                    continuation: request.continuation
                )
                pendingOrder.insert(requestID, at: 0)
            } else {
                request.continuation.resume(throwing: RoomTranslationError.unavailable)
            }
        }
        advanceDesiredSource(for: host.pair.target)
        drain()
    }

    private func deactivate(owner: UUID, matching hostID: UUID) {
        guard ownership.isCurrent(owner: owner, generation: hostID) else { return }
        deactivate(owner: owner, requeueActive: !expectedHosts.isEmpty)
    }

    private func cancel(_ requestID: UUID) {
        if let request = pending.removeValue(forKey: requestID) {
            pendingOrder.removeAll { $0 == requestID }
            request.continuation.resume(throwing: CancellationError())
            advanceDesiredSource(for: request.request.targetLanguage)
        } else if let request = active.removeValue(forKey: requestID) {
            executions.remove(requestID: requestID)
            request.continuation.resume(throwing: CancellationError())
            advanceDesiredSource(for: request.pair.target)
            drain()
        }
    }

    private func drain() {
        for owner in hosts.keys {
            guard var host = hosts[owner], let waiter = host.waiter else { continue }
            guard let requestID = pendingOrder.first(where: { requestID in
                guard let request = pending[requestID]?.request else { return false }
                return request.sourceLanguage == host.pair.source
                    && request.targetLanguage == host.pair.target
            }), let request = pending.removeValue(forKey: requestID) else { continue }

            pendingOrder.removeAll { $0 == requestID }
            host.waiter = nil
            hosts[owner] = host
            let executionID = executions.assign(requestID: requestID, owner: owner)
            active[requestID] = Active(
                owner: owner,
                pair: host.pair,
                request: request.request,
                continuation: request.continuation
            )
            waiter.resume(returning: Job(
                requestID: requestID,
                executionID: executionID,
                text: request.request.text
            ))
        }

        for target in Set(pending.values.map(\.request.targetLanguage)) {
            advanceDesiredSource(for: target)
        }
    }

    private func finish(
        _ requestID: UUID,
        executionID: UUID,
        result: Result<String, any Error>,
        suspendPair: Bool
    ) {
        guard executions.isCurrent(requestID: requestID, executionID: executionID) else { return }
        executions.remove(requestID: requestID)
        guard let request = active.removeValue(forKey: requestID) else { return }
        if suspendPair {
            suspendedPairs.insert(request.pair)
            failQueuedRequests(for: request.pair)
        }
        switch result {
        case let .success(value): request.continuation.resume(returning: value)
        case let .failure(error): request.continuation.resume(throwing: error)
        }
        advanceDesiredSource(for: request.pair.target)
        drain()
    }

    private func failQueuedRequests(for pair: LanguagePair) {
        let pendingIDs = pendingOrder.filter { id in
            guard let request = pending[id]?.request else { return false }
            return request.sourceLanguage == pair.source && request.targetLanguage == pair.target
        }
        for id in pendingIDs {
            guard let request = pending.removeValue(forKey: id) else { continue }
            request.continuation.resume(throwing: RoomTranslationError.unavailable)
        }
        pendingOrder.removeAll { pendingIDs.contains($0) }

        let activeIDs = active.compactMap { id, request in request.pair == pair ? id : nil }
        for id in activeIDs {
            guard let request = active.removeValue(forKey: id) else { continue }
            executions.remove(requestID: id)
            request.continuation.resume(throwing: RoomTranslationError.unavailable)
        }
    }

    private func advanceDesiredSource(for target: String) {
        let current = desiredSources[target]
        let hasCurrentWork = pending.values.contains {
            $0.request.targetLanguage == target && $0.request.sourceLanguage == current
        } || active.values.contains {
            $0.pair.target == target && $0.pair.source == current
        }
        guard !hasCurrentWork,
              let next = pendingOrder.lazy.compactMap({ self.pending[$0]?.request }).first(where: {
                  $0.targetLanguage == target
              })?.sourceLanguage,
              next != current else { return }
        desiredSources[target] = next
        configurationRevision &+= 1
    }

    private func failAllPending(with error: any Error) {
        let requests = Array(pending.values)
        pending.removeAll()
        pendingOrder.removeAll()
        for request in requests { request.continuation.resume(throwing: error) }
    }
}
#endif
