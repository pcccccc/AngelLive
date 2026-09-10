import Testing
@testable import AngelLiveCore

@Suite("Plugin update batches")
@MainActor
struct PluginUpdateBatchTests {
    @Test("A failed update does not stop the queue or disappear after success")
    func partialFailure() async {
        let batch = PluginUpdateBatch()
        var visited: [String] = []
        let count = await batch.run(pluginIds: ["source-a", "source-b", "source-c"]) { id in
            #expect(batch.isRunning)
            #expect(batch.currentPluginId == id)
            #expect(batch.completedCount == visited.count)
            visited.append(id)
            return id == "source-b" ? .failed("network unavailable") : .updated
        }
        #expect(count == 2)
        #expect(visited == ["source-a", "source-b", "source-c"])
        #expect(batch.failedPluginIds == ["source-b"])
        #expect(batch.outcomes["source-b"] == .failed("network unavailable"))
        #expect(batch.completedCount == 3)
        #expect(batch.currentPluginId == nil)
        #expect(!batch.isRunning)
    }

    @Test("Duplicate identifiers and reentrant starts cannot run an update twice")
    func deduplicationAndReentrancy() async {
        let batch = PluginUpdateBatch()
        var visited: [String] = []
        await batch.run(pluginIds: ["source-a", "source-a", "source-b"]) { id in
            visited.append(id)
            let duplicate = await batch.run(pluginIds: ["source-c"]) { _ in
                Issue.record("A second batch must not execute while the first is active")
                return .updated
            }
            #expect(duplicate == 0)
            return .updated
        }
        #expect(visited == ["source-a", "source-b"])
        #expect(batch.pluginIds == visited)
    }

    @Test("Retrying the failed set does not repeat successful updates")
    func retryFailures() async {
        let batch = PluginUpdateBatch()
        await batch.run(pluginIds: ["source-a", "source-b"]) { id in
            id == "source-b" ? .failed("timeout") : .updated
        }
        var retried: [String] = []
        await batch.run(pluginIds: batch.failedPluginIds) { id in
            retried.append(id)
            return .updated
        }
        #expect(retried == ["source-b"])
        #expect(batch.successCount == 1)
        #expect(batch.failedPluginIds.isEmpty)
    }

    @Test("An empty request preserves the previous result")
    func emptyRequest() async {
        let batch = PluginUpdateBatch()
        await batch.run(pluginIds: ["fixture.plugin"]) { _ in .updated }
        let count = await batch.run(pluginIds: []) { _ in
            Issue.record("Empty batches must not call the updater")
            return .updated
        }
        #expect(count == 0)
        #expect(batch.outcomes == ["fixture.plugin": .updated])
    }

    @Test("Cancellation stops pending work and releases the running state")
    func cancellation() async {
        let batch = PluginUpdateBatch()
        var visited: [String] = []
        let operation = Task { @MainActor in
            await batch.run(pluginIds: ["source-a", "source-b", "source-c"]) { id in
                visited.append(id)
                withUnsafeCurrentTask { $0?.cancel() }
                return .updated
            }
        }
        _ = await operation.value
        #expect(visited == ["source-a"])
        #expect(batch.outcomes["source-a"] == .updated)
        #expect(batch.outcomes["source-b"] == .cancelled)
        #expect(batch.outcomes["source-c"] == .cancelled)
        #expect(!batch.isRunning)
        #expect(batch.currentPluginId == nil)
    }

    @Test("A cancelled updater result stops the remaining queue")
    func cancelledResult() async {
        let batch = PluginUpdateBatch()
        var visited: [String] = []
        await batch.run(pluginIds: ["source-a", "source-b"]) { id in
            visited.append(id)
            batch.clearResult()
            #expect(batch.pluginIds.count == 2)
            return .cancelled
        }
        #expect(visited == ["source-a"])
        #expect(batch.outcomes.values.allSatisfy { $0 == .cancelled })
        batch.clearResult()
        #expect(batch.pluginIds.isEmpty)
        #expect(batch.outcomes.isEmpty)
    }
}
