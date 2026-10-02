import Foundation
import NaturalLanguage

public enum RoomTranslationEngine: String, CaseIterable, Sendable {
    case apple
    case llm

    public var displayName: String {
        switch self {
        case .apple: "Apple 原生翻译"
        case .llm: "大模型翻译"
        }
    }
}

public enum RoomTranslationError: Error, LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case invalidModel
    case apiKeyRequired
    case secureStorage
    case unavailable
    case authentication
    case rateLimited
    case serviceUnavailable
    case invalidResponse
    case busy
    case languageResourcesRequired

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "请输入 HTTPS 服务基础地址，例如 https://example.invalid/v1。"
        case .invalidModel:
            "请输入模型名称。"
        case .apiKeyRequired:
            "更改接口地址时需要重新填写 API Key。"
        case .secureStorage:
            "无法访问安全存储，请稍后重试。"
        case .unavailable:
            "当前翻译方式暂不可用。"
        case .authentication:
            "API 凭据无效，请检查后重试。"
        case .rateLimited:
            "请求过于频繁，请稍后重试。"
        case .serviceUnavailable:
            "翻译服务暂不可用，请稍后重试。"
        case .invalidResponse:
            "翻译服务返回了无法识别的结果。"
        case .busy:
            "等待翻译的标题较多，请稍后重试。"
        case .languageResourcesRequired:
            "请在翻译设置中下载所需语言包。"
        }
    }
}

public struct NativeTranslationLanguagePair: Identifiable, Hashable, Sendable {
    public let sourceLanguage: String
    public let targetLanguage: String

    public init(sourceLanguage: String, targetLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    public var id: String { "\(sourceLanguage)\u{0}\(targetLanguage)" }

    public var displayName: String {
        "\(Self.languageName(sourceLanguage)) → \(Self.languageName(targetLanguage))"
    }

    private static func languageName(_ identifier: String) -> String {
        switch identifier {
        case "en": "英语"
        case "ja": "日语"
        case "ko": "韩语"
        case "zh-Hans": "中文简体"
        case "zh-Hant": "中文繁体"
        default: Locale(identifier: "zh-Hans").localizedString(forIdentifier: identifier) ?? identifier
        }
    }
}

public enum NativeTranslationLanguageStatus: Sendable, Equatable {
    case checking
    case notDownloaded
    case installed
    case unsupported
}

enum RoomTranslationLanguageCatalog {
    static let commonSourceLanguages = ["en", "ja", "ko"]

    static func supportsAutomaticTranslation(from language: String) -> Bool {
        guard let base = baseLanguage(of: language) else { return false }
        return commonSourceLanguages.contains(base)
    }

    static func nativePairs(targetLanguage: String) -> [NativeTranslationLanguagePair] {
        commonSourceLanguages.compactMap { sourceLanguage in
            guard !roomTranslationLanguagesMatch(sourceLanguage, targetLanguage) else { return nil }
            return NativeTranslationLanguagePair(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
    }

    private static func baseLanguage(of language: String) -> String? {
        language
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first
            .map { $0.lowercased() }
    }
}

enum RoomTranslationContentKind: Hashable, Sendable {
    case roomTitle
    case danmaku
    case subtitle
}

enum RoomTranslationRequestPurpose: Hashable, Sendable {
    case automatic
    case explicitTest
    case prepareLanguages
}

struct RoomTranslationRequest: Sendable {
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
    let baseURL: URL?
    let model: String?
    let apiKey: String?
    let contentKind: RoomTranslationContentKind
    let purpose: RoomTranslationRequestPurpose

    init(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        baseURL: URL?,
        model: String?,
        apiKey: String?,
        contentKind: RoomTranslationContentKind = .roomTitle,
        purpose: RoomTranslationRequestPurpose = .automatic
    ) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.contentKind = contentKind
        self.purpose = purpose
    }
}

protocol RoomTranslationProvider: Sendable {
    func translate(_ request: RoomTranslationRequest) async throws -> String
}

protocol RoomTranslationRetrying: Sendable {
    func prepareForExplicitRetry() async
}

@MainActor
protocol RoomTranslationLanguagePreparing: Sendable {
    func prepareLanguages(sourceLanguage: String, targetLanguage: String) async throws
    func nativeLanguageStatus(
        for pair: NativeTranslationLanguagePair
    ) async -> NativeTranslationLanguageStatus
}

protocol RoomTitleLanguageDetecting: Sendable {
    func sourceLanguage(for text: String) -> String?
}

struct NaturalRoomTitleLanguageDetector: RoomTitleLanguageDetecting {
    func sourceLanguage(for text: String) -> String? {
        let meaningfulScalars = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard meaningfulScalars.count >= 3 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            .sorted { $0.value > $1.value }
        guard let first = hypotheses.first,
              first.value >= 0.5,
              hypotheses.count == 1 || first.value - hypotheses[1].value >= 0.15 else {
            return nil
        }
        return first.key.rawValue
    }
}

struct RoomTranslationCacheKey: Hashable, Sendable {
    let original: String
    let sourceLanguage: String
    let targetLanguage: String
    let engine: RoomTranslationEngine
    let endpoint: String
    let model: String
    let configurationRevision: Int
    let contentKind: RoomTranslationContentKind

    init(
        original: String,
        sourceLanguage: String,
        targetLanguage: String,
        engine: RoomTranslationEngine,
        endpoint: String,
        model: String,
        configurationRevision: Int,
        contentKind: RoomTranslationContentKind = .roomTitle
    ) {
        self.original = original
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.engine = engine
        self.endpoint = endpoint
        self.model = model
        self.configurationRevision = configurationRevision
        self.contentKind = contentKind
    }
}

func roomTranslationLanguagesMatch(_ source: String, _ target: String) -> Bool {
    let source = source.replacingOccurrences(of: "_", with: "-").lowercased()
    let target = target.replacingOccurrences(of: "_", with: "-").lowercased()
    if source == target { return true }

    let sourceParts = source.split(separator: "-")
    let targetParts = target.split(separator: "-")
    guard sourceParts.first == targetParts.first else { return false }

    // A Chinese script conversion is still a translation request. For other
    // languages, regional variants share the same source language.
    if sourceParts.first == "zh" {
        let sourceScript = sourceParts.first { $0 == "hans" || $0 == "hant" }
        let targetScript = targetParts.first { $0 == "hans" || $0 == "hant" }
        return sourceScript == targetScript || sourceScript == nil || targetScript == nil
    }
    return true
}
