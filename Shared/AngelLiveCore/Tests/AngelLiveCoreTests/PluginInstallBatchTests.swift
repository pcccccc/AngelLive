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
            #expect(batch.completedCount == visited.count)
            visited.append(id)
            return id == "source-b" ? .failed("network unavailable") : .installed
        }

        #expect(count == 2)
        #expect(visited == ["source-a", "source-b", "source-c"])
        #expect(batch.displayNames == ["source-a": "Source A", "source-b": "Source B"])
        #expect(batch.failedPluginIds == ["source-b"])
        #expect(batch.outcomes["source-b"] == .failed("network unavailable"))
        #expect(batch.completedCount == 3)
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
