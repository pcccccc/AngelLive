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

    public var completedCount: Int { outcomes.count }
    public var successCount: Int { outcomes.values.filter { $0 == .updated }.count }
    public var failedPluginIds: [String] {
        pluginIds.filter { if case .failed = outcomes[$0] { true } else { false } }
    }

    public init() {}

    public func clearResult() {
        guard !isRunning else { return }
        pluginIds = []
        outcomes = [:]
    }

    /// Runs a stable, deduplicated queue serially. Each failure is retained even
    /// when later updates succeed; cancellation stops before the next plugin.
    @discardableResult
    func run(
        pluginIds: [String],
        update: @MainActor (String) async -> Outcome
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

        for id in self.pluginIds {
            guard !Task.isCancelled else {
                for pendingId in self.pluginIds where outcomes[pendingId] == nil {
                    outcomes[pendingId] = .cancelled
                }
                break
            }
            currentPluginId = id
            outcomes[id] = await update(id)
            if outcomes[id] == .cancelled {
                for pendingId in self.pluginIds where outcomes[pendingId] == nil {
                    outcomes[pendingId] = .cancelled
                }
                break
            }
        }
        return successCount
    }
}
