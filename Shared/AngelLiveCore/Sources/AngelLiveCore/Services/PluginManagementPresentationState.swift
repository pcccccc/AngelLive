/// Platform-independent precedence for the single management summary surface.
public enum PluginManagementSummaryState: Equatable, Sendable {
    case running
    case failed
    case updates(Int)
    case checking
    case current
    case unchecked

    public static func resolve(
        isRunning: Bool,
        hasFailures: Bool,
        updateCount: Int,
        isChecking: Bool,
        isVerifiedCurrent: Bool
    ) -> Self {
        if isRunning { return .running }
        if hasFailures { return .failed }
        if updateCount > 0 { return .updates(updateCount) }
        if isChecking { return .checking }
        return isVerifiedCurrent ? .current : .unchecked
    }
}

/// Resolves ongoing work before stale catalog information or past results.
public enum PluginManagementRowPhase: Equatable, Sendable {
    case idle
    case install
    case update
    case queued
    case progress
    case success
    case failed(String)

    public static func resolve(
        actionState: RemotePluginCatalogActionState,
        isWaiting: Bool,
        isSuccessful: Bool
    ) -> Self {
        if isWaiting { return .queued }
        switch actionState {
        case .installing, .updating: return .progress
        case .failed(let message): return .failed(message)
        case .install, .update, .installed: break
        }
        if isSuccessful { return .success }
        switch actionState {
        case .install: return .install
        case .update: return .update
        case .installed: return .idle
        case .installing, .updating, .failed: return .idle
        }
    }
}
