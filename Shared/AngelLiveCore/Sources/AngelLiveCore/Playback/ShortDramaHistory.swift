import Foundation

/// Display identity only. Playback URLs, request headers and session credentials are never stored.
public struct ShortDramaHistoryMetadata: Codable, Equatable, Sendable {
    public let roomTitle: String
    public let roomCover: String
    public let userName: String
    public let userHeadImg: String
    public let userID: String
    /// Retained only to classify legacy history after uninstalling a plugin. Never used for playback routing.
    public let recordedLiveType: LiveType?
    public let episodeID: String?
    public let episodeTitle: String?
    public let episodeNumber: Int?
    public let lastWatchedAt: Date

    public init(room: LiveModel, episodeID: String? = nil, episodeTitle: String? = nil,
                episodeNumber: Int? = nil, lastWatchedAt: Date = .now) {
        roomTitle = room.roomTitle
        roomCover = room.roomCover
        userName = room.userName
        userHeadImg = room.userHeadImg
        userID = room.userId
        recordedLiveType = room.liveType
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.episodeNumber = episodeNumber
        self.lastWatchedAt = lastWatchedAt
    }

    var isValid: Bool {
        lastWatchedAt.timeIntervalSinceReferenceDate.isFinite
            && (episodeNumber.map { $0 > 0 } ?? true)
    }
}

public struct ShortDramaHistoryEntry: Identifiable, Sendable {
    public var id: ShortDramaProgressKey { key }
    public let key: ShortDramaProgressKey
    public let title: String
    public let coverURL: String?
    public let episodeTitle: String?
    public let episodeNumber: Int?
    public let position: Double
    public let duration: Double
    public let completed: Bool
    public let updatedAt: Date
    private let metadata: ShortDramaHistoryMetadata?

    init(snapshot: ShortDramaProgressSnapshot) {
        key = snapshot.key
        metadata = snapshot.historyMetadata
        let name = metadata?.roomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = metadata?.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        title = name.flatMap { $0.isEmpty ? nil : $0 }
            ?? author.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名短剧"
        coverURL = metadata?.roomCover.isEmpty == false ? metadata?.roomCover : nil
        let last = snapshot.lastEpisodeID.flatMap { snapshot.episodes[$0] }
        let sameEpisode = snapshot.lastEpisodeID == metadata?.episodeID
        episodeTitle = sameEpisode ? metadata?.episodeTitle : nil
        episodeNumber = sameEpisode ? metadata?.episodeNumber : nil
        position = last?.position ?? 0
        duration = last?.duration ?? 0
        completed = last?.completed ?? false
        updatedAt = max(metadata?.lastWatchedAt ?? .distantPast,
                        snapshot.episodes.values.map(\.updatedAt).max() ?? .distantPast)
    }

    /// Resolve the current installed plugin mapping; the mapping recorded with old display data is not authoritative.
    @MainActor
    public var room: LiveModel? {
        guard SandboxPluginCatalog.isInstalled(pluginId: key.pluginID),
              let platform = LiveParseJSPlatformManager.platform(forPluginId: key.pluginID) else { return nil }
        return makeRoom(liveType: platform.liveType)
    }

    func makeRoom(liveType: LiveType) -> LiveModel {
        LiveModel(userName: metadata?.userName ?? "", roomTitle: title,
                  roomCover: metadata?.roomCover ?? "", userHeadImg: metadata?.userHeadImg ?? "",
                  liveType: liveType, liveState: nil, userId: metadata?.userID ?? "",
                  roomId: key.roomID, liveWatchedCount: nil)
    }
}
