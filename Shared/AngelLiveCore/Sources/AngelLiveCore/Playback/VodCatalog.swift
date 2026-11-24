import Foundation

public enum VodWorkKind: String, Codable, Equatable, Sendable {
    case movie
    case series
}

public struct VodWork: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: VodWorkKind
    public let synopsis: String?
    public let posterURL: String?
    public let backdropURL: String?
    public let year: Int?

    public init(id: String, title: String, kind: VodWorkKind, synopsis: String? = nil,
                posterURL: String? = nil, backdropURL: String? = nil, year: Int? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.synopsis = synopsis
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let artwork = try VodArtworkPayload(from: decoder)
        try self.init(id: values.decode(String.self, forKey: .id),
                      title: values.decode(String.self, forKey: .title),
                      kind: values.decode(VodWorkKind.self, forKey: .kind),
                      synopsis: values.decodeIfPresent(String.self, forKey: .synopsis),
                      posterURL: artwork.poster, backdropURL: artwork.backdrop,
                      year: values.decodeIfPresent(Int.self, forKey: .year))
    }
}

private struct VodArtworkPayload: Decodable {
    let poster: String?
    let backdrop: String?

    private enum CodingKeys: String, CodingKey {
        case posterURL, backdropURL, bannerURL, landscapeURL
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func path(_ key: CodingKeys) -> String? {
            Self.clean(try? values.decode(String.self, forKey: key))
        }
        poster = path(.posterURL)
        backdrop = path(.backdropURL) ?? path(.bannerURL) ?? path(.landscapeURL)
    }

    static func clean(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public struct VodSeason: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let title: String

    public init(id: String, number: Int, title: String) {
        self.id = id
        self.number = number
        self.title = title
    }
}

public struct VodEpisode: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let episodeID: String
    public let seasonID: String
    public let number: Int
    public let title: String
    public let durationHint: Double?
    public let stillURL: String?
    public let synopsis: String?

    public init(pluginID: String, workID: String, episodeID: String, seasonID: String,
                number: Int, title: String, durationHint: Double? = nil,
                stillURL: String? = nil, synopsis: String? = nil) {
        id = "\(pluginID.utf8.count):\(pluginID)\(workID.utf8.count):\(workID)\(episodeID)"
        self.episodeID = episodeID
        self.seasonID = seasonID
        self.number = number
        self.title = title
        self.durationHint = durationHint
        self.stillURL = stillURL
        self.synopsis = synopsis
    }
}

public struct VodWorkDetail: Equatable, Sendable {
    public let pluginID: String
    public let workID: String
    public let title: String
    public let kind: VodWorkKind
    public let synopsis: String?
    public let posterURL: String?
    public let backdropURL: String?
    public let year: Int?
    public let seasons: [VodSeason]
    public let hasExplicitSeasons: Bool
    public let episodes: [VodEpisode]

    public init(pluginID: String, workID: String, title: String, kind: VodWorkKind,
                synopsis: String? = nil, posterURL: String? = nil, backdropURL: String? = nil, year: Int? = nil,
                seasons: [VodSeason], hasExplicitSeasons: Bool, episodes: [VodEpisode]) {
        self.pluginID = pluginID
        self.workID = workID
        self.title = title
        self.kind = kind
        self.synopsis = synopsis
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
        self.seasons = seasons
        self.hasExplicitSeasons = hasExplicitSeasons
        self.episodes = episodes
    }

    public func heroArtwork(portrait: Bool, preferredEpisode: VodEpisode?) -> (url: String?, fitsPoster: Bool) {
        if portrait { return (posterURL ?? backdropURL ?? episodes.first?.stillURL, false) }
        if let landscape = backdropURL ?? preferredEpisode?.stillURL ?? episodes.first?.stillURL {
            return (landscape, false)
        }
        return (posterURL, posterURL != nil)
    }
}

public enum VodMarkerKind: String, Codable, Equatable, Sendable {
    case intro
    case credits
}

