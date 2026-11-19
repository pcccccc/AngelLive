import Foundation
import Observation

/// An install operation owned by the source manager. The queue and its result
/// survive management-page navigation so iOS callers can render one consistent
/// installation status.
@MainActor
@Observable
public final class PluginInstallBatch {
    public enum Outcome: Equatable, Sendable {
        case installed
        case failed(String)
        case cancelled
    }

    public private(set) var pluginIds: [String] = []
    public private(set) var displayNames: [String: String] = [:]
    public private(set) var outcomes: [String: Outcome] = [:]
    public private(set) var currentPluginId: String?
    public private(set) var isRunning = false

    @available(*, deprecated, message: "Use remainingCount for the batch summary and per-plugin installation progress for the ring.")
    public var completedCount: Int { outcomes.count }
    public var remainingCount: Int { isRunning ? pluginIds.count - outcomes.count : 0 }
    public var successCount: Int { outcomes.values.filter { $0 == .installed }.count }
    public var failedPluginIds: [String] {
        pluginIds.filter { if case .failed = outcomes[$0] { true } else { false } }
    }
    public var cancelledCount: Int {
        outcomes.values.filter { $0 == .cancelled }.count
    }

    @ObservationIgnored private let operation = PluginBatchOperation<Outcome?>()

    public init() {}

    public func clearResult() {
        guard !isRunning else { return }
        pluginIds = []
        displayNames = [:]
        outcomes = [:]
        currentPluginId = nil
    }

    func isPending(_ pluginId: String) -> Bool {
        isRunning && outcomes[pluginId] == nil && pluginIds.contains(pluginId)
    }

    func cancel(_ pluginId: String) {
        guard isPending(pluginId) else { return }
        if currentPluginId == pluginId {
            operation.cancel()
        } else {
            outcomes[pluginId] = .cancelled
        }
    }

    /// Known login plugins are confirmed up front. An install that returns nil
    /// is staged for one shared confirmation after the initial queue finishes.
    @discardableResult
    func run(
        pluginIds: [String],
        displayNames: [String: String] = [:],
        knownLoginPluginIds: Set<String> = [],
        requestLoginConsent: (@MainActor ([String]) async -> Bool)? = nil,
        activateDeferred: (@MainActor (String) async -> Outcome)? = nil,
        install: @escaping @MainActor (String) async -> Outcome?
    ) async -> Int {
        guard !isRunning, !pluginIds.isEmpty else { return 0 }

        var seen = Set<String>()
        let snapshot = pluginIds.filter { seen.insert($0).inserted }
        guard !snapshot.isEmpty else { return 0 }

        self.pluginIds = snapshot
        self.displayNames = displayNames.filter { snapshot.contains($0.key) }
        outcomes = [:]
        currentPluginId = nil
        isRunning = true
        defer {
            currentPluginId = nil
            isRunning = false
        }

        guard !Task.isCancelled else {
            cancelPending()
            return 0
        }
        let loginIds = snapshot.filter { knownLoginPluginIds.contains($0) }
        if !loginIds.isEmpty, let requestLoginConsent {
            let approved = await requestLoginConsent(loginIds)
            guard approved, !Task.isCancelled else {
                cancelPending()
                return 0
            }
        }

        var deferredIds: [String] = []
        for id in snapshot where outcomes[id] == nil {
            guard !Task.isCancelled else {
                cancelPending()
                return successCount
            }
            currentPluginId = id
            let outcome = await operation.run { await install(id) }
            if let outcome {
                outcomes[id] = outcome
            } else if operation.wasCancelledIndividually {
                outcomes[id] = .cancelled
            } else {
                deferredIds.append(id)
            }
            if operation.shouldStopQueue || (outcome == .cancelled && !operation.wasCancelledIndividually) {
                cancelPending()
                return successCount
            }
        }
        currentPluginId = nil
        deferredIds.removeAll { outcomes[$0] != nil }
        if !deferredIds.isEmpty, !Task.isCancelled, let activateDeferred,
           await requestLoginConsent?(deferredIds) == true {
            for id in deferredIds where outcomes[id] == nil {
                guard !Task.isCancelled else { break }
                currentPluginId = id
                let outcome = await operation.run { await activateDeferred(id) }
                outcomes[id] = outcome
                if operation.shouldStopQueue || (outcome == .cancelled && !operation.wasCancelledIndividually) { break }
            }
        }
        cancelPending()
        return successCount
    }

    private func cancelPending() {
        for id in pluginIds where outcomes[id] == nil {
            outcomes[id] = .cancelled
        }
    }
}

/// A child operation can be cancelled separately from its serial queue.
/// Propagate cancellation of the caller to the same child.
@MainActor
final class PluginBatchOperation<Result: Sendable> {
    private var task: Task<Result, Never>?
    private(set) var wasCancelledIndividually = false
    private(set) var shouldStopQueue = false

    func run(_ operation: @escaping @MainActor () async -> Result) async -> Result {
        wasCancelledIndividually = false
        let task = Task { await operation() }
        self.task = task
        defer { self.task = nil }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        shouldStopQueue = Task.isCancelled || (task.isCancelled && !wasCancelledIndividually)
        return result
    }

    func cancel() {
        wasCancelledIndividually = true
        task?.cancel()
    }
}
