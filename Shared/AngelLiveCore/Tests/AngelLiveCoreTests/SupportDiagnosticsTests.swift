import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Support diagnostics", .serialized)
struct SupportDiagnosticsTests {
    @MainActor
    final class Fixture {
        var entries: [PluginConsoleEntry] = []
        var recordedSessionIDs: [UUID?] = []
    }

    @Test("sanitizer removes credentials from JSON, headers, URLs, and Unicode truncation")
    func sanitizerRedactsCredentials() {
        let json = SupportDiagnosticSanitizer.body(#"{"token":"secret-value","nested":{"password":"abc"},"message":"ok"}"#)
        #expect(!json.contains("secret-value"))
        #expect(!json.contains("\"abc\""))
        #expect(json.contains("\"message\":\"ok\""))

        let headers = SupportDiagnosticSanitizer.headers([
            "Authorization": "Bearer very-secret",
            "X-Trace": "trace-1"
        ])
        #expect(headers["Authorization"] == "<redacted>")
        #expect(headers["X-Trace"] == "trace-1")

        let inlineAuthorization = SupportDiagnosticSanitizer.text("Request failed: Authorization: Basic Zml4dHVyZTpwYXNzd29yZA==")
        #expect(!inlineAuthorization.contains("Zml4dHVyZTpwYXNzd29yZA=="))
        let headerText = SupportDiagnosticSanitizer.text("Cookie: a=b; c=d\nAuthorization: Basic dXNlcjpwYXNz\njwt='a.b.c'")
        #expect(!headerText.contains("a=b"))
        #expect(!headerText.contains("c=d"))
        #expect(!headerText.contains("dXNlcjpwYXNz"))
        #expect(!headerText.contains("a.b.c"))

        let sanitizedURL = SupportDiagnosticSanitizer.url("https://user:password@example.invalid/path?token=secret&room=42#fragment")
        #expect(!sanitizedURL.contains("password"))
        #expect(!sanitizedURL.contains("secret"))
        #expect(!sanitizedURL.contains("fragment"))
        #expect(sanitizedURL.contains("token="))
        #expect(sanitizedURL.contains("room="))
        let malformedURL = SupportDiagnosticSanitizer.url("https://user:secret@example.invalid/path with space?token=secret")
        #expect(!malformedURL.contains("secret"))

        let unicode = String(repeating: "诊断", count: 200)
        let truncated = SupportDiagnosticSanitizer.body(unicode, limit: 64)
        #expect(truncated.contains("已截断"))
        #expect(truncated.contains("字节"))
        #expect(String(decoding: Data(truncated.utf8), as: UTF8.self) == truncated)
    }

    @Test("recording freezes one session, preserves its operation ordering, and restores only the latest report")
    @MainActor
    func recordingFreezesAndRestores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = Fixture()
        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { fixture.entries },
            sessionSetter: { fixture.recordedSessionIDs.append($0) }
        )

        service.startRecording()
        let sessionID = try #require(fixture.recordedSessionIDs.last ?? nil)
        let firstOperation = try #require(service.recordAction(.openedHome, context: ["query": "token=hidden"]))
        let taskLocalOperation = UUID()
        let secondOperation = SupportDiagnosticContext.$operationID.withValue(taskLocalOperation) {
            service.recordAction(.searched, context: ["keyword": "live"])
        }
        #expect(secondOperation == taskLocalOperation)

        var captured = PluginConsoleEntry(
            tag: "fixture.plugin",
            method: "getRooms",
            status: .error,
            pluginVersion: "1.2.3",
            diagnosticSessionID: sessionID,
            operationID: firstOperation
        )
        captured.requestBody = #"{"cookie":"nope","page":1}"#
        captured.responseBody = #"{"result":"ok","session":"nope"}"#
        captured.errorMessage = "NETWORK timeout token=hidden"
        captured.httpRecords = [PluginConsoleHTTPRecord(
            url: "https://example.invalid/api?auth=hidden",
            method: "GET",
            headers: ["Cookie": "a=b", "X-Request-ID": "trace"],
            responseBody: "Bearer hidden",
            responseBodyKind: .utf8,
            responseBodyByteCount: 13,
            responseBodyWasTruncated: true
        )]
        let unrelated = PluginConsoleEntry(
            tag: "source-b",
            method: "getRooms",
            diagnosticSessionID: UUID()
        )
        fixture.entries = [captured, unrelated]

        service.stopRecording()
        let report = try #require(service.lastReport)
        #expect(!service.isRecording)
        #expect(fixture.recordedSessionIDs.last == .some(nil))
        #expect(report.entries.count == 1)
        #expect(report.entries[0].pluginVersion == "1.2.3")
        #expect(report.entries[0].operationID == firstOperation)
        #expect(report.actions.map(\.operationID) == [firstOperation, taskLocalOperation])
        #expect(!service.reportText.contains("hidden"))
        #expect(service.reportText.contains("已截断"))
        fixture.entries[0].responseBody = "token=later-callback"
        #expect(!service.reportText.contains("later-callback"))

