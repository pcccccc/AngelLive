import Foundation
import Observation

public enum LiveSubtitleLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chinese = "zh-CN"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .chinese: "中文普通话"
        }
    }
}

/// Device-local preference used only by the speech-resource management screen.
/// Spoken-language detection never uses this preference as a hint.
@MainActor @Observable
public final class LiveSubtitleSettings {
    public static let shared = LiveSubtitleSettings()
    public var sourceLanguage: LiveSubtitleLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: "liveSubtitle.sourceLanguage") }
    }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The legacy global enable preference is intentionally not restored.
        // Each FullUI room owns a fresh LiveSubtitlePlaybackState instead.
        sourceLanguage = defaults.string(forKey: "liveSubtitle.sourceLanguage")
            .flatMap(LiveSubtitleLanguage.init(rawValue:)) ?? .english
    }
}

public enum LiveSubtitlePhase: Equatable, Sendable {
    case off
    case preparing
    case modelDownloadRequired
    case downloadingModel
    case waitingForSpeech
    case detecting
    case manualSelectionRequired
    case speechResourcesRequired
    case downloadingSpeechResources
    case transcribing
    case unavailable
    case failed
}

/// A user authorizes only the resource requested by the current playback attempt.
public enum LiveSubtitleResourcePreparation: Equatable, Sendable {
    case languageDetection
    case speech(language: String)
}

/// A complete session snapshot. Hosts reject snapshots from an earlier activation.
public struct LiveSubtitleUpdate: Equatable, Sendable {
    public let phase: LiveSubtitlePhase
    public let sourceLanguage: String?
    public let message: String?
    public let downloadProgress: Double?

    public init(
        phase: LiveSubtitlePhase,
        sourceLanguage: String? = nil,
        message: String? = nil,
        downloadProgress: Double? = nil
    ) {
        self.phase = phase
        self.sourceLanguage = sourceLanguage
        self.message = message
        self.downloadProgress = downloadProgress
    }
}

/// Subtitle intent for one room in one player window. Enabling always starts with
/// audio-language detection; manual selection is available only after uncertainty.
@MainActor @Observable
public final class LiveSubtitlePlaybackState {
    public private(set) var isEnabled = false
    public private(set) var phase: LiveSubtitlePhase = .off
    public private(set) var sourceLanguage: String?
    public private(set) var statusMessage: String?
    public private(set) var downloadProgress: Double?
    public private(set) var resourcePreparation: LiveSubtitleResourcePreparation?
    public private(set) var activationID = UUID()

    public var sourceLanguageDisplayName: String? {
        sourceLanguage.map { Locale.current.localizedString(forIdentifier: $0) ?? $0 }
    }

    public init() {}

    /// User actions capture activationID when their control is presented. Rotating
    /// it invalidates old sheets, resource downloads and asynchronous detections.
    @discardableResult
    public func startAutomatically(activationID: UUID) -> Bool {
        guard self.activationID == activationID, !isEnabled || phase == .failed else { return false }
        self.activationID = UUID()
        isEnabled = true
        phase = .preparing
        sourceLanguage = nil
        statusMessage = nil
        downloadProgress = nil
        resourcePreparation = nil
        return true
    }

    @discardableResult
    public func chooseLanguage(_ identifier: String, activationID: UUID) -> Bool {
        guard self.activationID == activationID, isEnabled,
              phase == .manualSelectionRequired, !identifier.isEmpty else { return false }
        self.activationID = UUID()
        sourceLanguage = identifier
        phase = .preparing
        statusMessage = nil
        downloadProgress = nil
        resourcePreparation = nil
        return true
    }

    @discardableResult
    public func prepareResources(activationID: UUID) -> Bool {
        guard self.activationID == activationID, isEnabled else { return false }
        switch phase {
        case .modelDownloadRequired:
            resourcePreparation = .languageDetection
        case .speechResourcesRequired:
            guard let sourceLanguage else { return false }
            resourcePreparation = .speech(language: sourceLanguage)
        default:
            return false
        }
        self.activationID = UUID()
        phase = .preparing
        statusMessage = nil
        downloadProgress = nil
        return true
    }

    @discardableResult
    public func apply(_ update: LiveSubtitleUpdate, activationID: UUID) -> Bool {
        guard self.activationID == activationID else { return false }
        guard isEnabled, update.phase != .off else { return false }
        phase = update.phase
        sourceLanguage = update.sourceLanguage
        statusMessage = update.message
        downloadProgress = update.downloadProgress
        return true
    }

    public func stop() {
        isEnabled = false
        phase = .off
        sourceLanguage = nil
        statusMessage = nil
        downloadProgress = nil
        resourcePreparation = nil
        activationID = UUID()
    }
}
