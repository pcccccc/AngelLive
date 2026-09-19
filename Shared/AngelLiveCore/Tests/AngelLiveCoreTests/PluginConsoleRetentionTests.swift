import Foundation
import Testing
@testable import AngelLiveCore

extension PluginRuntimeDiagnosticsTests {
    @Test("diagnostic partitions retain business evidence after log floods and freeze on stop")
    @MainActor
    func partitionsRetainBusinessEvidence() throws {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        defer {
            service.setDiagnosticSessionID(nil)
            service.clear()
        }

        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let playbackID = service.log(
            tag: "fixture.plugin",
            method: "getPlayArgs",
            timestamp: occurredAt,
            pluginVersion: "1.0.0"
        )
        service.updateRequest(
            id: playbackID,
            body: #"{ "roomId": "room-42", "quality": "source" }"#
        )
        let failureID = service.log(
            tag: "fixture.plugin",
            method: "getRoomDetail",
            status: .error
        )
        service.updateStatus(
            id: failureID,
            status: .error,
            errorMessage: "fixture failure"
        )

        let frameRequest = LiveParsePluginManager.highFrequencyRequestSummary(
            function: "onDanmakuFrame",
            payload: [
                "connectionId": "connection-private",
                "frameType": "binary",
                "bytesBase64": Data("private-frame".utf8).base64EncodedString(),
                "text": "private-user-message"
            ]
        )
        let frameResponse = LiveParsePluginManager.highFrequencyResponseSummary(
            function: "onDanmakuFrame",
            value: [
                "ok": true,
                "messages": [["text": "private-danmaku-user-content"]],
                "writes": []
            ]
        )
        for index in 0..<1_100 {
            let id = service.log(
                tag: "Player",
                method: "debug-\(index)",
                status: .success,
                kind: .playerLog
            )
            service.updateStatus(id: id, status: .success, responseBody: "nal slice \(index)")
        }
        for index in 0..<1_100 {
            let id = service.log(
                tag: "fixture.plugin",
                method: index.isMultiple(of: 2) ? "onDanmakuFrame" : "onDanmakuTick",
                kind: .highFrequency
            )
            service.updateRequest(id: id, body: frameRequest)
            service.updateStatus(id: id, status: .success, responseBody: frameResponse)
        }

        service.updateStatus(
            id: playbackID,
            status: .success,
            responseBody: "<html>original playback response</html>"
        )
        service.appendHTTPRecord(
            pluginId: "fixture.plugin",
            context: PluginConsoleHTTPContext(
                parentEntryID: playbackID,
                association: .exact,
                candidateEntryIDs: [],
                pluginVersion: "1.0.0",
                diagnosticSessionID: sessionID,
                operationID: nil,
                isDiagnosticCapture: true
            ),
            record: PluginConsoleHTTPRecord(
                url: "https://source-a.example.invalid/play?room=42&token=private",
                method: "POST",
                headers: ["Cookie": "session=private", "Content-Type": "application/json"],
                body: #"{ "roomId": "room-42" }"#,
                bodyKind: .utf8,
                bodyByteCount: 23,
                statusCode: 200,
                responseHeaders: ["Content-Type": "text/html"],
                responseBody: "<html>wire response</html>",
                responseBodyKind: .utf8,
                responseBodyByteCount: 26,
                association: .exact,
                sanitize: true
            )
        )

        #expect(service.entries.count == 500)
        #expect(!service.entries.contains { $0.id == playbackID })
        let snapshot = service.snapshot(sessionID: sessionID)
        #expect(snapshot.filter { $0.kind == .invocation }.count == 2)
        #expect(snapshot.filter { $0.kind == .playerLog }.count == 50)
        #expect(snapshot.filter { $0.kind == .highFrequency }.count == 30)
        let playback = try #require(snapshot.first { $0.id == playbackID })
        #expect(playback.timestamp == occurredAt)
        #expect(playback.requestBody == #"{ "roomId": "room-42", "quality": "source" }"#)
        #expect(playback.responseBody == "<html>original playback response</html>")
        #expect(playback.httpRecords.first?.responseBody == "<html>wire response</html>")
        #expect(playback.httpRecords.first?.url.contains("room=42") == true)
        #expect(playback.httpRecords.first?.url.contains("private") == false)
        #expect(playback.httpRecords.first?.headers["Cookie"] == "<redacted>")
        let retainedHighFrequencyText = snapshot
            .filter { $0.kind == .highFrequency }
            .compactMap { [$0.requestBody, $0.responseBody].compactMap { $0 }.joined() }
            .joined()
        #expect(!retainedHighFrequencyText.contains("private-frame"))
        #expect(!retainedHighFrequencyText.contains("private-user-message"))
        #expect(!retainedHighFrequencyText.contains("private-danmaku-user-content"))
        #expect(retainedHighFrequencyText.contains("binaryByteCount"))
        #expect(retainedHighFrequencyText.contains("messageCount"))

        let omissions = service.omissionSummary(sessionID: sessionID)
        #expect(omissions.entryCount == 0)
        #expect(omissions.playerLogEntryCount == 1_050)
        #expect(omissions.highFrequencyEntryCount == 1_070)

        service.setDiagnosticSessionID(nil)
        let frozenResponse = service.snapshot(sessionID: sessionID)
            .first(where: { $0.id == playbackID })?.responseBody
        service.updateStatus(id: playbackID, status: .error, responseBody: "late callback")
        #expect(service.snapshot(sessionID: sessionID)
            .first(where: { $0.id == playbackID })?.responseBody == frozenResponse)