        let restored = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { [] },
            sessionSetter: { _ in }
        )
        #expect(restored.lastReport?.sessionID == report.sessionID)
        #expect(restored.errorMessage == nil)
    }

    @Test("an old delayed stop cannot stop a new session, and export has explicit no-report failure")
    @MainActor
    func oldStopDoesNotEndNewSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = Fixture()
        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { fixture.entries },
            sessionSetter: { fixture.recordedSessionIDs.append($0) }
        )

        #expect(throws: SupportDiagnosticsError.self) {
            try service.exportReport()
        }

        service.startRecording()
        let firstSession = try #require(fixture.recordedSessionIDs.last ?? nil)
        service.stopRecording(sessionID: firstSession)
        service.startRecording()
        let secondSession = try #require(fixture.recordedSessionIDs.last ?? nil)
        service.stopRecording(sessionID: firstSession)
        #expect(service.isRecording)
        #expect(fixture.recordedSessionIDs.last == secondSession)
        service.stopRecording(sessionID: secondSession)

        let exportURL = try service.exportReport()
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        #expect(try String(contentsOf: exportURL, encoding: .utf8).contains("支持诊断报告"))
        service.updateDescription("新的用户补充")
        #expect(!FileManager.default.fileExists(atPath: exportURL.path))
        _ = try service.exportReport()
        service.discardReport()
        #expect(service.lastReport == nil)
        #expect(!FileManager.default.fileExists(atPath: exportURL.path))
    }

    @Test("error snapshot makes absent platform responses explicit")
    @MainActor
    func errorSnapshotStatesCoverage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { [] },
            sessionSetter: { _ in }
        )
        service.makeReportForError(title: "播放失败", message: "token=private", detail: "https://example.invalid/?session=private")
        let report = try #require(service.lastReport)
        #expect(report.entries.isEmpty)
        #expect(report.limitations.joined().contains("未采集"))
        #expect(!service.reportText.contains("private"))
    }

    @Test("the five-minute auto-stop path is session guarded and includes a pending failure")
    @MainActor
    func automaticStopIncludesPendingFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = Fixture()
        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { fixture.entries },
            sessionSetter: { fixture.recordedSessionIDs.append($0) },
            automaticStopDelayNanoseconds: 1_000_000
        )
        service.startRecording()
        let sessionID = try #require(fixture.recordedSessionIDs.last ?? nil)
        service.makeReportForError(title: "播放失败", message: "Bearer pending-secret", detail: nil)
        #expect(service.isRecording)
        try await Task.sleep(nanoseconds: 50_000_000)

        let report = try #require(service.lastReport)
        #expect(!service.isRecording)
        #expect(report.sessionID == sessionID)
        #expect(report.failure?.title == "播放失败")
        #expect(!service.reportText.contains("pending-secret"))
        #expect(fixture.recordedSessionIDs.last == .some(nil))
    }

    @Test("a corrupted cache is visible and is never silently replaced during restoration")
    @MainActor
    func corruptCacheReportsRecoveryError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("latest.json"))

        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { [] },
            sessionSetter: { _ in }
        )
        #expect(service.lastReport == nil)
        #expect(service.errorMessage?.contains("无法恢复") == true)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("latest.json").path))
    }

    @Test("storage capping keeps the newest failure and a write failure keeps the current preview")
    @MainActor
    func storageCapKeepsNewestFailureAndWriteFailureKeepsPreview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = Fixture()
        let service = SupportDiagnosticsService(
            storageDirectory: directory,
            entriesProvider: { fixture.entries },
            sessionSetter: { fixture.recordedSessionIDs.append($0) }
        )
        service.startRecording()
        let sessionID = try #require(fixture.recordedSessionIDs.last ?? nil)
        fixture.entries = (0..<200).map { index in
            var entry = PluginConsoleEntry(
                tag: "fixture-\(index)", method: "getRooms",
                status: index == 199 ? .error : .success,
                diagnosticSessionID: sessionID
            )
            entry.responseBody = String(repeating: "x", count: 16_384) + "-\(index)"
            entry.errorMessage = index == 199 ? "latest failure" : nil
            return entry
        }
        service.stopRecording()
        let capped = try #require(service.lastReport)
        #expect(capped.entries.count < 200)
        #expect(capped.entries.contains { $0.pluginID == "fixture-199" && $0.errorMessage == "latest failure" })
        #expect(capped.limitations.joined().contains("较早插件调用"))

        service.startRecording()
        _ = service.recordAction(.openedHome)
        try FileManager.default.removeItem(at: directory)
        try Data("not-a-directory".utf8).write(to: directory)
        service.stopRecording()
        #expect(service.lastReport != nil)
        #expect(service.errorMessage?.contains("无法保存") == true)
    }
}
