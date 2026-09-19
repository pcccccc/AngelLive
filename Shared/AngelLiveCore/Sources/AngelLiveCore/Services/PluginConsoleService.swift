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
    public var body: String?
    public let bodyKind: PluginConsoleBodyKind?
    public let bodyByteCount: Int?
    public var bodyWasTruncated: Bool
    public let statusCode: Int?
    public let responseHeaders: [String: String]?
    public let omittedRequestHeaderCount: Int
    public let omittedResponseHeaderCount: Int
    public var responseBody: String?
    public let responseBodyKind: PluginConsoleBodyKind?
    public let responseBodyByteCount: Int?
    public var responseBodyWasTruncated: Bool
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

public enum PluginConsoleEntryKind: String, Codable, Sendable {
    case invocation
    case playerLog
    case highFrequency
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
    public let kind: PluginConsoleEntryKind
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
        kind: PluginConsoleEntryKind = .invocation,
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
        self.kind = kind
        self.status = status
        self.httpRecords = []
        self.omittedHTTPRecordCount = 0
    }
}

public struct PluginConsoleOmissionSummary: Codable, Sendable, Equatable {
    public var entryCount: Int
    public var playerLogEntryCount: Int
    public var highFrequencyEntryCount: Int
    public var bodyTruncationCount: Int
    public var bodyOmittedByteCount: Int
    public var httpRecordCount: Int
    public var unassignedHTTPRecordCount: Int

    public init(
        entryCount: Int = 0,
        playerLogEntryCount: Int = 0,
        highFrequencyEntryCount: Int = 0,
        bodyTruncationCount: Int = 0,
        bodyOmittedByteCount: Int = 0,
        httpRecordCount: Int = 0,
        unassignedHTTPRecordCount: Int = 0
    ) {
        self.entryCount = entryCount
        self.playerLogEntryCount = playerLogEntryCount
        self.highFrequencyEntryCount = highFrequencyEntryCount
        self.bodyTruncationCount = bodyTruncationCount
        self.bodyOmittedByteCount = bodyOmittedByteCount
        self.httpRecordCount = httpRecordCount
        self.unassignedHTTPRecordCount = unassignedHTTPRecordCount
    }
}

// MARK: - 控制台服务

@Observable
public final class PluginConsoleService: @unchecked Sendable {

    public static let shared = PluginConsoleService()

    private static let maxEntries = 500
    private static let maxDiagnosticInvocationEntriesPerSession = 200
    private static let maxDiagnosticPlayerLogEntriesPerSession = 50
    private static let maxDiagnosticHighFrequencyEntriesPerSession = 30
    private static let maxDiagnosticHTTPRecordsPerSession = 200
    private static let maxDiagnosticBodyBytesPerSession = 32 * 1_024 * 1_024
    private static let minimumRetainedBodyBytes = 4 * 1_024

