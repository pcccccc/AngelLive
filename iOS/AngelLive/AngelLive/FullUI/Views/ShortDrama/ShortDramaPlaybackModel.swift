import Foundation
import Observation
import AngelLiveCore

struct ShortDramaPlayback: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let quality: LiveQualityDetail
}

@MainActor
@Observable
final class ShortDramaPlaybackModel {
    let room: LiveModel
    private(set) var episodes: [ShortDramaEpisode] = []
    private(set) var selectedEpisodeID: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var playback: ShortDramaPlayback?
    private(set) var hasFinished = false
    private(set) var selectionNote: String?
    var autoplay = true

    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var completion = ShortDramaCompletionPolicy()
    @ObservationIgnored private var episodesPresented = false
    @ObservationIgnored private var episodeSwipeActive = false

    var selectedEpisode: ShortDramaEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    init(room: LiveModel) {
        self.room = room
    }

    func load() async {
        guard !isLoading else { return }
        cancelled = false
        let token = beginRequest()
        episodes = []
        selectedEpisodeID = nil
        let task = Task { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            do {
                let platform = try self.platform()
                let args = try await LiveParseJSPlatformManager.getPlayArgs(
                    platform: platform, roomId: self.room.roomId, userId: self.room.userId
                )
                guard self.isCurrent(token) else { return }
                self.episodes = try ShortDramaCatalog.episodes(
                    pluginID: platform.pluginId, roomID: self.room.roomId, playArgs: args
                )
                guard let first = ShortDramaCompletionPolicy.firstPlayableEpisode(in: self.episodes)
                    ?? self.episodes.first else { return }
                self.selectedEpisodeID = first.id
                await self.prepare(first, platform: platform, token: token)
            } catch {
                self.fail(error, token: token)
            }
        }
        request = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        finishRequest(token)
    }

    func selectEpisode(id: String) async {
        guard !cancelled, let episode = episodes.first(where: { $0.id == id }) else { return }
        // Selecting the playing episode closes the sheet without losing its position.
        if selectedEpisodeID == id, playback != nil, !hasFinished { return }
        if selectedEpisodeID == id, isLoading { return }
        let token = beginRequest()
        selectedEpisodeID = id
        let task = Task { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            do {
                await self.prepare(episode, platform: try self.platform(), token: token)
            } catch {
                self.fail(error, token: token)
            }
        }
        request = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        finishRequest(token)
    }

    func playbackFinished(id: UUID, error: Error?) async {
        guard !cancelled, playback?.id == id else { return }
        switch completion.finish(id: id, failed: error != nil) {
        case .ignored: return
        case .failed:
            playback = nil
            errorMessage = error?.localizedDescription
            selectionNote = nil
            return
        case .deferred:
            hasFinished = true
            return
        case .completed:
            hasFinished = true
            await continueAfterCompletion(id: id)
        }
    }

    func setEpisodesPresented(_ presented: Bool) async {
        guard !cancelled else { return }
        episodesPresented = presented
        await updateCompletionHold()
    }

    /// A swipe holds EOF independently of modal presentation until it commits or settles back.
    func setEpisodeSwipeActive(_ active: Bool) async {
        guard !cancelled else { return }
        episodeSwipeActive = active
        await updateCompletionHold()
    }

    func cancel() {
        cancelled = true
        generation = UUID()
        request?.cancel()
        request = nil
        playback = nil
        episodesPresented = false
        episodeSwipeActive = false
        completion = ShortDramaCompletionPolicy()
        isLoading = false
    }

    private func platform() throws -> LiveParseJSPlatform {
        guard let platform = LiveParseJSPlatformManager.platform(for: room.liveType) else {
            throw ShortDramaPlaybackError.unsupportedPlugin
        }
        // Resolve the selected installed version; registry metadata may describe a newer candidate.
        let behavior = try LiveParsePlugins.shared.resolve(pluginId: platform.pluginId).manifest.hostBehavior
        guard behavior?.contentKind == "shortDrama", behavior?.episodeSelection == "qualityList" else {
            throw ShortDramaPlaybackError.unsupportedPlugin
        }
        return platform
    }

    private func beginRequest() -> UUID {
        request?.cancel()
        generation = UUID()
        playback = nil
        completion.invalidate()
        hasFinished = false
        errorMessage = nil
        selectionNote = nil
        isLoading = true
        return generation
    }

    private func isCurrent(_ token: UUID) -> Bool {
        !cancelled && !Task.isCancelled && token == generation
    }

    private func finishRequest(_ token: UUID) {
        guard token == generation else { return }
        request = nil
        isLoading = false
    }

    private func prepare(_ episode: ShortDramaEpisode, platform: LiveParseJSPlatform, token: UUID) async {
        do {
            try rejectLocked(episode.quality)
            let quality = try await RoomPlaybackPreparer.prepare(
                roomId: room.roomId, cdn: episode.cdn, quality: episode.quality, plugin: platform
            )
            guard isCurrent(token) else { return }
            try rejectLocked(quality)
            guard !RoomPlaybackResolver.resolvePlan(selectedQuality: quality).isLive else {
                throw ShortDramaPlaybackError.requiresOnDemandMedia
            }
            guard let url = RoomPlaybackResolver.playableURL(for: quality) else {
                throw ShortDramaPlaybackError.noPlaybackURL
            }
            let id = UUID()
            completion.startPlayback(id: id)
            playback = ShortDramaPlayback(id: id, url: url, quality: quality)
        } catch {
            fail(error, token: token)
        }
    }

    private func rejectLocked(_ quality: LiveQualityDetail) throws {
        guard let action = RoomPlaybackResolver.lockAction(for: quality) else { return }
        switch action {
        case let .requestLogin(message), let .showMessage(message):
            throw ShortDramaPlaybackError.locked(message)
        }
    }

    private func fail(_ error: Error, token: UUID) {
        guard isCurrent(token) else { return }
        playback = nil
        errorMessage = error.localizedDescription
    }

    private func updateCompletionHold() async {
        guard let id = completion.setPresented(episodesPresented || episodeSwipeActive) else { return }
        await continueAfterCompletion(id: id)
    }

    private func continueAfterCompletion(id: UUID) async {
        guard !cancelled, playback?.id == id, hasFinished,
              let selectedEpisodeID else { return }
        guard autoplay else {
            selectionNote = "本集已结束"
            return
        }
        let next = ShortDramaCompletionPolicy.nextEpisode(
            in: episodes, after: selectedEpisodeID, autoplay: autoplay
        )
        guard let next else {
            selectionNote = "已看完全部可播放剧集"
            return
        }
        await selectEpisode(id: next.id)
    }
}

private enum ShortDramaPlaybackError: LocalizedError {
    case unsupportedPlugin
    case noPlaybackURL
    case requiresOnDemandMedia
    case locked(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlugin: "插件未声明支持短剧分集播放"
        case .noPlaybackURL: "本集暂无可用的播放地址，请重试或选择其他剧集"
        case .requiresOnDemandMedia: "本集未声明为点播媒体，无法进行短剧播放"
        case let .locked(message): message
        }
    }
}
