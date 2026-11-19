import Foundation
import Observation
import Testing
@testable import AngelLiveCore

@Suite("Plugin install batches")
@MainActor
struct PluginInstallBatchTests {
    @Test("A failed install does not stop the queue or disappear after success")
    func partialFailure() async {
        let batch = PluginInstallBatch()
        var visited: [String] = []

        let count = await batch.run(
            pluginIds: ["source-a", "source-b", "source-c"],
            displayNames: ["source-a": "Source A", "source-b": "Source B"]
        ) { id in
            #expect(batch.isRunning)
            #expect(batch.currentPluginId == id)
            #expect(batch.outcomes.count == visited.count)
            visited.append(id)
            return id == "source-b" ? .failed("network unavailable") : .installed
        }

        #expect(count == 2)
        #expect(visited == ["source-a", "source-b", "source-c"])
        #expect(batch.displayNames == ["source-a": "Source A", "source-b": "Source B"])
        #expect(batch.failedPluginIds == ["source-b"])
        #expect(batch.outcomes["source-b"] == .failed("network unavailable"))
        #expect(batch.outcomes.count == 3)
        #expect(batch.cancelledCount == 0)
        #expect(batch.currentPluginId == nil)
        #expect(!batch.isRunning)
    }

    @Test("Rejecting known login consent cancels the whole snapshot before installation")
    func rejectedConsentDoesNotInstall() async {
        let batch = PluginInstallBatch()
        var consentRequests: [[String]] = []
        var installed: [String] = []

        let count = await batch.run(
            pluginIds: ["source-a", "source-b", "source-c"],
            knownLoginPluginIds: ["source-b", "source-c"],
            requestLoginConsent: { ids in
                consentRequests.append(ids)
                return false
            },
            install: { id in
                installed.append(id)
                return .installed
            }
        )

        #expect(count == 0)
        #expect(consentRequests == [["source-b", "source-c"]])
        #expect(installed.isEmpty)
        #expect(batch.cancelledCount == 3)
        #expect(batch.outcomes.values.allSatisfy { $0 == .cancelled })
    }

    @Test("Approved login consent is requested once before the complete install queue")
    func approvedConsentInstallsCompleteQueue() async {
        let batch = PluginInstallBatch()
        var consentRequests: [[String]] = []
        var installed: [String] = []

        let count = await batch.run(
            pluginIds: ["source-a", "source-b", "source-c"],
            knownLoginPluginIds: ["source-a", "source-c"],
            requestLoginConsent: { ids in
                consentRequests.append(ids)
                return true
            },
            install: { id in
                installed.append(id)
                return .installed
            }
        )

        #expect(count == 3)
        #expect(consentRequests == [["source-a", "source-c"]])
        #expect(installed == ["source-a", "source-b", "source-c"])
        #expect(batch.successCount == 3)
    }

    enum ConsentDecision: CaseIterable {
        case approve, decline, stop
    }

