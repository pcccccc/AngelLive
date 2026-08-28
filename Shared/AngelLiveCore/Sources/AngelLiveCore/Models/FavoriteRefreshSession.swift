import Foundation
import CryptoKit

struct FavoriteRefreshFailureDiagnostic: Sendable, Equatable {
    let pluginId: String
    let liveType: String
    let roomFingerprint: String
    let kind: FavoriteRefreshFailureKind
    let standardCode: LiveParsePluginStandardErrorCode?
    let underlyingError: FavoriteRefreshUnderlyingError?
    let receivedHTTPResponse: Bool
    let attempts: Int
    let elapsed: Duration

    init(room: LiveModel, failure: FavoriteRefreshFailure) {
        pluginId = failure.pluginId
        liveType = room.liveType.rawValue
        let identity = "\(room.liveType.rawValue)\u{0}\(room.roomId)\u{0}\(room.userId)"
        roomFingerprint = SHA256.hash(data: Data(identity.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        kind = failure.kind
        standardCode = failure.standardCode
        underlyingError = failure.underlyingError
        receivedHTTPResponse = failure.receivedHTTPResponse
        attempts = failure.attempts
        elapsed = failure.elapsed
    }

    func logLine(generationID: UUID, index: Int, total: Int) -> String {
        let underlyingDomain = underlyingError.map { Self.quoted($0.domain) } ?? "-"
        let underlyingCode = underlyingError.map { String($0.code) } ?? "-"
        return "[FavoriteRefresh][Failure] generation=\(generationID) index=\(index)/\(total) "
            + "pluginId=\(Self.quoted(pluginId)) liveType=\(Self.quoted(liveType)) "
            + "roomFingerprint=\(roomFingerprint) "
            + "kind=\(Self.kindLabel(kind)) standardCode=\(standardCode?.rawValue ?? "-") "
            + "underlyingDomain=\(underlyingDomain) underlyingCode=\(underlyingCode) "
            + "receivedHTTPResponse=\(receivedHTTPResponse) attempts=\(attempts) elapsed=\(elapsed)"
    }

    private static func kindLabel(_ kind: FavoriteRefreshFailureKind) -> String {
        switch kind {
        case .deviceOffline: "deviceOffline"
        case .fastUnreachable(let reason): "fastUnreachable.\(reason)"
        case .timeout: "timeout"
        case .authenticationRequired: "authenticationRequired"
        case .notFound: "notFound"
        case .rateLimited: "rateLimited"
        case .blocked: "blocked"
        case .upstream: "upstream"
        case .invalidResponse: "invalidResponse"
        case .cancelled: "cancelled"
        case .unknown: "unknown"
        }
    }

    private static func quoted(_ rawValue: String) -> String {
        let bounded = String(rawValue.prefix(160))
        let escaped = bounded
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

public struct FavoriteRefreshOperation: Sendable {
    private let body: @Sendable (LiveModel, String, Bool) async throws -> LiveModel

    public init(
        _ body: @escaping @Sendable (LiveModel, String, Bool) async throws -> LiveModel
    ) {
        self.body = body
    }

    func callAsFunction(
        room: LiveModel,
        pluginId: String,
        allowNotFoundRetry: Bool
    ) async throws -> LiveModel {
        try await body(room, pluginId, allowNotFoundRetry)
    }

    public static let live = FavoriteRefreshOperation { room, pluginId, allowNotFoundRetry in
        try await ApiManager.fetchLastestLiveInfoFast(
            liveModel: room,
            resolvedPluginId: pluginId,
            allowNotFoundRetry: allowNotFoundRetry
        )
    }
}

public struct FavoritePluginIDResolver: Sendable {
    private let body: @Sendable ([LiveModel]) async -> [FavoriteResolvedPlugin]

    public init(_ body: @escaping @Sendable (LiveModel) -> String) {
        self.body = { rooms in
            rooms.map { FavoriteResolvedPlugin(pluginId: body($0)) }
        }
    }

    public init(
        batch body: @escaping @Sendable ([LiveModel]) async -> [FavoriteResolvedPlugin]
    ) {
        self.body = body
    }

    func resolve(_ rooms: [LiveModel]) async -> [FavoriteResolvedPlugin] {
        let resolved = await body(rooms)
        guard resolved.count == rooms.count else {
            return rooms.map {
                FavoriteResolvedPlugin(pluginId: "unknown:\($0.liveType.rawValue)")
            }
        }
        return resolved
    }

    /// 每轮只读取一次插件目录。后续调度、请求和 UI 都使用这份不可变快照。
    public static let catalog = FavoritePluginIDResolver(batch: { rooms in
        let installed = SandboxPluginCatalog.installedPluginMap()
        var byLiveType: [String: FavoriteResolvedPlugin] = [:]
        for metadata in installed.values {
            let liveTypes = metadata.liveTypes.isEmpty ? [metadata.pluginId] : metadata.liveTypes
            let identityKey: FavoriteIdentityKey
            switch metadata.hostBehavior?.favoriteIdentityKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
            case "userid", "user_id": identityKey = .userId
            default: identityKey = .roomId
            }
            for liveType in liveTypes where byLiveType[liveType] == nil {
                byLiveType[liveType] = FavoriteResolvedPlugin(
                    pluginId: metadata.pluginId,
                    displayName: metadata.displayName,
                    identityKey: identityKey,
                    preserveFavoriteRoomInfoOnRefresh:
                        metadata.hostBehavior?.preserveFavoriteRoomInfoOnRefresh == true
                )
            }
        }
        return rooms.map { room in
            byLiveType[room.liveType.rawValue]
                ?? FavoriteResolvedPlugin(pluginId: "unknown:\(room.liveType.rawValue)")
        }
    })
}

public struct FavoriteHTTPFailureCacheInvalidator: Sendable {
    private let body: @Sendable () async -> Void

    public init(_ body: @escaping @Sendable () async -> Void) {
        self.body = body
    }

    func invalidate() async {
        await body()
    }

    public static let none = FavoriteHTTPFailureCacheInvalidator {}
    public static let live = FavoriteHTTPFailureCacheInvalidator {
        await LiveParsePlugins.invalidateHTTPFailureCaches()
    }
}

/// 持有一轮收藏状态刷新。页面预算只结束前台反馈，请求仍在本 actor 管理下继续。
public actor FavoriteRefreshSession {
    private struct WorkItem: Sendable {
        let room: LiveModel
        let oldKey: String
        let pluginId: String
        let preserveFavoriteRoomInfoOnRefresh: Bool
    }

    private enum CircuitState: Sendable {
        case closed
        case suspect
        case reachable
        case open
    }

    private struct PluginState: Sendable {
        let pluginId: String
        let total: Int
        var queue: [WorkItem]
        var inFlight = 0
        var completed = 0
        var success = 0
        var failure = 0
        var skipped = 0
        var connectionLosses = 0
        var circuit: CircuitState = .closed
        var unavailableEmitted = false
    }

    private enum AttemptOutcome: Sendable {
        case success(WorkItem, LiveModel)
        case failure(WorkItem, FavoriteRefreshFailure)
        case cancelled(WorkItem)

        var item: WorkItem {
            switch self {
            case .success(let item, _), .failure(let item, _), .cancelled(let item): item
            }
        }
    }

    private struct ActiveGeneration {
        let id: UUID
        let startedAt: Duration
        let eventContinuation: AsyncStream<FavoriteRefreshEvent>.Continuation
        let foregroundContinuation: AsyncStream<Void>.Continuation
        var runTask: Task<Void, Never>?
        var foregroundTimer: Task<Void, Never>?
        var foregroundFinished = false
        var foregroundDuration: Duration = .zero
        var pluginProgress: [String: (completed: Int, total: Int)]
    }

    private let operation: FavoriteRefreshOperation
    private let timing: any FavoriteRefreshTiming
    private let pathObserver: any FavoriteNetworkPathObserving
    private let pluginResolver: FavoritePluginIDResolver
    private let failureCacheInvalidator: FavoriteHTTPFailureCacheInvalidator
    private let policy: FavoriteRefreshRequestPolicy

    private var active: ActiveGeneration?
    private var lastPathRevision: UInt64?

    public init(
        operation: FavoriteRefreshOperation = .live,
        timing: (any FavoriteRefreshTiming)? = nil,
        pathObserver: any FavoriteNetworkPathObserving = NetworkPathObserver.shared,
        pluginResolver: FavoritePluginIDResolver = .catalog,
        failureCacheInvalidator: FavoriteHTTPFailureCacheInvalidator = .live,
        policy: FavoriteRefreshRequestPolicy = .default
    ) {
        self.operation = operation
        self.timing = timing ?? ContinuousFavoriteRefreshTiming()
        self.pathObserver = pathObserver
        self.pluginResolver = pluginResolver
        self.failureCacheInvalidator = failureCacheInvalidator
        self.policy = policy
    }

    public func start(
        members: [LiveModel],
        trigger: FavoriteRefreshTrigger
    ) async -> FavoriteRefreshHandle {
        cancelActiveGeneration()

        let resolutions = await pluginResolver.resolve(members)
        let workItems = zip(members, resolutions).map { room, resolution in
            WorkItem(
                room: room,
                oldKey: AppFavoriteModel.favoriteUniqueKey(
                    for: room,
                    identityKey: resolution.identityKey
                ),
                pluginId: resolution.pluginId,
                preserveFavoriteRoomInfoOnRefresh:
                    resolution.preserveFavoriteRoomInfoOnRefresh
            )
        }

        let pathRevision = await pathObserver.currentRevision()
        let pathChanged = lastPathRevision.map { $0 != pathRevision } ?? false
        lastPathRevision = pathRevision
        if trigger == .manual || trigger == .pathRecovery || pathChanged {
            await failureCacheInvalidator.invalidate()
        }

        let generationID = UUID()
        let startedAt = await timing.now()
        let bufferSize = max(16, members.count * 4 + 8)
        let (events, eventContinuation) = AsyncStream.makeStream(
            of: FavoriteRefreshEvent.self,
            bufferingPolicy: .bufferingNewest(bufferSize)
        )
        let (foregroundSignal, foregroundContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        let foregroundCompletion = Task {
            var iterator = foregroundSignal.makeAsyncIterator()
            _ = await iterator.next()
        }

        let groupedWorkItems = Dictionary(grouping: workItems, by: \.pluginId)
        let progress = groupedWorkItems.mapValues { (completed: 0, total: $0.count) }
        let pluginTotals = groupedWorkItems.mapValues(\.count)
        let pluginDisplayNames = Dictionary(
            zip(resolutions.map(\.pluginId), resolutions.map(\.displayName)),
            uniquingKeysWith: { first, _ in first }
        )
        let pluginIDsByRoomKey = Dictionary(
            workItems.map { ($0.oldKey, $0.pluginId) },
            uniquingKeysWith: { first, _ in first }
        )
        let identityKeysByLiveType = Dictionary(
            zip(members.map { $0.liveType.rawValue }, resolutions.map(\.identityKey)),
            uniquingKeysWith: { first, _ in first }
        )
        active = ActiveGeneration(
            id: generationID,
            startedAt: startedAt,
            eventContinuation: eventContinuation,
            foregroundContinuation: foregroundContinuation,
            pluginProgress: progress
        )
        eventContinuation.onTermination = { [weak self] _ in
            Task { await self?.consumerTerminated(generationID: generationID) }
        }
        eventContinuation.yield(.started(generationID: generationID, total: members.count))

        let sessionTiming = timing
        let foregroundBudget = policy.foregroundBudget
        let timer = Task { [weak self] in
            do {
                try await sessionTiming.sleep(for: foregroundBudget)
                await self?.finishForeground(generationID: generationID)
            } catch {
                // 新代际或会话结束会取消计时器，不产生旧代际事件。
            }
        }
        active?.foregroundTimer = timer

        let runTask = Task { [weak self] in
            guard let self else { return }
            await self.run(generationID: generationID, workItems: workItems)
        }
        active?.runTask = runTask

        Logger.debug(
            "[FavoriteRefresh] generation=\(generationID) rooms=\(members.count) plugins=\(progress.count) trigger=\(trigger)",
            category: .favorite
        )

        return FavoriteRefreshHandle(
            generationID: generationID,
            events: events,
            foregroundCompletion: foregroundCompletion,
            pluginTotals: pluginTotals,
            pluginDisplayNames: pluginDisplayNames,
            pluginIDsByRoomKey: pluginIDsByRoomKey,
            identityKeysByLiveType: identityKeysByLiveType,
            roomKeys: workItems.map(\.oldKey)
        )
    }

    public func cancel() {
        cancelActiveGeneration()
    }

    private func run(generationID: UUID, workItems: [WorkItem]) async {
        guard isCurrent(generationID) else { return }
        let pathStatus = await pathObserver.currentStatus()
        guard isCurrent(generationID) else { return }

        if pathStatus == .unsatisfied {
            await finishWithoutNetwork(generationID: generationID, workItems: workItems)
            return
        }

        var states = makePluginStates(workItems: workItems)
        var activeRequestCount = 0
        var nextPluginOffset = 0
        var firstPatchDuration: Duration?
        var failureDiagnostics: [FavoriteRefreshFailureDiagnostic] = []

        await withTaskGroup(of: AttemptOutcome.self) { group in
            while isCurrent(generationID), !Task.isCancelled {
                while activeRequestCount < policy.maximumConcurrentRequests,
                      let candidate = nextWorkItem(states: &states, offset: &nextPluginOffset) {
                    guard var state = states[candidate.pluginId] else { continue }
                    state.inFlight += 1
                    let allowNotFoundRetry = state.success == 0
                    states[candidate.pluginId] = state
                    activeRequestCount += 1
                    let operation = self.operation
                    group.addTask {
                        do {
                            let room = try await operation(
                                room: candidate.room,
                                pluginId: candidate.pluginId,
                                allowNotFoundRetry: allowNotFoundRetry
                            )
                            return .success(candidate, room)
                        } catch is CancellationError {
                            return .cancelled(candidate)
                        } catch {
                            let failure = favoriteRefreshFailure(
                                from: error,
                                pluginId: candidate.pluginId
                            )
                            return .failure(candidate, failure)
                        }
                    }
                }

                guard activeRequestCount > 0 else { break }
                guard let outcome = await group.next() else { break }
                activeRequestCount -= 1

                guard isCurrent(generationID), !Task.isCancelled else {
                    group.cancelAll()
                    break
                }

                let item = outcome.item
                guard var state = states[item.pluginId] else { continue }
                state.inFlight = max(0, state.inFlight - 1)
                state.completed += 1
                var deviceOfflineDetected = false

                switch outcome {
                case .success(_, let refreshed):
                    state.success += 1
                    state.circuit = .reachable
                    state.connectionLosses = 0
                    if item.preserveFavoriteRoomInfoOnRefresh {
                        var merged = item.room
                        merged.liveState = refreshed.liveState
                        active?.eventContinuation.yield(.roomUpdated(
                            generationID: generationID,
                            oldKey: item.oldKey,
                            room: merged
                        ))
                    } else {
                        active?.eventContinuation.yield(.roomUpdated(
                            generationID: generationID,
                            oldKey: item.oldKey,
                            room: refreshed
                        ))
                    }
                    if firstPatchDuration == nil {
                        firstPatchDuration = await elapsed(generationID: generationID)
                    }

                case .failure(_, let failure):
                    state.failure += 1
                    failureDiagnostics.append(
                        FavoriteRefreshFailureDiagnostic(room: item.room, failure: failure)
                    )
                    deviceOfflineDetected = failure.kind == .deviceOffline
                    active?.eventContinuation.yield(.roomStale(
                        generationID: generationID,
                        key: item.oldKey,
                        reason: failure.kind
                    ))
                    updateCircuit(state: &state, failure: failure.kind)

                case .cancelled:
                    // 调用自身取消不是业务失败，不改变旧状态、新鲜度或熔断计数。
                    break
                }

                if state.circuit == .open {
                    let skippedItems = state.queue
                    if !skippedItems.isEmpty {
                        state.queue.removeAll(keepingCapacity: false)
                        state.skipped += skippedItems.count
                        state.completed += skippedItems.count
                        let reason = circuitSkipReason(for: outcome)
                        for skipped in skippedItems {
                            active?.eventContinuation.yield(.roomStale(
                                generationID: generationID,
                                key: skipped.oldKey,
                                reason: reason
                            ))
                        }
                    }
                    if !state.unavailableEmitted {
                        state.unavailableEmitted = true
                        active?.eventContinuation.yield(.pluginUnavailable(
                            generationID: generationID,
                            pluginId: state.pluginId,
                            skipped: skippedItems.count
                        ))
                    }
                }

                states[item.pluginId] = state
                updateProgress(generationID: generationID, state: state)

                if deviceOfflineDetected {
                    // 路径快照之后 URLSession 仍可能确认整机断网；停止全部尚未启动的请求。
                    for pluginId in states.keys.sorted() {
                        guard var offlineState = states[pluginId] else { continue }
                        let skippedItems = offlineState.queue
                        offlineState.queue.removeAll(keepingCapacity: false)
                        offlineState.skipped += skippedItems.count
                        offlineState.completed += skippedItems.count
                        offlineState.circuit = .open
                        for skipped in skippedItems {
                            active?.eventContinuation.yield(.roomStale(
                                generationID: generationID,
                                key: skipped.oldKey,
                                reason: .deviceOffline
                            ))
                        }
                        if !offlineState.unavailableEmitted {
                            offlineState.unavailableEmitted = true
                            active?.eventContinuation.yield(.pluginUnavailable(
                                generationID: generationID,
                                pluginId: pluginId,
                                skipped: skippedItems.count
                            ))
                        }
                        states[pluginId] = offlineState
                        updateProgress(generationID: generationID, state: offlineState)
                    }
                }
            }
            group.cancelAll()
        }

        guard isCurrent(generationID) else { return }
        let fullDuration = await elapsed(generationID: generationID)
        let pluginSummaries = states.values
            .map {
                FavoritePluginRefreshSummary(
                    pluginId: $0.pluginId,
                    total: $0.total,
                    success: $0.success,
                    failure: $0.failure,
                    skipped: $0.skipped
                )
            }
            .sorted { $0.pluginId < $1.pluginId }
        let summary = FavoriteRefreshSummary(
            generationID: generationID,
            total: workItems.count,
            succeeded: pluginSummaries.reduce(0) { $0 + $1.success },
            failed: pluginSummaries.reduce(0) { $0 + $1.failure },
            skipped: pluginSummaries.reduce(0) { $0 + $1.skipped },
            timeToFirstPatch: firstPatchDuration,
            foregroundDuration: active?.foregroundFinished == true
                ? (active?.foregroundDuration ?? fullDuration)
                : fullDuration,
            fullDuration: fullDuration,
            plugins: pluginSummaries
        )
        logFailures(generationID: generationID, diagnostics: failureDiagnostics)
        await complete(generationID: generationID, summary: summary)
    }

    private func makePluginStates(workItems: [WorkItem]) -> [String: PluginState] {
        Dictionary(grouping: workItems, by: \.pluginId).mapValues { pluginItems in
            PluginState(
                pluginId: pluginItems[0].pluginId,
                total: pluginItems.count,
                queue: pluginItems
            )
        }
    }

    private func nextWorkItem(
        states: inout [String: PluginState],
        offset: inout Int
    ) -> WorkItem? {
        let pluginIds = states.keys.sorted()
        guard !pluginIds.isEmpty else { return nil }

        for step in 0..<pluginIds.count {
            let index = (offset + step) % pluginIds.count
            let pluginId = pluginIds[index]
            guard var state = states[pluginId],
                  state.circuit != .open,
                  state.inFlight < policy.maximumConcurrentRequestsPerPlugin,
                  !state.queue.isEmpty else { continue }
            let item = state.queue.removeFirst()
            states[pluginId] = state
            offset = (index + 1) % pluginIds.count
            return item
        }
        return nil
    }

    private func updateCircuit(
        state: inout PluginState,
        failure: FavoriteRefreshFailureKind
    ) {
        switch failure {
        case .deviceOffline,
             .fastUnreachable(.noRoute),
             .fastUnreachable(.dns),
             .fastUnreachable(.connectionRefused):
            state.circuit = .open

        case .fastUnreachable(.connectionLost),
             .fastUnreachable(.otherConnectionFailure):
            state.connectionLosses += 1
            if state.connectionLosses >= 2 {
                state.circuit = .open
            } else if state.circuit != .reachable {
                state.circuit = .suspect
            }

        case .timeout, .authenticationRequired, .notFound, .rateLimited,
             .blocked, .upstream, .invalidResponse, .cancelled, .unknown:
            state.connectionLosses = 0
            if state.circuit != .reachable {
                state.circuit = .closed
            }
        }
    }

    private func circuitSkipReason(for outcome: AttemptOutcome) -> FavoriteRefreshFailureKind {
        if case .failure(_, let failure) = outcome {
            return failure.kind
        }
        return .unknown
    }

    private func updateProgress(generationID: UUID, state: PluginState) {
        guard active?.id == generationID else { return }
        active?.pluginProgress[state.pluginId] = (state.completed, state.total)
        // UI 不展示逐房间精确计数；按固定桶发布，避免大收藏列表把 MainActor 淹没。
        guard state.completed == 1
                || state.completed == state.total
                || state.completed.isMultiple(of: 8) else { return }
        active?.eventContinuation.yield(.pluginProgress(
            generationID: generationID,
            pluginId: state.pluginId,
            completed: state.completed,
            total: state.total
        ))
    }

    private func finishWithoutNetwork(
        generationID: UUID,
        workItems: [WorkItem]
    ) async {
        let grouped = Dictionary(grouping: workItems, by: \.pluginId)
        for (pluginId, items) in grouped {
            for item in items {
                active?.eventContinuation.yield(.roomStale(
                    generationID: generationID,
                    key: item.oldKey,
                    reason: .deviceOffline
                ))
            }
            active?.eventContinuation.yield(.pluginUnavailable(
                generationID: generationID,
                pluginId: pluginId,
                skipped: items.count
            ))
            active?.pluginProgress[pluginId] = (items.count, items.count)
        }
        let duration = await elapsed(generationID: generationID)
        let summaries = grouped.map { pluginId, items in
            FavoritePluginRefreshSummary(
                pluginId: pluginId,
                total: items.count,
                success: 0,
                failure: 0,
                skipped: items.count
            )
        }.sorted { $0.pluginId < $1.pluginId }
        let summary = FavoriteRefreshSummary(
            generationID: generationID,
            total: workItems.count,
            succeeded: 0,
            failed: 0,
            skipped: workItems.count,
            timeToFirstPatch: nil,
            foregroundDuration: duration,
            fullDuration: duration,
            plugins: summaries
        )
        await complete(generationID: generationID, summary: summary)
    }

    private func finishForeground(generationID: UUID) async {
        guard var current = active,
              current.id == generationID,
              !current.foregroundFinished else { return }
        current.foregroundFinished = true
        current.foregroundDuration = max(await timing.now() - current.startedAt, .zero)
        let pending = Set(current.pluginProgress.compactMap { pluginId, progress in
            progress.completed < progress.total ? pluginId : nil
        })
        current.eventContinuation.yield(.foregroundFinished(
            generationID: generationID,
            pendingPluginIds: pending
        ))
        current.foregroundContinuation.yield(())
        current.foregroundContinuation.finish()
        active = current
        Logger.debug(
            "[FavoriteRefresh] generation=\(generationID) foregroundFinished pendingPlugins=\(pending.count) duration=\(current.foregroundDuration)",
            category: .favorite
        )
    }

    private func complete(
        generationID: UUID,
        summary: FavoriteRefreshSummary
    ) async {
        await finishForeground(generationID: generationID)
        guard let current = active, current.id == generationID else { return }
        current.eventContinuation.yield(.completed(generationID: generationID, summary: summary))
        current.eventContinuation.finish()
        current.foregroundTimer?.cancel()
        active = nil
        Logger.debug(
            "[FavoriteRefresh] generation=\(generationID) completed success=\(summary.succeeded) failure=\(summary.failed) skipped=\(summary.skipped) firstPatch=\(String(describing: summary.timeToFirstPatch)) fullDuration=\(summary.fullDuration)",
            category: .favorite
        )
    }

    private func logFailures(
        generationID: UUID,
        diagnostics: [FavoriteRefreshFailureDiagnostic]
    ) {
        guard !diagnostics.isEmpty else { return }
        let sorted = diagnostics.sorted {
            ($0.pluginId, $0.liveType, $0.roomFingerprint)
                < ($1.pluginId, $1.liveType, $1.roomFingerprint)
        }
        let pluginCounts = Dictionary(grouping: sorted, by: \.pluginId)
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        Logger.warning(
            "[FavoriteRefresh][FailureSummary] generation=\(generationID) total=\(sorted.count) byPlugin=\(pluginCounts)",
            category: .favorite
        )
        for (offset, diagnostic) in sorted.enumerated() {
            Logger.warning(
                diagnostic.logLine(
                    generationID: generationID,
                    index: offset + 1,
                    total: sorted.count
                ),
                category: .favorite
            )
        }
    }

    private func elapsed(generationID: UUID) async -> Duration {
        guard let current = active, current.id == generationID else { return .zero }
        return max(await timing.now() - current.startedAt, .zero)
    }

    private func isCurrent(_ generationID: UUID) -> Bool {
        active?.id == generationID
    }

    private func consumerTerminated(generationID: UUID) {
        guard active?.id == generationID else { return }
        cancelActiveGeneration()
    }

    private func cancelActiveGeneration() {
        guard let current = active else { return }
        active = nil
        current.runTask?.cancel()
        current.foregroundTimer?.cancel()
        current.foregroundContinuation.yield(())
        current.foregroundContinuation.finish()
        current.eventContinuation.finish()
    }
}
