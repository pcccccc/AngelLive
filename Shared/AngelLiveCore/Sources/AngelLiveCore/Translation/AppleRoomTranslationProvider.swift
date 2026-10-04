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
    func firstCurrent(
        in candidates: [(requestID: UUID, executionID: UUID)]
    ) -> (requestID: UUID, executionID: UUID)? {
        candidates.first {
            isCurrent(requestID: $0.requestID, executionID: $0.executionID)
        }
    }
    mutating func retire(owner: UUID) -> [UUID] {
        let requestIDs = assignments.compactMap { $0.value.owner == owner ? $0.key : nil }
        for requestID in requestIDs { assignments.removeValue(forKey: requestID) }
        return requestIDs
    }
    mutating func remove(requestID: UUID) { assignments.removeValue(forKey: requestID) }
}

struct RoomTranslationNativeBatchResponse: Sendable {
    let clientIdentifier: String?
    let targetText: String
}

enum RoomTranslationNativeBatchRouter {
    static func results(
        requestIDs: [UUID],
        responses: [RoomTranslationNativeBatchResponse]
    ) -> [UUID: String] {
        let expected = Set(requestIDs)
        var results: [UUID: String] = [:]
        for response in responses {
            guard let identifier = response.clientIdentifier,
                  let requestID = UUID(uuidString: identifier),
                  expected.contains(requestID),
                  results[requestID] == nil else { continue }
            results[requestID] = response.targetText
        }
        return results
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

enum NativeTranslationAvailabilityStatus: Sendable {
    case installed
    case supported
    case unsupported
}

enum NativeTranslationStrategy: Hashable, Sendable {
    case systemDefault
    case lowLatency
}

enum NativeTranslationSessionSelection: Equatable, Sendable {
    case installed(NativeTranslationStrategy)
    case downloadCapable
}

private extension NativeTranslationAvailabilityStatus {
    var publicStatus: NativeTranslationLanguageStatus {
        switch self {
        case .installed: .installed
        case .supported: .notDownloaded
        case .unsupported: .unsupported
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
protocol NativeTranslationAvailabilityChecking: AnyObject {
    func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
private final class SystemNativeTranslationAvailability: NativeTranslationAvailabilityChecking {
    func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus {
        let availability: LanguageAvailability
        if strategy == .lowLatency, #available(iOS 26.4, macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            availability = LanguageAvailability()
        }
        let status = await availability.status(
            from: Locale.Language(identifier: pair.sourceLanguage),
            to: Locale.Language(identifier: pair.targetLanguage)
        )
        switch status {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor @Observable
final class NativeTranslationResourcePolicy {
    private struct Key: Hashable {
        let pair: NativeTranslationLanguagePair
        let strategy: NativeTranslationStrategy
    }

    private struct InFlightCheck {
        let id: UUID
        let task: Task<NativeTranslationAvailabilityStatus, Never>
    }

    @ObservationIgnored private let availability: any NativeTranslationAvailabilityChecking
    @ObservationIgnored private var cachedStatuses: [Key: NativeTranslationAvailabilityStatus] = [:]
    @ObservationIgnored private var inFlightChecks: [Key: InFlightCheck] = [:]

    init(availability: any NativeTranslationAvailabilityChecking) {
        self.availability = availability
    }

    func requireInstalled(
        _ pair: NativeTranslationLanguagePair
    ) async throws -> NativeTranslationStrategy {
        var hasSupportedStrategy = false
        for strategy in automaticStrategies {
            switch await status(for: pair, strategy: strategy) {
            case .installed:
                return strategy
            case .supported:
                hasSupportedStrategy = true
            case .unsupported:
                break
            }
        }
        throw hasSupportedStrategy
            ? RoomTranslationError.languageResourcesRequired
            : RoomTranslationError.unavailable
    }

    func sessionSelection(
        for pair: NativeTranslationLanguagePair,
        purpose: RoomTranslationRequestPurpose
    ) async throws -> NativeTranslationSessionSelection {
        switch purpose {
        case .automatic:
            return .installed(try await requireInstalled(pair))
        case .explicitTest:
            do {
                return .installed(try await requireInstalled(pair))
            } catch RoomTranslationError.languageResourcesRequired {
                return .downloadCapable
            }
        case .prepareLanguages:
            return .downloadCapable
        }
    }

    func refreshAutomaticStatus(
        _ pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationAvailabilityStatus {
        invalidate(pair)
        var hasSupportedStrategy = false
        for strategy in automaticStrategies {
            switch await status(for: pair, strategy: strategy) {
            case .installed:
                return .installed
            case .supported:
                hasSupportedStrategy = true
            case .unsupported:
                break
            }
        }
        return hasSupportedStrategy ? .supported : .unsupported
    }

    func refreshDownloadStatus(
        _ pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationAvailabilityStatus {
        invalidate(pair)
        return await status(for: pair, strategy: downloadStrategy)
    }

    func invalidate(_ pair: NativeTranslationLanguagePair) {
        cachedStatuses = cachedStatuses.filter { $0.key.pair != pair }
        let matchingKeys = inFlightChecks.keys.filter { $0.pair == pair }
        for key in matchingKeys {
            inFlightChecks.removeValue(forKey: key)?.task.cancel()
        }
    }

    func clearCachedStatuses() {
        cachedStatuses.removeAll()
        for check in inFlightChecks.values { check.task.cancel() }
        inFlightChecks.removeAll()
    }

    private var automaticStrategies: [NativeTranslationStrategy] {
        if #available(iOS 26.4, macOS 26.4, *) {
            return [.lowLatency, .systemDefault]
        }
        return [.systemDefault]
    }

    private var downloadStrategy: NativeTranslationStrategy {
        if #available(iOS 26.4, macOS 26.4, *) {
            return .lowLatency
        }
        return .systemDefault
    }

    private func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus {
        let key = Key(pair: pair, strategy: strategy)
        if let cached = cachedStatuses[key] { return cached }
        if let existing = inFlightChecks[key] { return await existing.task.value }

        let checkID = UUID()
        let availability = availability
        let task = Task { @MainActor in
            await availability.status(for: pair, strategy: strategy)
        }
        inFlightChecks[key] = InFlightCheck(id: checkID, task: task)
        let status = await task.value
        guard inFlightChecks[key]?.id == checkID else { return status }
        inFlightChecks.removeValue(forKey: key)
        cachedStatuses[key] = status
        return status
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor @Observable
final class AppleRoomTranslationProvider:
    RoomTranslationProvider,
    RoomTranslationRetrying,
    RoomTranslationLanguagePreparing
{
    static let shared = AppleRoomTranslationProvider()

    private struct Job: Sendable {
        let requestID: UUID
        let executionID: UUID
        let text: String
        let purpose: RoomTranslationRequestPurpose
    }
    private enum HostWork: Sendable {
        case translations([Job])
        case prepareLanguages(Job)
    }
    private struct Host {
        let id: UUID
        let pair: NativeTranslationLanguagePair
        var waiter: CheckedContinuation<HostWork?, Never>?
    }
    private struct Pending {
        let request: RoomTranslationRequest
        let continuation: CheckedContinuation<String, any Error>
    }
    private struct Active {
        let owner: UUID
        let pair: NativeTranslationLanguagePair
        let request: RoomTranslationRequest
        let continuation: CheckedContinuation<String, any Error>
    }

    @ObservationIgnored private let resources: NativeTranslationResourcePolicy
    private(set) var configurationRevision = 0
    private var expectedHosts: Set<UUID> = []
    private var desiredSources: [String: String] = [:]
    private var ownership = RoomTranslationHostOwnership()
    private var executions = RoomTranslationNativeExecutionState()
    private var hosts: [UUID: Host] = [:]
    private var suspendedPairs: Set<NativeTranslationLanguagePair> = []
    private var pendingOrder: [UUID] = []
    private var pending: [UUID: Pending] = [:]
    private var active: [UUID: Active] = [:]

    init(availability: (any NativeTranslationAvailabilityChecking)? = nil) {
        resources = NativeTranslationResourcePolicy(
            availability: availability ?? SystemNativeTranslationAvailability()
        )
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage
        )
        if request.purpose == .automatic {
            _ = try await resources.requireInstalled(pair)
        }
        guard !expectedHosts.isEmpty else { throw RoomTranslationError.unavailable }
        if request.purpose == .prepareLanguages {
            suspendedPairs.remove(pair)
            resources.invalidate(pair)
        } else {
            guard !suspendedPairs.contains(pair) else { throw RoomTranslationError.unavailable }
        }

        let requestID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingOrder.append(requestID)
                pending[requestID] = Pending(request: request, continuation: continuation)
                if desiredSources[pair.targetLanguage] == nil {
                    desiredSources[pair.targetLanguage] = pair.sourceLanguage
                    configurationRevision &+= 1
                }
                drain()
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancel(requestID) }
        })
    }

    func prepareLanguages(sourceLanguage: String, targetLanguage: String) async throws {
        _ = try await translate(RoomTranslationRequest(
            text: "",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            baseURL: nil,
            model: nil,
            apiKey: nil,
            purpose: .prepareLanguages
        ))
    }

    func nativeLanguageStatus(
        for pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationLanguageStatus {
        await resources.refreshAutomaticStatus(pair).publicStatus
    }

    func downloadLanguageStatus(
        for pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationLanguageStatus {
        await resources.refreshDownloadStatus(pair).publicStatus
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
        suspendedPairs.removeAll()
        resources.clearCachedStatuses()
        configurationRevision &+= 1
        drain()
    }

    nonisolated static func hostAction(
        owner: UUID,
        sourceLanguage: String,
        targetLanguage: String
    ) -> (TranslationSession) async -> Void {
        { downloadCapableSession in
            let hostID = UUID()
            let pair = NativeTranslationLanguagePair(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            var installedOnlySession: (
                strategy: NativeTranslationStrategy,
                session: TranslationSession
            )?
            await shared.registerHost(owner: owner, hostID: hostID, pair: pair)

            await withTaskCancellationHandler(operation: {
                hostLoop: while let work = await shared.nextWork(owner: owner, hostID: hostID) {
                    switch work {
                    case .prepareLanguages(let job):
                        do {
                            try Task.checkCancellation()
                            try await downloadCapableSession.prepareTranslation()
                            try Task.checkCancellation()
                            let status = await shared.refreshDownloadStatus(pair)
                            await shared.finish(
                                job.requestID,
                                executionID: job.executionID,
                                result: status == .installed
                                    ? .success("")
                                    : .failure(RoomTranslationError.languageResourcesRequired),
                                suspendPair: false
                            )
                        } catch is CancellationError {
                            if Task.isCancelled {
                                await shared.deactivate(owner: owner, matching: hostID)
                                break hostLoop
                            }
                            await shared.refreshDownloadResources(pair)
                            await shared.finish(
                                job.requestID,
                                executionID: job.executionID,
                                result: .failure(RoomTranslationError.unavailable),
                                suspendPair: false
                            )
                        } catch {
                            await shared.refreshDownloadResources(pair)
                            await shared.finish(
                                job.requestID,
                                executionID: job.executionID,
                                result: .failure(RoomTranslationError.unavailable),
                                suspendPair: false
                            )
                        }

                    case .translations(let jobs):
                        do {
                            try Task.checkCancellation()
                            let session: TranslationSession
                            if let purpose = jobs.first?.purpose,
                               #available(iOS 26.0, macOS 26.0, *) {
                                let selection = try await shared.sessionSelection(
                                    for: pair,
                                    purpose: purpose
                                )
                                try Task.checkCancellation()
                                switch selection {
                                case .installed(let strategy):
                                    if let installedOnlySession,
                                       installedOnlySession.strategy == strategy {
                                        session = installedOnlySession.session
                                    } else {
                                        let created: TranslationSession
                                        if strategy == .lowLatency,
                                           #available(iOS 26.4, macOS 26.4, *) {
                                            created = TranslationSession(
                                                installedSource: Locale.Language(identifier: sourceLanguage),
                                                target: Locale.Language(identifier: targetLanguage),
                                                preferredStrategy: .lowLatency
                                            )
                                        } else {
                                            created = TranslationSession(
                                                installedSource: Locale.Language(identifier: sourceLanguage),
                                                target: Locale.Language(identifier: targetLanguage)
                                            )
                                        }
                                        installedOnlySession = (strategy: strategy, session: created)
                                        session = created
                                    }
                                case .downloadCapable:
                                    session = downloadCapableSession
                                }
                            } else {
                                session = downloadCapableSession
                            }

                            let responses = try await session.translations(from: jobs.map {
                                TranslationSession.Request(
                                    sourceText: $0.text,
                                    clientIdentifier: $0.requestID.uuidString
                                )
                            })
                            try Task.checkCancellation()
                            let routed = RoomTranslationNativeBatchRouter.results(
                                requestIDs: jobs.map(\.requestID),
                                responses: responses.map {
                                    RoomTranslationNativeBatchResponse(
                                        clientIdentifier: $0.clientIdentifier,
                                        targetText: $0.targetText
                                    )
                                }
                            )
                            for job in jobs {
                                await shared.finish(
                                    job.requestID,
                                    executionID: job.executionID,
                                    result: routed[job.requestID].map(Result.success)
                                        ?? .failure(RoomTranslationError.invalidResponse),
                                    suspendPair: false
                                )
                            }
                        } catch is CancellationError {
                            if Task.isCancelled {
                                await shared.deactivate(owner: owner, matching: hostID)
                                break hostLoop
                            }
                            await shared.failTranslationWork(jobs, pair: pair)
                        } catch {
                            await shared.failTranslationWork(jobs, pair: pair)
                        }
                    }
                }
            }, onCancel: {
                Task { @MainActor in shared.deactivate(owner: owner, matching: hostID) }
            })
            await shared.deactivate(owner: owner, matching: hostID)
        }
    }

    private func sessionSelection(
        for pair: NativeTranslationLanguagePair,
        purpose: RoomTranslationRequestPurpose
    ) async throws -> NativeTranslationSessionSelection {
        try await resources.sessionSelection(for: pair, purpose: purpose)
    }

    private func refreshDownloadResources(_ pair: NativeTranslationLanguagePair) async {
        _ = await resources.refreshDownloadStatus(pair)
    }

    private func refreshDownloadStatus(
        _ pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationAvailabilityStatus {
        await resources.refreshDownloadStatus(pair)
    }

    private func registerHost(
        owner: UUID,
        hostID: UUID,
        pair: NativeTranslationLanguagePair
    ) {
        guard expectedHosts.contains(owner) else { return }
        deactivate(owner: owner, requeueActive: true)
        ownership.install(owner: owner, generation: hostID)
        hosts[owner] = Host(id: hostID, pair: pair, waiter: nil)
    }

    private func nextWork(owner: UUID, hostID: UUID) async -> HostWork? {
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
        advanceDesiredSource(for: host.pair.targetLanguage)
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
            advanceDesiredSource(for: request.pair.targetLanguage)
            drain()
        }
    }

    private func drain() {
        for owner in hosts.keys {
            guard var host = hosts[owner], let waiter = host.waiter else { continue }
            guard let seedID = pendingOrder.first(where: { requestID in
                guard let request = pending[requestID]?.request else { return false }
                return request.sourceLanguage == host.pair.sourceLanguage
                    && request.targetLanguage == host.pair.targetLanguage
            }), let seed = pending[seedID]?.request else { continue }

            let selectedIDs: [UUID]
            if seed.purpose == .prepareLanguages {
                selectedIDs = [seedID]
            } else {
                selectedIDs = Array(pendingOrder.lazy.filter { requestID in
                    guard let request = self.pending[requestID]?.request else { return false }
                    return request.sourceLanguage == host.pair.sourceLanguage
                        && request.targetLanguage == host.pair.targetLanguage
                        && request.purpose == seed.purpose
                }.prefix(32))
            }

            var jobs: [Job] = []
            for requestID in selectedIDs {
                guard let request = pending.removeValue(forKey: requestID) else { continue }
                pendingOrder.removeAll { $0 == requestID }
                let executionID = executions.assign(requestID: requestID, owner: owner)
                active[requestID] = Active(
                    owner: owner,
                    pair: host.pair,
                    request: request.request,
                    continuation: request.continuation
                )
                jobs.append(Job(
                    requestID: requestID,
                    executionID: executionID,
                    text: request.request.text,
                    purpose: request.request.purpose
                ))
            }
            guard let firstJob = jobs.first else { continue }
            host.waiter = nil
            hosts[owner] = host
            waiter.resume(returning: firstJob.purpose == .prepareLanguages
                ? .prepareLanguages(firstJob)
                : .translations(jobs))
        }

        for target in Set(pending.values.map(\.request.targetLanguage)) {
            advanceDesiredSource(for: target)
        }
    }

    private func failTranslationWork(
        _ jobs: [Job],
        pair: NativeTranslationLanguagePair
    ) async {
        guard let first = jobs.first else { return }
        let status = await resources.refreshAutomaticStatus(pair)
        if first.purpose == .automatic, status != .installed {
            let error: RoomTranslationError = status == .supported
                ? .languageResourcesRequired
                : .unavailable
            for job in jobs {
                finish(
                    job.requestID,
                    executionID: job.executionID,
                    result: .failure(error),
                    suspendPair: false
                )
            }
            return
        }
        guard let representative = executions.firstCurrent(
            in: jobs.map { (requestID: $0.requestID, executionID: $0.executionID) }
        ) else { return }
        finish(
            representative.requestID,
            executionID: representative.executionID,
            result: .failure(RoomTranslationError.unavailable),
            suspendPair: true
        )
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
        request.continuation.resume(with: result)
        advanceDesiredSource(for: request.pair.targetLanguage)
        drain()
    }

    private func failQueuedRequests(for pair: NativeTranslationLanguagePair) {
        let pendingIDs = pendingOrder.filter { id in
            guard let request = pending[id]?.request else { return false }
            return request.sourceLanguage == pair.sourceLanguage
                && request.targetLanguage == pair.targetLanguage
        }
        for id in pendingIDs {
            guard let request = pending.removeValue(forKey: id) else { continue }
            request.continuation.resume(throwing: RoomTranslationError.unavailable)
        }
        pendingOrder.removeAll { pendingIDs.contains($0) }

        let activeIDs = active.compactMap { $0.value.pair == pair ? $0.key : nil }
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
            $0.pair.targetLanguage == target && $0.pair.sourceLanguage == current
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