    @Test("Manifest-only login consent is requested once and stopped staging is rolled back", arguments: ConsentDecision.allCases)
    func manifestOnlyLoginConsent(decision: ConsentDecision) async throws {
        let fixture = try ProgressFixture()
        defer { fixture.cleanUp() }
        let stagingRoot = fixture.staging
        let storage = fixture.storage
        let item = fixture.item(path: "plugin.zip")
        let batch = PluginInstallBatch()
        let consent = BatchConsentRecorder { reason in
            #expect(reason == .installingLoginPluginsBatch(plugins: [
                LoginPluginEntry(pluginId: item.id, displayName: item.displayName)
            ]))
            #expect(batch.isRunning)
            #expect(batch.currentPluginId == nil)
            #expect(batch.outcomes.isEmpty)
            #expect(storage.listInstalledVersions(pluginId: item.id).isEmpty)
            #expect(storage.loadState().plugins[item.id]?.lastGoodVersion == nil)
            do {
                let staged = try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
                #expect(staged.count == 1)
                let directory = try #require(staged.first)
                let manifest = try LiveParsePluginManifest.load(from: directory.appendingPathComponent("manifest.json"))
                #expect(manifest.auth?.required == false)
                #expect(manifest.requiresLogin)
            } catch {
                Issue.record(error)
            }
            if decision == .stop { batch.cancel(item.id) }
            return decision != .decline
        }

        let installed = await PluginSourceManager.runInstallBatch(
            batch, candidates: [item], updater: fixture.updater, pluginManager: fixture.pluginManager,
            consentRequester: consent, stagingRoot: stagingRoot
        )

        let approved = decision == .approve
        #expect(consent.requests == 1)
        #expect(!batch.isRunning)
        #expect(batch.currentPluginId == nil)
        #expect(batch.outcomes[item.id] == (approved ? .installed : .cancelled))
        #expect(batch.cancelledCount == (approved ? 0 : 1))
        #expect(installed == (approved ? 1 : 0))
        #expect(item.installState == (approved ? .installed : .notInstalled))
        #expect(!FileManager.default.fileExists(atPath: stagingRoot.path))
        #expect(storage.listInstalledVersions(pluginId: item.id).count == (approved ? 1 : 0))
        #expect(storage.loadState().plugins[item.id]?.lastGoodVersion == (approved ? item.item.version : nil))
    }

    @Test("Duplicate identifiers and reentrant starts cannot install twice")
    func deduplicationAndReentrancy() async {
        let batch = PluginInstallBatch()
        var visited: [String] = []

        await batch.run(pluginIds: ["source-a", "source-a", "source-b"]) { id in
            visited.append(id)
            let duplicate = await batch.run(pluginIds: ["source-c"]) { _ in
                Issue.record("A second batch must not execute while the first is active")
                return .installed
            }
            #expect(duplicate == 0)
            return .installed
        }

        #expect(visited == ["source-a", "source-b"])
        #expect(batch.pluginIds == visited)
    }

    @Test("Retrying explicit failures does not repeat successful installs")
    func retryFailures() async {
        let batch = PluginInstallBatch()
        await batch.run(pluginIds: ["source-a", "source-b"]) { id in
            id == "source-b" ? .failed("timeout") : .installed
        }

        var retried: [String] = []
        await batch.run(pluginIds: batch.failedPluginIds) { id in
            retried.append(id)
            return .installed
        }

        #expect(retried == ["source-b"])
        #expect(batch.pluginIds == ["source-b"])
        #expect(batch.successCount == 1)
        #expect(batch.failedPluginIds.isEmpty)
    }

    @Test("Cancellation stops pending installs and preserves completed results")
    func cancellation() async {
        let batch = PluginInstallBatch()
        var visited: [String] = []
        let operation = Task { @MainActor in
            await batch.run(pluginIds: ["source-a", "source-b", "source-c"]) { id in
                visited.append(id)
                withUnsafeCurrentTask { $0?.cancel() }
                return .installed
            }
        }

        _ = await operation.value
        #expect(visited == ["source-a"])
        #expect(batch.outcomes["source-a"] == .installed)
        #expect(batch.outcomes["source-b"] == .cancelled)
        #expect(batch.outcomes["source-c"] == .cancelled)
        #expect(batch.cancelledCount == 2)
        #expect(!batch.isRunning)
    }

    @Test("A cancelled install result stops and cancels the remaining queue")
    func cancelledResultStopsQueue() async {
        let batch = PluginInstallBatch()
        var visited: [String] = []

        await batch.run(pluginIds: ["source-a", "source-b", "source-c"]) { id in
            visited.append(id)
            return id == "source-b" ? .cancelled : .installed
        }

        #expect(visited == ["source-a", "source-b"])
        #expect(batch.outcomes["source-a"] == .installed)
        #expect(batch.outcomes["source-b"] == .cancelled)
        #expect(batch.outcomes["source-c"] == .cancelled)
        #expect(batch.cancelledCount == 2)
    }

    @Test("Batch count includes only unfinished selections after deduplication and individual stops")
    func remainingCount() async {
        let manager = PluginSourceManager()
        #expect(manager.activeInstallationCount == 0)
        let ids = ["source-a", "source-a", "source-b", "source-c"]
        var visited: [String] = []
        await manager.installBatch.run(pluginIds: ids) { id in
            visited.append(id)
            if id == "source-a" {
                #expect(manager.activeInstallationCount == 3)
                manager.cancelInstallation(pluginId: "source-b")
                #expect(manager.activeInstallationCount == 2)
                manager.cancelInstallation(pluginId: id)
                #expect(Task.isCancelled)
                return .cancelled
            }
            #expect(manager.activeInstallationCount == 1)
            return .installed
        }
        #expect(visited == ["source-a", "source-c"])
        #expect(manager.installBatch.outcomes == ["source-a": .cancelled, "source-b": .cancelled, "source-c": .installed])
        #expect(manager.activeInstallationCount == 0)

        visited.removeAll()
        await manager.updateBatch.run(pluginIds: ids) { id in
            visited.append(id)
            if id == "source-a" {
                #expect(manager.activeInstallationCount == 3)
                manager.cancelInstallation(pluginId: "source-b")
                #expect(manager.activeInstallationCount == 2)
                manager.cancelInstallation(pluginId: id)
                #expect(Task.isCancelled)
                return .cancelled
            }
            #expect(manager.activeInstallationCount == 1)
            return .updated
        }
        #expect(visited == ["source-a", "source-c"])
        #expect(manager.updateBatch.outcomes == ["source-a": .cancelled, "source-b": .cancelled, "source-c": .updated])
        #expect(manager.activeInstallationCount == 0)
    }

    @Test("Download samples use actual bytes and unknown lengths stay indeterminate", arguments: [true, false])
    func byteProgress(hasLength: Bool) async throws {
        let fixture = try ProgressFixture()
        defer { fixture.cleanUp() }
        let progress = ProgressRecorder()
        let item = fixture.item(path: hasLength ? "known.zip" : "unknown.zip")

        let manifest = try await fixture.updater.install(item: item.item, stagingDirectory: fixture.staging) {
            progress.values.append($0)
        }
        try await fixture.updater.activateStaged(
            manifest: manifest, directory: fixture.staging, manager: fixture.pluginManager
        ) { progress.values.append($0) }

        #expect(progress.values.first == .downloading(nil))
        #expect(progress.values.suffix(2).elementsEqual([.verifyingAndExtracting, .activating]))
        let downloadFractions = progress.values.dropLast(2).compactMap(\.fractionCompleted)
        if hasLength {
            #expect(downloadFractions.last == 1)
            #expect(downloadFractions.allSatisfy { (0...1).contains($0) })
            #expect(downloadFractions == downloadFractions.sorted())
        } else {
            #expect(downloadFractions.isEmpty)
        }
        #expect(fixture.storage.loadState().plugins[item.id]?.lastGoodVersion == item.item.version)
    }

    @Test("Per-plugin progress rejects decreasing fractions and clears on completion")
    func monotonicProgress() {
        let id = "fixture.plugin"
        let progress = PluginInstallationProgressStore()
        progress.report(.downloading(0.2), for: id)
        #expect(progress.values[id]?.fractionCompleted == 0.2)
        progress.report(.downloading(0.7), for: id)
        progress.report(.downloading(0.5), for: id)
        #expect(progress.values[id]?.fractionCompleted == 0.7)
        progress.report(.verifyingAndExtracting, for: id)
        progress.report(.activating, for: id)
        #expect(progress.values[id]?.fractionCompleted == 1)
        progress.clear(for: id)
        #expect(progress.values[id] == nil)
    }

    @Test("Stopping a partial download cancels URLSession and resets only that plugin")
    func cancelDownload() async throws {
        let fixture = try ProgressFixture(stalledDownload: true)
        defer { fixture.cleanUp() }
        let stopped = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        LoginArchiveURLProtocol.onStalledStop = stopped.continuation
        defer {
            LoginArchiveURLProtocol.onStalledStop = nil
            stopped.continuation.finish()
        }
        let item = fixture.item(path: "stalled.zip")
        let batch = PluginInstallBatch()
        let progress = PluginInstallationProgressStore()
        let changes = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { changes.continuation.finish() }
        let operation = Task {
            await PluginSourceManager.runInstallBatch(
                batch, candidates: [item], updater: fixture.updater, pluginManager: fixture.pluginManager,
                consentRequester: nil, progress: progress, stagingRoot: fixture.staging
            )
        }
        var stoppedDuringDownload = false
        var nextChange = changes.stream.makeAsyncIterator()
        while true {
            let (stage, outcome) = withObservationTracking {
                (progress.values[item.id], batch.outcomes[item.id])
            } onChange: {
                changes.continuation.yield(())
            }
            if case .downloading(let fraction?) = stage, fraction > 0 {
                #expect(fraction == 0.5)
                #expect(batch.remainingCount == 1)
                batch.cancel(item.id)
                stoppedDuringDownload = true
                break
            }
            if outcome != nil { break }
            guard await nextChange.next() != nil else { break }
        }
        let installed = await operation.value
        try #require(stoppedDuringDownload)
        var stopEvents = stopped.stream.makeAsyncIterator()
        #expect(await stopEvents.next() != nil)
        #expect(installed == 0)
        #expect(batch.outcomes[item.id] == .cancelled)
        #expect(!batch.isRunning)
        #expect(batch.remainingCount == 0)
        #expect(progress.values.isEmpty)
        #expect(item.installState == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.staging.path))
        #expect(fixture.storage.listInstalledVersions(pluginId: item.id).isEmpty)
        #expect(fixture.storage.loadState().plugins[item.id]?.lastGoodVersion == nil)
    }

    @Test("Candidate selection cannot widen an explicit source scope")
    func candidateSelectionHonorsScopeAndState() {
        let requested = makeItem(id: "source-a")
        let outsideScope = makeItem(id: "source-b")
        let failed = makeItem(id: "source-c")
        failed.installState = .failed("retryable")
        let installed = makeItem(id: "source-d")
        installed.installState = .notInstalled
        let inFlight = makeItem(id: "source-e")
        inFlight.installState = .installing

        let candidates = PluginSourceManager.installCandidates(
            pluginIds: ["source-c", "source-a", "source-c", "source-d", "source-e", "missing"],
            remotePlugins: [outsideScope, requested, failed, installed, inFlight],
            isInstalled: { $0 == "source-d" }
        )

        #expect(candidates.map(\.id) == ["source-c", "source-a"])
    }

    @Test("A scoped catalog keeps the selected source item for duplicate plugin identifiers")
    func scopedCatalogUsesConcreteSourceItem() throws {
        let sourceAURL = "https://source-a.example.invalid/index.json"
        let sourceBURL = "https://source-b.example.invalid/index.json"
        let sourceA = makeItem(
            id: "fixture.plugin",
            version: "1.0.0",
            zipURL: "https://source-a.example.invalid/plugin.zip"
        )
        let sourceB = makeItem(
            id: "fixture.plugin",
            version: "2.0.0",
            zipURL: "https://source-b.example.invalid/plugin.zip"
        )

        let catalog = PluginSourceManager.resolveCatalogPlugins(
            sourceURLs: [sourceBURL],
            allPlugins: [sourceA],
            sourceHealth: [
                sourceAURL: .healthy(pluginCount: 1),
                sourceBURL: .healthy(pluginCount: 1),
            ],
            sourceRemotePlugins: [sourceAURL: [sourceA], sourceBURL: [sourceB]]
        )
        let selected = try #require(PluginSourceManager.installCandidates(
            pluginIds: ["fixture.plugin"],
            remotePlugins: catalog,
            isInstalled: { _ in false }
        ).first)

        #expect(catalog.count == 1)
        #expect(catalog.first === sourceB)
        #expect(selected === sourceB)
        #expect(selected.item.version == "2.0.0")
        #expect(selected.item.zipURL == "https://source-b.example.invalid/plugin.zip")
    }

    @Test("Unknown and failed source scopes do not fall back to the all-source catalog")
    func unhealthyScopeDoesNotFallBack() {
        let healthyURL = "https://source-a.example.invalid/index.json"
        let failedURL = "https://source-b.example.invalid/index.json"
        let allSourceItem = makeItem(id: "fixture.plugin")
        let failedSourceItem = makeItem(
            id: "fixture.plugin",
            version: "2.0.0",
            zipURL: "https://source-b.example.invalid/plugin.zip"
        )

        let catalog = PluginSourceManager.resolveCatalogPlugins(
            sourceURLs: ["https://unknown.example.invalid/index.json", failedURL],
            allPlugins: [allSourceItem],
            sourceHealth: [
                healthyURL: .healthy(pluginCount: 1),
                failedURL: .failed("unavailable"),
            ],
            sourceRemotePlugins: [healthyURL: [allSourceItem], failedURL: [failedSourceItem]]
        )

        #expect(catalog.isEmpty)
    }

    private func makeItem(
        id: String,
        version: String = "1.0.0",
        zipURL: String? = nil
    ) -> RemotePluginDisplayItem {
        RemotePluginDisplayItem(item: LiveParseRemotePluginItem(
            pluginId: id,
            version: version,
            zipURL: zipURL ?? "https://\(id).example.invalid/plugin.zip",
            sha256: String(repeating: "0", count: 64)
        ))
    }
}

