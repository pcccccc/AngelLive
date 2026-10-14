import AngelLiveCore
#if canImport(KSPlayer)
import KSPlayer
#endif

public enum KSPlayerLiveReconnectPolicy: Sendable {
    /// Preserve the plugin/resolver live semantic and allow KSPlayer's live reconnect path.
    case playerManaged
    /// Disable KSPlayer's internal live reconnect; AngelLive's recovery coordinator rebuilds the session.
    case applicationManaged
}

public struct KSPlayerAppliedSessionConfiguration {
    public let plan: RoomPlaybackPlan
    public let playerTypes: [MediaPlayerProtocol.Type]
    public let effectiveIsLive: Bool
}

/// Applies one resolved stream to one KSOptions instance without mutating global defaults.
public enum KSPlayerSessionConfigurator {
    @MainActor
    public static func apply(
        quality: LiveQualityDetail,
        to options: KSOptions,
        fallbackUserAgent: String,
        liveReconnectPolicy: KSPlayerLiveReconnectPolicy
    ) -> KSPlayerAppliedSessionConfiguration {
        let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: quality)
        let mediaTransform = quality.playbackHints?.mediaTransform
        #if canImport(KSPlayer)
        let playerTypes: [MediaPlayerProtocol.Type] = mediaTransform == nil
            ? plan.playerKinds.map(playerType(for:))
            : [MediaTransformPlayer.self]
        #else
        let playerTypes = plan.playerKinds.map(playerType(for:))
        #endif
        (options as? PlayerOptions)?.mediaTransform = mediaTransform
        let requestOptions = RoomPlaybackResolver.requestOptions(
            for: quality,
            fallbackUserAgent: fallbackUserAgent
        )

        options.userAgent = requestOptions.userAgent
        // FFmpeg consumes this as an input option when opening the format context.
        // Assignment also clears any prior stream's key when the next quality is unencrypted.
        options.formatContextOptions["decryption_key"] = quality.decryption?.key
        options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = nil
        options.formatContextOptions["headers"] = nil
        if !requestOptions.headers.isEmpty {
            options.appendHeader(requestOptions.headers)
        }

        let effectiveIsLive: Bool
        switch liveReconnectPolicy {
        case .playerManaged:
            // The composed player must reopen through the transform factory after recovery.
            effectiveIsLive = mediaTransform == nil && plan.isLive
        case .applicationManaged:
            // Some hosts may intentionally rebuild the entire session after an IO failure.
            effectiveIsLive = false
        }

        #if canImport(KSPlayer)
        options.playerTypes = playerTypes
        options.isLive = effectiveIsLive
        #endif

        return KSPlayerAppliedSessionConfiguration(
            plan: plan,
            playerTypes: playerTypes,
            effectiveIsLive: effectiveIsLive
        )
    }

    @MainActor
    private static func playerType(for kind: RoomPlaybackPlayerKind) -> MediaPlayerProtocol.Type {
        switch kind {
        case .avPlayer:
            KSAVPlayer.self
        case .mePlayer:
            KSMEPlayer.self
        }
    }
}
