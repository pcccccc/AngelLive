import Foundation

/// JavaScriptCore 异常在其所属串行队列上提取后的值快照。
/// 不持有 JSValue，也不参与业务错误分类。
public struct LiveParseJSExceptionSnapshot: Codable, Sendable, Equatable {
    public let name: String?
    public let message: String
    public let stack: String?
    public let sourceURL: String?
    public let line: Int?
    public let column: Int?

    public init(
        name: String?,
        message: String,
        stack: String?,
        sourceURL: String?,
        line: Int?,
        column: Int?
    ) {
        self.name = name.map { SupportDiagnosticSanitizer.text($0, limit: 256) }
        self.message = SupportDiagnosticSanitizer.text(message)
        self.stack = stack.map { SupportDiagnosticSanitizer.text($0) }
        self.sourceURL = sourceURL.map { SupportDiagnosticSanitizer.url($0) }
        self.line = line
        self.column = column
    }
}

public enum LiveParsePluginStandardErrorCode: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case invalidArgs = "INVALID_ARGS"
    case authRequired = "AUTH_REQUIRED"
    case notFound = "NOT_FOUND"
    /// 主播未开播 / 已下播 / 暂无播放地址，宿主显示已下播状态而不是错误页。
    case notLive = "NOT_LIVE"
    case blocked = "BLOCKED"
    case rateLimited = "RATE_LIMITED"
    case network = "NETWORK"
    case timeout = "TIMEOUT"
    case unsupported = "UNSUPPORTED"
    case parse = "PARSE"
    case invalidResponse = "INVALID_RESPONSE"
    case upstream = "UPSTREAM"
}

public extension LiveParsePluginStandardErrorCode {
    /// 旧版插件使用过的 code 别名（错误协议 v1 迁移前的写法），新插件一律使用标准枚举值。
    static let legacyAliases: [String: LiveParsePluginStandardErrorCode] = [
        "REQUIRES_AUTH": .authRequired,
        "AUTH": .authRequired,
        "AUTH_FAILED": .authRequired,
        "INVALID_INPUT": .invalidArgs,
        "INVALID_STATE": .invalidArgs,
        "DECODE_FAILED": .parse,
        "OFFLINE": .notLive,
        "STREAM_UNAVAILABLE": .notLive,
        "406": .blocked,
        "UPSTREAM_RESTRICTED": .blocked,
        "REQUEST_FAILED": .network,
        "DEPRECATED": .unsupported,
        "SIGNING_FAILED": .unsupported,
        "SIGNING_UNAVAILABLE": .unsupported
    ]

    /// 解析插件上报的 code：先匹配标准值，再查旧别名，都不匹配时归为 `.unknown`。
    static func resolve(_ rawCode: String) -> LiveParsePluginStandardErrorCode {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = LiveParsePluginStandardErrorCode(rawValue: trimmed) {
            return code
        }
        return legacyAliases[trimmed.uppercased()] ?? .unknown
    }
}

public struct LiveParsePluginStandardError: Sendable, Codable, Equatable {
    public let code: LiveParsePluginStandardErrorCode
    public let message: String
    public let context: [String: String]

    public init(code: LiveParsePluginStandardErrorCode, message: String, context: [String: String] = [:]) {
        self.code = code
        self.message = message
        self.context = context
    }
}

