import Foundation
import Testing
@testable import AngelLiveCore

// MARK: - semverCompare Tests

@Suite("semverCompare")
struct SemverCompareTests {
    @Test("version components compare by normalized sign", arguments: [
        ("1.0.0", "1.0.0", 0),
        ("0.0.0", "0.0.0", 0),
        ("12.34.56", "12.34.56", 0),
        ("2.0.0", "1.0.0", 1),
        ("1.0.0", "2.0.0", -1),
        ("1.2.0", "1.1.0", 1),
        ("1.1.0", "1.2.0", -1),
        ("1.0.2", "1.0.1", 1),
        ("1.0.1", "1.0.2", -1),
        ("1", "1.0.0", 0),
        ("1.2", "1.2.0", 0),
        ("2", "1.9.9", 1),
        ("1.0.0", "1.0.abc", 0),
        ("abc.0.0", "0.0.0", 0),
        ("", "", 0),
        ("0.0.1", "", 1)
    ])
    func comparison(lhs: String, rhs: String, expectedSign: Int) {
        #expect(semverCompare(lhs, rhs).signum() == expectedSign)
    }
}

// MARK: - PlatformCapability Cache Tests

@Suite("PlatformCapability cache")
struct PlatformCapabilityCacheTests {

    @Test("invalidateCache can be called multiple times")
    func invalidateMultiple() {
        PlatformCapability.invalidateCache()
        PlatformCapability.invalidateCache()
        PlatformCapability.invalidateCache()
    }
}

// MARK: - Logger Tests

@Suite("Logger")
struct LoggerTests {

    @Test("LogLevel ordering")
    func levelOrdering() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.warning)
        #expect(LogLevel.warning < LogLevel.error)
    }
}

// MARK: - Plugin Index Error Tests

@Suite("Plugin index errors")
struct PluginIndexErrorTests {

    @Test("non-JSON responses include response diagnostics")
    func nonJSONResponseDescription() {
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: "https://example.com/plugins.json")!,
            statusCode: 200,
            contentType: "text/html",
            bodyPreview: "<html>blocked</html>"
        )

        let description = PluginSourceManager.detailedErrorDescription(
            LiveParsePluginIndexFetchError.nonJSONResponse(diagnostics)
        )

        #expect(description.contains("返回的不是 JSON"))
        #expect(description.contains("https://example.com/plugins.json"))
        #expect(description.contains("HTTP 200"))
        #expect(description.contains("text/html"))
        #expect(description.contains("<html>blocked</html>"))
    }

    @Test("wrapped decoding errors keep coding path and response diagnostics")
    func wrappedDecodingErrorDescription() {
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: "https://example.com/plugins.json")!,
            statusCode: 200,
            contentType: "application/json",
            bodyPreview: "{\"apiVersion\":\"1\"}"
        )
        let context = DecodingError.Context(
            codingPath: [AnyCodingKey(stringValue: "apiVersion")!],
            debugDescription: "Expected to decode Int but found a string instead."
        )

        let description = PluginSourceManager.detailedErrorDescription(
            LiveParsePluginIndexFetchError.decodingFailed(
                diagnostics,
                .typeMismatch(Int.self, context)
            )
        )

        #expect(description.contains("类型不匹配"))
        #expect(description.contains("apiVersion"))
        #expect(description.contains("application/json"))
        #expect(description.contains("{\"apiVersion\":\"1\"}"))
    }
}

@Suite("Plugin error card parsing")
struct PluginErrorCardParsingTests {

    @Test("structured plugin error message exposes summary and diagnostics")
    func structuredMessageParsing() {
        let message = "拉取插件索引失败: 返回的不是 JSON。URL https://example.com/plugins.json, HTTP 200, Content-Type text/html, 响应片段 <html>blocked</html>"
        let parsed = ParsedPluginSourceErrorMessage(message: message)

        #expect(parsed.summary == "拉取插件索引失败: 返回的不是 JSON")
        #expect(parsed.details.map(\.label) == ["URL", "HTTP", "Content-Type", "响应片段"])
        #expect(parsed.details[0].value == "https://example.com/plugins.json")
        #expect(parsed.details[1].value == "200")
        #expect(parsed.details[2].value == "text/html")
        #expect(parsed.details[3].value == "<html>blocked</html>")
        #expect(parsed.details[0].isURL)
        #expect(parsed.details[3].isResponsePreview)
    }

    @Test("plain plugin error message remains a single summary")
    func plainMessageParsing() {
        let message = "拉取插件索引失败: 请求超时"
        let parsed = ParsedPluginSourceErrorMessage(message: message)

        #expect(parsed.summary == message)
        #expect(parsed.details.isEmpty)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
