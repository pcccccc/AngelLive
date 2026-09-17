import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin runtime diagnostics", .serialized)
struct PluginRuntimeDiagnosticsTests {
    @Test("overlapping HTTP completions remain attached to their initiating calls")
    @MainActor
    func overlappingHTTPKeepsExactParent() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              first() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/first" });
              },
              second() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/second" });
              }
            };
            """)

        let firstContext = await fixture.makeContext(method: "first")
        let secondContext = await fixture.makeContext(method: "second")
        async let first: Void = invoke(
            fixture.runtime,
            name: "first",
            context: firstContext
        )
        async let second: Void = invoke(
            fixture.runtime,
            name: "second",
            context: secondContext
        )
        try await first
        try await second

        let entries = PluginConsoleService.shared.snapshot(sessionID: fixture.sessionID)
        let firstEntry = try #require(entries.first { $0.id == firstContext.entryID })
        let secondEntry = try #require(entries.first { $0.id == secondContext.entryID })
        #expect(firstEntry.httpRecords.count == 1)
        #expect(secondEntry.httpRecords.count == 1)
        #expect(firstEntry.httpRecords[0].url.hasSuffix("/first"))
        #expect(secondEntry.httpRecords[0].url.hasSuffix("/second"))
        #expect(firstEntry.httpRecords[0].association == .exact)
        #expect(secondEntry.httpRecords[0].association == .exact)
    }

    @Test("a cancelled call cannot redirect its late HTTP response to a newer call")
    @MainActor
    func cancelledCallKeepsFrozenHTTPParent() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              first() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/first" });
              },
              second() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/second" });
              }
            };
            """)

        let cancelledContext = await fixture.makeContext(method: "first")
        let cancelledTask = Task {
            try await invoke(fixture.runtime, name: "first", context: cancelledContext)
        }
        await waitForPendingPromiseCount(1, runtime: fixture.runtime)
        cancelledTask.cancel()
        _ = try? await cancelledTask.value

        let newerContext = await fixture.makeContext(method: "second")
        try await invoke(fixture.runtime, name: "second", context: newerContext)
        await waitForHTTPRecord(entryID: cancelledContext.entryID)

        let entries = PluginConsoleService.shared.snapshot(sessionID: fixture.sessionID)
        let cancelledEntry = try #require(entries.first { $0.id == cancelledContext.entryID })
        let newerEntry = try #require(entries.first { $0.id == newerContext.entryID })
        #expect(cancelledEntry.httpRecords.count == 1)
        #expect(newerEntry.httpRecords.count == 1)
        #expect(cancelledEntry.httpRecords[0].url.hasSuffix("/first"))
        #expect(newerEntry.httpRecords[0].url.hasSuffix("/second"))
    }

    @Test("HTTP started after a Promise suspension is retained without guessed attribution")
    @MainActor
    func delayedHTTPUsesStandaloneUncertainEntry() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              delayedFirst() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/gate-first" }).then(function () {
                  return Host.http.request({ url: "https://runtime-diagnostics.invalid/delayed-first" });
                });
              },
              delayedSecond() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/gate-second" }).then(function () {
                  return Host.http.request({ url: "https://runtime-diagnostics.invalid/delayed-second" });
                });
              }
            };
            """)

        let firstContext = await fixture.makeContext(method: "delayedFirst")
        let secondContext = await fixture.makeContext(method: "delayedSecond")
        async let first: Void = invoke(
            fixture.runtime,
            name: "delayedFirst",
            context: firstContext
        )
        async let second: Void = invoke(
            fixture.runtime,
            name: "delayedSecond",
            context: secondContext
        )
        try await first
        try await second

        let entries = PluginConsoleService.shared.snapshot(sessionID: fixture.sessionID)
        let parents = entries.filter { [firstContext.entryID, secondContext.entryID].contains($0.id) }
        let standalone = entries.filter { $0.method == "Host.http" }
        #expect(parents.allSatisfy { $0.httpRecords.count == 1 })
        #expect(parents.allSatisfy { $0.httpRecords[0].association == .exact })
        #expect(standalone.count == 2)
        #expect(standalone.allSatisfy { $0.httpRecords.first?.association == .uncertain })
        #expect(standalone.allSatisfy { $0.httpRecords.first?.candidateEntryIDs.isEmpty == false })
    }

    @Test("mixed diagnostic sessions never fall back to the newer session")
    @MainActor
    func mixedSessionsRemainUnassigned() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              never() { return new Promise(function () {}); },
              http() {
                return Host.http.request({
                  url: "https://runtime-diagnostics.invalid/mixed?token=fixture-secret"
                });
              }
            };
            """)

        let oldContext = await fixture.makeContext(method: "oldNever")
        let oldTask = Task {
            try await invoke(fixture.runtime, name: "never", context: oldContext)
        }
        await waitForPendingPromiseCount(1, runtime: fixture.runtime)

        let newSessionID = UUID()
        PluginConsoleService.shared.setDiagnosticSessionID(newSessionID)
        let newContext = await fixture.makeContext(method: "newNever")
        let newTask = Task {
            try await invoke(fixture.runtime, name: "never", context: newContext)
        }
        await waitForPendingPromiseCount(2, runtime: fixture.runtime)

        _ = try await fixture.runtime.callPluginFunction(name: "http")

        oldTask.cancel()
        newTask.cancel()
        _ = try? await oldTask.value
        _ = try? await newTask.value

        let standalone = try #require(
            PluginConsoleService.shared.entries.first { $0.method == "Host.http" }
        )
        let record = try #require(standalone.httpRecords.first)
        #expect(standalone.diagnosticSessionID == nil)
        #expect(record.association == .uncertain)
        #expect(Set(record.candidateEntryIDs) == Set([oldContext.entryID, newContext.entryID]))
        #expect(!record.url.contains("fixture-secret"))
        #expect(
            PluginConsoleService.shared.omissionSummary(sessionID: fixture.sessionID)
                .unassignedHTTPRecordCount == 1
        )
        #expect(
            PluginConsoleService.shared.omissionSummary(sessionID: newSessionID)
                .unassignedHTTPRecordCount == 1
        )
    }

    @Test("synchronous and Promise errors retain safe JavaScript stacks")
    @MainActor
    func exceptionsRetainSnapshots() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              syncFailure() {
                const error = new TypeError("sync failure marker");
                error.sourceURL = "https://login.example.invalid/plugin.js?token=fixture-secret";
                error.line = 41;
                error.column = 9;
                throw error;
              },
              promiseFailure() {
                return Promise.resolve().then(function promiseStep() {
                  throw new Error("promise failure marker");
                });
              }
            };
            """)

        let syncContext = await fixture.makeContext(method: "syncFailure")
        await #expect(throws: LiveParsePluginError.self) {
            _ = try await fixture.runtime.callPluginFunction(
                name: "syncFailure",
                consoleContext: syncContext
            )
        }
        let promiseContext = await fixture.makeContext(method: "promiseFailure")
        await #expect(throws: LiveParsePluginError.self) {
            _ = try await fixture.runtime.callPluginFunction(
                name: "promiseFailure",
                consoleContext: promiseContext
            )
        }

        let entries = PluginConsoleService.shared.snapshot(sessionID: fixture.sessionID)
        let syncException = try #require(entries.first { $0.id == syncContext.entryID }?.exception)
        let promiseException = try #require(entries.first { $0.id == promiseContext.entryID }?.exception)
        #expect(syncException.name == "TypeError")
        #expect(syncException.message.contains("sync failure marker"))
        #expect(syncException.stack?.contains("syncFailure") == true)
        #expect(syncException.sourceURL?.contains("fixture-secret") == false)
        #expect(syncException.line == 41)
        #expect(syncException.column == 9)
        #expect(promiseException.message.contains("promise failure marker"))
        #expect(promiseException.stack?.contains("promiseStep") == true)
    }

    @Test("HTTP bodies report truncation and sensitive calls retain omission")
    @MainActor
    func bodyMetadataAndSensitiveProtection() async throws {
        let fixture = try await RuntimeDiagnosticFixture()
        defer { fixture.resetConsole() }
        try await fixture.runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              longBody() {
                return Host.http.request({ url: "https://runtime-diagnostics.invalid/long" });
              },
              sensitive() {
                return Host.http.request({
                  url: "https://runtime-diagnostics.invalid/sensitive?token=fixture-secret",
                  method: "POST",
                  headers: { Authorization: "Bearer fixture-secret" },
                  body: "fixture-secret"
                });
              }
            };
            """)

        let longContext = await fixture.makeContext(method: "longBody")
        _ = try await fixture.runtime.callPluginFunction(
            name: "longBody",
            consoleContext: longContext
        )

        let sensitiveContext = await fixture.makeContext(method: "sensitive")
        await fixture.runtime.beginSensitiveLoggingSuppression()
        _ = try await fixture.runtime.callPluginFunction(
            name: "sensitive",
            consoleContext: sensitiveContext
        )
        await fixture.runtime.endSensitiveLoggingSuppression()

        let entries = PluginConsoleService.shared.snapshot(sessionID: fixture.sessionID)
        let longRecord = try #require(entries.first { $0.id == longContext.entryID }?.httpRecords.first)
        #expect(longRecord.responseBodyKind == .utf8)
        #expect(longRecord.responseBodyByteCount == 20_000)
        #expect(longRecord.responseBodyWasTruncated)
        #expect((longRecord.responseBody?.utf8.count ?? 0) <= 16_500)

        let sensitiveRecord = try #require(entries.first { $0.id == sensitiveContext.entryID }?.httpRecords.first)
        #expect(sensitiveRecord.headers.isEmpty)
        #expect(sensitiveRecord.body == nil)
        #expect(sensitiveRecord.bodyKind == .omittedSensitive)
        let encoded = try JSONEncoder().encode(sensitiveRecord)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("fixture-secret"))
    }
}

