import Foundation

public struct PlaybackSurfaceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}

public enum PlaybackSessionRole: Int, Codable, Sendable, CaseIterable {
    case preview
    case auxiliary
    case secondary
    case primary
}

public enum PlaybackGlobalCapability: String, Codable, Hashable, Sendable, CaseIterable {
    case audioFocus
    case nowPlaying
    case pictureInPicture
    case remoteCommands
}

public struct PlaybackSessionDescriptor: Equatable, Sendable {
    public let surfaceID: PlaybackSurfaceID
    public var role: PlaybackSessionRole
    public var supportedGlobalCapabilities: Set<PlaybackGlobalCapability>

    public init(
        surfaceID: PlaybackSurfaceID = PlaybackSurfaceID(),
        role: PlaybackSessionRole,
        supportedGlobalCapabilities: Set<PlaybackGlobalCapability> = []
    ) {
        self.surfaceID = surfaceID
        self.role = role
        self.supportedGlobalCapabilities = supportedGlobalCapabilities
    }
}

public struct PlaybackSessionSnapshot: Equatable, Sendable {
    public let descriptor: PlaybackSessionDescriptor
    public let isEligibleForGlobalOwnership: Bool
    public let isActive: Bool
    public let ownedGlobalCapabilities: Set<PlaybackGlobalCapability>
}

@MainActor
public protocol PlaybackSessionParticipant: AnyObject {
    var playbackSessionDescriptor: PlaybackSessionDescriptor { get }

    func playbackSessionDidChangeOwnedCapabilities(_ capabilities: Set<PlaybackGlobalCapability>)
    func playbackSessionRegistryDidRequestResourceRelease()
}

/// Arbitrates process-global media capabilities without owning player implementations.
/// Participants remain weakly held so a forgotten unregister cannot retain a playback surface.
@MainActor
public final class PlaybackSessionRegistry {
    public static let shared = PlaybackSessionRegistry()

    private final class WeakParticipant {
        weak var value: (any PlaybackSessionParticipant)?

        init(_ value: any PlaybackSessionParticipant) {
            self.value = value
        }
    }

    private struct Entry {
        let participant: WeakParticipant
        var descriptor: PlaybackSessionDescriptor
        var isEligibleForGlobalOwnership: Bool
        let registrationOrder: UInt64
        var activationOrder: UInt64
        var ownedGlobalCapabilities: Set<PlaybackGlobalCapability>
    }

    private var entries: [PlaybackSurfaceID: Entry] = [:]
    private var activeID: PlaybackSurfaceID?
    private var sequence: UInt64 = 0

    public init() {}

    public var sessionCount: Int {
        pruneDeallocatedParticipants()
        return entries.count
    }

    public var activeSurfaceID: PlaybackSurfaceID? {
        pruneDeallocatedParticipants()
        return activeID
    }

    @discardableResult
    public func register(
        _ participant: any PlaybackSessionParticipant,
        eligibleForGlobalOwnership: Bool = true
    ) -> Bool {
        pruneDeallocatedParticipants()

        let descriptor = participant.playbackSessionDescriptor
        guard entries[descriptor.surfaceID] == nil else { return false }

        sequence &+= 1
        entries[descriptor.surfaceID] = Entry(
            participant: WeakParticipant(participant),
            descriptor: descriptor,
            isEligibleForGlobalOwnership: eligibleForGlobalOwnership,
            registrationOrder: sequence,
            activationOrder: 0,
            ownedGlobalCapabilities: []
        )
        return true
    }

    @discardableResult
    public func refreshDescriptor(for surfaceID: PlaybackSurfaceID) -> Bool {
        pruneDeallocatedParticipants()
        guard var entry = entries[surfaceID], let participant = entry.participant.value else {
            return false
        }

        let descriptor = participant.playbackSessionDescriptor
        guard descriptor.surfaceID == surfaceID else { return false }
        entry.descriptor = descriptor
        entries[surfaceID] = entry
        reconcileOwnership()
        return true
    }

    @discardableResult
    public func activate(_ surfaceID: PlaybackSurfaceID) -> Bool {
        pruneDeallocatedParticipants()
        guard var entry = entries[surfaceID], entry.isEligibleForGlobalOwnership else {
            return false
        }

        sequence &+= 1
        entry.activationOrder = sequence
        entries[surfaceID] = entry
        activeID = surfaceID
        reconcileOwnership()
        return true
    }

