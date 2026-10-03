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

    public var completedCount: Int { outcomes.count }
    public var successCount: Int { outcomes.values.filter { $0 == .installed }.count }
    public var failedPluginIds: [String] {
        pluginIds.filter { if case .failed = outcomes[$0] { true } else { false } }
    }
    public var cancelledCount: Int {
        outcomes.values.filter { $0 == .cancelled }.count
    }

    public init() {}

    public func clearResult() {
        guard !isRunning else { return }
        pluginIds = []
        displayNames = [:]
        outcomes = [:]
        currentPluginId = nil
    }

    /// Runs a stable, de-duplicated queue serially. Known login plugins are
    /// confirmed once before any install starts. Rejecting that confirmation
    /// cancels the complete snapshot without invoking the installer.
    @discardableResult
    func run(
        pluginIds: [String],
        displayNames: [String: String] = [:],
        knownLoginPluginIds: Set<String> = [],
        requestLoginConsent: (@MainActor ([String]) async -> Bool)? = nil,
        install: @MainActor (String) async -> Outcome
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

        let loginIds = snapshot.filter { knownLoginPluginIds.contains($0) }
        if !loginIds.isEmpty, let requestLoginConsent {
            let approved = await requestLoginConsent(loginIds)
            guard approved, !Task.isCancelled else {
                cancelPending()
                return 0
            }
        }

        for id in snapshot {
            guard !Task.isCancelled else {
                cancelPending()
                break
            }
            currentPluginId = id
            outcomes[id] = await install(id)
            if outcomes[id] == .cancelled {
                cancelPending()
                break
            }
        }
        return successCount
    }

    private func cancelPending() {
        for id in pluginIds where outcomes[id] == nil {
            outcomes[id] = .cancelled
        }
    }
}
