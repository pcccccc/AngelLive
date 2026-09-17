//
//  PluginConsoleService.swift
//  AngelLiveCore
//
//  Created by pangchong on 2026/4/2.
//

import Foundation
import Observation

// MARK: - HTTP 子请求记录

public enum PluginConsoleBodyKind: String, Codable, Sendable {
    case utf8
    case binary
    case omittedSensitive
}

public enum PluginConsoleHTTPAssociation: String, Codable, Sendable {
    /// Host.http 在插件函数的同步执行区间内触发，可严格绑定到该调用。
    case exact
    /// Host.http 在异步 reaction 中触发，只能确定一组仍在等待的候选调用。
    case uncertain
    /// Host.http 触发时没有可用的父调用上下文。
    case unassociated
}

public struct PluginConsoleHTTPRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: String?
    public let bodyKind: PluginConsoleBodyKind?
    public let bodyByteCount: Int?
    public let bodyWasTruncated: Bool
    public let statusCode: Int?
    public let responseHeaders: [String: String]?
    public let omittedRequestHeaderCount: Int
    public let omittedResponseHeaderCount: Int
    public let responseBody: String?
    public let responseBodyKind: PluginConsoleBodyKind?
    public let responseBodyByteCount: Int?
    public let responseBodyWasTruncated: Bool
    public let error: String?
    public let duration: TimeInterval?
    public let association: PluginConsoleHTTPAssociation
    public let candidateEntryIDs: [UUID]
    public let omittedCandidateEntryIDCount: Int

    public init(
        url: String,
        method: String,
        headers: [String: String],
        startedAt: Date = Date(),
        body: String? = nil,
        bodyKind: PluginConsoleBodyKind? = nil,
        bodyByteCount: Int? = nil,
        bodyWasTruncated: Bool = false,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: String? = nil,
        responseBodyKind: PluginConsoleBodyKind? = nil,
        responseBodyByteCount: Int? = nil,
        responseBodyWasTruncated: Bool = false,
        error: String? = nil,
        duration: TimeInterval? = nil,
        association: PluginConsoleHTTPAssociation = .unassociated,
        candidateEntryIDs: [UUID] = [],
        omittedCandidateEntryIDCount: Int = 0,
        sanitize: Bool = false
    ) {
        let requestHeaderSnapshot = Self.headerSnapshot(headers, sanitize: sanitize)
        let responseHeaderSnapshot = responseHeaders.map {
            Self.headerSnapshot($0, sanitize: sanitize)
        }
        self.id = UUID()
        self.startedAt = startedAt
        self.url = sanitize
            ? SupportDiagnosticSanitizer.text(
                SupportDiagnosticSanitizer.url(url),
                limit: 4_096
            )
            : url
        self.method = sanitize ? SupportDiagnosticSanitizer.text(method, limit: 128) : method
        self.headers = requestHeaderSnapshot.values
        self.body = sanitize ? body.map { SupportDiagnosticSanitizer.body($0) } : body
        self.bodyKind = bodyKind
        self.bodyByteCount = bodyByteCount
        self.bodyWasTruncated = bodyWasTruncated
        self.statusCode = statusCode
        self.responseHeaders = responseHeaderSnapshot?.values
        self.omittedRequestHeaderCount = requestHeaderSnapshot.omittedCount
        self.omittedResponseHeaderCount = responseHeaderSnapshot?.omittedCount ?? 0
        self.responseBody = sanitize
            ? responseBody.map { SupportDiagnosticSanitizer.body($0) }
            : responseBody
        self.responseBodyKind = responseBodyKind
        self.responseBodyByteCount = responseBodyByteCount
        self.responseBodyWasTruncated = responseBodyWasTruncated
        self.error = sanitize ? error.map { SupportDiagnosticSanitizer.text($0) } : error
        self.duration = duration
        self.association = association
        self.candidateEntryIDs = Array(candidateEntryIDs.prefix(64))
        self.omittedCandidateEntryIDCount = omittedCandidateEntryIDCount
            + max(0, candidateEntryIDs.count - 64)
    }

    private static func headerSnapshot(
        _ headers: [String: String],
        sanitize: Bool
    ) -> (values: [String: String], omittedCount: Int) {
        guard sanitize else { return (headers, 0) }
        let sanitized = SupportDiagnosticSanitizer.headers(headers)
        let retained = sanitized.keys.sorted().prefix(32)
        var values: [String: String] = [:]
        for key in retained {
            let boundedKey = SupportDiagnosticSanitizer.text(key, limit: 128)
            values[boundedKey] = SupportDiagnosticSanitizer.text(
                sanitized[key] ?? "",
                limit: 512
            )
        }
        return (values, max(0, sanitized.count - values.count))
    }
}

