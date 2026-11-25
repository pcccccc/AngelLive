#if DEBUG
import Foundation

@MainActor
public struct VodDemoSandbox {
    public nonisolated static let isEnabled = ProcessInfo.processInfo.arguments.contains("-AngelLiveVodDemo")
    public nonisolated static let pluginID = "fixture.plugin"
    public nonisolated static let longVideoPluginID = "fixture.longvideo"
    public nonisolated static let unsupportedPluginID = "fixture.unsupported"
    nonisolated static let defaultsSuiteName = "dev.angellive.vod-demo"

    public static let current: Result<Self, Error> = Result { try prepare() }

    public let pluginManager: LiveParsePluginManager
    public let pluginAvailability: PluginAvailabilityService
    public let history: HistoryModel
    public let favorite: AppFavoriteModel
    public let progress: VodProgressStore

    private static func prepare() throws -> Self {
        guard isEnabled else { throw VodCatalogError.unsupportedPlugin }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AngelLiveVodDemo-\(UUID().uuidString)", isDirectory: true)
        let storage = try LiveParsePluginStorage(baseDirectory: directory.appendingPathComponent("LiveParse", isDirectory: true))
        try installFixture(pluginID: pluginID, schema: VodProtocol.currentSchema, storage: storage)
        try installFixture(pluginID: unsupportedPluginID, schema: VodProtocol.currentSchema + 1, storage: storage)
        try installLongVideoFixture(storage: storage)

        let manager = LiveParsePlugins.makeFixtureManager(storage: storage)
        let installedIDs = Array(SandboxPluginCatalog.installedPluginMap(storage: storage).keys)
        let supported = try manager.resolve(pluginId: pluginID)
        let unsupported = try manager.resolve(pluginId: unsupportedPluginID)
        let longVideo = try manager.resolve(pluginId: longVideoPluginID)
        guard Set(installedIDs) == [pluginID, unsupportedPluginID, longVideoPluginID],
              VodPluginPolicy.isSupported(supported),
              VodPluginPolicy.declaresVodContent(unsupported.manifest),
              !VodPluginPolicy.isSupported(unsupported),
              VodPluginPolicy.isLongVideoSupported(longVideo.manifest) else {
            throw VodCatalogError.unsupportedPlugin
        }
        let availability = PluginAvailabilityService(initialInstalledPluginIds: installedIDs, pluginManager: { manager })

        let defaults = UserDefaults.shared
        defaults.removePersistentDomain(forName: Self.defaultsSuiteName)
        defaults.set(false, forKey: "AppFavoriteModel.favoriteICloudSyncEnabled")
        let refresh = FavoriteRefreshSession(
            operation: FavoriteRefreshOperation { _, _, _ in throw CancellationError() },
            pathObserver: VodDemoOfflinePath(),
            pluginResolver: FavoritePluginIDResolver { _ in pluginID },
            failureCacheInvalidator: .none
        )
        let favorite = AppFavoriteModel(
            refreshSession: refresh,
            defaults: defaults,
            localStore: FavoriteLocalStore(directory: directory.appendingPathComponent("Favorites", isDirectory: true))
        )
        return Self(pluginManager: manager, pluginAvailability: availability,
                    history: HistoryModel(defaults: defaults), favorite: favorite,
                    progress: VodProgressStore(directory: directory.appendingPathComponent("Progress", isDirectory: true)))
    }

    private static func installFixture(pluginID: String, schema: Int, storage: LiveParsePluginStorage) throws {
        let version = "1.0.0"
        let directory = storage.pluginVersionDirectory(pluginId: pluginID, version: version)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = """
        {
          "pluginId": "\(pluginID)", "version": "\(version)", "apiVersion": 1, "entry": "index.js",
          "liveTypes": ["\(pluginID)"], "hostBehavior": {"contentKind": "vod", "vodSchema": \(schema)},
          "capabilities": {"vod": "available"}
        }
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        // Playback data comes from the local media fixture. The catalog requires a valid entry file.
        let entry = "globalThis.LiveParsePlugin = { apiVersion: 1 };"
        try Data(entry.utf8).write(to: directory.appendingPathComponent("index.js"), options: .atomic)
    }

    private static func installLongVideoFixture(storage: LiveParsePluginStorage) throws {
        let version = "1.0.0"
        let directory = storage.pluginVersionDirectory(pluginId: longVideoPluginID, version: version)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = """
        {
          "pluginId": "\(longVideoPluginID)", "version": "\(version)", "apiVersion": 1, "entry": "index.js",
          "liveTypes": ["\(longVideoPluginID)"], "capabilities": {"playback": "available"},
          "hostBehavior": {"contentKind": "longVideo", "orientation": "landscape", "episodeSelection": "qualityList"}
        }
        """
        let entry = """
        globalThis.LiveParsePlugin = {
          apiVersion: 1,
          getPlayback({ roomId, sampleURL }) {
            const titles = ["第01集", "山间停靠", "海岬终点"];
            return [{ cdn: "source-a", qualitys: titles.map((title, index) => ({
              roomId, title, qn: index + 1, url: index === 0 ? sampleURL : "",
              liveCodeType: "flv", liveType: "\(longVideoPluginID)", requestContext: { sampleURL },
              playbackHints: {
                isLive: false, preferredEngines: ["mePlayer"],
                selectionBehavior: index === 0 ? "direct" : "refreshOnSelect"
              }
            })) }];
          },
          refreshPlayback({ quality }) {
            if (quality.qn !== 2 && quality.qn !== 3) throw new Error("未知分集");
            return { ...quality, url: quality.requestContext.sampleURL };
          }
        };
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        try Data(entry.utf8).write(to: directory.appendingPathComponent("index.js"), options: .atomic)
    }
}

private struct VodDemoOfflinePath: FavoriteNetworkPathObserving {
    func currentStatus() async -> FavoriteNetworkPathStatus { .unsatisfied }
}
#endif
