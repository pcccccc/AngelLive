import Foundation

/// Tracks committed session changes, including logout while already logged out.
/// Owned by PlatformSessionManager's actor; contains no credential material.
final class PlatformSessionMetadataRevisionStore {
    private let defaults: UserDefaults
    private let prefix = "AngelLive.SessionStore.metadataRevision."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func revision(pluginId: String) -> String {
        defaults.string(forKey: prefix + pluginId) ?? "unmodified"
    }

    @discardableResult
    func recordMutation(pluginId: String) -> String {
        let revision = UUID().uuidString
        defaults.set(revision, forKey: prefix + pluginId)
        return revision
    }
}