@MainActor
private final class RuntimeDiagnosticFixture {
    let sessionID = UUID()
    let runtime: JSRuntime
    private let session: URLSession

    init() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeDiagnosticsURLProtocol.self]
        session = URLSession(configuration: configuration)
        runtime = JSRuntime(pluginId: "fixture.plugin", session: session)
        PluginConsoleService.shared.clear()
        PluginConsoleService.shared.setDiagnosticSessionID(sessionID)
    }

    func makeContext(method: String) async -> PluginConsoleInvocationContext {
        let entryID = PluginConsoleService.shared.log(
            tag: "fixture.plugin",
            method: method,
            pluginVersion: "1.2.3",
            operationID: UUID()
        )
        return PluginConsoleService.shared.invocationContext(for: entryID)!
    }

    func resetConsole() {
        session.invalidateAndCancel()
        PluginConsoleService.shared.setDiagnosticSessionID(nil)
        PluginConsoleService.shared.clear()
    }
}

private final class RuntimeDiagnosticsURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "runtime-diagnostics.invalid"
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
                headerFields: ["Content-Type": "application/octet-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == "/first" {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let data: Data
        if url.path == "/long" {
            data = Data(repeating: 0x61, count: 20_000)
        } else {
            data = Data("{\"ok\":true}".utf8)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func invoke(
    _ runtime: JSRuntime,
    name: String,
    context: PluginConsoleInvocationContext
) async throws {
    _ = try await runtime.callPluginFunction(name: name, consoleContext: context)
}

private func waitForPendingPromiseCount(_ expected: Int, runtime: JSRuntime) async {
    for _ in 0..<1_000 {
        if await runtime.pendingPromiseCallCountForTesting() == expected { return }
        await Task.yield()
    }
}

@MainActor
private func waitForHTTPRecord(entryID: UUID) async {
    for _ in 0..<100 {
        if PluginConsoleService.shared.entries
            .first(where: { $0.id == entryID })?
            .httpRecords.isEmpty == false {
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
