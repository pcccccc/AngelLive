#if canImport(KSPlayer)
import AngelLiveCore
import AVFoundation
import Foundation
import KSPlayer
import KSPlayerUI
import Observation

public struct OnDemandSubtitleTrack: Identifiable, Equatable, Sendable {
    public let id: String
    public let subtitleID: String
    public let name: String
    public let language: String?
    public let isExternal: Bool
    public let format: VodSubtitleFormat?
}

public struct OnDemandAudioTrack: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let name: String
    public let language: String?
}

public enum OnDemandSubtitleFontSizeTier: Double, CaseIterable, Sendable {
    case small = 14
    case standard = 16
    case large = 20
}

/// Point-in-time track snapshots belong to the same surface and UUID as playback controls.
@MainActor
@Observable
public final class KSOnDemandPlayerController {
    public typealias PlaybackFinishDisposition = KSShortDramaPlayerController.PlaybackFinishDisposition

    public struct PlaybackStatus: Equatable, Sendable {
        public let isPlaying: Bool
        public let isPreparing: Bool

        public static let preparing = Self(isPlaying: false, isPreparing: true)
    }

    public private(set) var subtitleTracks: [OnDemandSubtitleTrack] = []
    public private(set) var selectedSubtitleID: String?
    public private(set) var audioTracks: [OnDemandAudioTrack] = []
    public private(set) var selectedAudioTrackID: Int32?
    public private(set) var subtitleDelay = 0.0
    public private(set) var subtitleFontSizeTier: OnDemandSubtitleFontSizeTier = .standard

    public var coordinator: KSVideoPlayer.Coordinator? { transport.coordinator }
    public var playbackID: UUID? { transport.playbackID }
    public var wantsPlayback: Bool { transport.wantsPlayback }

    @ObservationIgnored private let transport = KSShortDramaPlayerController()
    @ObservationIgnored private var externalTracks: [VodExternalSubtitle] = []
    @ObservationIgnored private var externalInfoByID: [String: URLSubtitleInfo] = [:]
    @ObservationIgnored private var subtitleInfoByID: [String: any SubtitleInfo] = [:]
    @ObservationIgnored private var subtitleSelectionWasSet = false
    @ObservationIgnored private let fontSizeOwner = UUID()

    // KSPlayer exposes one process-wide base size. A departing surface can only release its own override.
    private static var originalFontSize: Double?
    private static var fontSizeOverrides: [(owner: UUID, size: Double)] = []

    public init() {}

    public func attach(
        _ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID, url: URL,
        subtitles: [VodExternalSubtitle] = [], userAgent: String? = nil,
        resumePosition: Double?, desiredPlayback: Bool
    ) {
        if self.coordinator !== coordinator || self.playbackID != playbackID {
            if self.coordinator === coordinator, let model = coordinator.playerLayer?.subtitleModel {
                model.subtitleDelay = 0
                model.url = url
            }
            resetTrackState()
            externalTracks = subtitles
            for subtitle in subtitles where externalInfoByID[subtitle.id] == nil {
                externalInfoByID[subtitle.id] = URLSubtitleInfo(
                    subtitleID: subtitle.id, name: subtitle.name, url: subtitle.url,
                    userAgent: userAgent, languageCode: subtitle.language
                )
            }
        }
        transport.attach(coordinator, playbackID: playbackID, url: url,
                         resumePosition: resumePosition, desiredPlayback: desiredPlayback)
        if let layer = coordinator.playerLayer {
            if !desiredPlayback || transport.isRestoring(for: playbackID) { layer.pause() }
            if layer.player.isReadyToPlay { refreshTracks() }
        }
    }

    public func release(_ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID) {
        if self.coordinator === coordinator {
            guard self.playbackID == playbackID else { return }
            coordinator.playerLayer?.subtitleModel.subtitleDelay = 0
            resetTrackState()
        }
        transport.release(coordinator, playbackID: playbackID)
    }

    public func pause() { transport.pause() }
    public func play() { transport.play() }

    public func stop() {
        if let coordinator, let playbackID { release(coordinator, playbackID: playbackID) }
        transport.stop()
    }

    public func setDesiredPlayback(_ desired: Bool, applyImmediately: Bool = true) {
        transport.setDesiredPlayback(desired, applyImmediately: applyImmediately)
    }

    public func setRate(_ rate: Float) { transport.setRate(rate) }

    public func seek(to time: Double, playbackID: UUID) async -> Bool {
        guard time.isFinite else { return false }
        return await transport.seek(to: time, playbackID: playbackID)
    }

