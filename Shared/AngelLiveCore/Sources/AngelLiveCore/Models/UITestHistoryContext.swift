#if DEBUG
import Foundation

/// Explicit launch contract for the FullUI history smoke tests. Release builds have no test route.
public struct UITestLaunchConfiguration: Sendable {
    public enum ConfigurationError: Error, Equatable { case invalidArguments, missingState, unsafeDirectory }

    public let runID: UUID
    public let resetsState: Bool

    public static func current(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> Self? {
        let reservedArguments: Set<String> = ["--ui-testing", "--ui-test-run-id", "--ui-test-reset"]
        guard !arguments.contains(where: { $0.hasPrefix("--ui-test") && !reservedArguments.contains($0) }) else {
            throw ConfigurationError.invalidArguments
        }
        guard arguments.contains("--ui-testing") else {
            if arguments.contains("--ui-test-run-id") || arguments.contains("--ui-test-reset") {
                throw ConfigurationError.invalidArguments
            }
            return nil
        }
        guard arguments.filter({ $0 == "--ui-testing" }).count == 1,
              arguments.filter({ $0 == "--ui-test-run-id" }).count == 1,
              arguments.filter({ $0 == "--ui-test-reset" }).count <= 1,
              let index = arguments.firstIndex(of: "--ui-test-run-id"),
              arguments.indices.contains(index + 1),
              let runID = UUID(uuidString: arguments[index + 1]) else {
            throw ConfigurationError.invalidArguments
        }
        return Self(runID: runID, resetsState: arguments.contains("--ui-test-reset"))
    }

    /// Shared defaults/plugin access must not silently fall back after malformed test arguments.
    static let process: Self? = {
        do { return try current() }
        catch { fatalError("Invalid UI test launch configuration: \(error)") }
    }()

    var defaultsSuiteName: String { "dev.angellive.ui-tests.\(runID.uuidString)" }
    var directory: URL { URL.cachesDirectory.appendingPathComponent("AngelLiveUITests", isDirectory: true)
        .appendingPathComponent(runID.uuidString, isDirectory: true) }
    var defaults: UserDefaults { UserDefaults(suiteName: defaultsSuiteName)! }
}

@MainActor
public struct UITestHistoryContext {
    public let history: HistoryModel
    public let progress: ShortDramaProgressStore
    public let favorite: AppFavoriteModel
    public let directory: URL

    /// Call once per app launch, before constructing the real history page.
    /// Relaunch with the same run ID and without reset to verify persisted mutations.
    public static func prepare(configuration: UITestLaunchConfiguration) throws -> Self {
        let directory = configuration.directory
        let fileManager = FileManager.default
        // A reset is never permitted to follow a symlink outside this UUID's test root.
        for candidate in [directory.deletingLastPathComponent(), directory] {
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw UITestLaunchConfiguration.ConfigurationError.unsafeDirectory
            }
        }
        let marker = directory.appendingPathComponent("history-seeded")
        let defaults = configuration.defaults
        if configuration.resetsState {
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
            defaults.removePersistentDomain(forName: configuration.defaultsSuiteName)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: marker.path) {
            throw UITestLaunchConfiguration.ConfigurationError.missingState
        }

        let history = HistoryModel(defaults: defaults)
        // No plugin resolution is needed to classify these explicit history fixtures.
        let progress = ShortDramaProgressStore(
            directory: directory.appendingPathComponent("ShortDramaProgress", isDirectory: true),
            write: { data, url in try data.write(to: url, options: .atomic) },
            resolveHistoryPlugin: { _ in nil }
        )
        if configuration.resetsState {
            for suffix in ["b", "a"] {
                history.addHistory(room: room(id: "live-\(suffix)", title: "测试直播 \(suffix.uppercased())", type: "fixture.live"))
            }
            for (index, suffix) in ["a", "b"].enumerated() {
                let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "drama-\(suffix)")
                let episodeID = "episode-\(index + 1)"
                let date = Date(timeIntervalSince1970: 1_700_000_100 - Double(index))
                let metadata = ShortDramaHistoryMetadata(
                    room: room(id: key.roomID, title: "测试短剧 \(suffix.uppercased())", type: "fixture.drama"),
                    episodeID: episodeID, episodeTitle: "第\(index + 1)集", episodeNumber: index + 1,
                    lastWatchedAt: date
                )
                try progress.updateEpisode(.init(position: Double((index + 1) * 30), duration: 300,
                                                 completed: false, updatedAt: date),
                                           episodeID: episodeID, for: key, historyMetadata: metadata)
                try progress.flush(for: key)
            }
            defaults.set(false, forKey: "AppFavoriteModel.favoriteICloudSyncEnabled")
            defaults.synchronize()
            try Data("1".utf8).write(to: marker, options: .atomic)
        }
        progress.loadHistory()
        // Construction stores callbacks but starts no requests or synchronization.
        let refresh = FavoriteRefreshSession(
            operation: FavoriteRefreshOperation { _, _, _ in throw CancellationError() },
            pathObserver: UITestOfflinePath(),
            pluginResolver: FavoritePluginIDResolver { _ in "fixture.plugin" },
            failureCacheInvalidator: .none
        )
        let favorite = AppFavoriteModel(refreshSession: refresh, defaults: defaults)
        return Self(history: history, progress: progress, favorite: favorite, directory: directory)
    }

    private static func room(id: String, title: String, type: LiveType) -> LiveModel {
        LiveModel(userName: "测试主播", roomTitle: title, roomCover: "", userHeadImg: "",
                  liveType: type, liveState: nil, userId: "fixture-user", roomId: id, liveWatchedCount: nil)
    }
}

private struct UITestOfflinePath: FavoriteNetworkPathObserving {
    func currentStatus() async -> FavoriteNetworkPathStatus { .unsatisfied }
}
#endif