// MARK: - 日志条目

public enum PluginConsoleEntryStatus: String, Codable, Sendable {
    case loading
    case success
    case error
}

public struct PluginConsoleInvocationContext: Codable, Sendable {
    public let entryID: UUID
    public let pluginVersion: String?
    public let diagnosticSessionID: UUID?
    public let operationID: UUID?

    public init(
        entryID: UUID,
        pluginVersion: String?,
        diagnosticSessionID: UUID?,
        operationID: UUID?
    ) {
        self.entryID = entryID
        self.pluginVersion = pluginVersion
        self.diagnosticSessionID = diagnosticSessionID
        self.operationID = operationID
    }
}

public struct PluginConsoleHTTPContext: Codable, Sendable {
    public let parentEntryID: UUID?
    public let association: PluginConsoleHTTPAssociation
    public let candidateEntryIDs: [UUID]
    public let pluginVersion: String?
    public let diagnosticSessionID: UUID?
    public let operationID: UUID?
    public let omittedCandidateEntryIDCount: Int
    public let isDiagnosticCapture: Bool
    public let diagnosticSessionIDsForOmission: [UUID]

    public init(
        parentEntryID: UUID?,
        association: PluginConsoleHTTPAssociation,
        candidateEntryIDs: [UUID],
        pluginVersion: String?,
        diagnosticSessionID: UUID?,
        operationID: UUID?,
        omittedCandidateEntryIDCount: Int = 0,
        isDiagnosticCapture: Bool = false,
        diagnosticSessionIDsForOmission: [UUID] = []
    ) {
        self.parentEntryID = parentEntryID
        self.association = association
        self.candidateEntryIDs = candidateEntryIDs
        self.pluginVersion = pluginVersion
        self.diagnosticSessionID = diagnosticSessionID
        self.operationID = operationID
        self.omittedCandidateEntryIDCount = omittedCandidateEntryIDCount
        self.isDiagnosticCapture = isDiagnosticCapture
        self.diagnosticSessionIDsForOmission = diagnosticSessionIDsForOmission
    }
}

public struct PluginConsoleEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let tag: String       // 插件 ID
    public let method: String    // 调用方法名（如 getCategories）
    public let timestamp: Date
    public let pluginVersion: String?
    public let diagnosticSessionID: UUID?
    public let operationID: UUID?
    public var status: PluginConsoleEntryStatus
    public var duration: TimeInterval?
    public var requestBody: String?
    public var responseBody: String?
    public var errorMessage: String?
    public var exception: LiveParseJSExceptionSnapshot?
    public var httpRecords: [PluginConsoleHTTPRecord]
    public var omittedHTTPRecordCount: Int

    public init(
        tag: String,
        method: String,
        status: PluginConsoleEntryStatus = .loading,
        timestamp: Date = Date(),
        pluginVersion: String? = nil,
        diagnosticSessionID: UUID? = nil,
        operationID: UUID? = nil
    ) {
        self.id = UUID()
        let sanitize = diagnosticSessionID != nil
        self.tag = sanitize ? SupportDiagnosticSanitizer.text(tag, limit: 256) : tag
        self.method = sanitize ? SupportDiagnosticSanitizer.text(method, limit: 256) : method
        self.timestamp = timestamp
        self.pluginVersion = sanitize
            ? pluginVersion.map { SupportDiagnosticSanitizer.text($0, limit: 128) }
            : pluginVersion
        self.diagnosticSessionID = diagnosticSessionID
        self.operationID = operationID
        self.status = status
        self.httpRecords = []
        self.omittedHTTPRecordCount = 0
    }
}