    public private(set) var entries: [PluginConsoleEntry] = []
    @MainActor public private(set) var diagnosticEntries: [PluginConsoleEntry] = []

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
        if let sessionID {
            diagnosticEntries.removeAll(keepingCapacity: true)
            omissionSummaries[sessionID] = PluginConsoleOmissionSummary()
        }
        diagnosticStateLock.withLock {
            storedDiagnosticSessionID = sessionID
        }
    }

    @MainActor
    public func log(
        tag: String,
        method: String,
        status: PluginConsoleEntryStatus = .loading,
        kind: PluginConsoleEntryKind = .invocation,
        timestamp: Date = Date(),
        pluginVersion: String? = nil,
        diagnosticSessionID: UUID? = nil,
        operationID: UUID? = nil,
        captureCurrentDiagnosticSession: Bool = true
    ) -> UUID {
        let capturedSessionID = captureCurrentDiagnosticSession
            ? diagnosticSessionID ?? self.diagnosticSessionID
            : diagnosticSessionID
        let entry = PluginConsoleEntry(
            tag: tag,
            method: method,
            status: status,
            kind: kind,
            timestamp: timestamp,
            pluginVersion: pluginVersion,
            diagnosticSessionID: capturedSessionID,
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
        updateEntry(id: id) { entry in
            let sanitize = entry.diagnosticSessionID != nil
            entry.status = status
            entry.duration = duration
            entry.responseBody = sanitize
                ? responseBody.map { SupportDiagnosticSanitizer.body($0) }
                : responseBody
            entry.errorMessage = sanitize
                ? errorMessage.map { SupportDiagnosticSanitizer.text($0) }
                : errorMessage
        }
    }

    @MainActor
    public func updateRequest(id: UUID, body: String?) {
        updateEntry(id: id) { entry in
            entry.requestBody = entry.diagnosticSessionID == nil
                ? body
                : body.map { SupportDiagnosticSanitizer.body($0) }
        }
    }

    @MainActor
    public func updateException(id: UUID, exception: LiveParseJSExceptionSnapshot) {
        updateEntry(id: id) { entry in
            entry.exception = exception
        }
    }

    @MainActor
    public func invocationContext(for id: UUID) -> PluginConsoleInvocationContext? {
        guard let entry = entries.first(where: { $0.id == id })
            ?? diagnosticEntries.first(where: { $0.id == id }) else { return nil }
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
        if context.association == .exact, let parentEntryID = context.parentEntryID {
            var foundParent = false
            var consoleIndex: Int?
            if let index = entries.firstIndex(where: { $0.id == parentEntryID }) {
                appendHTTPRecord(record, to: &entries[index], recordOmission: false)
                consoleIndex = index
                foundParent = true
            }
            if let index = activeDiagnosticEntryIndex(id: parentEntryID) {
                appendHTTPRecord(record, to: &diagnosticEntries[index], recordOmission: true)
                if let sessionID = diagnosticEntries[index].diagnosticSessionID {
                    enforceDiagnosticHTTPRecordLimit(sessionID: sessionID)
                    enforceDiagnosticBodyLimit(sessionID: sessionID)
                }
                foundParent = true
            } else if let consoleIndex,
                      let sessionID = activeOmittedDiagnosticSessionID(
                        forConsoleEntryAt: consoleIndex
                      ) {
                recordLateOmittedContent(
                    consoleEntryAt: consoleIndex,
                    sessionID: sessionID,
                    httpRecordCount: 1
                )
            }
            if foundParent { return }
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
            kind: .invocation,
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
        diagnosticEntries.filter { $0.diagnosticSessionID == sessionID }
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
        diagnosticEntries.removeAll()
        omissionSummaries.removeAll()
    }

    @MainActor
    private func insert(_ entry: PluginConsoleEntry) {
        entries.insert(entry, at: 0)
        if let sessionID = entry.diagnosticSessionID,
           sessionID == diagnosticSessionID {
            diagnosticEntries.insert(entry, at: 0)
            enforceDiagnosticEntryLimit(kind: entry.kind, sessionID: sessionID)
            enforceDiagnosticHTTPRecordLimit(sessionID: sessionID)
            enforceDiagnosticBodyLimit(sessionID: sessionID)
        }
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    @MainActor
    private func updateEntry(id: UUID, mutation: (inout PluginConsoleEntry) -> Void) {
        var consoleIndex: Int?
        if let index = entries.firstIndex(where: { $0.id == id }) {
            mutation(&entries[index])
            consoleIndex = index
        }
        if let index = activeDiagnosticEntryIndex(id: id) {
            let sessionID = diagnosticEntries[index].diagnosticSessionID
            mutation(&diagnosticEntries[index])
            if let sessionID {
                enforceDiagnosticBodyLimit(sessionID: sessionID)
            }
        } else if let consoleIndex,
                  let sessionID = activeOmittedDiagnosticSessionID(
                    forConsoleEntryAt: consoleIndex
                  ) {
            recordLateOmittedContent(
                consoleEntryAt: consoleIndex,
                sessionID: sessionID
            )
        }
    }

    @MainActor
    private func activeDiagnosticEntryIndex(id: UUID) -> Int? {
        guard let index = diagnosticEntries.firstIndex(where: { $0.id == id }),
              diagnosticEntries[index].diagnosticSessionID == diagnosticSessionID else {
            return nil
        }
        return index
    }

    @MainActor
    private func activeOmittedDiagnosticSessionID(
        forConsoleEntryAt index: Int
    ) -> UUID? {
        guard let sessionID = entries[index].diagnosticSessionID,
              sessionID == diagnosticSessionID,
              !diagnosticEntries.contains(where: { $0.id == entries[index].id }) else {
            return nil
        }
        return sessionID
    }

    @MainActor
    private func recordLateOmittedContent(
        consoleEntryAt index: Int,
        sessionID: UUID,
        httpRecordCount: Int = 0
    ) {
        let omittedBodyBytes = entryBodyByteCount(entries[index])
        var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
        summary.httpRecordCount += httpRecordCount
        if omittedBodyBytes > 0 {
            summary.bodyTruncationCount += 1
            summary.bodyOmittedByteCount += omittedBodyBytes
            compactConsoleEntry(id: entries[index].id)
        }
        omissionSummaries[sessionID] = summary
    }

    @MainActor
    private func appendHTTPRecord(
        _ record: PluginConsoleHTTPRecord,
        to entry: inout PluginConsoleEntry,
        recordOmission: Bool
    ) {
        if !recordOmission, entry.diagnosticSessionID != nil, entry.httpRecords.count >= 100 {
            let removalCount = entry.httpRecords.count - 99
            entry.httpRecords.removeFirst(removalCount)
            entry.omittedHTTPRecordCount += removalCount
        }
        entry.httpRecords.append(record)
    }

    @MainActor
    private func enforceDiagnosticEntryLimit(
        kind: PluginConsoleEntryKind,
        sessionID: UUID
    ) {
        let limit: Int
        switch kind {
        case .invocation:
            limit = Self.maxDiagnosticInvocationEntriesPerSession
        case .playerLog:
            limit = Self.maxDiagnosticPlayerLogEntriesPerSession
        case .highFrequency:
            limit = Self.maxDiagnosticHighFrequencyEntriesPerSession
        }

        var matchingIndices = diagnosticEntries.indices.filter {
            diagnosticEntries[$0].diagnosticSessionID == sessionID
                && diagnosticEntries[$0].kind == kind
        }
        while matchingIndices.count > limit {
            let removalIndex = diagnosticEntryEvictionIndex(
                kind: kind,
                matchingIndices: matchingIndices
            )
            let removed = diagnosticEntries.remove(at: removalIndex)
            recordDiagnosticOmission(removed)
            matchingIndices = diagnosticEntries.indices.filter {
                diagnosticEntries[$0].diagnosticSessionID == sessionID
                    && diagnosticEntries[$0].kind == kind
            }
        }
    }

    @MainActor
    private func diagnosticEntryEvictionIndex(
        kind: PluginConsoleEntryKind,
        matchingIndices: [Int]
    ) -> Int {
        let preferredIndices: ArraySlice<Int>
        if kind == .invocation, matchingIndices.count > 40 {
            // Entries are newest first. Reserve evidence from both ends of the
            // invocation timeline, then evict non-errors from the middle first.
            preferredIndices = matchingIndices.dropFirst(20).dropLast(20)
        } else {
            preferredIndices = matchingIndices[...]
        }
        if let index = preferredIndices.last(where: {
            !Self.isEntryFailure(diagnosticEntries[$0])
        }) {
            return index
        }
        if let index = matchingIndices.last(where: {
            !Self.isEntryFailure(diagnosticEntries[$0])
        }) {
            return index
        }
        return preferredIndices.last ?? matchingIndices.last!
    }

    private static func isEntryFailure(_ entry: PluginConsoleEntry) -> Bool {
        entry.status == .error
            || entry.errorMessage != nil
            || entry.exception != nil
            || entry.httpRecords.contains(where: isHTTPError)
    }

    @MainActor
    private func enforceDiagnosticHTTPRecordLimit(sessionID: UUID) {
        var recordCount = diagnosticEntries.lazy
            .filter { $0.diagnosticSessionID == sessionID }
            .reduce(0) { $0 + $1.httpRecords.count }
        while recordCount > Self.maxDiagnosticHTTPRecordsPerSession {
            guard let location = diagnosticHTTPRecordEvictionLocation(sessionID: sessionID) else {
                break
            }
            let removed = diagnosticEntries[location.entry]
                .httpRecords.remove(at: location.record)
            diagnosticEntries[location.entry].omittedHTTPRecordCount += 1
            removeConsoleHTTPRecord(id: removed.id)
            var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
            summary.httpRecordCount += 1
            omissionSummaries[sessionID] = summary
            recordCount -= 1
        }
    }

    @MainActor
    private func diagnosticHTTPRecordEvictionLocation(
        sessionID: UUID
    ) -> (entry: Int, record: Int)? {
        struct RecordLocation {
            let entry: Int
            let record: Int
            let value: PluginConsoleHTTPRecord
        }
        var records: [RecordLocation] = []
        for entryIndex in diagnosticEntries.indices {
            let entry = diagnosticEntries[entryIndex]
            guard entry.diagnosticSessionID == sessionID else { continue }
            for recordIndex in entry.httpRecords.indices {
                records.append(RecordLocation(
                    entry: entryIndex,
                    record: recordIndex,
                    value: entry.httpRecords[recordIndex]
                ))
            }
        }
        records.sort { $0.value.startedAt < $1.value.startedAt }
        guard !records.isEmpty else { return nil }
        let protectedIDs = Set(
            records.prefix(20).map { $0.value.id }
                + records.suffix(20).map { $0.value.id }
        )
        let middle = records.filter { !protectedIDs.contains($0.value.id) }
        let middleSuccess = middle.first { !Self.isHTTPError($0.value) }
        let anySuccess = records.first { !Self.isHTTPError($0.value) }
        guard let candidate = middleSuccess ?? anySuccess ?? middle.first ?? records.first else {
            return nil
        }
        return (candidate.entry, candidate.record)
    }

    private static func isHTTPError(_ record: PluginConsoleHTTPRecord) -> Bool {
        record.error != nil
            || (record.statusCode.map { !(200...399).contains($0) } ?? false)
    }

    @MainActor
    private func removeConsoleHTTPRecord(id: UUID) {
        for entryIndex in entries.indices {
            guard let recordIndex = entries[entryIndex].httpRecords.firstIndex(where: {
                $0.id == id
            }) else { continue }
            entries[entryIndex].httpRecords.remove(at: recordIndex)
            entries[entryIndex].omittedHTTPRecordCount += 1
            return
        }
    }

    private enum DiagnosticBodyLocation {
        case entryRequest(Int)
        case entryResponse(Int)
        case httpRequest(entry: Int, record: Int)
        case httpResponse(entry: Int, record: Int)
    }

    private struct DiagnosticBodyCandidate {
        let priority: Int
        let byteCount: Int
        let location: DiagnosticBodyLocation
    }

    @MainActor
    private func enforceDiagnosticBodyLimit(sessionID: UUID) {
        var total = diagnosticBodyByteCount(sessionID: sessionID)
        while total > Self.maxDiagnosticBodyBytesPerSession {
            let overage = total - Self.maxDiagnosticBodyBytesPerSession
            guard let candidate = diagnosticBodyCandidates(sessionID: sessionID)
                .filter({ $0.byteCount > Self.minimumRetainedBodyBytes })
                .min(by: { lhs, rhs in
                    lhs.priority == rhs.priority
                        ? lhs.byteCount > rhs.byteCount
                        : lhs.priority < rhs.priority
                }) else { break }
            let byteLimit = max(
                Self.minimumRetainedBodyBytes,
                candidate.byteCount - overage
            )
            let omitted = truncateDiagnosticBody(
                at: candidate.location,
                byteLimit: byteLimit
            )
            guard omitted > 0 else { break }
            var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
            summary.bodyTruncationCount += 1
            summary.bodyOmittedByteCount += omitted
            omissionSummaries[sessionID] = summary
            total -= omitted
        }
    }

    @MainActor
    private func diagnosticBodyByteCount(sessionID: UUID) -> Int {
        diagnosticEntries.lazy
            .filter { $0.diagnosticSessionID == sessionID }
            .reduce(0) { total, entry in
                total
                    + (entry.requestBody?.utf8.count ?? 0)
                    + (entry.responseBody?.utf8.count ?? 0)
                    + entry.httpRecords.reduce(0) { httpTotal, record in
                        httpTotal
                            + (record.body?.utf8.count ?? 0)
                            + (record.responseBody?.utf8.count ?? 0)
                    }
            }
    }

    @MainActor
    private func diagnosticBodyCandidates(
        sessionID: UUID
    ) -> [DiagnosticBodyCandidate] {
        var candidates: [DiagnosticBodyCandidate] = []
        for entryIndex in diagnosticEntries.indices {
            let entry = diagnosticEntries[entryIndex]
            guard entry.diagnosticSessionID == sessionID else { continue }
            let nonInvocationPriority = entry.kind == .invocation ? 1 : 0
            if let request = entry.requestBody {
                candidates.append(.init(
                    priority: entry.kind == .invocation ? 2 : nonInvocationPriority,
                    byteCount: request.utf8.count,
                    location: .entryRequest(entryIndex)
                ))
            }
            if let response = entry.responseBody {
                candidates.append(.init(
                    priority: nonInvocationPriority,
                    byteCount: response.utf8.count,
                    location: .entryResponse(entryIndex)
                ))
            }
            for recordIndex in entry.httpRecords.indices {
                let record = entry.httpRecords[recordIndex]
                if let body = record.body {
                    candidates.append(.init(
                        priority: entry.kind == .invocation ? 2 : nonInvocationPriority,
                        byteCount: body.utf8.count,
                        location: .httpRequest(entry: entryIndex, record: recordIndex)
                    ))
                }
                if let response = record.responseBody {
                    candidates.append(.init(
                        priority: nonInvocationPriority,
                        byteCount: response.utf8.count,
                        location: .httpResponse(entry: entryIndex, record: recordIndex)
                    ))
                }
            }
        }
        return candidates
    }

    @MainActor
    private func truncateDiagnosticBody(
        at location: DiagnosticBodyLocation,
        byteLimit: Int
    ) -> Int {
        func truncated(_ text: String) -> (value: String, omitted: Int) {
            let value = SupportDiagnosticSanitizer.body(text, limit: byteLimit)
            return (value, max(0, text.utf8.count - value.utf8.count))
        }

        switch location {
        case .entryRequest(let entryIndex):
            guard let text = diagnosticEntries[entryIndex].requestBody else { return 0 }
            let result = truncated(text)
            diagnosticEntries[entryIndex].requestBody = result.value
            mirrorEntryBody(
                id: diagnosticEntries[entryIndex].id,
                requestBody: result.value
            )
            return result.omitted
        case .entryResponse(let entryIndex):
            guard let text = diagnosticEntries[entryIndex].responseBody else { return 0 }
            let result = truncated(text)
            diagnosticEntries[entryIndex].responseBody = result.value
            mirrorEntryBody(
                id: diagnosticEntries[entryIndex].id,
                responseBody: result.value
            )
            return result.omitted
        case .httpRequest(let entryIndex, let recordIndex):
            guard let text = diagnosticEntries[entryIndex].httpRecords[recordIndex].body else {
                return 0
            }
            let result = truncated(text)
            let recordID = diagnosticEntries[entryIndex].httpRecords[recordIndex].id
            diagnosticEntries[entryIndex].httpRecords[recordIndex].body = result.value
            diagnosticEntries[entryIndex].httpRecords[recordIndex].bodyWasTruncated = true
            mirrorHTTPBody(id: recordID, requestBody: result.value)
            return result.omitted
        case .httpResponse(let entryIndex, let recordIndex):
            guard let text = diagnosticEntries[entryIndex].httpRecords[recordIndex].responseBody else {
                return 0
            }
            let result = truncated(text)
            let recordID = diagnosticEntries[entryIndex].httpRecords[recordIndex].id
            diagnosticEntries[entryIndex].httpRecords[recordIndex].responseBody = result.value
            diagnosticEntries[entryIndex].httpRecords[recordIndex].responseBodyWasTruncated = true
            mirrorHTTPBody(id: recordID, responseBody: result.value)
            return result.omitted
        }
    }

    @MainActor
    private func mirrorEntryBody(
        id: UUID,
        requestBody: String? = nil,
        responseBody: String? = nil
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if let requestBody { entries[index].requestBody = requestBody }
        if let responseBody { entries[index].responseBody = responseBody }
    }

    @MainActor
    private func mirrorHTTPBody(
        id: UUID,
        requestBody: String? = nil,
        responseBody: String? = nil
    ) {
        for entryIndex in entries.indices {
            guard let recordIndex = entries[entryIndex].httpRecords.firstIndex(where: {
                $0.id == id
            }) else { continue }
            if let requestBody {
                entries[entryIndex].httpRecords[recordIndex].body = requestBody
                entries[entryIndex].httpRecords[recordIndex].bodyWasTruncated = true
            }
            if let responseBody {
                entries[entryIndex].httpRecords[recordIndex].responseBody = responseBody
                entries[entryIndex].httpRecords[recordIndex].responseBodyWasTruncated = true
            }
            return
        }
    }

    @MainActor
    private func recordDiagnosticOmission(_ entry: PluginConsoleEntry) {
        guard let sessionID = entry.diagnosticSessionID else { return }
        var summary = omissionSummaries[sessionID] ?? PluginConsoleOmissionSummary()
        switch entry.kind {
        case .invocation:
            summary.entryCount += 1
        case .playerLog:
            summary.playerLogEntryCount += 1
        case .highFrequency:
            summary.highFrequencyEntryCount += 1
        }
        let omittedBodyBytes = entryBodyByteCount(entry)
        if omittedBodyBytes > 0 {
            summary.bodyTruncationCount += 1
            summary.bodyOmittedByteCount += omittedBodyBytes
            compactConsoleEntry(id: entry.id)
        }
        summary.httpRecordCount += entry.httpRecords.count
        omissionSummaries[sessionID] = summary
    }

    private func entryBodyByteCount(_ entry: PluginConsoleEntry) -> Int {
        (entry.requestBody?.utf8.count ?? 0)
            + (entry.responseBody?.utf8.count ?? 0)
            + entry.httpRecords.reduce(0) { total, record in
                total
                    + (record.body?.utf8.count ?? 0)
                    + (record.responseBody?.utf8.count ?? 0)
            }
    }

    @MainActor
    private func compactConsoleEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].requestBody = nil
        entries[index].responseBody = nil
        for recordIndex in entries[index].httpRecords.indices {
            entries[index].httpRecords[recordIndex].body = nil
            entries[index].httpRecords[recordIndex].bodyWasTruncated = true
            entries[index].httpRecords[recordIndex].responseBody = nil
            entries[index].httpRecords[recordIndex].responseBodyWasTruncated = true
        }
    }
}