    public func isSeekable(for playbackID: UUID?) -> Bool { transport.isSeekable(for: playbackID) }
    public func isRestoring(for playbackID: UUID) -> Bool { transport.isRestoring(for: playbackID) }

    public func playbackStatus(for id: UUID?) -> PlaybackStatus {
        guard let id, id == playbackID, !isRestoring(for: id),
              let layer = coordinator?.playerLayer else { return .preparing }
        let playing = layer.player.isPlaying
        let playable = layer.player.loadState == .playable
        let isPreparing = switch layer.state {
        case .initialized, .preparing:
            true
        case .bufferFinished, .paused, .playedToTheEnd, .error:
            false
        case .buffering:
            !playable || !playing
        case .readyToPlay:
            // A local asset may start and keep advancing without another layer state transition.
            !playable && !playing
        }
        return PlaybackStatus(isPlaying: wantsPlayback && (playing || layer.state == .bufferFinished),
                              isPreparing: isPreparing)
    }

    public func playbackHasFailed(for playbackID: UUID) -> Bool { transport.playbackHasFailed(for: playbackID) }

    public func restoreIfPossible(model: VodPlaybackModel, onReady: @escaping (UUID) -> Void) {
        transport.restoreIfPossible(
            matchesPlayback: { model.playback?.id == $0 },
            finishRestoration: { id, position, duration, succeeded, resume in
                await model.restorationCompleted(id: id, position: position, duration: duration,
                                                 succeeded: succeeded, resumePlayback: resume)
            },
            hasFinished: { model.hasFinished },
            onReady: onReady
        )
    }

    public func synchronize(layer: KSPlayerLayer, state: KSPlayerState, playbackID: UUID? = nil) {
        guard let current = self.playbackID, playbackID == nil || playbackID == current,
              coordinator?.playerLayer === layer else { return }
        if layer.player.isReadyToPlay { refreshTracks() }
        transport.synchronize(layer: layer, state: state)
    }

    public func handlePlaybackFinished(
        layer: KSPlayerLayer, playbackID: UUID, error: Error?
    ) -> PlaybackFinishDisposition {
        transport.handlePlaybackFinished(layer: layer, playbackID: playbackID, error: error)
    }

    public func timeSample(for playbackID: UUID?) -> (current: Double, duration: Double)? {
        guard let playbackID, playbackID == self.playbackID else { return nil }
        if coordinator?.playerLayer?.player.isReadyToPlay == true { refreshTracks() }
        return transport.timeSample(for: playbackID)
    }