@MainActor
private final class ProgressRecorder {
    var values: [PluginInstallationProgress] = []
}

private struct ProgressFixture {
    let root: URL
    let staging: URL
    let storage: LiveParsePluginStorage
    let session: URLSession
    let updater: LiveParsePluginUpdater
    let pluginManager: LiveParsePluginManager

    init(stalledDownload: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        staging = root.appendingPathComponent("staging", isDirectory: true)
        storage = try LiveParsePluginStorage(baseDirectory: root.appendingPathComponent("storage", isDirectory: true))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginArchiveURLProtocol.self]
        // Bound the deliberately stalled fixture if cancellation regresses.
        if stalledDownload { configuration.timeoutIntervalForResource = 5 }
        session = URLSession(configuration: configuration)
        updater = LiveParsePluginUpdater(storage: storage, session: session)
        pluginManager = LiveParsePluginManager(storage: storage, session: session)
    }

    func item(path: String) -> RemotePluginDisplayItem {
        RemotePluginDisplayItem(item: LiveParseRemotePluginItem(
            pluginId: "fixture.plugin", version: "1.0.0",
            zipURL: "https://source.example.invalid/\(path)",
            sha256: updater.sha256Hex(LoginArchiveURLProtocol.archive), auth: ManifestAuth(required: false)
        ))
    }

    func cleanUp() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class BatchConsentRecorder: PluginInstallConsentRequesting {
    private(set) var requests = 0
    private let decide: (PluginInstallConsentReason) -> Bool

    init(decide: @escaping (PluginInstallConsentReason) -> Bool) {
        self.decide = decide
    }

    func requestConsent(reason: PluginInstallConsentReason) async -> Bool {
        requests += 1
        return decide(reason)
    }
}