public struct VodMarker: Codable, Equatable, Sendable {
    public let kind: VodMarkerKind
    public let start: Double
    public let end: Double

    public init(kind: VodMarkerKind, start: Double, end: Double) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    func fits(duration: Double?) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start
            && (duration.map { $0 <= 0 || end <= $0 } ?? true)
    }
}

public enum VodSubtitleFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case srt
    case vtt
    case ass
}

public struct VodExternalSubtitle: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "ext:\(subtitleID)" }
    public let subtitleID: String
    public let name: String
    public let language: String?
    public let format: VodSubtitleFormat
    public let url: URL

    public init(subtitleID: String, name: String, language: String? = nil,
                format: VodSubtitleFormat, url: URL) {
        self.subtitleID = subtitleID
        self.name = name
        self.language = language
        self.format = format
        self.url = url
    }
}

public struct VodPlaybackSource: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct VodResolvedPlayback: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let workID: String
    public let episodeID: String
    public let rawEpisodeID: String
    public let sourceID: String?
    public let sources: [VodPlaybackSource]
    public let url: URL
    public let quality: LiveQualityDetail
    public let refreshOnSelect: Bool
    public let subtitles: [VodExternalSubtitle]
    public let introMarker: VodMarker?
    public let creditsMarker: VodMarker?
    public let resumePosition: Double?

    public init(id: UUID = UUID(), workID: String, episodeID: String, rawEpisodeID: String,
                sourceID: String? = nil, sources: [VodPlaybackSource] = [], url: URL,
                quality: LiveQualityDetail, refreshOnSelect: Bool = false,
                subtitles: [VodExternalSubtitle] = [], introMarker: VodMarker? = nil,
                creditsMarker: VodMarker? = nil, resumePosition: Double? = nil) {
        self.id = id
        self.workID = workID
        self.episodeID = episodeID
        self.rawEpisodeID = rawEpisodeID
        self.sourceID = sourceID
        self.sources = sources
        self.url = url
        self.quality = quality
        self.refreshOnSelect = refreshOnSelect
        self.subtitles = subtitles
        self.introMarker = introMarker
        self.creditsMarker = creditsMarker
        self.resumePosition = resumePosition
    }

    func startingSession(id: UUID, at position: Double?) -> Self {
        Self(id: id, workID: workID, episodeID: episodeID, rawEpisodeID: rawEpisodeID,
             sourceID: sourceID, sources: sources, url: url, quality: quality,
             refreshOnSelect: refreshOnSelect, subtitles: subtitles, introMarker: introMarker,
             creditsMarker: creditsMarker, resumePosition: position)
    }
}

public enum VodCatalogError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedPlugin
    case missingIdentity
    case mismatchedIdentity
    case unsupportedWorkKind
    case duplicateIdentifier
    case requiresOnDemandMedia
    case invalidPlaybackURL

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlugin: "插件未声明受支持的点播协议"
        case .missingIdentity: "点播目录缺少必要标识"
        case .mismatchedIdentity: "插件返回了与请求不符的点播内容"
        case .unsupportedWorkKind: "插件返回了不受支持的作品类型"
        case .duplicateIdentifier: "点播目录包含重复标识"
        case .requiresOnDemandMedia: "本集未明确声明为点播媒体"
        case .invalidPlaybackURL: "本集暂无有效播放地址"
        }
    }
}

public enum VodCatalog {
    public static let movieSeasonID = "__movie_season__"

    public static func works(from data: Data) throws -> [VodWork] {
        try JSONDecoder().decode(VodWorksResponse.self, from: data).normalized
    }

    public static func detail(from data: Data, pluginID: String, workID: String,
                              fallbackTitle: String = "", fallbackPosterURL: String? = nil) throws -> VodWorkDetail {
        try JSONDecoder().decode(VodDetailResponse.self, from: data).normalized(
            pluginID: pluginID, workID: workID, fallbackTitle: fallbackTitle, fallbackPosterURL: fallbackPosterURL
        )
    }

