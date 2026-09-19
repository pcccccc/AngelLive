import Foundation
import Observation

/// Associates work started by the support flow with plugin and HTTP diagnostics.
public enum SupportDiagnosticContext {
    @TaskLocal public static var operationID: UUID?
}

public enum SupportDiagnosticAction: String, Codable, Sendable, CaseIterable {
    case openedHome
    case openedPlatform
    case openedFavorites
    case openedSearch
    case openedHistory
    case openedSettings
    case searched
    case openedRoom
    case closedRoom
    case playbackConfigured
    case retriedPlayback
    case selectedQuality
    case selectedLine
    case enteredBackground
    case returnedForeground
    case openedPluginManagement
    case openedAccountManagement

    public var title: String {
        switch self {
        case .openedHome: "打开首页"
        case .openedPlatform: "打开平台"
        case .openedFavorites: "打开收藏"
        case .openedSearch: "打开搜索"
        case .openedHistory: "打开历史记录"
        case .openedSettings: "打开设置"
        case .searched: "搜索"
        case .openedRoom: "打开直播间"
        case .closedRoom: "离开直播间"
        case .playbackConfigured: "配置播放线路与清晰度"
        case .retriedPlayback: "重试播放"
        case .selectedQuality: "选择清晰度"
        case .selectedLine: "选择线路"
        case .enteredBackground: "进入后台"
        case .returnedForeground: "返回前台"
        case .openedPluginManagement: "打开插件管理"
        case .openedAccountManagement: "打开账号管理"
        }
    }
}

public struct SupportDiagnosticActionRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let action: SupportDiagnosticAction
    public let timestamp: Date
    public let context: [String: String]
    public let operationID: UUID
}

public struct SupportDiagnosticHTTPRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: String?
    public let bodyKind: String?
    public let bodyByteCount: Int?
    public let bodyWasTruncated: Bool
    public let statusCode: Int?
    public let responseHeaders: [String: String]?
    public var responseBody: String?
    public let responseBodyKind: String?
    public let responseBodyByteCount: Int?
    public var responseBodyWasTruncated: Bool
    public let error: String?
    public let duration: TimeInterval?
    public let association: String
    public let candidateEntryIDs: [UUID]
    public let omittedRequestHeaderCount: Int
    public let omittedResponseHeaderCount: Int
    public let omittedCandidateEntryIDCount: Int
}

public struct SupportDiagnosticException: Codable, Sendable {
    public let name: String?
    public let message: String
    public let stack: String?
    public let sourceURL: String?
    public let line: Int?
    public let column: Int?
}

public struct SupportDiagnosticPluginEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let pluginID: String
    public let pluginVersion: String?
    public let method: String
    public let timestamp: Date
    public let status: String
    public let duration: TimeInterval?
    public let requestBody: String?
    public var responseBody: String?
    public let errorMessage: String?
    public let exception: SupportDiagnosticException?
    public let operationID: UUID?
    public var httpRecords: [SupportDiagnosticHTTPRecord]
    public var omittedHTTPRecordCount: Int
    /// Absent in schema 1 reports; their mixed log source cannot be reconstructed reliably.
    public var kind: PluginConsoleEntryKind? = nil
}

public struct SupportDiagnosticFailureSummary: Codable, Sendable {
    public let title: String
    public let message: String
    public let detail: String?
}

public struct SupportDiagnosticReport: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let sessionID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let appVersion: String
    public let build: String
    public let operatingSystem: String
    public let hostPlatform: String
    public var userDescription: String?
    public let actions: [SupportDiagnosticActionRecord]
    public var entries: [SupportDiagnosticPluginEntry]
    public let failure: SupportDiagnosticFailureSummary?
    /// Explicitly lists unavailable or bounded data so a missing record is not mistaken for success.
    public var limitations: [String]
    /// Captured when recording starts. Older reports did not collect this information.
    public var environment: [String: String]? = nil
}

/// Best-effort redaction for support artifacts. It deliberately preserves useful error codes and
/// messages, but callers must omit values from runtime APIs that are known to be sensitive.
public enum SupportDiagnosticSanitizer {
    public static let maximumBodyBytes = 1_048_576
    private static let sensitiveKeyPattern =
        #"(?i)(authorization|proxy-authorization|cookie|set-cookie|token|jwt|password|passwd|secret|session|csrf|api[_-]?key|credential|signature|(?:^|[_-])(?:auth|sign|sig)(?:$|[_-]))"#

