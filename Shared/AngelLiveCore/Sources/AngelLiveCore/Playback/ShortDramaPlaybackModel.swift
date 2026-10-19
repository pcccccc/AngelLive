import Foundation
import Observation

public struct ShortDramaPlayback: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let quality: LiveQualityDetail
    public let resumePosition: Double?
}

/// FullUI hosts share playback policy and local progress; engines and presentation stay in the host.
@MainActor
@Observable
public final class ShortDramaPlaybackModel {
    public let room: LiveModel
    public private(set) var episodes: [ShortDramaEpisode] = []
    public private(set) var selectedEpisodeID: String?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var playback: ShortDramaPlayback?
    public private(set) var hasFinished = false
    public private(set) var selectionNote: String?
    public private(set) var progressWarning: String?
    public var autoplay = true

    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var completion = ShortDramaCompletionPolicy()
    @ObservationIgnored private var episodesPresented = false
    @ObservationIgnored private var episodeSwipeActive = false
    @ObservationIgnored private var scrubbingPlaybackID: UUID?
    @ObservationIgnored private var completionAllowsAutoplay = true
    @ObservationIgnored private let dependencies: ShortDramaPlaybackDependencies
    @ObservationIgnored private let progressStore: ShortDramaProgressStore
    @ObservationIgnored private var progress: ShortDramaProgressSession?
    @ObservationIgnored private var progressStorageAvailable = true

    public var selectedEpisode: ShortDramaEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    public init(room: LiveModel) {
        self.room = room
        dependencies = .live
        progressStore = .shared
    }

    init(room: LiveModel, dependencies: ShortDramaPlaybackDependencies, progressStore: ShortDramaProgressStore) {
        self.room = room
        self.dependencies = dependencies
        self.progressStore = progressStore
    }