    public static func playback(from data: Data, workID: String, episode: VodEpisode,
                                liveType: LiveType, sourceID: String? = nil) throws -> VodResolvedPlayback {
        try JSONDecoder().decode(VodPlaybackResponse.self, from: data).normalized(
            workID: workID, episode: episode, liveType: liveType, sourceID: sourceID
        )
    }

    static func hasIdentity(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func mediaURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value, encodingInvalidCharacters: false) else { return nil }
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        case "file": return url.path.hasPrefix("/") && url.path.count > 1 ? url : nil
        default: return nil
        }
    }
}

/// Optional annotations and unknown work kinds are dropped individually at the wire boundary.
struct VodAnnotation<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: Decoder) {
        value = try? Value(from: decoder)
    }
}

struct VodWorksResponse: Decodable, Sendable {
    let works: [VodAnnotation<VodWork>]

    var normalized: [VodWork] {
        works.compactMap(\.value).filter { VodCatalog.hasIdentity($0.id) }
    }
}

struct VodDetailResponse: Decodable, Sendable {
    struct Episode: Decodable, Sendable {
        let id: String
        let seasonId: String?
        let number: Int
        let title: String
        let durationHint: Double?
        let stillURL: String?
        let synopsis: String?
    }

    let workId: String?
    let title: String?
    let kind: String?
    let synopsis: String?
    private let artwork: VodArtworkPayload
    let year: Int?
    let seasons: [VodSeason]?
    let episodes: [Episode]

    private enum CodingKeys: String, CodingKey {
        case workId, title, kind, synopsis, year, seasons, episodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workId = try values.decodeIfPresent(String.self, forKey: .workId)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        kind = try values.decodeIfPresent(String.self, forKey: .kind)
        synopsis = try values.decodeIfPresent(String.self, forKey: .synopsis)
        artwork = try VodArtworkPayload(from: decoder)
        year = try values.decodeIfPresent(Int.self, forKey: .year)
        seasons = try values.decodeIfPresent([VodSeason].self, forKey: .seasons)
        episodes = try values.decode([Episode].self, forKey: .episodes)
    }

    func normalized(pluginID: String, workID: String, fallbackTitle: String,
                    fallbackPosterURL: String?) throws -> VodWorkDetail {
        guard VodCatalog.hasIdentity(pluginID), VodCatalog.hasIdentity(workID) else {
            throw VodCatalogError.missingIdentity
        }
        if let workId {
            guard VodCatalog.hasIdentity(workId) else { throw VodCatalogError.missingIdentity }
            guard workId == workID else { throw VodCatalogError.mismatchedIdentity }
        }
        let seasons = seasons ?? []
        let workKind: VodWorkKind
        if let kind {
            guard let recognized = VodWorkKind(rawValue: kind) else { throw VodCatalogError.unsupportedWorkKind }
            workKind = recognized
        } else {
            workKind = seasons.isEmpty && episodes.count == 1 ? .movie : .series
        }
        let seasonIDs = Set(seasons.map(\.id))
        let episodeIDs = Set(episodes.map(\.id))
        guard seasonIDs.count == seasons.count, episodeIDs.count == episodes.count else {
            throw VodCatalogError.duplicateIdentifier
        }
        guard seasonIDs.allSatisfy(VodCatalog.hasIdentity), episodeIDs.allSatisfy(VodCatalog.hasIdentity) else {
            throw VodCatalogError.missingIdentity
        }
        let synthesizeSeason = workKind == .movie && seasons.isEmpty
        let sortedSeasons = synthesizeSeason
            ? [VodSeason(id: VodCatalog.movieSeasonID, number: 1, title: "")]
            : seasons.sorted { $0.number < $1.number }
        let grouped = Dictionary(grouping: try episodes.map { episode in
            let seasonID: String
            if synthesizeSeason {
                seasonID = VodCatalog.movieSeasonID
            } else if seasons.isEmpty {
                seasonID = episode.seasonId ?? ""
            } else {
                guard let declaredID = episode.seasonId, VodCatalog.hasIdentity(declaredID) else {
                    throw VodCatalogError.missingIdentity
                }
                guard seasonIDs.contains(declaredID) else { throw VodCatalogError.mismatchedIdentity }
                seasonID = declaredID
            }
            return VodEpisode(pluginID: pluginID, workID: workID, episodeID: episode.id,
                              seasonID: seasonID, number: episode.number, title: episode.title,
                              durationHint: episode.durationHint, stillURL: VodArtworkPayload.clean(episode.stillURL), synopsis: episode.synopsis)
        }, by: \.seasonID)
        let sortedEpisodes = seasons.isEmpty && !synthesizeSeason
            ? grouped.keys.sorted().flatMap { grouped[$0, default: []].sorted { $0.number < $1.number } }
            : sortedSeasons.flatMap { grouped[$0.id, default: []].sorted { $0.number < $1.number } }
        return VodWorkDetail(pluginID: pluginID, workID: workID, title: title ?? fallbackTitle, kind: workKind,
                             synopsis: synopsis, posterURL: artwork.poster ?? VodArtworkPayload.clean(fallbackPosterURL),
                             backdropURL: artwork.backdrop, year: year,
                             seasons: sortedSeasons, hasExplicitSeasons: !seasons.isEmpty, episodes: sortedEpisodes)
    }
}

