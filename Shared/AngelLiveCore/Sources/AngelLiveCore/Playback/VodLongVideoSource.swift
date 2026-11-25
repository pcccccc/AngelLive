import Foundation

@MainActor
final class VodLongVideoSource {
    private struct Selection {
        let cdn: LiveQualityModel
        let quality: LiveQualityDetail
        let source: VodPlaybackSource?

        var isAutoSelectable: Bool {
            !RoomPlaybackResolver.isLocked(quality)
                && (RoomPlaybackResolver.requiresRefreshOnSelect(quality) || mediaURL(for: quality) != nil)
        }
    }

    private struct LockedQuality: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let room: LiveModel
    private let platform: LiveParseJSPlatform
    private let refresher: Refresher
    private let loadArguments: @MainActor () async throws -> [LiveQualityModel]
    private let qualityList: Bool
    private var episodeSelections: [String: [Selection]] = [:]
    private var defaultMovieSourceID: String?

    init(room: LiveModel, plugin: LiveParseLoadedPlugin,
         pluginManager: LiveParsePluginManager = LiveParsePlugins.shared,
         loadContext: @escaping @MainActor () async throws -> [String: String] = { [:] }) {
        let platform = LiveParseJSPlatform(pluginId: plugin.manifest.pluginId, liveTypes: [room.liveType])
        self.room = room
        self.platform = platform
        refresher = Refresher(platform: platform, manager: pluginManager)
        qualityList = plugin.manifest.hostBehavior?.episodeSelection == "qualityList"
        loadArguments = {
            let context = try await loadContext()
            try Task.checkCancellation()
            return try await LiveParseJSPlatformManager.getPlayArgs(
                platform: platform, roomId: room.roomId, userId: room.userId,
                context: context, pluginManager: pluginManager
            )
        }
    }

    var dependencies: VodPlaybackDependencies {
        VodPlaybackDependencies(
            loadDetail: { try await self.loadDetail() },
            resolvePlayback: { try await self.resolvePlayback(detail: $0, episode: $1, sourceID: $2) },
            isEpisodeAutoSelectable: { episode in
                self.episodeSelections[episode.episodeID]?.contains(where: \.isAutoSelectable) == true
            }
        )
    }

    private func loadDetail() async throws -> VodWorkDetail {
        let args = try await loadArguments()
        try Task.checkCancellation()
        let kind: VodWorkKind
        let episodes: [VodEpisode]
        if qualityList {
            let catalog = try ShortDramaCatalog.episodes(pluginID: platform.pluginId, roomID: room.roomId, playArgs: args)
            kind = catalog.count > 1 ? .series : .movie
            episodes = catalog.map {
                episode(id: String($0.number), number: $0.number, title: $0.quality.title, kind: kind)
            }
            episodeSelections = Dictionary(uniqueKeysWithValues: zip(episodes, catalog).map { episode, item in
                (episode.episodeID, [Selection(cdn: item.cdn, quality: item.quality, source: nil)])
            })
        } else {
            kind = .movie
            episodes = [episode(id: "main", number: 1, title: room.roomTitle, kind: kind)]
            episodeSelections = ["main": movieSelections(in: args)]
            let initial = RoomPlaybackResolver.initialSelection(
                in: args, preferredCdnIndex: 0, preference: PlayerSettingModel().defaultPlaybackQuality
            )
            defaultMovieSourceID = sourceID(cdnIndex: initial.cdnIndex, qualityIndex: initial.qualityIndex)
        }
        return VodWorkDetail(
            pluginID: platform.pluginId, workID: room.roomId, title: room.roomTitle, kind: kind,
            posterURL: VodCatalog.hasIdentity(room.roomCover) ? room.roomCover : nil,
            seasons: kind == .movie ? [VodSeason(id: VodCatalog.movieSeasonID, number: 1, title: "")] : [],
            hasExplicitSeasons: false, episodes: episodes
        )
    }

    private func episode(id: String, number: Int, title: String, kind: VodWorkKind) -> VodEpisode {
        VodEpisode(
            pluginID: platform.pluginId, workID: room.roomId, episodeID: id,
            seasonID: kind == .movie ? VodCatalog.movieSeasonID : "", number: number, title: title
        )
    }

