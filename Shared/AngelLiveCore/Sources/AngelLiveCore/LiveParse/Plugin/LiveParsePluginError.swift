import Foundation

public enum LiveParsePluginStandardErrorCode: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case invalidArgs = "INVALID_ARGS"
    case authRequired = "AUTH_REQUIRED"
    case notFound = "NOT_FOUND"
    case blocked = "BLOCKED"
    case rateLimited = "RATE_LIMITED"
    case network = "NETWORK"
    case timeout = "TIMEOUT"
    case parse = "PARSE"
    case invalidResponse = "INVALID_RESPONSE"
    case upstream = "UPSTREAM"
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

        let codeText = (object["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = LiveParsePluginStandardErrorCode(rawValue: codeText) ?? .unknown
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
