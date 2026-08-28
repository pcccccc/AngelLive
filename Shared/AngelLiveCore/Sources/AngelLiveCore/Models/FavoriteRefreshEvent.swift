import Foundation

public enum FavoriteRefreshTrigger: Sendable, Equatable {
    case automatic
    case manual
    case pathRecovery
}

public enum FavoriteForegroundPhase: Sendable, Equatable {
    case idle
    case refreshing(generationID: UUID)
    case finished(generationID: UUID, pendingPluginIds: Set<String>)
}

public enum FavoritePluginRefreshPhase: Sendable, Equatable {
    case pending(completed: Int, total: Int)
    case reachable(completed: Int, total: Int)
    case unavailable(skipped: Int, total: Int)
    case completed(success: Int, failure: Int, skipped: Int)
}

public enum FavoriteStatusFreshness: Sendable, Equatable {
    case fresh(updatedAt: Date)
    case refreshing
    case stale(reason: FavoriteRefreshFailureKind, lastUpdatedAt: Date?)
}

public struct FavoriteResolvedPlugin: Sendable, Equatable {
    public let pluginId: String
    public let displayName: String
    public let identityKey: FavoriteIdentityKey
    public let preserveFavoriteRoomInfoOnRefresh: Bool

    public init(
        pluginId: String,
        displayName: String? = nil,
        identityKey: FavoriteIdentityKey = .roomId,
        preserveFavoriteRoomInfoOnRefresh: Bool = false
    ) {
        let normalizedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pluginId = pluginId
        if let normalizedName, !normalizedName.isEmpty {
            self.displayName = normalizedName
        } else {
            self.displayName = pluginId
        }
        self.identityKey = identityKey
        self.preserveFavoriteRoomInfoOnRefresh = preserveFavoriteRoomInfoOnRefresh
    }
}

public struct FavoritePluginRefreshSummary: Sendable, Equatable {
    public let pluginId: String
    public let total: Int
    public let success: Int
    public let failure: Int
    public let skipped: Int

    public init(pluginId: String, total: Int, success: Int, failure: Int, skipped: Int) {
        self.pluginId = pluginId
        self.total = total
        self.success = success
        self.failure = failure
        self.skipped = skipped
    }
}

public struct FavoriteRefreshSummary: Sendable, Equatable {
    public let generationID: UUID
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    public let skipped: Int
    public let timeToFirstPatch: Duration?
    public let foregroundDuration: Duration
    public let fullDuration: Duration
    public let plugins: [FavoritePluginRefreshSummary]

    public init(
        generationID: UUID,
        total: Int,
        succeeded: Int,
        failed: Int,
        skipped: Int,
        timeToFirstPatch: Duration?,
        foregroundDuration: Duration,
        fullDuration: Duration,
        plugins: [FavoritePluginRefreshSummary]
    ) {
        self.generationID = generationID
        self.total = total
        self.succeeded = succeeded
        self.failed = failed
        self.skipped = skipped
        self.timeToFirstPatch = timeToFirstPatch
        self.foregroundDuration = foregroundDuration
        self.fullDuration = fullDuration
        self.plugins = plugins
    }
}

public enum FavoriteRefreshEvent: Sendable {
    case started(generationID: UUID, total: Int)
    case roomUpdated(generationID: UUID, oldKey: String, room: LiveModel)
    case roomStale(
        generationID: UUID,
        key: String,
        reason: FavoriteRefreshFailureKind
    )
    case pluginProgress(
        generationID: UUID,
        pluginId: String,
        completed: Int,
        total: Int
    )
    case pluginUnavailable(
        generationID: UUID,
        pluginId: String,
        skipped: Int
    )
    case foregroundFinished(
        generationID: UUID,
        pendingPluginIds: Set<String>
    )
    case completed(generationID: UUID, summary: FavoriteRefreshSummary)

    public var generationID: UUID {
        switch self {
        case .started(let generationID, _),
             .roomUpdated(let generationID, _, _),
             .roomStale(let generationID, _, _),
             .pluginProgress(let generationID, _, _, _),
             .pluginUnavailable(let generationID, _, _),
             .foregroundFinished(let generationID, _),
             .completed(let generationID, _):
            generationID
        }
    }
}

public struct FavoriteRefreshHandle: Sendable {
    public let generationID: UUID
    public let events: AsyncStream<FavoriteRefreshEvent>
    public let foregroundCompletion: Task<Void, Never>
    public let pluginTotals: [String: Int]
    public let pluginDisplayNames: [String: String]
    public let pluginIDsByRoomKey: [String: String]
    public let identityKeysByLiveType: [String: FavoriteIdentityKey]
    public let roomKeys: [String]

    public init(
        generationID: UUID,
        events: AsyncStream<FavoriteRefreshEvent>,
        foregroundCompletion: Task<Void, Never>,
        pluginTotals: [String: Int],
        pluginDisplayNames: [String: String],
        pluginIDsByRoomKey: [String: String],
        identityKeysByLiveType: [String: FavoriteIdentityKey],
        roomKeys: [String]
    ) {
        self.generationID = generationID
        self.events = events
        self.foregroundCompletion = foregroundCompletion
        self.pluginTotals = pluginTotals
        self.pluginDisplayNames = pluginDisplayNames
        self.pluginIDsByRoomKey = pluginIDsByRoomKey
        self.identityKeysByLiveType = identityKeysByLiveType
        self.roomKeys = roomKeys
    }
}