    public func load() async {
        guard !isLoading else { return }
        cancelled = false
        let token = beginRequest()
        episodes = []
        selectedEpisodeID = nil
        let task = Task { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            do {
                let platform = try self.platform()
                let args = try await self.dependencies.loadArguments(platform, self.room)
                guard self.isCurrent(token) else { return }
                self.episodes = try ShortDramaCatalog.episodes(
                    pluginID: platform.pluginId, roomID: self.room.roomId, playArgs: args
                )
                self.loadProgress(pluginID: platform.pluginId)
                guard let first = self.progress?.preferredEpisode(in: self.episodes)
                    ?? ShortDramaCompletionPolicy.firstPlayableEpisode(in: self.episodes)
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

    public func selectEpisode(id: String) async {
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

    public func playbackFinished(id: UUID, error: Error?) async {
        guard !cancelled, playback?.id == id else { return }
        if let error {
            // A player reopened at the beginning keeps its UUID. Its real error must still
            // reach the UI when a natural EOF for this UUID was already recorded earlier.
            _ = completion.finish(id: id, failed: true)
            completion.invalidate()
            flushProgress()
            progress?.invalidate()
            scrubbingPlaybackID = nil
            playback = nil
            hasFinished = false
            errorMessage = error.localizedDescription
            selectionNote = nil
            return
        }
        switch completion.finish(id: id, failed: false) {
        case .ignored, .failed: return
        case .deferred:
            hasFinished = true
            recordCompletion(id: id)
            return
        case .completed:
            hasFinished = true
            recordCompletion(id: id)
            await continueAfterCompletion(id: id)
        }
    }

    public func setEpisodesPresented(_ presented: Bool) async {
        guard !cancelled else { return }
        episodesPresented = presented
        await updateCompletionHold()
    }

    /// A swipe holds EOF independently of modal presentation until it commits or settles back.
    public func setEpisodeSwipeActive(_ active: Bool) async {
        guard !cancelled else { return }
        episodeSwipeActive = active
        await updateCompletionHold()
    }

    /// Establish the hold synchronously, before the player is paused or a seek task starts.
    public func beginScrubbing(playbackID: UUID) -> Bool {
        guard !cancelled, playback?.id == playbackID, scrubbingPlaybackID == nil else { return false }
        scrubbingPlaybackID = playbackID
        _ = completion.setPresented(true)
        return true
    }

    public func completeScrubbing(
        playbackID: UUID,
        targetTime: Double?,
        duration: Double,
        seekSucceeded: Bool,
        resumePlayback: Bool
    ) async {
        guard !cancelled, playback?.id == playbackID, scrubbingPlaybackID == playbackID else { return }

        if seekSucceeded, let targetTime, targetTime.isFinite, duration.isFinite, duration > 0 {
            if progress?.seekSucceeded(playbackID: playbackID, position: targetTime, duration: duration) == true {
                commitProgress(flushImmediately: true)
            }
            // A seek starts a new completion cycle for this same player instance. Discard EOF
            // captured at the old position, while retaining the independent sheet/swipe hold.
            completion.startPlayback(id: playbackID)
            hasFinished = false
            selectionNote = nil
            completionAllowsAutoplay = true
            if targetTime >= duration {
                completionAllowsAutoplay = resumePlayback
                hasFinished = true
                _ = completion.finish(id: playbackID, failed: false)
            }
        } else if hasFinished {
            // Cancellation/failure retains a natural EOF observed during the scrub, together
            // with the intent captured before dragging (a paused seek must not start playback).
            completionAllowsAutoplay = resumePlayback
        }

        scrubbingPlaybackID = nil
        await updateCompletionHold()
    }

    public func cancel() {
        flushProgress()
        progress?.invalidate()
        cancelled = true
        generation = UUID()
        request?.cancel()
        request = nil
        playback = nil
        episodesPresented = false
        episodeSwipeActive = false
        scrubbingPlaybackID = nil
        completionAllowsAutoplay = true
        completion = ShortDramaCompletionPolicy()
        isLoading = false
    }

    private func platform() throws -> LiveParseJSPlatform {
        try dependencies.resolvePlatform(room)
    }

    private func beginRequest() -> UUID {
        flushProgress()
        progress?.invalidate()
        request?.cancel()
        generation = UUID()
        playback = nil
        completion.invalidate()
        scrubbingPlaybackID = nil
        completionAllowsAutoplay = true
        _ = completion.setPresented(episodesPresented || episodeSwipeActive)
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
            let quality = try await dependencies.prepare(platform, room, episode)
            guard isCurrent(token) else { return }
            try rejectLocked(quality)
            guard !RoomPlaybackResolver.resolvePlan(selectedQuality: quality).isLive else {
                throw ShortDramaPlaybackError.requiresOnDemandMedia
            }
            guard let url = RoomPlaybackResolver.playableURL(for: quality) else {
                throw ShortDramaPlaybackError.noPlaybackURL
            }
            // Another window may have accepted progress while this episode was preparing.
            if progressStorageAvailable { loadProgress(pluginID: platform.pluginId) }
            let id = UUID()
            completion.startPlayback(id: id)
            let resumePosition = progress?.start(playbackID: id, episodeID: episode.id)
            playback = ShortDramaPlayback(id: id, url: url, quality: quality, resumePosition: resumePosition)
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

    public func playbackReady(id: UUID, duration: Double) {
        guard playback?.id == id, playback?.resumePosition == nil else { return }
        let previous = progress?.snapshot
        guard progress?.ready(playbackID: id, duration: duration) == true else { return }
        if progress?.snapshot != previous {
            commitProgress(flushImmediately: true)
        }
    }

    public func restorationCompleted(
        id: UUID, position: Double, duration: Double, succeeded: Bool, resumePlayback: Bool
    ) async {
        guard !cancelled, playback?.id == id else { return }
        guard succeeded, position.isFinite, position >= 0, duration.isFinite, duration > 0 else {
            // Keep the historical snapshot intact; the existing retry action prepares a new player.
            progress?.invalidate()
            playback = nil
            errorMessage = "未能恢复播放进度，请重试或选择其他剧集"
            return
        }
        progress?.ready(playbackID: id, duration: duration)
        recordProgress(id: id, position: position, duration: duration)
        if position >= duration {
            // A confirmed restore to the endpoint follows the same paused/autoplay semantics
            // as a successful user seek, including the independent sheet/swipe holds.
            completionAllowsAutoplay = resumePlayback
            switch completion.finish(id: id, failed: false) {
            case .completed:
                hasFinished = true
                recordCompletion(id: id)
                await continueAfterCompletion(id: id)
            case .deferred:
                hasFinished = true
                recordCompletion(id: id)
            case .ignored, .failed:
                break
            }
        }
    }

    public func recordProgress(id: UUID, position: Double, duration: Double) {
        guard !cancelled, playback?.id == id, scrubbingPlaybackID == nil,
              progress?.record(playbackID: id, position: position, duration: duration) == true else { return }
        commitProgress(flushImmediately: false)
    }

    public func flushProgress() {
        guard progressStorageAvailable, let key = progress?.snapshot.key else { return }
        do {
            try progressStore.flush(for: key)
        } catch {
            warnAboutProgress("播放进度暂时无法保存")
        }
    }

    private func commitProgress(flushImmediately: Bool) {
        guard progressStorageAvailable, let progress, let episodeID = progress.activeEpisodeID,
              let episodeProgress = progress.snapshot.episodes[episodeID] else { return }
        do {
            // Submit only this UUID's accepted episode event, never its possibly stale full snapshot.
            try progressStore.updateEpisode(episodeProgress, episodeID: episodeID, for: progress.snapshot.key)
            if flushImmediately {
                try progressStore.flush(for: progress.snapshot.key)
            } else {
                try progressStore.flushIfNeeded(for: progress.snapshot.key)
            }
        } catch {
            warnAboutProgress("播放进度暂时无法保存")
        }
    }

    private func loadProgress(pluginID: String) {
        let key = ShortDramaProgressKey(pluginID: pluginID, roomID: room.roomId)
        do {
            progress = ShortDramaProgressSession(snapshot: try progressStore.load(for: key))
            progressStorageAvailable = true
        } catch {
            // A damaged or unreadable file is retained rather than replaced by an empty snapshot.
            progress = ShortDramaProgressSession(snapshot: ShortDramaProgressSnapshot(key: key))
            progressStorageAvailable = false
            warnAboutProgress("暂时无法读取观看进度，本次将从头播放")
        }
    }

    private func recordCompletion(id: UUID) {
        if progress?.complete(playbackID: id) == true {
            commitProgress(flushImmediately: true)
        }
    }

    private func warnAboutProgress(_ message: String) {
        guard progressWarning == nil else { return }
        progressWarning = message
    }

    private func updateCompletionHold() async {
        guard let id = completion.setPresented(
            episodesPresented || episodeSwipeActive || scrubbingPlaybackID != nil
        ) else { return }
        await continueAfterCompletion(id: id)
    }

    private func continueAfterCompletion(id: UUID) async {
        guard !cancelled, playback?.id == id, hasFinished,
              let selectedEpisodeID else { return }
        guard autoplay, completionAllowsAutoplay else {
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

/// Internal seams preserve the production plugin path while allowing ordered async responses in tests.
@MainActor
struct ShortDramaPlaybackDependencies {
    var resolvePlatform: @MainActor (LiveModel) throws -> LiveParseJSPlatform
    var loadArguments: @MainActor (LiveParseJSPlatform, LiveModel) async throws -> [LiveQualityModel]
    var prepare: @MainActor (LiveParseJSPlatform, LiveModel, ShortDramaEpisode) async throws -> LiveQualityDetail

    static let live = ShortDramaPlaybackDependencies(
        resolvePlatform: { room in
            guard let platform = LiveParseJSPlatformManager.platform(for: room.liveType) else {
                throw ShortDramaPlaybackError.unsupportedPlugin
            }
            // Resolve the selected installed version; registry metadata may describe a newer candidate.
            let behavior = try LiveParsePlugins.shared.resolve(pluginId: platform.pluginId).manifest.hostBehavior
            guard behavior?.contentKind == "shortDrama", behavior?.episodeSelection == "qualityList" else {
                throw ShortDramaPlaybackError.unsupportedPlugin
            }
            return platform
        },
        loadArguments: { platform, room in
            try await LiveParseJSPlatformManager.getPlayArgs(
                platform: platform, roomId: room.roomId, userId: room.userId
            )
        },
        prepare: { platform, room, episode in
            try await RoomPlaybackPreparer.prepare(
                roomId: room.roomId, cdn: episode.cdn, quality: episode.quality, plugin: platform
            )
        }
    )
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