        let nextSessionID = UUID()
        service.setDiagnosticSessionID(nextSessionID)
        _ = service.log(
            tag: "fixture.plugin",
            method: "late-old-session",
            diagnosticSessionID: sessionID,
            captureCurrentDiagnosticSession: false
        )
        #expect(service.diagnosticEntries.isEmpty)
        let nextID = service.log(tag: "fixture.plugin", method: "getRooms")
        #expect(service.diagnosticEntries.map(\.id) == [nextID])
    }

    @Test("HTTP retention preserves beginning, ending, and failures")
    @MainActor
    func httpRetentionPreservesBoundariesAndFailures() throws {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        defer {
            service.setDiagnosticSessionID(nil)
            service.clear()
        }
        let entryID = service.log(tag: "fixture.plugin", method: "getPlayArgs")
        let context = PluginConsoleHTTPContext(
            parentEntryID: entryID,
            association: .exact,
            candidateEntryIDs: [],
            pluginVersion: nil,
            diagnosticSessionID: sessionID,
            operationID: nil,
            isDiagnosticCapture: true
        )
        for index in 0..<205 {
            service.appendHTTPRecord(
                pluginId: "fixture.plugin",
                context: context,
                record: PluginConsoleHTTPRecord(
                    url: "https://source-a.example.invalid/request-\(index)",
                    method: "GET",
                    headers: [:],
                    startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    statusCode: index == 100 ? 500 : 200,
                    association: .exact,
                    sanitize: true
                )
            )
        }
        let entry = try #require(service.snapshot(sessionID: sessionID).first)
        #expect(entry.httpRecords.count == 200)
        #expect(entry.httpRecords.contains { $0.url.hasSuffix("request-0") })
        #expect(entry.httpRecords.contains { $0.url.hasSuffix("request-100") })
        #expect(entry.httpRecords.contains { $0.url.hasSuffix("request-204") })
        #expect(service.omissionSummary(sessionID: sessionID).httpRecordCount == 5)
    }

    @Test("invocation retention treats HTTP failures as failure evidence")
    @MainActor
    func invocationRetentionKeepsHTTPFailures() {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        defer {
            service.setDiagnosticSessionID(nil)
            service.clear()
        }
        var failedEntryID: UUID?
        for index in 0..<201 {
            let entryID = service.log(tag: "fixture.plugin", method: "call-\(index)")
            service.updateStatus(id: entryID, status: .success)
            if index == 100 {
                failedEntryID = entryID
                service.appendHTTPRecord(
                    pluginId: "fixture.plugin",
                    context: PluginConsoleHTTPContext(
                        parentEntryID: entryID,
                        association: .exact,
                        candidateEntryIDs: [],
                        pluginVersion: nil,
                        diagnosticSessionID: sessionID,
                        operationID: nil,
                        isDiagnosticCapture: true
                    ),
                    record: PluginConsoleHTTPRecord(
                        url: "https://source-a.example.invalid/failure",
                        method: "GET",
                        headers: [:],
                        statusCode: 500,
                        association: .exact,
                        sanitize: true
                    )
                )
            }
        }
        #expect(service.diagnosticEntries.count == 200)
        #expect(service.diagnosticEntries.contains { $0.id == failedEntryID })
        #expect(service.omissionSummary(sessionID: sessionID).entryCount == 1)
    }

    @Test("late bodies stay compact after an active diagnostic entry is evicted")
    @MainActor
    func lateBodiesDoNotReviveEvictedDiagnosticEntry() throws {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        defer {
            service.setDiagnosticSessionID(nil)
            service.clear()
        }

        var pendingEntryID: UUID?
        for index in 0..<201 {
            let entryID = service.log(tag: "fixture.plugin", method: "pending-\(index)")
            if index == 20 {
                pendingEntryID = entryID
            } else {
                service.updateStatus(id: entryID, status: .success)
            }
        }
        let entryID = try #require(pendingEntryID)
        #expect(service.entries.contains { $0.id == entryID })
        #expect(!service.diagnosticEntries.contains { $0.id == entryID })
        let initialSummary = service.omissionSummary(sessionID: sessionID)
        #expect(initialSummary.entryCount == 1)
        #expect(initialSummary.bodyTruncationCount == 0)
        #expect(initialSummary.bodyOmittedByteCount == 0)
        #expect(initialSummary.httpRecordCount == 0)

        let lateResponse = "<html>late business response</html>"
        service.updateStatus(
            id: entryID,
            status: .error,
            duration: 2.5,
            responseBody: lateResponse,
            errorMessage: "late failure"
        )
        var developerEntry = try #require(service.entries.first { $0.id == entryID })
        #expect(developerEntry.status == .error)
        #expect(developerEntry.duration == 2.5)
        #expect(developerEntry.errorMessage == "late failure")
        #expect(developerEntry.responseBody == nil)
        #expect(!service.diagnosticEntries.contains { $0.id == entryID })

        let requestBody = #"{"roomId":"late-room"}"#
        let responseBody = #"{"value":"late-response"}"#
        service.appendHTTPRecord(
            pluginId: "fixture.plugin",
            context: PluginConsoleHTTPContext(
                parentEntryID: entryID,
                association: .exact,
                candidateEntryIDs: [],
                pluginVersion: nil,
                diagnosticSessionID: sessionID,
                operationID: nil,
                isDiagnosticCapture: true
            ),
            record: PluginConsoleHTTPRecord(
                url: "https://source-a.example.invalid/late?room=42",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: requestBody,
                bodyKind: .utf8,
                bodyByteCount: requestBody.utf8.count,
                statusCode: 503,
                responseHeaders: ["Content-Type": "application/json"],
                responseBody: responseBody,
                responseBodyKind: .utf8,
                responseBodyByteCount: responseBody.utf8.count,
                association: .exact,
                sanitize: true
            )
        )
        developerEntry = try #require(service.entries.first { $0.id == entryID })
        let metadata = try #require(developerEntry.httpRecords.first)
        #expect(metadata.statusCode == 503)
        #expect(metadata.url.contains("room=42"))
        #expect(metadata.body == nil)
        #expect(metadata.responseBody == nil)
        #expect(metadata.bodyWasTruncated)
        #expect(metadata.responseBodyWasTruncated)
        #expect(!service.diagnosticEntries.contains { $0.id == entryID })

        let summary = service.omissionSummary(sessionID: sessionID)
        #expect(summary.entryCount == 1)
        #expect(summary.httpRecordCount == 1)
        #expect(summary.bodyTruncationCount == 2)
        #expect(
            summary.bodyOmittedByteCount
                == lateResponse.utf8.count + requestBody.utf8.count + responseBody.utf8.count
        )
    }

    @Test("diagnostic body storage stays within its live memory budget")
    @MainActor
    func liveBodyBudgetIsBounded() {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        defer {
            service.setDiagnosticSessionID(nil)
            service.clear()
        }
        let body = String(repeating: "x", count: SupportDiagnosticSanitizer.maximumBodyBytes)
        for index in 0..<34 {
            let id = service.log(tag: "fixture.plugin", method: "getRooms-\(index)")
            service.updateStatus(id: id, status: .success, responseBody: body)
        }
        let storedBytes = service.diagnosticEntries.reduce(0) {
            $0 + ($1.requestBody?.utf8.count ?? 0) + ($1.responseBody?.utf8.count ?? 0)
        }
        #expect(storedBytes <= 32 * 1_024 * 1_024)
        let summary = service.omissionSummary(sessionID: sessionID)
        #expect(summary.bodyTruncationCount > 0)
        #expect(summary.bodyOmittedByteCount > 0)
        for diagnostic in service.diagnosticEntries {
            let console = service.entries.first { $0.id == diagnostic.id }
            #expect(console?.responseBody == diagnostic.responseBody)
        }
    }

    @Test("ordinary credential-bearing HTTP keeps useful response text without credential literals")
    @MainActor
    func credentialBearingHTTPRetainsRedactedResponse() async throws {
        let service = PluginConsoleService.shared
        service.clear()
        let sessionID = UUID()
        service.setDiagnosticSessionID(sessionID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CredentialEchoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            service.setDiagnosticSessionID(nil)
            service.clear()
        }
        let runtime = JSRuntime(pluginId: "fixture.plugin", session: session)
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              fetch() {
                return Host.http.request({
                  url: "https://credential-echo.invalid/data?room=42",
                  headers: { Authorization: "Bearer fixture-credential-secret" }
                });
              }
            };
            """)
        let entryID = service.log(tag: "fixture.plugin", method: "fetch")
        let context = try #require(service.invocationContext(for: entryID))
        _ = try await runtime.callPluginFunction(name: "fetch", consoleContext: context)

        let entry = try #require(service.snapshot(sessionID: sessionID).first {
            $0.id == entryID
        })
        let record = try #require(entry.httpRecords.first)
        #expect(record.headers["Authorization"] == "<redacted>")
        #expect(record.url.contains("room=42"))
        #expect(record.responseBody?.contains("public-response-marker") == true)
        #expect(record.responseBody?.contains("fixture-credential-secret") == false)
        #expect(record.responseBodyKind == .utf8)
    }
}

private final class CredentialEchoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "credential-echo.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? "missing"
        let body = #"{ "echo": "\#(authorization)", "value": "public-response-marker" }"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
