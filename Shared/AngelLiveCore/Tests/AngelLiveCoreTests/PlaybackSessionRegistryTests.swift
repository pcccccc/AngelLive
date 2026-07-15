import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
@Suite("PlaybackSessionRegistry")
struct PlaybackSessionRegistryTests {
    private final class Participant: PlaybackSessionParticipant {
        let playbackSessionDescriptor: PlaybackSessionDescriptor
        private(set) var ownershipHistory: [Set<PlaybackGlobalCapability>] = []
        private(set) var releaseCount = 0

        init(
            role: PlaybackSessionRole,
            capabilities: Set<PlaybackGlobalCapability> = [.audioFocus, .nowPlaying, .remoteCommands]
        ) {
            playbackSessionDescriptor = PlaybackSessionDescriptor(
                role: role,
                supportedGlobalCapabilities: capabilities
            )
        }

        func playbackSessionDidChangeOwnedCapabilities(_ capabilities: Set<PlaybackGlobalCapability>) {
            ownershipHistory.append(capabilities)
        }

        func playbackSessionRegistryDidRequestResourceRelease() {
            releaseCount += 1
        }
    }

    @Test("Only the active surface owns process-global capabilities")
    func activeSurfaceOwnsCapabilities() {
        let registry = PlaybackSessionRegistry()
        let primary = Participant(role: .primary)
        let secondary = Participant(role: .secondary)

        #expect(registry.register(primary))
        #expect(registry.register(secondary))
        #expect(registry.activeSurfaceID == nil)

        #expect(registry.activate(primary.playbackSessionDescriptor.surfaceID))
        #expect(registry.isOwner(primary.playbackSessionDescriptor.surfaceID, of: .remoteCommands))
        #expect(!registry.isOwner(secondary.playbackSessionDescriptor.surfaceID, of: .remoteCommands))

        #expect(registry.activate(secondary.playbackSessionDescriptor.surfaceID))
        #expect(!registry.isOwner(primary.playbackSessionDescriptor.surfaceID, of: .nowPlaying))
        #expect(registry.isOwner(secondary.playbackSessionDescriptor.surfaceID, of: .nowPlaying))
        #expect(primary.ownershipHistory == [primary.playbackSessionDescriptor.supportedGlobalCapabilities, []])
        #expect(secondary.ownershipHistory == [secondary.playbackSessionDescriptor.supportedGlobalCapabilities])
    }

    @Test("Removing the active surface restores the most recently active eligible surface")
    func activeRemovalFallsBackAndReleasesResources() {
        let registry = PlaybackSessionRegistry()
        let primary = Participant(role: .primary)
        let secondary = Participant(role: .secondary)

        registry.register(primary)
        registry.register(secondary)
        registry.activate(primary.playbackSessionDescriptor.surfaceID)
        registry.activate(secondary.playbackSessionDescriptor.surfaceID)

        #expect(registry.unregister(secondary.playbackSessionDescriptor.surfaceID))
        #expect(registry.activeSurfaceID == primary.playbackSessionDescriptor.surfaceID)
        #expect(registry.isOwner(primary.playbackSessionDescriptor.surfaceID, of: .audioFocus))
        #expect(secondary.releaseCount == 1)
        #expect(primary.releaseCount == 0)
    }

    @Test("Stopping an inactive surface cannot disturb the active owner")
    func inactiveRemovalPreservesOwner() {
        let registry = PlaybackSessionRegistry()
        let active = Participant(role: .primary)
        let inactive = Participant(role: .secondary)

        registry.register(active)
        registry.register(inactive)
        registry.activate(active.playbackSessionDescriptor.surfaceID)

        #expect(registry.unregister(inactive.playbackSessionDescriptor.surfaceID))
        #expect(registry.activeSurfaceID == active.playbackSessionDescriptor.surfaceID)
        #expect(registry.owner(of: .remoteCommands) == active.playbackSessionDescriptor.surfaceID)
        #expect(active.ownershipHistory.count == 1)
        #expect(inactive.releaseCount == 1)
    }

    @Test("An ineligible surface cannot become or remain the active owner")
    func eligibilityControlsOwnership() {
        let registry = PlaybackSessionRegistry()
        let primary = Participant(role: .primary)
        let preview = Participant(role: .preview, capabilities: [.pictureInPicture])

        registry.register(primary)
        registry.register(preview, eligibleForGlobalOwnership: false)
        registry.activate(primary.playbackSessionDescriptor.surfaceID)

        #expect(!registry.activate(preview.playbackSessionDescriptor.surfaceID))
        #expect(registry.setEligibility(false, for: primary.playbackSessionDescriptor.surfaceID))
        #expect(registry.activeSurfaceID == nil)
        #expect(registry.owner(of: .remoteCommands) == nil)

        #expect(registry.setEligibility(true, for: preview.playbackSessionDescriptor.surfaceID))
        #expect(registry.activeSurfaceID == preview.playbackSessionDescriptor.surfaceID)
        #expect(registry.owner(of: .pictureInPicture) == preview.playbackSessionDescriptor.surfaceID)
        #expect(registry.owner(of: .remoteCommands) == nil)
    }

    @Test("Releasing all sessions clears ownership and releases every participant once")
    func releaseAllSessions() {
        let registry = PlaybackSessionRegistry()
        let first = Participant(role: .primary)
        let second = Participant(role: .secondary)

        registry.register(first)
        registry.register(second)
        registry.activate(first.playbackSessionDescriptor.surfaceID)
        registry.releaseAll()

        #expect(registry.sessionCount == 0)
        #expect(registry.activeSurfaceID == nil)
        #expect(first.releaseCount == 1)
        #expect(second.releaseCount == 1)
        #expect(first.ownershipHistory.last == [])
    }

    @Test("The registry does not retain playback surfaces")
    func registryHoldsParticipantsWeakly() {
        let registry = PlaybackSessionRegistry()
        var participant: Participant? = Participant(role: .primary)
        weak let weakParticipant = participant

        registry.register(participant!)
        registry.activate(participant!.playbackSessionDescriptor.surfaceID)
        participant = nil

        #expect(weakParticipant == nil)
        #expect(registry.sessionCount == 0)
        #expect(registry.activeSurfaceID == nil)
    }
}
