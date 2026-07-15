import AngelLiveCore
import Combine
#if canImport(KSPlayer)
import KSPlayer
#endif

/// Binds a KSPlayer layer to AngelLive's process-wide playback ownership registry.
/// The registry owns no player objects; this bridge remains view/session scoped.
@MainActor
public final class KSPlayerPlaybackSession: ObservableObject, PlaybackSessionParticipant {
    public let playbackSessionDescriptor: PlaybackSessionDescriptor

    @Published public private(set) var ownedGlobalCapabilities: Set<PlaybackGlobalCapability> = []

    public var surfaceID: PlaybackSurfaceID {
        playbackSessionDescriptor.surfaceID
    }

    public var onResourceRelease: (@MainActor () -> Void)?

    private let registry: PlaybackSessionRegistry
    private weak var playerLayer: KSPlayerLayer?
    private var isRegistered = false

    public init(
        surfaceID: PlaybackSurfaceID = PlaybackSurfaceID(),
        role: PlaybackSessionRole,
        supportedGlobalCapabilities: Set<PlaybackGlobalCapability>,
        registry: PlaybackSessionRegistry = .shared
    ) {
        playbackSessionDescriptor = PlaybackSessionDescriptor(
            surfaceID: surfaceID,
            role: role,
            supportedGlobalCapabilities: supportedGlobalCapabilities
        )
        self.registry = registry
    }

    @discardableResult
    public func register(eligibleForGlobalOwnership: Bool = true) -> Bool {
        if isRegistered { return true }
        isRegistered = registry.register(
            self,
            eligibleForGlobalOwnership: eligibleForGlobalOwnership
        )
        return isRegistered
    }

    @discardableResult
    public func activate() -> Bool {
        guard register() else { return false }
        return registry.activate(surfaceID)
    }

    @discardableResult
    public func setEligibility(_ isEligible: Bool) -> Bool {
        guard register(eligibleForGlobalOwnership: isEligible) else { return false }
        return registry.setEligibility(isEligible, for: surfaceID)
    }

    public func attach(playerLayer: KSPlayerLayer?) {
        guard self.playerLayer !== playerLayer else { return }

        #if canImport(KSPlayer)
        if ownedGlobalCapabilities.contains(.remoteCommands),
           let oldLayer = self.playerLayer as? KSComplexPlayerLayer {
            oldLayer.removeRemoteControllEvent()
        }
        #endif

        self.playerLayer = playerLayer
        applyRemoteCommandOwnership()
    }

    public func owns(_ capability: PlaybackGlobalCapability) -> Bool {
        ownedGlobalCapabilities.contains(capability)
    }

    public func invalidate(releasingResources: Bool = false) {
        guard isRegistered else { return }
        registry.unregister(surfaceID, releasingResources: releasingResources)
        isRegistered = false
        playerLayer = nil
    }

    public func playbackSessionDidChangeOwnedCapabilities(
        _ capabilities: Set<PlaybackGlobalCapability>
    ) {
        ownedGlobalCapabilities = capabilities
        applyRemoteCommandOwnership()
    }

    public func playbackSessionRegistryDidRequestResourceRelease() {
        playerLayer?.stop()
        onResourceRelease?()
    }

    private func applyRemoteCommandOwnership() {
        #if canImport(KSPlayer)
        guard let playerLayer = playerLayer as? KSComplexPlayerLayer else { return }
        if ownedGlobalCapabilities.contains(.remoteCommands) {
            playerLayer.registerRemoteControllEvent()
        } else {
            playerLayer.removeRemoteControllEvent()
        }
        #endif
    }
}
