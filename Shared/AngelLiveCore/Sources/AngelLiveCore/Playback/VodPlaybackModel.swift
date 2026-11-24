import Foundation
import Observation

public struct VodCreditsOffer: Equatable, Sendable {
    public let playbackID: UUID
    public let nextEpisode: VodEpisode
}

@MainActor
@Observable
public final class VodPlaybackModel {
    public private(set) var detail: VodWorkDetail?
    public private(set) var selectedSeasonID: String?
    public private(set) var selectedEpisodeID: String?
    public private(set) var playback: VodResolvedPlayback?
    public private(set) var isLoadingDetail = false
    public private(set) var isLoadingPlayback = false
    public private(set) var errorMessage: String?
    public private(set) var progressWarning: String?
    public private(set) var selectionNote: String?
    public private(set) var hasFinished = false
    public private(set) var activeIntroSkipTarget: Double?
    public private(set) var progressSnapshot: VodProgressSnapshot?

    public var seasonEpisodes: [VodEpisode] {
        guard let detail else { return [] }
        guard let selectedSeasonID else { return detail.episodes }
        return detail.episodes.filter { $0.seasonID == selectedSeasonID }
    }

    public var selectedEpisode: VodEpisode? {
        detail?.episodes.first { $0.id == selectedEpisodeID }
    }

    public var preferredEpisode: VodEpisode? {
        guard let detail else { return nil }
        if let progressSnapshot {
            return VodProgressSession(snapshot: progressSnapshot).preferredEpisode(in: detail.episodes)
        }
        return detail.episodes.first
    }

    public var creditsOffer: VodCreditsOffer? {
        guard autoplayEnabled(), !overlayHold, scrubbingPlaybackID == nil else { return nil }
        return pendingCreditsOffer
    }

    @ObservationIgnored private let dependencies: VodPlaybackDependencies
    @ObservationIgnored private let progressStore: VodProgressStore
    @ObservationIgnored private let autoplayEnabled: @MainActor () -> Bool
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var progress: VodProgressSession?
    @ObservationIgnored private var progressStorageAvailable = true
    @ObservationIgnored private var selectedSourceID: String?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var completion = ShortDramaCompletionPolicy()
    @ObservationIgnored private var introDismissed = false
    @ObservationIgnored private var creditsDismissed = false
    @ObservationIgnored private var deferredAutoplayAllowed = true
    private var overlayHold = false
    private var scrubbingPlaybackID: UUID?
    private var pendingCreditsOffer: VodCreditsOffer?

    public convenience init(room: LiveModel) {
        self.init(dependencies: .live(room: room))
    }

    public init(dependencies: VodPlaybackDependencies, progressStore: VodProgressStore = .shared,
                autoplayEnabled: (@MainActor () -> Bool)? = nil) {
        self.dependencies = dependencies
        self.progressStore = progressStore
        let settings = GeneralSettingModel()
        self.autoplayEnabled = autoplayEnabled ?? { settings.vodAutoplayEnabled }
    }

    public func load() async {
        await loadDetail()
    }

    public func loadDetail() async {
        guard !isLoadingDetail else { return }
        cancelled = false
        let token = beginRequest()
        isLoadingDetail = true
        detail = nil
        selectedSeasonID = nil
        selectedEpisodeID = nil
        progressSnapshot = nil
        progressWarning = nil
        progress = nil
        let task = Task { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            do {
                let detail = try await self.dependencies.loadDetail()
                guard self.isCurrent(token) else { return }
                self.detail = detail
                self.loadProgress(for: detail)
                self.selectedEpisodeID = self.preferredEpisode?.id
                self.selectedSeasonID = self.preferredEpisode.flatMap { preferred in
                    detail.seasons.first { $0.id == preferred.seasonID }?.id
                } ?? detail.seasons.first?.id
            } catch {
                self.fail(error, token: token, fallback: "无法加载作品详情，请重试")
            }
        }
        await waitForRequest(task, token: token)
    }

    public func selectSeason(id: String) {
        guard detail?.seasons.contains(where: { $0.id == id }) == true else { return }
        selectedSeasonID = id
    }

