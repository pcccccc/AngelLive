import Foundation

@MainActor
public enum VodHostRouting {
    public static func declaresVod(_ room: LiveModel) -> Bool {
        selectedPlugin(for: room).map { declaresVod($0.manifest) } ?? false
    }

    public static func isVod(_ room: LiveModel) -> Bool {
        selectedPlugin(for: room).map { isVod($0) } ?? false
    }

    public static func usesDirectPlayer(_ room: LiveModel) -> Bool {
        selectedPlugin(for: room).map { usesDirectPlayer($0.manifest) } ?? false
    }

    public static func preferredOrientation(for room: LiveModel) -> HostContentOrientation {
        preferredOrientation(for: selectedPlugin(for: room)?.manifest)
    }

    static func declaresVod(_ manifest: LiveParsePluginManifest) -> Bool {
        VodPluginPolicy.declaresVodContent(manifest) || usesDirectPlayer(manifest)
    }

    static func isVod(_ plugin: LiveParseLoadedPlugin) -> Bool {
        VodPluginPolicy.isSupported(plugin) || usesDirectPlayer(plugin.manifest)
    }

    static func usesDirectPlayer(_ manifest: LiveParsePluginManifest) -> Bool {
        VodPluginPolicy.isLongVideoSupported(manifest)
    }

    static func preferredOrientation(for manifest: LiveParsePluginManifest?) -> HostContentOrientation {
        manifest?.hostBehavior?.declaredOrientation ?? .landscape
    }

    public static func model(for room: LiveModel) -> VodPlaybackModel {
        #if DEBUG
        if let work = VodDemoWork.matching(room), let sandbox = try? VodDemoSandbox.current.get() {
            return work.makeModel(progressStore: sandbox.progress)
        }
        #endif
        return VodPlaybackModel(room: room)
    }

    public static func sources(for detail: VodWorkDetail, episode: VodEpisode) async throws -> [VodPlaybackSource] {
        #if DEBUG
        if VodDemoWork.isEnabled {
            return detail.pluginID == VodDemoSandbox.pluginID ? VodDemoWork.sources : []
        }
        #endif
        guard let platform = LiveParseJSPlatformManager.platform(forPluginId: detail.pluginID) else { return [] }
        // The plugin publishes its line labels with the playback response for the episode.
        let playback = try await LiveParseJSPlatformManager.getVodPlayback(
            platform: platform, workId: detail.workID, episode: episode
        )
        return playback.sources
    }

    static func selectedPlugin(for room: LiveModel) -> LiveParseLoadedPlugin? {
        #if DEBUG
        if VodDemoWork.isEnabled {
            guard let work = VodDemoWork.matching(room), let sandbox = try? VodDemoSandbox.current.get() else { return nil }
            return try? sandbox.pluginManager.resolve(pluginId: work.pluginID)
        }
        #endif
        guard let platform = SandboxPluginCatalog.platform(for: room.liveType) else { return nil }
        return try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId)
    }
}

public extension VodWorkDetail {
    func displayTags(sourceCount: Int) -> [String] {
        sourceCount > 1 ? ["多线路"] : []
    }

    func displayMetadata(formatTime: (Double) -> String) -> String {
        var parts = year.map { [String($0)] } ?? []
        parts.append(kind == .movie ? "电影" : "剧集")
        if kind == .series {
            if hasExplicitSeasons { parts.append("共 \(seasons.count) 季") }
            parts.append("\(episodes.count) 集")
        } else if let duration = episodes.first?.durationHint {
            parts.append(formatTime(duration))
        }
        return parts.joined(separator: " · ")
    }

    func playTitle(for episode: VodEpisode, snapshot: VodProgressSnapshot?, formatTime: (Double) -> String) -> String {
        let progress = snapshot?.episodes[episode.id]
        let position = progress?.completed == false ? progress?.position ?? 0 : 0
        guard position > 0 || (snapshot?.lastEpisodeID != nil && snapshot?.lastEpisodeID != episode.id) else {
            return "立即播放"
        }
        let prefix = kind == .series ? "第 \(episode.number) 集 " : ""
        return "继续观看 · \(prefix)\(formatTime(position))"
    }
}

public extension VodEpisodeProgress {
    var fractionWatched: Double? {
        guard !completed, position > 0, duration > 0 else { return nil }
        return min(1, position / duration)
    }
}