public enum LiveParsePluginError: Error, LocalizedError, CustomStringConvertible, Sendable {
    case invalidManifest(String)
    case incompatibleAPIVersion(expected: Int, actual: Int)
    case missingEntryFile(String)
    case pluginNotFound(String)
    case jsException(String)
    case standardized(LiveParsePluginStandardError)
    case invalidReturnValue(String)
    case checksumMismatch(expected: String, actual: String)
    case zipSlipDetected(String)
    case installFailed(String)

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .invalidManifest(let reason):
            return "Invalid manifest: \(reason)"
        case .incompatibleAPIVersion(let expected, let actual):
            return "Incompatible apiVersion. Expected \(expected), got \(actual)."
        case .missingEntryFile(let name):
            return "Missing entry file: \(name)"
        case .pluginNotFound(let pluginId):
            return "Plugin not found: \(pluginId)"
        case .jsException(let message):
            return "JS exception: \(message)"
        case .standardized(let error):
            if error.context.isEmpty {
                return "JS plugin error [\(error.code.rawValue)]: \(error.message)"
            }
            return "JS plugin error [\(error.code.rawValue)]: \(error.message), context=\(error.context)"
        case .invalidReturnValue(let message):
            return "Invalid JS return value: \(message)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        case .zipSlipDetected(let path):
            return "Zip Slip detected for path: \(path)"
        case .installFailed(let reason):
            return "Install failed: \(reason)"
        }
    }
}

public extension LiveParsePluginError {
    static func fromJSException(_ rawMessage: String) -> LiveParsePluginError {
        let normalized = normalizeJSMessage(rawMessage)

        if let parsed = parseStandardizedErrorPayload(from: normalized) {
            return .standardized(parsed)
        }
        if let guessed = guessLegacyStandardizedError(from: normalized) {
            return .standardized(guessed)
        }
        return .jsException(normalized)
    }
}

private extension LiveParsePluginError {
    static var standardErrorMarker: String { "LP_PLUGIN_ERROR:" }

    static func normalizeJSMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Error: ") {
            return String(trimmed.dropFirst("Error: ".count))
        }
        return trimmed
    }

    static func parseStandardizedErrorPayload(from message: String) -> LiveParsePluginStandardError? {
        guard let markerRange = message.range(of: standardErrorMarker) else { return nil }
        let payloadText = String(message[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payloadText.isEmpty, let data = payloadText.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // 旧插件可能把 code 写成数字（如 406），统一转成字符串再解析。
        let rawCode = (object["code"] as? String) ?? (object["code"] as? NSNumber)?.stringValue ?? ""
        let codeText = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = LiveParsePluginStandardErrorCode.resolve(codeText)
        let payloadMessage = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var context: [String: String] = [:]

        if let contextObject = object["context"] as? [String: Any] {
            for (key, value) in contextObject {
                context[key] = String(describing: value)
            }
        }

        let normalizedMessage: String
        if let payloadMessage, !payloadMessage.isEmpty {
            normalizedMessage = payloadMessage
        } else {
            normalizedMessage = message
        }

        return LiveParsePluginStandardError(code: code, message: normalizedMessage, context: context)
    }

    static func guessLegacyStandardizedError(from message: String) -> LiveParsePluginStandardError? {
        let lower = message.lowercased()
        func make(_ code: LiveParsePluginStandardErrorCode) -> LiveParsePluginStandardError {
            LiveParsePluginStandardError(code: code, message: message)
        }

        if lower.contains("requires cookie") || (lower.contains("cookie") && lower.contains("require")) {
            return make(.authRequired)
        }
        if lower.contains("rate limit") || lower.contains("too many requests") {
            return make(.rateLimited)
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return make(.timeout)
        }
        if lower.contains("blocked") || lower.contains("verify_check") || lower.contains("captcha") {
            return make(.blocked)
        }
        if lower.contains("is required") || lower.contains("sharecode is empty") || lower.contains("roomid is empty") {
            return make(.invalidArgs)
        }
        if lower.contains("not found") || lower.contains("missing ") {
            return make(.notFound)
        }
        if lower.contains("parse") || lower.contains("json") || lower.contains("decode") {
            return make(.parse)
        }
        if lower.contains("invalid response") || lower.contains("network") || lower.contains("request failed") {
            return make(.network)
        }
        if lower.contains("api failed") || lower.contains("code invalid") || lower.contains("status_code") {
            return make(.upstream)
        }
        if lower.contains("invalid return value") {
            return make(.invalidResponse)
        }
        return nil
    }
}