public struct PluginConsoleOmissionSummary: Codable, Sendable, Equatable {
    public var entryCount: Int
    public var httpRecordCount: Int
    public var unassignedHTTPRecordCount: Int

    public init(
        entryCount: Int = 0,
        httpRecordCount: Int = 0,
        unassignedHTTPRecordCount: Int = 0
    ) {
        self.entryCount = entryCount
        self.httpRecordCount = httpRecordCount
        self.unassignedHTTPRecordCount = unassignedHTTPRecordCount
    }
}

// MARK: - 控制台服务

@Observable
public final class PluginConsoleService: @unchecked Sendable {

    public static let shared = PluginConsoleService()

    private static let maxEntries = 500
    private static let maxDiagnosticEntriesPerSession = 200
    private static let maxDiagnosticHTTPRecordsPerSession = 200

    public private(set) var entries: [PluginConsoleEntry] = []

    /// 诊断 session 会由 FullUI 显式开启。锁只保护这个很小的跨隔离状态；
    /// entries 仍只允许主 actor 读写。
    @ObservationIgnored private let diagnosticStateLock = NSLock()
    @ObservationIgnored private var storedDiagnosticSessionID: UUID?
    @ObservationIgnored private var omissionSummaries: [UUID: PluginConsoleOmissionSummary] = [:]

    private init() {}

    public var diagnosticSessionID: UUID? {
        diagnosticStateLock.withLock { storedDiagnosticSessionID }
    }

    public var isDiagnosticRecording: Bool {
        diagnosticSessionID != nil
    }

    @MainActor
    public func setDiagnosticSessionID(_ sessionID: UUID?) {
        diagnosticStateLock.withLock {
            storedDiagnosticSessionID = sessionID
        }
    }

    @MainActor
    public func log(
        tag: String,
        method: String,
        status: PluginConsoleEntryStatus = .loading,
        pluginVersion: String? = nil,
        diagnosticSessionID: UUID? = nil,
        operationID: UUID? = nil
    ) -> UUID {
        let entry = PluginConsoleEntry(
            tag: tag,
            method: method,
            status: status,
            pluginVersion: pluginVersion,
            diagnosticSessionID: diagnosticSessionID ?? self.diagnosticSessionID,
            operationID: operationID
        )
        insert(entry)
        return entry.id
    }

    @MainActor
    public func updateStatus(
        id: UUID,
        status: PluginConsoleEntryStatus,
        duration: TimeInterval? = nil,
        responseBody: String? = nil,
        errorMessage: String? = nil
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let sanitize = entries[index].diagnosticSessionID != nil
        entries[index].status = status
        entries[index].duration = duration
        entries[index].responseBody = sanitize
            ? responseBody.map { SupportDiagnosticSanitizer.body($0) }
            : responseBody
        entries[index].errorMessage = sanitize
            ? errorMessage.map { SupportDiagnosticSanitizer.text($0) }
            : errorMessage
    }