    private func movieSelections(in args: [LiveQualityModel]) -> [Selection] {
        args.enumerated().flatMap { cdnIndex, cdn in
            cdn.qualitys.enumerated().compactMap { qualityIndex, quality in
                guard RoomPlaybackResolver.requiresRefreshOnSelect(quality)
                        || Self.mediaURL(for: quality) != nil else { return nil }
                let qualityTitle = RoomPlaybackResolver.qualityDisplayTitle(quality, in: args)
                let title = args.count > 1
                    ? "\(RoomPlaybackResolver.cdnDisplayName(for: cdn)) · \(qualityTitle)" : qualityTitle
                let source = VodPlaybackSource(id: sourceID(cdnIndex: cdnIndex, qualityIndex: qualityIndex), title: title)
                return Selection(cdn: cdn, quality: quality, source: source)
            }
        }
    }

    private func sourceID(cdnIndex: Int, qualityIndex: Int) -> String {
        "\(cdnIndex):\(qualityIndex)"
    }

    private func resolvePlayback(detail: VodWorkDetail, episode: VodEpisode,
                                 sourceID: String?) async throws -> VodResolvedPlayback {
        let selections = episodeSelections[episode.episodeID] ?? []
        let selection: Selection?
        if let sourceID {
            selection = selections.first { $0.source?.id == sourceID }
        } else if qualityList {
            selection = selections.first
        } else {
            selection = selections.first { $0.source?.id == defaultMovieSourceID && $0.isAutoSelectable }
                ?? selections.first(where: \.isAutoSelectable)
        }
        guard let selection else { throw VodCatalogError.invalidPlaybackURL }
        try Self.checkLock(selection.quality)
        var quality = try await RoomPlaybackPreparer.prepare(
            roomId: room.roomId, cdn: selection.cdn, quality: selection.quality, plugin: refresher
        )
        try Task.checkCancellation()
        try Self.checkLock(quality)
        guard quality.playbackHints?.isLive != true else { throw VodCatalogError.requiresOnDemandMedia }
        let original = selection.quality.playbackHints ?? LivePlaybackHints()
        var hints = quality.playbackHints ?? LivePlaybackHints()
        hints.isLive = false
        hints.streamFormat = hints.streamFormat ?? original.streamFormat
        hints.latencyMode = hints.latencyMode ?? original.latencyMode
        hints.preferredEngines = hints.preferredEngines ?? original.preferredEngines
        hints.requiresCustomSegmentLoader = hints.requiresCustomSegmentLoader ?? original.requiresCustomSegmentLoader
        hints.selectionBehavior = hints.selectionBehavior ?? original.selectionBehavior
        hints.startPositionSeconds = hints.startPositionSeconds ?? original.startPositionSeconds
        hints.mediaTransform = hints.mediaTransform ?? original.mediaTransform
        if hints.streamFormat == .hlsLive || (RoomPlaybackResolver.isHLSQuality(quality)
            && (hints.streamFormat == nil || hints.streamFormat == .unknown)) {
            hints.streamFormat = .hlsVod
        }
        quality.playbackHints = hints
        guard let url = Self.mediaURL(for: quality) else { throw VodCatalogError.invalidPlaybackURL }
        // The original selection stays cached for re-selection and retry. This result is already prepared.
        return VodResolvedPlayback(
            workID: detail.workID, episodeID: episode.id, rawEpisodeID: episode.episodeID,
            sourceID: selection.source?.id, sources: selections.compactMap(\.source),
            url: url, quality: quality, refreshOnSelect: false
        )
    }

    private static func checkLock(_ quality: LiveQualityDetail) throws {
        switch RoomPlaybackResolver.lockAction(for: quality) {
        case .requestLogin(let message), .showMessage(let message): throw LockedQuality(message: message)
        case nil: break
        }
    }

    private nonisolated static func mediaURL(for quality: LiveQualityDetail) -> URL? {
        if let url = VodCatalog.mediaURL(quality.url) { return url }
        guard let url = RoomPlaybackResolver.playableURL(for: quality),
              let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "file": return url.path.hasPrefix("/") && url.path.count > 1 ? url : nil
        case "resolve": return nil
        default: return url.host?.isEmpty == false ? url : nil
        }
    }

    private struct Refresher: LivePluginPlaybackRefreshing {
        let platform: LiveParseJSPlatform
        let manager: LiveParsePluginManager

        func refreshPlayback(roomId: String, cdn: LiveQualityModel,
                             quality: LiveQualityDetail) async throws -> LiveQualityDetail {
            try await LiveParseJSPlatformManager.refreshPlayback(
                platform: platform, roomId: roomId, cdn: cdn, quality: quality, pluginManager: manager
            )
        }
    }
}
