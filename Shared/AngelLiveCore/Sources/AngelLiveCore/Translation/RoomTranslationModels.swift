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
        }
    }
}

struct RoomTranslationRequest: Sendable {
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
    let baseURL: URL?
    let model: String?
    let apiKey: String?
}

protocol RoomTranslationProvider: Sendable {
    func translate(_ request: RoomTranslationRequest) async throws -> String
}

protocol RoomTranslationRetrying: Sendable {
    func prepareForExplicitRetry() async
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