    @MainActor
    public func updateRequest(id: UUID, body: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].requestBody = entries[index].diagnosticSessionID == nil
            ? body
            : body.map { SupportDiagnosticSanitizer.body($0) }
    }

    @MainActor
    public func updateException(id: UUID, exception: LiveParseJSExceptionSnapshot) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].exception = exception
    }

    @MainActor
    public func invocationContext(for id: UUID) -> PluginConsoleInvocationContext? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        return PluginConsoleInvocationContext(
            entryID: entry.id,
            pluginVersion: entry.pluginVersion,
            diagnosticSessionID: entry.diagnosticSessionID,
            operationID: entry.operationID
        )
    }

    /// 将 HTTP 记录写到发起时冻结的归属。不能严格证明父调用时，创建独立
    /// Host.http 条目并保留候选 ID，避免把晚到响应错挂到另一个并发调用。
    @MainActor
    public func appendHTTPRecord(
        pluginId: String,
        context: PluginConsoleHTTPContext,
        record: PluginConsoleHTTPRecord
    ) {
        if context.association == .exact,
           let parentEntryID = context.parentEntryID,
           let index = entries.firstIndex(where: { $0.id == parentEntryID }) {
            if entries[index].diagnosticSessionID != nil,
               entries[index].httpRecords.count >= 100 {
                let removalCount = entries[index].httpRecords.count - 99
                entries[index].httpRecords.removeFirst(removalCount)
                entries[index].omittedHTTPRecordCount += removalCount
            }
            entries[index].httpRecords.append(record)
            if let sessionID = entries[index].diagnosticSessionID {
                enforceDiagnosticLimits(sessionID: sessionID)
            }
            return
        }

        let status: PluginConsoleEntryStatus
        if record.error != nil || (record.statusCode.map { !(200...399).contains($0) } ?? false) {
            status = .error
        } else {
            status = .success
        }
        var entry = PluginConsoleEntry(
            tag: context.isDiagnosticCapture
                ? SupportDiagnosticSanitizer.text(pluginId, limit: 256)
                : pluginId,
            method: "Host.http",
            status: status,
            timestamp: record.startedAt,
            pluginVersion: context.isDiagnosticCapture
                ? context.pluginVersion.map { SupportDiagnosticSanitizer.text($0, limit: 128) }
                : context.pluginVersion,
            diagnosticSessionID: context.diagnosticSessionID,
            operationID: context.operationID
        )
        entry.duration = record.duration
        entry.errorMessage = record.error
        entry.httpRecords = [record]
        if context.diagnosticSessionID == nil, context.isDiagnosticCapture {
            for sessionID in context.diagnosticSessionIDsForOmission {
                var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
                summary.unassignedHTTPRecordCount += 1
                omissionSummaries[sessionID] = summary
            }
        }
        insert(entry)
    }

    /// 返回值是完全由值类型组成的冻结快照，可安全交给报告编码器。
    @MainActor
    public func snapshot(sessionID: UUID) -> [PluginConsoleEntry] {
        entries.filter { $0.diagnosticSessionID == sessionID }
    }

    @MainActor
    public func omissionSummary(sessionID: UUID) -> PluginConsoleOmissionSummary {
        omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
    }

    /// 开发者模式或一次显式诊断 session 任一开启时记录。
    public var isEnabled: Bool {
        isDiagnosticRecording
            || UserDefaults.shared.bool(forKey: GeneralSettingModel.globalDeveloperMode)
    }

    @MainActor
    public func clear() {
        entries.removeAll()
        omissionSummaries.removeAll()
    }

    @MainActor
    private func insert(_ entry: PluginConsoleEntry) {
        entries.insert(entry, at: 0)
        if let sessionID = entry.diagnosticSessionID {
            enforceDiagnosticLimits(sessionID: sessionID)
        }
        if entries.count > Self.maxEntries {
            let removed = entries.suffix(entries.count - Self.maxEntries)
            for entry in removed {
                recordOmission(entry)
            }
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }


    @MainActor
    private func enforceDiagnosticLimits(sessionID: UUID) {
        func sessionEntryCount() -> Int {
            entries.lazy.filter { $0.diagnosticSessionID == sessionID }.count
        }
        func sessionHTTPRecordCount() -> Int {
            entries.lazy
                .filter { $0.diagnosticSessionID == sessionID }
                .reduce(0) { $0 + $1.httpRecords.count }
        }

        while sessionEntryCount() > Self.maxDiagnosticEntriesPerSession
                || sessionHTTPRecordCount() > Self.maxDiagnosticHTTPRecordsPerSession {
            guard let oldestIndex = entries.lastIndex(where: {
                $0.diagnosticSessionID == sessionID
            }) else { break }
            let removed = entries.remove(at: oldestIndex)
            recordOmission(removed)
        }
    }

    @MainActor
    private func recordOmission(_ entry: PluginConsoleEntry) {
        guard let sessionID = entry.diagnosticSessionID else { return }
        var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
        summary.entryCount += 1
        summary.httpRecordCount += entry.httpRecords.count + entry.omittedHTTPRecordCount
        omissionSummaries[sessionID] = summary
    }
}
