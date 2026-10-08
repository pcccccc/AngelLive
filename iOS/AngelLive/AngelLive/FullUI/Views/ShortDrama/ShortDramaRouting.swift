import AngelLiveCore

/// Routing is scoped to FullUI and follows the same selected plugin version as playback.
enum ShortDramaRouting {
    static func isShortDrama(_ room: LiveModel) -> Bool {
        guard let platform = SandboxPluginCatalog.platform(for: room.liveType),
              let plugin = try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId) else {
            return false
        }
        let behavior = plugin.manifest.hostBehavior
        return behavior?.contentKind == "shortDrama"
            && behavior?.episodeSelection == "qualityList"
    }
}
