import Foundation
import Observation

/// Holds one reversible removal intent without changing storage or the runtime.
@MainActor
@Observable
public final class PluginDeferredUninstall {
    public private(set) var pendingUninstallPluginId: String?
    public private(set) var pendingUninstallDeadline: Date?

    @ObservationIgnored private let canUninstall: @MainActor (String) -> Bool
    @ObservationIgnored private let uninstall: @MainActor (String) -> Bool
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UUID?

    public init(
        delay: Duration = .seconds(5),
        canUninstall: @escaping @MainActor (String) -> Bool,
        uninstall: @escaping @MainActor (String) -> Bool,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
        self.canUninstall = canUninstall
        self.uninstall = uninstall
        self.sleep = sleep
    }

    deinit {
        commitTask?.cancel()
    }

    @discardableResult
    public func stageUninstall(pluginId: String) -> Bool {
        guard canUninstall(pluginId) else { return false }
        guard pendingUninstallPluginId != pluginId else { return true }
        commitPendingUninstall()
        pendingUninstallPluginId = pluginId
        let components = delay.components
        pendingUninstallDeadline = Date().addingTimeInterval(
            Double(components.seconds) + Double(components.attoseconds) / 1e18
        )
        let token = UUID()
        generation = token
        let sleep = sleep
        let delay = delay
        commitTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.commitPendingUninstall()
        }
        return true
    }

    public func undoPendingUninstall() {
        clearPending()
    }

    /// An empty commit is successful, making lifecycle flushes idempotent.
    /// Failure still clears the intent so the caller can show the plugin again.
    @discardableResult
    public func commitPendingUninstall() -> Bool {
        guard let pluginId = pendingUninstallPluginId else { return true }
        clearPending()
        return uninstall(pluginId)
    }

    private func clearPending() {
        commitTask?.cancel()
        commitTask = nil
        generation = nil
        pendingUninstallPluginId = nil
        pendingUninstallDeadline = nil
    }
}