    public func selectEpisode(id: String, sourceID: String? = nil) async {
        guard !cancelled, let detail, let episode = detail.episodes.first(where: { $0.id == id }) else { return }
        if id == selectedEpisodeID, sourceID == nil || sourceID == selectedSourceID {
            if isLoadingPlayback { return }
            if let playback, !playback.refreshOnSelect, !hasFinished,
               progressSnapshot?.episodes[id]?.completed != true { return }
        }

        let token = beginRequest()
        isLoadingPlayback = true
        selectedEpisodeID = id
        selectedSeasonID = detail.seasons.first { $0.id == episode.seasonID }?.id
        selectedSourceID = sourceID
        let task = Task { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            do {
                var resolved = try await self.dependencies.resolvePlayback(detail, episode, sourceID)
                guard self.isCurrent(token) else { return }
                self.selectedSourceID = sourceID ?? resolved.sourceID
                if resolved.refreshOnSelect {
                    resolved = try await self.dependencies.resolvePlayback(detail, episode, self.selectedSourceID)
                    guard self.isCurrent(token) else { return }
                }
                guard resolved.workID == detail.workID, resolved.episodeID == episode.id,
                      resolved.rawEpisodeID == episode.episodeID else { throw VodCatalogError.mismatchedIdentity }
                guard resolved.quality.playbackHints?.isLive == false else {
                    throw VodCatalogError.requiresOnDemandMedia
                }
                self.loadProgress(for: detail)
                let id = UUID()
                let resume = self.progress?.start(playbackID: id, episodeID: episode.id)
                let playback = resolved.startingSession(id: id, at: resume)
                self.completion.startPlayback(id: id)
                self.playback = playback
            } catch {
                self.fail(error, token: token, fallback: "无法播放本集，请重试")
            }
        }
        await waitForRequest(task, token: token)
    }

    public func retry() async {
        if detail != nil, let selectedEpisodeID {
            await selectEpisode(id: selectedEpisodeID, sourceID: selectedSourceID)
        } else {
            await loadDetail()
        }
    }

    /// Returns a seek target. The host confirms the actual seek through the scrubbing callbacks.
    public func skipIntro(playbackID: UUID) -> Double? {
        guard playback?.id == playbackID, let target = activeIntroSkipTarget else { return nil }
        dismissIntroPrompt(playbackID: playbackID)
        return target
    }

    public func dismissIntroPrompt(playbackID: UUID) {
        guard playback?.id == playbackID else { return }
        introDismissed = true
        activeIntroSkipTarget = nil
    }

    public func dismissCreditsOffer(playbackID: UUID) {
        guard playback?.id == playbackID else { return }
        creditsDismissed = true
        pendingCreditsOffer = nil
    }

    public func advanceToNextEpisode() async {
        guard let offer = creditsOffer, playback?.id == offer.playbackID else { return }
        await selectEpisode(id: offer.nextEpisode.id)
    }

    public func setOverlayHoldPresented(_ presented: Bool) async {
        overlayHold = presented
        await updateCompletionHold()
    }

    @discardableResult
    public func beginScrubbing(playbackID: UUID) -> Bool {
        guard playback?.id == playbackID, scrubbingPlaybackID == nil else { return false }
        scrubbingPlaybackID = playbackID
        _ = completion.setPresented(true)
        return true
    }

    public func completeScrubbing(playbackID: UUID, targetTime: Double?, duration: Double,
                                  seekSucceeded: Bool, resumePlayback: Bool) async {
        guard let playback, playback.id == playbackID, scrubbingPlaybackID == playbackID else { return }
        if seekSucceeded, let targetTime, targetTime.isFinite, targetTime >= 0,
           duration.isFinite, duration > 0 {
            completion.startPlayback(id: playbackID)
            deferredAutoplayAllowed = true
            hasFinished = false
            selectionNote = nil
            if let marker = playback.creditsMarker, marker.fits(duration: duration), targetTime < marker.start {
                creditsDismissed = false
            }
            if let marker = playback.introMarker, marker.fits(duration: duration), targetTime < marker.end {
                introDismissed = false
            }
            acceptPosition(id: playbackID, position: targetTime, duration: duration, flush: true, confirmedSeek: true)
        } else {
            deferredAutoplayAllowed = resumePlayback
        }
        scrubbingPlaybackID = nil
        await updateCompletionHold()
    }

