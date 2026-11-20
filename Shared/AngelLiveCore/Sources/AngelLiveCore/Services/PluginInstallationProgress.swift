import Observation

/// The ring measures bytes received. Once the archive has arrived, it stays
/// filled while the installer verifies, extracts, and activates the plugin.
public enum PluginInstallationProgress: Equatable, Sendable {
    case downloading(Double?)
    case verifyingAndExtracting
    case activating

    public var fractionCompleted: Double? {
        switch self {
        case .downloading(let fraction): fraction
        case .verifyingAndExtracting, .activating: 1
        }
    }
}

typealias PluginInstallationProgressHandler = @MainActor @Sendable (PluginInstallationProgress) -> Void

@MainActor
@Observable
final class PluginInstallationProgressStore {
    private(set) var values: [String: PluginInstallationProgress] = [:]

    func report(_ progress: PluginInstallationProgress, for pluginId: String) {
        let previous = values[pluginId]
        guard previous != progress else { return }
        if let previousFraction = previous?.fractionCompleted,
           let nextFraction = progress.fractionCompleted,
           nextFraction < previousFraction { return }
        values[pluginId] = progress
    }

    func clear(for pluginId: String) {
        values.removeValue(forKey: pluginId)
    }
}
