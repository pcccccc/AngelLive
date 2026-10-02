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

/// Subtitle preferences are independent of title and chat translation.
/// FullUI alone consumes these preferences; no global player defaults are changed.
@MainActor @Observable
public final class LiveSubtitleSettings {
    public static let shared = LiveSubtitleSettings()
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "liveSubtitle.enabled") }
    }
    public var sourceLanguage: LiveSubtitleLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: "liveSubtitle.sourceLanguage") }
    }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "liveSubtitle.enabled")
        sourceLanguage = defaults.string(forKey: "liveSubtitle.sourceLanguage")
            .flatMap(LiveSubtitleLanguage.init(rawValue:)) ?? .english
    }
}