    public func playbackReady(id: UUID, duration: Double) {
        guard playback?.id == id, progress?.ready(playbackID: id, duration: duration) == true else { return }
        commitProgress(flush: false, playbackStarted: true)
    }

    public func restorationCompleted(id: UUID, position: Double, duration: Double,
                                     succeeded: Bool, resumePlayback: Bool) async {
        guard playback?.id == id else { return }
        guard succeeded else {
            selectionNote = "暂时无法恢复观看位置，可重试本集"
            return
        }
        playbackReady(id: id, duration: duration)
        acceptPosition(id: id, position: position, duration: duration, flush: true)
        if duration > 0, position >= duration {
            activeIntroSkipTarget = nil
            hasFinished = true
            selectionNote = "已恢复到片尾"
        }
    }

    public func recordProgress(id: UUID, position: Double, duration: Double) {
        guard scrubbingPlaybackID == nil else { return }
        acceptPosition(id: id, position: position, duration: duration, flush: false)
    }

    public func playbackFinished(id: UUID, error: Error?) async {
        guard playback?.id == id else { return }
        if error != nil {
            _ = beginRequest()
            errorMessage = "播放中断，请重试本集"
            return
        }
        if completion.finish(id: id, failed: false) == .completed {
            await finishEpisode(id: id)
        }
    }

    public func flushProgress() {
        guard progressStorageAvailable, let key = progressSnapshot?.key else { return }
        do {
            try progressStore.flush(for: key)
        } catch {
            progressWarning = "播放进度暂时无法保存"
        }
    }

    public func cancel() {
        _ = beginRequest()
        cancelled = true
        overlayHold = false
    }

    private func beginRequest() -> UUID {
        flushProgress()
        progress?.invalidate()
        request?.cancel()
        request = nil
        generation = UUID()
        playback = nil
        isLoadingDetail = false
        isLoadingPlayback = false
        hasFinished = false
        errorMessage = nil
        selectionNote = nil
        activeIntroSkipTarget = nil
        pendingCreditsOffer = nil
        introDismissed = false
        creditsDismissed = false
        scrubbingPlaybackID = nil
        deferredAutoplayAllowed = true
        completion.invalidate()
        _ = completion.setPresented(overlayHold)
        return generation
    }

    private func isCurrent(_ token: UUID) -> Bool {
        !cancelled && !Task.isCancelled && generation == token
    }

    private func waitForRequest(_ task: Task<Void, Never>, token: UUID) async {
        request = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard generation == token else { return }
        request = nil
        isLoadingDetail = false
        isLoadingPlayback = false
    }

    private func fail(_ error: Error, token: UUID, fallback: String) {
        guard isCurrent(token), !(error is CancellationError) else { return }
        errorMessage = (error as? VodCatalogError)?.errorDescription ?? fallback
    }

    private func loadProgress(for detail: VodWorkDetail) {
        let key = VodProgressKey(pluginID: detail.pluginID, workID: detail.workID)
        let snapshot: VodProgressSnapshot
        do {
            snapshot = try progressStore.load(for: key)
            progressStorageAvailable = true
        } catch {
            snapshot = progressSnapshot ?? VodProgressSnapshot(key: key)
            progressStorageAvailable = false
            progressWarning = "暂时无法读取观看进度，本次将从头播放"
        }
        progressSnapshot = snapshot
        progress = VodProgressSession(snapshot: snapshot)
    }

    private func acceptPosition(id: UUID, position: Double, duration: Double, flush: Bool, confirmedSeek: Bool = false) {
        guard let playback, playback.id == id, !hasFinished,
              position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return }
        if !introDismissed, let marker = playback.introMarker, marker.fits(duration: duration),
           position >= marker.start, position < marker.end {
            activeIntroSkipTarget = marker.end
        } else {
            activeIntroSkipTarget = nil
        }

        let creditsStart = playback.creditsMarker.flatMap { $0.fits(duration: duration) ? $0.start : nil }
        let isInCredits = creditsStart.map { position >= $0 } ?? false
        let changed: Bool?
        if confirmedSeek {
            changed = progress?.seekSucceeded(playbackID: id, position: position, duration: duration,
                                              creditsStart: creditsStart)
        } else if isInCredits {
            changed = progress?.markCreditsReached(playbackID: id, position: position, duration: duration)
        } else {
            changed = progress?.record(playbackID: id, position: position, duration: duration)
        }
        if changed == true { commitProgress(flush: flush || isInCredits) }

