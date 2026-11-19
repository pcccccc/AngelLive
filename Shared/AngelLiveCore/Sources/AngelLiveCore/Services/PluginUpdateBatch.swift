import Foundation
import Observation

/// A FullUI update operation. Its lifetime belongs to the source manager, so
/// closing a management page doesn't lose progress or start a second batch.
@MainActor
@Observable
public final class PluginUpdateBatch {
    public enum Outcome: Equatable, Sendable {
        case updated
        case failed(String)
        case cancelled
    }

    public private(set) var pluginIds: [String] = []
    public private(set) var outcomes: [String: Outcome] = [:]
    public private(set) var currentPluginId: String?
    public private(set) var isRunning = false

    @available(*, deprecated, message: "Use remainingCount for the batch summary and per-plugin installation progress for the ring.")
    public var completedCount: Int { outcomes.count }
    public var remainingCount: Int { isRunning ? pluginIds.count - outcomes.count : 0 }
    public var successCount: Int { outcomes.values.filter { $0 == .updated }.count }
    public var failedPluginIds: [String] {
        pluginIds.filter { if case .failed = outcomes[$0] { true } else { false } }
    }

    @ObservationIgnored private let operation = PluginBatchOperation<Outcome>()

    public init() {}

    public func clearResult() {
        guard !isRunning else { return }
        pluginIds = []
        outcomes = [:]
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

    /// Runs a stable, deduplicated queue serially. Each failure is retained even
    /// when later updates succeed; cancellation stops before the next plugin.
    @discardableResult
    func run(
        pluginIds: [String],
        update: @escaping @MainActor (String) async -> Outcome
    ) async -> Int {
        guard !isRunning, !pluginIds.isEmpty else { return 0 }
        var seen = Set<String>()
        self.pluginIds = pluginIds.filter { seen.insert($0).inserted }
        outcomes = [:]
        isRunning = true
        defer {
            currentPluginId = nil
            isRunning = false
        }

        for id in self.pluginIds where outcomes[id] == nil {
            guard !Task.isCancelled else { break }
            currentPluginId = id
            let outcome = await operation.run { await update(id) }
            outcomes[id] = outcome
            if operation.shouldStopQueue || (outcome == .cancelled && !operation.wasCancelledIndividually) { break }
        }
        for id in self.pluginIds where outcomes[id] == nil {
            outcomes[id] = .cancelled
        }
        return successCount
    }
}
