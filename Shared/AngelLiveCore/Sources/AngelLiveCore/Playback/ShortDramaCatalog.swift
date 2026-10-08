import Foundation

public struct ShortDramaEpisode: Identifiable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let cdn: LiveQualityModel
    public let quality: LiveQualityDetail
}

public enum ShortDramaCatalogError: Error, LocalizedError, Equatable, Sendable {
    case missingIdentity
    case invalidCDNCount
    case invalidEpisodeNumber(Int)
    case duplicateEpisodeNumber(Int)

    public var errorDescription: String? {
        switch self {
        case .missingIdentity: "剧集缺少插件或剧目标识"
        case .invalidCDNCount: "分集列表必须使用单一播放线路"
        case .invalidEpisodeNumber: "分集列表包含无效集数"
        case .duplicateEpisodeNumber: "分集列表包含重复集数"
        }
    }
}

/// qualityList 的 qn 是正整数集数；宿主保留所有分集并按集数排序。
public enum ShortDramaCatalog {
    public static func episodes(
        pluginID: String,
        roomID: String,
        playArgs: [LiveQualityModel]
    ) throws -> [ShortDramaEpisode] {
        guard !pluginID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShortDramaCatalogError.missingIdentity
        }
        let populatedCDNs = playArgs.filter { !$0.qualitys.isEmpty }
        guard !populatedCDNs.isEmpty else { return [] }
        guard populatedCDNs.count == 1 else { throw ShortDramaCatalogError.invalidCDNCount }
        let cdn = populatedCDNs[0]
        var numbers = Set<Int>()
        for quality in cdn.qualitys {
            guard quality.qn > 0 else { throw ShortDramaCatalogError.invalidEpisodeNumber(quality.qn) }
            guard numbers.insert(quality.qn).inserted else {
                throw ShortDramaCatalogError.duplicateEpisodeNumber(quality.qn)
            }
        }
        return cdn.qualitys.sorted { $0.qn < $1.qn }.map { quality in
            let title = quality.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // UTF-8 length prefixes keep arbitrary plugin/room separators collision-free.
            let id = "\(pluginID.utf8.count):\(pluginID)\(roomID.utf8.count):\(roomID)\(quality.qn)"
            return ShortDramaEpisode(
                id: id,
                number: quality.qn,
                title: title.isEmpty ? "第 \(quality.qn) 集" : title,
                cdn: cdn,
                quality: quality
            )
        }
    }
}

/// A playback UUID accepts one finish event. A modal defers normal completion until dismissal.
public struct ShortDramaCompletionPolicy: Sendable {
    public enum Action: Equatable, Sendable {
        case ignored
        case failed
        case deferred
        case completed
    }

    private var playbackID: UUID?
    private var finishedID: UUID?
    private var pendingID: UUID?
    private var isPresented = false

    public init() {}

    public mutating func startPlayback(id: UUID) {
        playbackID = id
        finishedID = nil
        pendingID = nil
    }

    public mutating func invalidate() {
        playbackID = nil
        finishedID = nil
        pendingID = nil
    }

    public mutating func finish(id: UUID, failed: Bool) -> Action {
        guard playbackID == id, finishedID != id else { return .ignored }
        finishedID = id
        if failed { return .failed }
        if isPresented {
            pendingID = id
            return .deferred
        }
        return .completed
    }

    public mutating func setPresented(_ presented: Bool) -> UUID? {
        isPresented = presented
        guard !presented, pendingID == playbackID else { return nil }
        defer { pendingID = nil }
        return pendingID
    }

    public static func nextEpisode(
        in episodes: [ShortDramaEpisode],
        after episodeID: String,
        autoplay: Bool
    ) -> ShortDramaEpisode? {
        guard autoplay, let index = episodes.firstIndex(where: { $0.id == episodeID }) else { return nil }
        return episodes.dropFirst(index + 1).first(where: isPlayableSelection)
    }

    public static func firstPlayableEpisode(in episodes: [ShortDramaEpisode]) -> ShortDramaEpisode? {
        episodes.first(where: isPlayableSelection)
    }

    private static func isPlayableSelection(_ episode: ShortDramaEpisode) -> Bool {
        !RoomPlaybackResolver.isLocked(episode.quality)
            && (RoomPlaybackResolver.requiresRefreshOnSelect(episode.quality)
                || RoomPlaybackResolver.playableURL(for: episode.quality) != nil)
    }
}