struct VodPlaybackResponse: Decodable, Sendable {
    struct Subtitle: Decodable, Sendable {
        let id: String
        let name: String
        let language: String?
        let format: String
        let url: String

        var normalized: VodExternalSubtitle? {
            guard VodCatalog.hasIdentity(id), let format = VodSubtitleFormat(rawValue: format.lowercased()),
                  let url = VodCatalog.mediaURL(url) else { return nil }
            return VodExternalSubtitle(subtitleID: id, name: name, language: language, format: format, url: url)
        }
    }

    let workId: String?
    let episodeId: String?
    let sourceId: String?
    let sources: [VodPlaybackSource]?
    let url: String?
    let isLive: Bool?
    let userAgent: String?
    let headers: [String: String]?
    let requestContext: [String: String]?
    let refreshOnSelect: Bool?
    let subtitles: [VodAnnotation<Subtitle>]?
    let markers: [VodAnnotation<VodMarker>]?

    func normalized(workID: String, episode: VodEpisode, liveType: LiveType,
                    sourceID: String?) throws -> VodResolvedPlayback {
        guard isLive == false else { throw VodCatalogError.requiresOnDemandMedia }
        guard workId.map({ $0 == workID }) ?? true, episodeId.map({ $0 == episode.episodeID }) ?? true,
              sourceID == nil || sourceId == nil || sourceID == sourceId else {
            throw VodCatalogError.mismatchedIdentity
        }
        guard let url = url.flatMap(VodCatalog.mediaURL) else { throw VodCatalogError.invalidPlaybackURL }
        let isHLS = url.pathExtension.lowercased() == "m3u8"
        let quality = LiveQualityDetail(
            roomId: workID, title: episode.title, qn: episode.number, url: url.absoluteString,
            liveCodeType: isHLS ? .hls : .flv, liveType: liveType, userAgent: userAgent, headers: headers,
            requestContext: requestContext,
            playbackHints: LivePlaybackHints(streamFormat: isHLS ? .hlsVod : nil, isLive: false)
        )
        let markers = markers?.compactMap(\.value).filter { $0.fits(duration: episode.durationHint) } ?? []
        let subtitles = subtitles?.compactMap { $0.value?.normalized } ?? []
        return VodResolvedPlayback(
            workID: workID, episodeID: episode.id, rawEpisodeID: episode.episodeID,
            sourceID: sourceId ?? sourceID, sources: sources ?? [], url: url, quality: quality,
            refreshOnSelect: refreshOnSelect ?? false, subtitles: subtitles,
            introMarker: markers.first { $0.kind == .intro }, creditsMarker: markers.first { $0.kind == .credits }
        )
    }
}
