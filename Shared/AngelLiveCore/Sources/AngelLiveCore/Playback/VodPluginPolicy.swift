public enum VodProtocol {
    public static let currentSchema = 1
    static let entryPoints: Set<String> = ["getVodWorks", "getVodDetail", "getVodPlayback"]
}

public enum VodPluginPolicy {
    public static func declaresVodContent(_ manifest: LiveParsePluginManifest) -> Bool {
        manifest.hostBehavior?.contentKind == "vod"
    }

    public static func isLongVideoSupported(_ manifest: LiveParsePluginManifest) -> Bool {
        guard let behavior = manifest.hostBehavior, behavior.contentKind == "longVideo" else { return false }
        return behavior.episodeSelection == nil || behavior.episodeSelection == "qualityList"
    }

    public static func isSupported(pluginId: String) -> Bool {
        guard let plugin = try? LiveParsePlugins.shared.resolve(pluginId: pluginId) else { return false }
        return isSupported(plugin)
    }

    public static func isSupported(_ plugin: LiveParseLoadedPlugin) -> Bool {
        status(for: plugin).isSupported
    }

    static func status(for plugin: LiveParseLoadedPlugin) -> FeatureStatus {
        let manifest = plugin.manifest
        guard declaresVodContent(manifest), manifest.hostBehavior?.episodeSelection == nil,
              (manifest.hostBehavior?.vodSchema ?? 1) == VodProtocol.currentSchema else { return .unavailable }
        return PlatformCapability.selectedStatus(.vod, plugin: plugin)
    }
}