        if isInCredits {
            if !creditsDismissed, let next = nextEpisode {
                pendingCreditsOffer = VodCreditsOffer(playbackID: id, nextEpisode: next)
            }
        } else {
            pendingCreditsOffer = nil
        }
    }

    private func commitProgress(flush: Bool, playbackStarted: Bool = false) {
        guard let detail, let episode = selectedEpisode, let snapshot = progress?.snapshot,
              let sample = snapshot.episodes[episode.id] else { return }
        progressSnapshot = snapshot
        guard progressStorageAvailable else { return }
        let metadata = VodHistoryMetadata(
            title: detail.title, posterURL: detail.posterURL, kind: detail.kind, episodeID: episode.id,
            episodeTitle: episode.title, episodeNumber: episode.number, lastWatchedAt: sample.updatedAt
        )
        do {
            try progressStore.updateEpisode(sample, episodeID: episode.id, for: snapshot.key,
                                            historyMetadata: metadata, playbackStarted: playbackStarted)
            if flush {
                try progressStore.flush(for: snapshot.key)
            } else {
                try progressStore.flushIfNeeded(for: snapshot.key)
            }
            progressSnapshot = try progressStore.load(for: snapshot.key)
        } catch {
            progressWarning = "播放进度暂时无法保存"
        }
    }

    private var nextEpisode: VodEpisode? {
        guard let detail, detail.kind == .series,
              let index = detail.episodes.firstIndex(where: { $0.id == selectedEpisodeID }) else { return nil }
        return detail.episodes.dropFirst(index + 1).first
    }

    private func updateCompletionHold() async {
        guard let id = completion.setPresented(overlayHold || scrubbingPlaybackID != nil) else { return }
        await finishEpisode(id: id)
    }

    private func finishEpisode(id: UUID) async {
        guard let playback, playback.id == id else { return }
        let duration = selectedEpisodeID.flatMap { progressSnapshot?.episodes[$0]?.duration }
        let hasCredits = playback.creditsMarker.map { $0.fits(duration: duration) } ?? false
        if hasCredits, let duration {
            // A short credits interval can fall between the last periodic sample and EOF.
            acceptPosition(id: id, position: duration, duration: duration, flush: true)
        } else if progress?.complete(playbackID: id) == true {
            commitProgress(flush: true)
        }
        activeIntroSkipTarget = nil
        hasFinished = true
        if !hasCredits, autoplayEnabled(), deferredAutoplayAllowed, let next = nextEpisode {
            await selectEpisode(id: next.id)
        } else {
            selectionNote = "本集已结束"
        }
    }
}

@MainActor
public struct VodPlaybackDependencies {
    let loadDetail: @MainActor () async throws -> VodWorkDetail
    let resolvePlayback: @MainActor (VodWorkDetail, VodEpisode, String?) async throws -> VodResolvedPlayback

    public init(loadDetail: @escaping @MainActor () async throws -> VodWorkDetail,
                resolvePlayback: @escaping @MainActor (VodWorkDetail, VodEpisode, String?) async throws -> VodResolvedPlayback) {
        self.loadDetail = loadDetail
        self.resolvePlayback = resolvePlayback
    }

    static func live(room: LiveModel) -> Self {
        Self(
            loadDetail: {
                guard let platform = LiveParseJSPlatformManager.platform(for: room.liveType) else {
                    throw VodCatalogError.unsupportedPlugin
                }
                return try await LiveParseJSPlatformManager.getVodDetail(
                    platform: platform, workId: room.roomId, fallbackTitle: room.roomTitle,
                    fallbackPosterURL: room.roomCover
                )
            },
            resolvePlayback: { detail, episode, sourceID in
                guard let platform = LiveParseJSPlatformManager.platform(forPluginId: detail.pluginID) else {
                    throw VodCatalogError.unsupportedPlugin
                }
                return try await LiveParseJSPlatformManager.getVodPlayback(
                    platform: platform, workId: detail.workID, episode: episode, sourceId: sourceID
                )
            }
        )
    }
}