    static func trackDisplayName(_ name: String, language: String?) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unspecified = ["", "und", "unknown"]
        let code: String
        if unspecified.contains(value.lowercased()) {
            code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        } else if (2...3).contains(value.count), value.allSatisfy({ $0.isASCII && $0.isLetter }) {
            code = value.lowercased()
        } else {
            return name
        }
        guard !unspecified.contains(code) else { return "未指定语言" }
        let canonical = ["zho": "zh", "chi": "zh", "eng": "en", "jpn": "ja"][code] ?? code
        return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: canonical) ?? code
    }

    public func refreshTracks() {
        guard playbackID != nil, let layer = coordinator?.playerLayer, layer.player.isReadyToPlay else { return }
        let model = layer.subtitleModel
        let embeddedInfos = layer.player.subtitleDataSource?.infos() ?? []
        let embeddedTracks = layer.player.tracks(mediaType: .subtitle).compactMap { $0 as? any SubtitleInfo }
        var infos: [String: any SubtitleInfo] = [:]
        var subtitles: [OnDemandSubtitleTrack] = []

        for info in embeddedInfos + embeddedTracks + model.subtitleInfos where !(info is URLSubtitleInfo) {
            let id = "int:\(info.subtitleID)"
            guard infos[id] == nil else { continue }
            infos[id] = info
            subtitles.append(OnDemandSubtitleTrack(id: id, subtitleID: info.subtitleID,
                                                    name: Self.trackDisplayName(info.name, language: info.languageCode),
                                                    language: info.languageCode, isExternal: false, format: nil))
        }
        for subtitle in externalTracks {
            guard infos[subtitle.id] == nil, let info = externalInfoByID[subtitle.id] else { continue }
            model.addSubtitle(info: info)
            infos[subtitle.id] = info
            subtitles.append(OnDemandSubtitleTrack(id: subtitle.id, subtitleID: info.subtitleID,
                                                    name: Self.trackDisplayName(subtitle.name, language: subtitle.language),
                                                    language: subtitle.language,
                                                    isExternal: true, format: subtitle.format))
        }
        subtitleInfoByID = infos
        if subtitleTracks != subtitles { subtitleTracks = subtitles }
        if subtitleSelectionWasSet {
            let desired = selectedSubtitleID.flatMap { infos[$0] }
            if model.selectedSubtitleInfo?.subtitleID != desired?.subtitleID { layer.select(subtitleInfo: desired) }
        } else {
            let selected = model.selectedSubtitleInfo
            let id = subtitles.first { infos[$0.id] === selected }?.id
                ?? subtitles.first { $0.subtitleID == selected?.subtitleID }?.id
            if selectedSubtitleID != id { selectedSubtitleID = id }
        }

        let tracks = layer.player.tracks(mediaType: .audio)
        var ids: Set<Int32> = []
        let audio = tracks.filter { ids.insert($0.trackID).inserted }.map {
            OnDemandAudioTrack(id: $0.trackID, name: Self.trackDisplayName($0.name, language: $0.languageCode), language: $0.languageCode)
        }
        if audioTracks != audio { audioTracks = audio }
        let audioID = tracks.first { $0.isEnabled }?.trackID
        if selectedAudioTrackID != audioID { selectedAudioTrackID = audioID }
    }

    public func selectSubtitle(id: String?) {
        guard let layer = coordinator?.playerLayer, playbackID != nil else { return }
        let trackID = id.flatMap { requested in
            subtitleTracks.first { $0.id == requested || $0.subtitleID == requested }?.id
        }
        let info = trackID.flatMap { subtitleInfoByID[$0] }
        guard id == nil || info != nil else { return }
        subtitleSelectionWasSet = true
        selectedSubtitleID = trackID
        layer.select(subtitleInfo: info)
        if id == nil { layer.select(subtitleInfo: nil, isSecondary: true) }
        redrawSubtitles(in: layer)
    }

    public func selectAudioTrack(id: Int32) {
        guard playbackID != nil, let layer = coordinator?.playerLayer,
              let track = layer.player.tracks(mediaType: .audio).first(where: { $0.trackID == id }) else { return }
        layer.player.select(track: track)
        refreshTracks()
    }

    public func setSubtitleDelay(_ delay: Double) {
        guard !delay.isNaN, playbackID != nil, let layer = coordinator?.playerLayer else { return }
        subtitleDelay = min(max(delay, -10), 10)
        layer.subtitleModel.subtitleDelay = subtitleDelay
        redrawSubtitles(in: layer)
    }

    public func adjustSubtitleDelay(by delta: Double) { setSubtitleDelay(subtitleDelay + delta) }
    public func resetSubtitleDelay() { setSubtitleDelay(0) }

    public func setSubtitleFontSizeTier(_ tier: OnDemandSubtitleFontSizeTier) {
        guard playbackID != nil, let layer = coordinator?.playerLayer else { return }
        if Self.originalFontSize == nil { Self.originalFontSize = KSOptions.subtitleFontSize }
        Self.fontSizeOverrides.removeAll { $0.owner == fontSizeOwner }
        Self.fontSizeOverrides.append((fontSizeOwner, tier.rawValue))
        KSOptions.subtitleFontSize = tier.rawValue
        subtitleFontSizeTier = tier
        redrawSubtitles(in: layer)
    }

    private func redrawSubtitles(in layer: KSPlayerLayer) {
        let model = layer.subtitleModel
        model.cleanParts()
        let size = model.screenSize
        guard layer.player.isReadyToPlay, size.width > 0, size.height > 0 else { return }
        model.subtitle(currentTime: layer.player.currentPlaybackTime, playRatio: model.playRatio, screenSize: size)
    }

    private func resetTrackState() {
        Self.fontSizeOverrides.removeAll { $0.owner == fontSizeOwner }
        if let size = Self.fontSizeOverrides.last?.size {
            KSOptions.subtitleFontSize = size
        } else if let original = Self.originalFontSize {
            KSOptions.subtitleFontSize = original
            Self.originalFontSize = nil
        }
        subtitleFontSizeTier = .standard
        subtitleDelay = 0
        selectedSubtitleID = nil
        selectedAudioTrackID = nil
        subtitleSelectionWasSet = false
        subtitleTracks = []
        audioTracks = []
        externalTracks = []
        externalInfoByID = [:]
        subtitleInfoByID = [:]
    }
}
#endif
