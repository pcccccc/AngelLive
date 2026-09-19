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
        #expect(sanitizedURL.contains("fragment"))
        #expect(sanitizedURL.contains("token="))
        #expect(sanitizedURL.contains("room=42"))
        #expect(SupportDiagnosticSanitizer.url("https://example.invalid/#token=private&room=room-a") == "https://example.invalid/#token=<redacted>&room=room-a")
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

    @Test("raw HTML and JSON retain formatting, ordering, escaped text and ordinary URL parameters")
    func originalBodiesArePreserved() throws {
        let json = "{\n  \"z\": 1e+02,\n  \"rooms\" : [ { \"id\": \"room-a\", \"text\": \"\\u4f60\\u597d\" } ],\n  \"a\": \"https:\\/\\/example.invalid/list?q=live%20music&page=2\"\n}\n"
        let html = "<!doctype html>\r\n<html><head><title>直播</title></head>\r\n<body>  <a href=\"https://example.invalid/list?room=room-a&page=2\">房间</a><script>const result = {\"z\":1, \"a\":2};</script></body></html>\r\n"
        #expect(SupportDiagnosticSanitizer.body(json) == json)
        #expect(SupportDiagnosticSanitizer.body(html) == html)
        let form = "<form>\n<input value='private-csrf' name='csrfToken'>\n<input name=\"room\" value=\"room-a\">\n</form>"
        let sanitizedForm = SupportDiagnosticSanitizer.body(form)
        #expect(!sanitizedForm.contains("private-csrf"))
        #expect(sanitizedForm.contains("<input name=\"room\" value=\"room-a\">"))
        let credentials = "{\n  \"z\": 1,\n  \"t\\u006fken\": {\"nested\":[\"private-value\"]},\n  \"url\": \"https:\\/\\/example.invalid/?room=room-a&token=private-value\",\n  \"a\": 2\n}"
        let sanitized = SupportDiagnosticSanitizer.body(credentials)
        #expect(!sanitized.contains("private-value"))
        #expect(sanitized.contains("\"z\": 1,\n"))
        #expect(sanitized.contains("room=room-a"))
        #expect(sanitized.hasSuffix("\"a\": 2\n}"))
        #expect(try JSONSerialization.jsonObject(with: Data(sanitized.utf8)) is [String: Any])
    }

    @Test("report and restored export include full HTML transport body and separate plugin JSON result")
    @MainActor
    func reportPreservesTransportAndPluginBodies() throws {
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
        let operation = service.recordAction(.openedRoom, context: ["pluginID": "fixture.plugin", "roomID": "room-a", "anchorName": "示例主播"])
        let html = "<!DOCTYPE html>\n<html>\n" + String(repeating: "<p>original  HTML &amp; text</p>\n", count: 900) + "</html>\n"
        let payload = "{\n  \"roomId\": \"room-a\",\n  \"page\": 2\n}"
        let response = "{\n  \"z\": \"room-a\",\n  \"a\": [1, 2]\n}"
        var entry = PluginConsoleEntry(tag: "fixture.plugin", method: "getPlayArgs", status: .success, pluginVersion: "1.2.3", diagnosticSessionID: sessionID, operationID: operation)
        entry.requestBody = payload
        entry.responseBody = response
        entry.httpRecords = [PluginConsoleHTTPRecord(
            url: "https://example.invalid/room?room=room-a&page=2&token=private",
            method: "POST",
            headers: ["Content-Type": "application/json", "Cookie": "credential=private"],
            body: payload,
            bodyKind: .utf8,
            bodyByteCount: payload.utf8.count,
            statusCode: 200,
            responseHeaders: ["Content-Type": "text/html; charset=utf-8"],
            responseBody: html,
            responseBodyKind: .utf8,
            responseBodyByteCount: html.utf8.count,
            association: .exact
        )]
        fixture.entries = [entry]
        service.stopRecording()
        let report = try #require(service.lastReport)
        #expect(report.entries[0].httpRecords[0].responseBody == html)
        #expect(report.entries[0].responseBody == response)
        #expect(report.entries[0].requestBody == payload)
        #expect(service.reportText.contains(html))
        #expect(service.reportText.contains(response))
        #expect(service.reportText.contains("房间 ID：room-a"))
        #expect(service.reportText.contains("fixture.plugin @ 1.2.3"))
        #expect(service.reportText.contains("room=room-a&page=2"))
        #expect(!service.reportText.contains("private"))
        let restored = SupportDiagnosticsService(storageDirectory: directory, entriesProvider: { [] }, sessionSetter: { _ in })
        let exported = try String(contentsOf: restored.exportReport(), encoding: .utf8)
        #expect(exported.contains(html))
        #expect(exported.contains(response))
        #expect(restored.lastReport?.environment != nil)
    }

    @Test("schema one report still restores without invented environment or log classification")
    @MainActor
    func oldReportRestores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SupportDiagnosticsService(storageDirectory: directory, entriesProvider: { [] }, sessionSetter: { _ in })
        service.makeReportForError(title: "错误快照", message: "fixture failure", detail: nil)
        let url = directory.appendingPathComponent("latest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "environment")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let restored = SupportDiagnosticsService(storageDirectory: directory, entriesProvider: { [] }, sessionSetter: { _ in })
        #expect(restored.errorMessage == nil)
        #expect(restored.lastReport?.schemaVersion == 1)
        #expect(restored.lastReport?.environment == nil)
        #expect(restored.reportText.contains("此报告未采集设备型号"))
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
        fixture.entries = (0..<32).map { index in
            var entry = PluginConsoleEntry(
                tag: "fixture-\(index)", method: "getRooms",
                status: index == 31 ? .error : .success,
                diagnosticSessionID: sessionID
            )
            entry.requestBody = "{\"roomID\":\"room-\(index)\"}"
            entry.responseBody = String(repeating: "x", count: 600_000) + "-\(index)"
            entry.errorMessage = index == 31 ? "latest failure" : nil
            return entry
        }
        service.stopRecording()
        let capped = try #require(service.lastReport)
        #expect(capped.entries.count == 32)
        #expect(capped.entries.contains { $0.pluginID == "fixture-31" && $0.errorMessage == "latest failure" })
        #expect(capped.entries.first?.requestBody == #"{"roomID":"room-0"}"#)
        #expect(capped.limitations.joined().contains("响应正文已缩短"))
        #expect(try Data(contentsOf: directory.appendingPathComponent("latest.json")).count <= 16 * 1_024 * 1_024)

        service.startRecording()
        _ = service.recordAction(.openedHome)
        try FileManager.default.removeItem(at: directory)
        try Data("not-a-directory".utf8).write(to: directory)
        service.stopRecording()
        #expect(service.lastReport != nil)
        #expect(service.errorMessage?.contains("无法保存") == true)
    }
}