private final class LoginArchiveURLProtocol: URLProtocol {
    @MainActor static var onStalledStop: AsyncStream<Void>.Continuation?

    static let archive = Data(base64Encoded: """
    UEsDBBQAAAAIAAAAIQBGHbW+vgAAACkBAAANAAAAbWFuaWZlc3QuanNvbm2QPQ+CMBCGd3/GzaTo
    yooxMXHyazEMjRxwerSlLagx/HdbiItxvOfej8u9wXBfk9qWkEFFT99bFDOCBAa0jrQKq5VYimUg
    0tD5C1cJMA14fBl0kF1+7UUCqLx9BfdMxM3FhN43kL3BYteTxdBbSXY4hjAdRBvWj7iehtN+F9yN
    98ZlaTohgU/ZGkZBapBMZUi8an0nXOtWkpoO+S8s5u4D1UpyPnmiuvg2541kRlVjrL+Tih/p7FWX
    COO4+ABQSwMEFAAAAAgAAAAhACqmckArAAAAKQAAAAkAAABwbHVnaW4uanMrSyxS8MksSw1ILCpO
    DcgpTc/MU7BVqFZILMgMSy0qzszPs1IwVKi15gIAUEsBAhQDFAAAAAgAAAAhAEYdtb6+AAAAKQEA
    AA0AAAAAAAAAAAAAAIABAAAAAG1hbmlmZXN0Lmpzb25QSwECFAMUAAAACAAAACEAKqZyQCsAAAAp
    AAAACQAAAAAAAAAAAAAAgAHpAAAAcGx1Z2luLmpzUEsFBgAAAAACAAIAcgAAADsBAAAAAA==
    """, options: .ignoreUnknownCharacters)!

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "source.example.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stalled = url.lastPathComponent == "stalled.zip"
        let stalledLength = 256 * 1024
        let headers = stalled || url.lastPathComponent == "known.zip"
            ? ["Content-Length": String(stalled ? stalledLength : Self.archive.count)] : nil
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // CFNetwork buffers small writes, so emit a large incomplete body
        // for the in-flight cancellation assertion.
        client?.urlProtocol(self, didLoad: stalled ? Data(repeating: 0, count: stalledLength / 2) : Self.archive)
        guard !stalled else { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard request.url?.lastPathComponent == "stalled.zip" else { return }
        Task { @MainActor in Self.onStalledStop?.yield(()) }
    }
}