    @discardableResult
    public func setEligibility(_ isEligible: Bool, for surfaceID: PlaybackSurfaceID) -> Bool {
        pruneDeallocatedParticipants()
        guard var entry = entries[surfaceID] else { return false }

        entry.isEligibleForGlobalOwnership = isEligible
        entries[surfaceID] = entry

        if activeID == surfaceID, !isEligible {
            activeID = fallbackSurfaceID(excluding: surfaceID)
        } else if activeID == nil, isEligible {
            activeID = fallbackSurfaceID()
        }
        reconcileOwnership()
        return true
    }

    @discardableResult
    public func unregister(_ surfaceID: PlaybackSurfaceID, releasingResources: Bool = true) -> Bool {
        pruneDeallocatedParticipants()
        guard let removed = entries.removeValue(forKey: surfaceID) else { return false }

        if activeID == surfaceID {
            activeID = fallbackSurfaceID()
        }

        if let participant = removed.participant.value {
            if !removed.ownedGlobalCapabilities.isEmpty {
                participant.playbackSessionDidChangeOwnedCapabilities([])
            }
            if releasingResources {
                participant.playbackSessionRegistryDidRequestResourceRelease()
            }
        }
        reconcileOwnership()
        return true
    }

    public func releaseAll() {
        let participants = entries.values.compactMap { entry -> (participant: any PlaybackSessionParticipant, wasOwner: Bool)? in
            guard let participant = entry.participant.value else { return nil }
            return (participant, !entry.ownedGlobalCapabilities.isEmpty)
        }

        entries.removeAll()
        activeID = nil
        participants.forEach { item in
            if item.wasOwner {
                item.participant.playbackSessionDidChangeOwnedCapabilities([])
            }
            item.participant.playbackSessionRegistryDidRequestResourceRelease()
        }
    }

    public func isOwner(_ surfaceID: PlaybackSurfaceID, of capability: PlaybackGlobalCapability) -> Bool {
        pruneDeallocatedParticipants()
        return entries[surfaceID]?.ownedGlobalCapabilities.contains(capability) == true
    }

    public func owner(of capability: PlaybackGlobalCapability) -> PlaybackSurfaceID? {
        pruneDeallocatedParticipants()
        return entries.first(where: { $0.value.ownedGlobalCapabilities.contains(capability) })?.key
    }

    public func snapshot() -> [PlaybackSessionSnapshot] {
        pruneDeallocatedParticipants()
        return entries.values
            .map { entry in
                PlaybackSessionSnapshot(
                    descriptor: entry.descriptor,
                    isEligibleForGlobalOwnership: entry.isEligibleForGlobalOwnership,
                    isActive: entry.descriptor.surfaceID == activeID,
                    ownedGlobalCapabilities: entry.ownedGlobalCapabilities
                )
            }
            .sorted { $0.descriptor.surfaceID.description < $1.descriptor.surfaceID.description }
    }

    private func reconcileOwnership() {
        for surfaceID in Array(entries.keys) {
            guard var entry = entries[surfaceID] else { continue }
            let nextCapabilities: Set<PlaybackGlobalCapability>
            if surfaceID == activeID, entry.isEligibleForGlobalOwnership {
                nextCapabilities = entry.descriptor.supportedGlobalCapabilities
            } else {
                nextCapabilities = []
            }

            guard entry.ownedGlobalCapabilities != nextCapabilities else { continue }
            entry.ownedGlobalCapabilities = nextCapabilities
            entries[surfaceID] = entry
            entry.participant.value?.playbackSessionDidChangeOwnedCapabilities(nextCapabilities)
        }
    }

    private func fallbackSurfaceID(excluding excludedID: PlaybackSurfaceID? = nil) -> PlaybackSurfaceID? {
        entries.values
            .filter {
                $0.descriptor.surfaceID != excludedID &&
                    $0.isEligibleForGlobalOwnership &&
                    $0.participant.value != nil
            }
            .max { lhs, rhs in
                let left = (lhs.activationOrder, lhs.descriptor.role.rawValue, lhs.registrationOrder)
                let right = (rhs.activationOrder, rhs.descriptor.role.rawValue, rhs.registrationOrder)
                return left < right
            }?
            .descriptor.surfaceID
    }

    private func pruneDeallocatedParticipants() {
        let deadIDs = entries.compactMap { surfaceID, entry in
            entry.participant.value == nil ? surfaceID : nil
        }
        guard !deadIDs.isEmpty else { return }

        deadIDs.forEach { entries.removeValue(forKey: $0) }
        if let activeID, deadIDs.contains(activeID) {
            self.activeID = fallbackSurfaceID()
        }
        reconcileOwnership()
    }
}
