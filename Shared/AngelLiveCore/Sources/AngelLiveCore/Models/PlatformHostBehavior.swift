import Foundation

public enum FavoriteIdentityKey: String, Sendable {
    case roomId
    case userId
}

public enum PlatformHostBehavior {
    public static func favoriteIdentityKey(for liveType: LiveType) -> FavoriteIdentityKey {
        guard let rawValue = behavior(for: liveType)?.favoriteIdentityKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return .roomId
        }
        switch rawValue {
        case "userid", "user_id":
            return .userId
        case "roomid", "room_id":
            return .roomId
        default:
            return .roomId
        }
    }

    public static func shouldPreserveFavoriteRoomInfoOnRefresh(for liveType: LiveType) -> Bool {
        behavior(for: liveType)?.preserveFavoriteRoomInfoOnRefresh == true
    }

    public static func liveStateOnFavoriteRefreshFailure(for liveType: LiveType) -> LiveState {
        guard let rawValue = behavior(for: liveType)?.liveStateFailureFallback,
              let liveState = LiveState(rawValue: rawValue) else {
            return .unknow
        }
        return liveState
    }

    public static func supportsLiveEndPolling(for liveType: LiveType) -> Bool {
        if let declared = behavior(for: liveType)?.supportsLiveEndPolling {
            return declared
        }
        return PlatformCapability.supports(.liveState, for: liveType)
    }

    public static func declaredOrientation(for liveType: LiveType) -> HostContentOrientation? {
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else { return nil }
        if let selected = try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId) {
            return selected.manifest.hostBehavior?.declaredOrientation
        }
        return platform.hostBehavior?.declaredOrientation
    }

    public static func declaredOrientation(for room: LiveModel) -> HostContentOrientation? {
        declaredOrientation(for: room.liveType)
    }

    public static func isPlayableRoom(_ room: LiveModel) -> Bool {
        isPlayableRoom(room, includesOnDemand: true)
    }

    public static func isPlayableRoom(_ room: LiveModel, includesOnDemand: Bool) -> Bool {
        let platform = SandboxPluginCatalog.platform(for: room.liveType)
        let manifest = includesOnDemand
            ? platform.flatMap { try? LiveParsePlugins.shared.resolve(pluginId: $0.pluginId).manifest }
            : nil
        return isPlayableRoom(room, manifest: manifest, playableLiveStates: platform?.hostBehavior?.playableLiveStates)
    }

    static func isPlayableRoom(_ room: LiveModel, manifest: LiveParsePluginManifest?,
                               playableLiveStates: [String]? = nil) -> Bool {
        if let manifest, declaresOnDemand(manifest) { return true }
        let state = room.liveState ?? LiveState.unknow.rawValue
        guard let playableLiveStates, !playableLiveStates.isEmpty else { return state == LiveState.live.rawValue }
        return playableLiveStates.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == state && !state.isEmpty }
    }

    static func declaresOnDemand(_ manifest: LiveParsePluginManifest) -> Bool {
        manifest.hostBehavior?.selectsShortDramaEpisodes == true
            || VodPluginPolicy.isLongVideoSupported(manifest) || VodPluginPolicy.declaresVodContent(manifest)
    }

    public static func externalRoomURL(for liveType: LiveType, roomId: String, userId: String) -> URL? {
        guard var template = behavior(for: liveType)?.externalRoomURLTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !template.isEmpty else {
            return nil
        }

        template = template
            .replacingOccurrences(of: "{roomId}", with: roomId)
            .replacingOccurrences(of: "{userId}", with: userId)
        return URL(string: template)
    }

    public static func themeColorHex(for liveType: LiveType) -> String? {
        let normalized = behavior(for: liveType)?.themeColor?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func behavior(for liveType: LiveType) -> ManifestHostBehavior? {
        SandboxPluginCatalog.platform(for: liveType)?.hostBehavior
    }
}