    public static func text(_ value: String, limit: Int = 16_384) -> String {
        let jsonSanitized = SupportDiagnosticBodyRedactor.redact(
            value,
            isSensitiveKey: isSensitiveKey,
            sanitizeString: { redactCredentials(in: sanitizeEmbeddedURLs($0)) }
        )
        let urlSanitized = sanitizeEmbeddedURLs(jsonSanitized)
        let credentialSanitized = redactCredentials(in: urlSanitized)
        return truncate(credentialSanitized, limit: limit)
    }

    public static func headers(_ values: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { key, value in
            (key, isSensitiveKey(key) ? "<redacted>" : text(value))
        })
    }

    public static func url(_ value: String) -> String {
        // Preserve query order, percent encoding and all ordinary reproduction inputs.
        // URLComponents.string would normalize the original request spelling.
        let withoutUserInfo = redactMalformedUserInfo(value)
        let parts = withoutUserInfo.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let fragment = parts.count == 2 ? "#" + redactURLParameters(parts[1]) : ""
        guard let base = parts.first else { return withoutUserInfo }
        guard let queryIndex = base.firstIndex(of: "?") else { return String(base) + fragment }
        return String(base[...queryIndex]) + redactURLParameters(base[base.index(after: queryIndex)...]) + fragment
    }

    private static func redactURLParameters(_ value: Substring) -> String {
        value.split(separator: "&", omittingEmptySubsequences: false).map { component -> String in
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            return isSensitiveKey(key.removingPercentEncoding ?? key) ? "\(key)=<redacted>" : String(component)
        }.joined(separator: "&")
    }

    public static func body(_ value: String, limit: Int = maximumBodyBytes) -> String {
        text(value, limit: limit)
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        key.range(of: sensitiveKeyPattern, options: .regularExpression) != nil
    }

    private static func sanitizeEmbeddedURLs(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s\"'<>]+"#, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        let matches = expression.matches(in: value, range: range).reversed()
        var result = value
        for match in matches {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: url(String(result[swiftRange])))
        }
        return result
    }

    private static func redactCredentials(in value: String) -> String {
        let patterns = [
            (#"(?im)^\s*((?:proxy-)?authorization|set-cookie|cookie)\s*:\s*[^\r\n]*"#, "$1: <redacted>"),
            (#"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#, "$1 <redacted>"),
            (#"(?i)\b((?:authorization|cookie|token|jwt|password|passwd|secret|session|csrf|api[_-]?key|credential))\s*([:=])\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;&\"'<>}\]]+)"#, "$1$2<redacted>")
        ]
        return patterns.reduce(value) { result, item in
            guard let expression = try? NSRegularExpression(pattern: item.0) else { return result }
            return expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: item.1
            )
        }
    }

    private static func redactMalformedUserInfo(_ base: String) -> String {
        guard let schemeRange = base.range(of: "://") else { return base }
        let authorityStart = schemeRange.upperBound
        let authorityEnd = base[authorityStart...].firstIndex(where: { "/?#".contains($0) }) ?? base.endIndex
        guard let at = base[authorityStart..<authorityEnd].lastIndex(of: "@") else { return base }
        return String(base[..<authorityStart]) + String(base[base.index(after: at)...])
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        let byteLimit = max(0, limit)
        let bytes = value.lengthOfBytes(using: .utf8)
        guard bytes > byteLimit else { return value }

        let marker = "[已截断；脱敏后原始内容 \(bytes) 字节]"
        let prefixLimit = max(0, byteLimit - marker.lengthOfBytes(using: .utf8))
        var prefix = ""
        var prefixBytes = 0
        for character in value {
            let characterBytes = String(character).lengthOfBytes(using: .utf8)
            guard prefixBytes + characterBytes <= prefixLimit else { break }
            prefix.append(character)
            prefixBytes += characterBytes
        }
        return prefix + marker
    }
}

@MainActor
@Observable
public final class SupportDiagnosticsService {
    public static let shared = SupportDiagnosticsService()

    public private(set) var isRecording = false
    public private(set) var startedAt: Date?
    public private(set) var lastReport: SupportDiagnosticReport?
    public private(set) var errorMessage: String?

    private static let maximumActions = 200
    private static let maximumEntries = 280
    private static let maximumReportBytes = 16 * 1_024 * 1_024
    private static let reportLimitHeadroom = 1_024

    private let storageDirectory: URL
    private let entriesProvider: @MainActor @Sendable () -> [PluginConsoleEntry]
    private let sessionSetter: @MainActor @Sendable (UUID?) -> Void
    private let omissionSummaryProvider: @MainActor @Sendable (UUID) -> PluginConsoleOmissionSummary
    private let automaticStopDelayNanoseconds: UInt64
    private var activeSessionID: UUID?
    private var actions: [SupportDiagnosticActionRecord] = []
    private var droppedActionCount = 0
    private var pendingFailure: SupportDiagnosticFailureSummary?
    private var automaticStopTask: Task<Void, Never>?
    private var recordingEnvironment: [String: String]?

    init(
        storageDirectory: URL? = nil,
        entriesProvider: @escaping @MainActor @Sendable () -> [PluginConsoleEntry] = { PluginConsoleService.shared.diagnosticEntries },
        sessionSetter: @escaping @MainActor @Sendable (UUID?) -> Void = { PluginConsoleService.shared.setDiagnosticSessionID($0) },
        omissionSummaryProvider: @escaping @MainActor @Sendable (UUID) -> PluginConsoleOmissionSummary = { PluginConsoleService.shared.omissionSummary(sessionID: $0) },
        automaticStopDelayNanoseconds: UInt64 = 300_000_000_000
    ) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory()
        self.entriesProvider = entriesProvider
        self.sessionSetter = sessionSetter
        self.omissionSummaryProvider = omissionSummaryProvider
        self.automaticStopDelayNanoseconds = automaticStopDelayNanoseconds
        restoreLastReport()
    }

    public func startRecording() {
        guard !isRecording else { return }
        do {
            try prepareStorage()
        } catch {
            errorMessage = "无法准备诊断缓存：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        isRecording = true
        startedAt = Date()
        recordingEnvironment = SupportDiagnosticEnvironment.snapshot()
        actions.removeAll(keepingCapacity: true)
        droppedActionCount = 0
        pendingFailure = nil
        errorMessage = nil
        sessionSetter(sessionID)
        automaticStopTask?.cancel()
        let delay = automaticStopDelayNanoseconds
        automaticStopTask = Task { @MainActor [weak self, delay] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.stopRecording(sessionID: sessionID)
        }
    }

    public func stopRecording() {
        guard let sessionID = activeSessionID else { return }
        stopRecording(sessionID: sessionID)
    }

    /// A delayed UI callback can retain this ID and will not stop a newer recording.
    public func stopRecording(sessionID: UUID) {
        guard sessionID == activeSessionID, let start = startedAt else { return }

        // Clear the runtime marker before taking the snapshot. Later callbacks cannot enter this report.
        sessionSetter(nil)
        let report = makeRecordingReport(sessionID: sessionID, startedAt: start, endedAt: Date())
        automaticStopTask?.cancel()
        automaticStopTask = nil
        activeSessionID = nil
        isRecording = false
        startedAt = nil
        actions.removeAll(keepingCapacity: true)
        droppedActionCount = 0
        pendingFailure = nil
        lastReport = boundedMemoryReport(from: report)
        recordingEnvironment = nil

        do {
            lastReport = try save(lastReport ?? report)
            try invalidateExport()
            errorMessage = nil
        } catch {
            errorMessage = "无法保存诊断报告：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
        }
    }

    public func discardReport() {
        lastReport = nil
        do {
            let fileURL = reportFileURL
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try invalidateExport()
            errorMessage = nil
        } catch {
            errorMessage = "无法删除诊断缓存：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
        }
    }

    @discardableResult
    public func recordAction(
        _ action: SupportDiagnosticAction,
        context: [String: String] = [:]
    ) -> UUID? {
        guard isRecording else { return nil }
        let operationID = SupportDiagnosticContext.operationID ?? UUID()
        guard actions.count < Self.maximumActions else {
            droppedActionCount += 1
            return operationID
        }
        var sanitizedContext: [String: String] = [:]
        for (key, value) in context {
            let sanitizedKey = SupportDiagnosticSanitizer.text(key, limit: 256)
            let headerValue = SupportDiagnosticSanitizer.headers([key: value])[key] ?? "<redacted>"
            sanitizedContext[sanitizedKey] = headerValue == "<redacted>"
                ? headerValue
                : SupportDiagnosticSanitizer.text(value, limit: 1_024)
        }
        actions.append(.init(
            id: UUID(),
            action: action,
            timestamp: Date(),
            context: sanitizedContext,
            operationID: operationID
        ))
        return operationID
    }

    public func updateDescription(_ description: String) {
        guard var report = lastReport else { return }
        report.userDescription = SupportDiagnosticSanitizer.text(description)
        lastReport = boundedMemoryReport(from: report)
        do {
            lastReport = try save(lastReport ?? report)
            try invalidateExport()
            errorMessage = nil
        } catch {
            errorMessage = "无法保存用户补充：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
        }
    }

    public func makeReportForError(title: String, message: String, detail: String?) {
        guard !isRecording else {
            pendingFailure = SupportDiagnosticFailureSummary(
                title: SupportDiagnosticSanitizer.text(title),
                message: SupportDiagnosticSanitizer.text(message),
                detail: detail.map { SupportDiagnosticSanitizer.text($0) }
            )
            errorMessage = "已记录当前错误；停止录制后会写入诊断报告。"
            return
        }

        let now = Date()
        let failure = SupportDiagnosticFailureSummary(
            title: SupportDiagnosticSanitizer.text(title),
            message: SupportDiagnosticSanitizer.text(message),
            detail: detail.map { SupportDiagnosticSanitizer.text($0) }
        )
        let report = SupportDiagnosticReport(
            schemaVersion: SupportDiagnosticReport.currentSchemaVersion,
            sessionID: UUID(),
            startedAt: now,
            endedAt: now,
            appVersion: Self.appVersion,
            build: Self.buildNumber,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            hostPlatform: Self.hostPlatform,
            userDescription: nil,
            actions: [],
            entries: [],
            failure: failure,
            limitations: Self.cacheLimitations(prefix: "此为当前错误快照；未启动录制，因此未采集插件调用、HTTP 请求或平台返回。"),
            environment: SupportDiagnosticEnvironment.snapshot()
        )
        lastReport = boundedMemoryReport(from: report)
        do {
            lastReport = try save(lastReport ?? report)
            try invalidateExport()
            errorMessage = nil
        } catch {
            errorMessage = "无法保存错误快照：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
        }
    }

    /// Writes a readable, sanitized text copy locally. The caller chooses whether to share the URL.
    public func exportReport() throws -> URL {
        guard lastReport != nil else {
            throw SupportDiagnosticsError.noReport
        }
        try prepareStorage()
        let outputURL = storageDirectory.appendingPathComponent("support-report.txt")
        try Data(reportText.utf8).write(to: outputURL, options: [.atomic])
        return outputURL
    }

    public var reportText: String {
        guard let report = lastReport else { return "暂无诊断报告。" }
        var lines = [
            "AngelLive 支持诊断报告",
            "架构版本：\(report.schemaVersion)",
            "会话：\(report.sessionID.uuidString)",
            "开始：\(Self.dateFormatter.string(from: report.startedAt))",
            "结束：\(Self.dateFormatter.string(from: report.endedAt))",
            "应用版本：\(report.appVersion) (\(report.build))",
            "系统：\(report.hostPlatform) · \(report.operatingSystem)"
        ]
        lines += SupportDiagnosticReportSummary.lines(for: report)
        if report.entries.isEmpty {
            lines += ["", "调用详情", "未记录插件调用或 HTTP 请求。"]
        } else {
            let groups: [(String, [SupportDiagnosticPluginEntry])] = [
                ("业务调用与 HTTP 详情", report.entries.filter { $0.kind == nil || $0.kind == .invocation }),
                ("播放器日志（独立保留；不代表用户操作）", report.entries.filter { $0.kind == .playerLog }),
                ("弹幕帧与定时调用摘要", report.entries.filter { $0.kind == .highFrequency })
            ]
            for (title, entries) in groups where !entries.isEmpty {
                lines += ["", title]
                for entry in entries {
                    lines.append("[\(Self.dateFormatter.string(from: entry.timestamp))] 来源=\(entry.pluginID)\(entry.pluginVersion.map { " version=\($0)" } ?? "") method=\(entry.method) 结果=\(SupportDiagnosticReportSummary.status(entry)) id=\(entry.id.uuidString)\(entry.operationID.map { " operation=\($0.uuidString)" } ?? "")\(entry.duration.map { " duration=\(Self.durationText($0))" } ?? "")")
                    if let request = entry.requestBody {
                        lines.append(entry.kind == .playerLog ? "  日志位置：\(request)" : "  插件调用参数（凭证已脱敏）：\n\(request)")
                    }
                    if let response = entry.responseBody {
                        lines.append(entry.kind == .playerLog ? "  日志内容：\(response)" : "  插件返回（凭证已脱敏）：\n\(response)")
                    }
                    if let error = entry.errorMessage { lines.append("  错误：\(error)") }
                    if let exception = entry.exception {
                        lines.append("  JS 异常：\(exception.name.map { "\($0): " } ?? "")\(exception.message)")
                        if let stack = exception.stack { lines.append("  JS 堆栈：\(stack)") }
                        if let sourceURL = exception.sourceURL {
                            lines.append("  JS 来源：\(sourceURL)\(exception.line.map { ":\($0)" } ?? "")\(exception.column.map { ":\($0)" } ?? "")")
                        }
                    }
                    for request in entry.httpRecords {
                        lines.append("  [\(Self.dateFormatter.string(from: request.startedAt))] HTTP \(request.method) \(request.url) id=\(request.id.uuidString) association=\(request.association)\(request.statusCode.map { " status=\($0)" } ?? "")\(request.duration.map { " duration=\(Self.durationText($0))" } ?? "")")
                        if !request.headers.isEmpty { lines.append("    请求头：\(Self.formatHeaders(request.headers))") }
                        if let body = request.body { lines.append("    HTTP 请求正文\(Self.bodyNote(kind: request.bodyKind, byteCount: request.bodyByteCount, wasTruncated: request.bodyWasTruncated))：\n\(body)\n    [HTTP 请求正文结束]") }
                        else if request.bodyKind == PluginConsoleBodyKind.omittedSensitive.rawValue { lines.append("    请求体：已因敏感运行时数据省略\(Self.bodyNote(kind: request.bodyKind, byteCount: request.bodyByteCount, wasTruncated: request.bodyWasTruncated))") }
                        if let headers = request.responseHeaders { lines.append("    响应头：\(Self.formatHeaders(headers))") }
                        if let body = request.responseBody { lines.append("    HTTP 响应正文\(Self.bodyNote(kind: request.responseBodyKind, byteCount: request.responseBodyByteCount, wasTruncated: request.responseBodyWasTruncated))：\n\(body)\n    [HTTP 响应正文结束]") }
                        else if request.responseBodyKind == PluginConsoleBodyKind.omittedSensitive.rawValue { lines.append("    响应体：已因敏感运行时数据省略\(Self.bodyNote(kind: request.responseBodyKind, byteCount: request.responseBodyByteCount, wasTruncated: request.responseBodyWasTruncated))") }
                        if let error = request.error { lines.append("    请求错误：\(error)") }
                        if !request.candidateEntryIDs.isEmpty { lines.append("    候选调用：\(request.candidateEntryIDs.map(\.uuidString).joined(separator: ", "))") }
                        if request.omittedRequestHeaderCount > 0 { lines.append("    另有 \(request.omittedRequestHeaderCount) 个请求头未保留。") }
                        if request.omittedResponseHeaderCount > 0 { lines.append("    另有 \(request.omittedResponseHeaderCount) 个响应头未保留。") }
                        if request.omittedCandidateEntryIDCount > 0 { lines.append("    另有 \(request.omittedCandidateEntryIDCount) 个候选调用 ID 未保留。") }
                    }
                    if entry.omittedHTTPRecordCount > 0 { lines.append("  另有 \(entry.omittedHTTPRecordCount) 条 HTTP 记录因数量限制未保留。") }
                }
            }
        }
        return SupportDiagnosticSanitizer.text(lines.joined(separator: "\n"), limit: Self.maximumReportBytes)
    }

    private func makeRecordingReport(sessionID: UUID, startedAt: Date, endedAt: Date) -> SupportDiagnosticReport {
        let matchingEntries = entriesProvider()
            .filter { $0.diagnosticSessionID == sessionID }
            .sorted { $0.timestamp < $1.timestamp }
        let retainedEntries = Array(matchingEntries.suffix(Self.maximumEntries)).map(Self.sanitize)
        var limitations: [String] = []
        if matchingEntries.count > retainedEntries.count {
            limitations.append("插件调用最多保留 \(Self.maximumEntries) 条；另有 \(matchingEntries.count - retainedEntries.count) 条较早调用未写入报告。")
        }
        if droppedActionCount > 0 {
            limitations.append("业务操作最多保留 \(Self.maximumActions) 条；另有 \(droppedActionCount) 条未写入报告。")
        }
        if retainedEntries.isEmpty {
            limitations.append("本次录制未采集到插件调用或 HTTP 请求；这不表示平台返回成功。")
        }
        let omissionSummary = omissionSummaryProvider(sessionID)
        if omissionSummary.entryCount > 0 {
            limitations.append("业务调用最多保留 200 条，优先保留错误和录制起点；另有 \(omissionSummary.entryCount) 条调用未保留。")
        }
        if omissionSummary.httpRecordCount > 0 {
            limitations.append("本次录制最多保留 200 条 HTTP 记录；另有 \(omissionSummary.httpRecordCount) 条较早请求未保留。")
        }
        if omissionSummary.unassignedHTTPRecordCount > 0 {
            limitations.append("另有 \(omissionSummary.unassignedHTTPRecordCount) 条 HTTP 因跨录制归属不确定而未纳入报告。")
        }
        if omissionSummary.playerLogEntryCount > 0 {
            limitations.append("播放器日志独立保留最多 50 条；另有 \(omissionSummary.playerLogEntryCount) 条未保留，不占用业务调用名额。")
        }
        if omissionSummary.highFrequencyEntryCount > 0 {
            limitations.append("弹幕帧与定时调用独立保留最多 30 条摘要；另有 \(omissionSummary.highFrequencyEntryCount) 条未保留，不占用业务调用名额。")
        }
        if omissionSummary.bodyTruncationCount > 0 {
            limitations.append("录制缓冲的正文总量最多 32 MiB；运行中发生 \(omissionSummary.bodyTruncationCount) 次正文缩短或随记录省略，减少 \(omissionSummary.bodyOmittedByteCount) 字节占用。保留的截断正文带有明确标记。")
        }
        limitations.append("弹幕帧仅保留类型、大小和数量摘要；停止录制时尚未返回的调用标为未完成，后续响应不写入报告。")
        limitations = Self.cacheLimitations(prefix: nil, existing: limitations)
        return SupportDiagnosticReport(
            schemaVersion: SupportDiagnosticReport.currentSchemaVersion,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            appVersion: Self.appVersion,
            build: Self.buildNumber,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            hostPlatform: Self.hostPlatform,
            userDescription: nil,
            actions: actions,
            entries: retainedEntries,
            failure: pendingFailure,
            limitations: limitations,
            environment: recordingEnvironment
        )
    }

    private static func sanitize(_ entry: PluginConsoleEntry) -> SupportDiagnosticPluginEntry {
        SupportDiagnosticPluginEntry(
            id: entry.id,
            pluginID: SupportDiagnosticSanitizer.text(entry.tag),
            pluginVersion: entry.pluginVersion.map { SupportDiagnosticSanitizer.text($0) },
            method: SupportDiagnosticSanitizer.text(entry.method),
            timestamp: entry.timestamp,
            status: statusText(entry.status),
            duration: entry.duration,
            requestBody: entry.requestBody.map { SupportDiagnosticSanitizer.body($0) },
            responseBody: entry.responseBody.map { SupportDiagnosticSanitizer.body($0) },
            errorMessage: entry.errorMessage.map { SupportDiagnosticSanitizer.text($0) },
            exception: entry.exception.map(sanitize),
            operationID: entry.operationID,
            httpRecords: entry.httpRecords.map(sanitize),
            omittedHTTPRecordCount: entry.omittedHTTPRecordCount,
            kind: entry.kind
        )
    }

    private static func sanitize(_ record: PluginConsoleHTTPRecord) -> SupportDiagnosticHTTPRecord {
        SupportDiagnosticHTTPRecord(
            id: record.id,
            startedAt: record.startedAt,
            url: SupportDiagnosticSanitizer.url(record.url),
            method: SupportDiagnosticSanitizer.text(record.method),
            headers: SupportDiagnosticSanitizer.headers(record.headers),
            body: record.body.map { SupportDiagnosticSanitizer.body($0) },
            bodyKind: record.bodyKind?.rawValue,
            bodyByteCount: record.bodyByteCount,
            bodyWasTruncated: record.bodyWasTruncated,
            statusCode: record.statusCode,
            responseHeaders: record.responseHeaders.map(SupportDiagnosticSanitizer.headers),
            responseBody: record.responseBody.map { SupportDiagnosticSanitizer.body($0) },
            responseBodyKind: record.responseBodyKind?.rawValue,
            responseBodyByteCount: record.responseBodyByteCount,
            responseBodyWasTruncated: record.responseBodyWasTruncated,
            error: record.error.map { SupportDiagnosticSanitizer.text($0) },
            duration: record.duration,
            association: record.association.rawValue,
            candidateEntryIDs: record.candidateEntryIDs,
            omittedRequestHeaderCount: record.omittedRequestHeaderCount,
            omittedResponseHeaderCount: record.omittedResponseHeaderCount,
            omittedCandidateEntryIDCount: record.omittedCandidateEntryIDCount
        )
    }

    private static func sanitize(_ exception: LiveParseJSExceptionSnapshot) -> SupportDiagnosticException {
        SupportDiagnosticException(
            name: exception.name.map { SupportDiagnosticSanitizer.text($0, limit: 256) },
            message: SupportDiagnosticSanitizer.text(exception.message),
            stack: exception.stack.map { SupportDiagnosticSanitizer.text($0) },
            sourceURL: exception.sourceURL.map { SupportDiagnosticSanitizer.url($0) },
            line: exception.line,
            column: exception.column
        )
    }

    private static func statusText(_ status: PluginConsoleEntryStatus) -> String {
        switch status {
        case .loading: "loading"
        case .success: "success"
        case .error: "error"
        }
    }

    private var reportFileURL: URL { storageDirectory.appendingPathComponent("latest.json") }

    private func prepareStorage() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    private func restoreLastReport() {
        let fileURL = reportFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            lastReport = try JSONDecoder().decode(SupportDiagnosticReport.self, from: Data(contentsOf: fileURL))
        } catch {
            errorMessage = "无法恢复上次诊断报告：\(SupportDiagnosticSanitizer.text(error.localizedDescription))"
        }
    }

    private func boundedMemoryReport(from report: SupportDiagnosticReport) -> SupportDiagnosticReport {
        (try? boundedReport(report)) ?? report
    }

    private func save(_ report: SupportDiagnosticReport) throws -> SupportDiagnosticReport {
        let bounded = try boundedReport(report)
        try prepareStorage()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(bounded).write(to: reportFileURL, options: [.atomic])
        return bounded
    }

    private func boundedReport(_ report: SupportDiagnosticReport) throws -> SupportDiagnosticReport {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bounded = report
        var droppedEntries = 0
        var trimmedBodyCount = 0
        while true {
            let data = try encoder.encode(bounded)
            guard data.count > Self.maximumReportBytes - Self.reportLimitHeadroom else { break }

            // Keep invocation inputs, response identity/status and the recording's beginning.
            // Only at the total cap shorten the largest response, with an inline byte-count marker.
            if let location = largestResponse(in: bounded), location.bytes > 4_096 {
                if let httpIndex = location.httpIndex,
                   let body = bounded.entries[location.entryIndex].httpRecords[httpIndex].responseBody {
                    bounded.entries[location.entryIndex].httpRecords[httpIndex].responseBody =
                        SupportDiagnosticSanitizer.body(body, limit: 4_096)
                    bounded.entries[location.entryIndex].httpRecords[httpIndex].responseBodyWasTruncated = true
                } else if let body = bounded.entries[location.entryIndex].responseBody {
                    bounded.entries[location.entryIndex].responseBody = SupportDiagnosticSanitizer.body(body, limit: 4_096)
                }
                trimmedBodyCount += 1
            } else if !bounded.entries.isEmpty {
                let firstBusinessID = bounded.entries.first { $0.kind == nil || $0.kind == .invocation }?.id
                let index = bounded.entries.firstIndex { $0.kind == .playerLog || $0.kind == .highFrequency }
                    ?? bounded.entries.firstIndex { $0.id != firstBusinessID && !SupportDiagnosticReportSummary.hasFailure($0) }
                    ?? (bounded.entries.count > 1 ? 1 : 0)
                bounded.entries.remove(at: index)
                droppedEntries += 1
            } else {
                throw SupportDiagnosticsError.reportTooLarge
            }
        }
        if trimmedBodyCount > 0 {
            bounded.limitations.append("报告总量达到 \(Self.maximumReportBytes) 字节上限；\(trimmedBodyCount) 段响应正文已缩短，正文内标明原始字节数与截断。调用参数、状态和关联仍保留。")
        }
        if droppedEntries > 0 {
            bounded.limitations.append("报告 JSON 总量上限为 \(Self.maximumReportBytes) 字节；另有 \(droppedEntries) 条记录未持久化。优先保留业务起点和失败记录。")
        }
        guard try encoder.encode(bounded).count <= Self.maximumReportBytes else {
            throw SupportDiagnosticsError.reportTooLarge
        }
        return bounded
    }

    private func largestResponse(in report: SupportDiagnosticReport) -> (entryIndex: Int, httpIndex: Int?, bytes: Int)? {
        var largest: (entryIndex: Int, httpIndex: Int?, bytes: Int)?
        for (entryIndex, entry) in report.entries.enumerated() {
            let bytes = entry.responseBody?.utf8.count ?? 0
            if bytes > (largest?.bytes ?? 0) { largest = (entryIndex, nil, bytes) }
            for (httpIndex, record) in entry.httpRecords.enumerated() {
                let bytes = record.responseBody?.utf8.count ?? 0
                if bytes > (largest?.bytes ?? 0) { largest = (entryIndex, httpIndex, bytes) }
            }
        }
        return largest
    }

    private func invalidateExport() throws {
        let exportURL = storageDirectory.appendingPathComponent("support-report.txt")
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
    }

    private static func defaultStorageDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SupportDiagnostics", isDirectory: true)
    }

    private static func cacheLimitations(prefix: String?, existing: [String] = []) -> [String] {
        var limitations = existing
        if let prefix { limitations.insert(prefix, at: 0) }
        #if os(tvOS)
        limitations.append("tvOS 的诊断报告保存在系统可清理的缓存中；系统清理后可能无法在下次启动时恢复。")
        #endif
        return limitations
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "未知"
    }

    private static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "未知"
    }

    private static var hostPlatform: String {
        #if os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(macOS)
        "macOS"
        #else
        "未知"
        #endif
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func formatHeaders(_ headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.3fs", duration)
    }

    private static func bodyNote(kind: String?, byteCount: Int?, wasTruncated: Bool) -> String {
        var notes: [String] = []
        if wasTruncated { notes.append("已截断") }
        if let byteCount { notes.append("原始 \(byteCount) 字节") }
        if kind == PluginConsoleBodyKind.binary.rawValue { notes.append("二进制内容") }
        return notes.isEmpty ? "" : " [\(notes.joined(separator: "；"))]"
    }
}

public enum SupportDiagnosticsError: LocalizedError {
    case noReport
    case reportTooLarge

    public var errorDescription: String? {
        switch self {
        case .noReport: "暂无可导出的诊断报告。"
        case .reportTooLarge: "诊断报告超过安全的本地缓存上限。"
        }
    }
}
