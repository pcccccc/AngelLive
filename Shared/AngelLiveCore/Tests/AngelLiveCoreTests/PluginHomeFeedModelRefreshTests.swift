import Foundation
import Testing
@testable import AngelLiveCore

@Suite(.serialized)
struct PluginHomeFeedModelRefreshTests {
    @Test("fresh matching cache skips automatic fetch while force refreshes")
    @MainActor
    func ttlAndForce() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let feed = makeModelFeed(pluginId: "source-a", ttl: 60)
        #expect(await fixture.store.save(
            [feed], contextRevisions: ["source-a": "r1"],
            fetchedAtByPluginId: ["source-a": clock.addingTimeInterval(-30)]
        ))
        let counter = FetchCounter(response: try responseDTO())
        let model = makeModel(fixture: fixture, counter: counter, now: clock, ids: ["source-a"])

        await model.refresh(installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r1"]))
        #expect(await counter.count == 0)
        #expect(model.pluginStates["source-a"] == .cached)

        await model.refresh(
            installedPluginIds: ["source-a"],
            context: .init(pluginRevisions: ["source-a": "r1"]),
            force: true
        )
        #expect(await counter.count == 1)
    }

    @Test("expired cache refreshes and a changed plugin revision retires the old result")
    @MainActor
    func expiryAndGenerationGuard() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let feed = makeModelFeed(pluginId: "source-a", ttl: 60)
        #expect(await fixture.store.save(
            [feed], contextRevisions: ["source-a": "r1"],
            fetchedAtByPluginId: ["source-a": clock.addingTimeInterval(-61)]
        ))
        let gate = FetchGate()
        let service = PluginHomeFeedService { pluginId, _ in try await gate.fetch(pluginId: pluginId) }
        let model = PluginHomeFeedModel(
            service: service, cacheStore: fixture.store, now: { clock },
            platformProvider: { _ in [platform("source-a")] }
        )

        let first = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r1"])
        ) }
        await gate.waitForStarted(1)
        let second = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r2"])
        ) }
        await gate.waitForStarted(2)
        await gate.resume(call: 1, response: try responseDTO(revision: "old"))
        await gate.resume(call: 2, response: try responseDTO(revision: "new"))
        await first.value
        await second.value

        #expect(model.bannerEntries.first?.banner.title == "new")
    }

    @Test("same snapshot joins one round and fetch concurrency is capped at three")
    @MainActor
    func joiningAndConcurrencyLimit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = FetchGate()
        let ids = (1...5).map { "source-\($0)" }
        let service = PluginHomeFeedService { pluginId, _ in try await gate.fetch(pluginId: pluginId) }
        let model = PluginHomeFeedModel(
            service: service, cacheStore: fixture.store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            platformProvider: { _ in ids.map(platform) }
        )
        let context = PluginHomeFeedRefreshContext(pluginRevisions: Dictionary(
            uniqueKeysWithValues: ids.map { ($0, "r1") }
        ))

        let first = Task { await model.refresh(installedPluginIds: ids, context: context) }
        let joined = Task { await model.refresh(installedPluginIds: ids, context: context) }
        await gate.waitForStarted(3)
        #expect(await gate.maximumActive == 3)
        #expect(await gate.startedCount == 3)
        await gate.resumeAll(response: try responseDTO())
        await gate.waitForStarted(5)
        await gate.resumeAll(response: try responseDTO())
        await first.value
        await joined.value
        #expect(await gate.startedCount == 5)
        #expect(await gate.maximumActive == 3)
    }

    @Test("partial failure preserves successful content and compatibility failure names")
    @MainActor
    func partialFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = PluginHomeFeedService { pluginId, _ in
            if pluginId == "source-b" { throw FixtureError.failed }
            return try responseDTO(revision: pluginId)
        }
        let model = PluginHomeFeedModel(
            service: service, cacheStore: fixture.store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            platformProvider: { _ in [platform("source-a"), platform("source-b")] }
        )

        await model.refresh(installedPluginIds: ["source-a", "source-b"])

        #expect(model.bannerEntries.map(\.pluginId) == ["source-a"])
        #expect(model.pluginStates["source-a"] == .cached)
        guard case .failed = model.pluginStates["source-b"] else {
            Issue.record("Expected source-b failure state")
            return
        }
        #expect(model.failedPluginNames == ["source-b"])
    }

    @Test("non-cooperative retired fetch blocks newer rounds and only latest context starts")
    @MainActor
    func nonCooperativeRetirementSerializesRapidContexts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = FetchGate(honorsCancellation: false)
        let model = PluginHomeFeedModel(
            service: PluginHomeFeedService { pluginId, _ in try await gate.fetch(pluginId: pluginId) },
            cacheStore: fixture.store, now: { Date(timeIntervalSince1970: 2_000_000_000) },
            platformProvider: { _ in [platform("source-a")] }
        )

        let first = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r1"])
        ) }
        await gate.waitForStarted(1)
        let superseded = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r2"])
        ) }
        await Task.yield()
        let latest = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r3"])
        ) }
        await Task.yield()
        #expect(await gate.startedCount == 1)

        await gate.resume(call: 1, response: try responseDTO(revision: "retired"))
        await gate.waitForStarted(2)
        #expect(await gate.startedCount == 2)
        await gate.resume(call: 2, response: try responseDTO(revision: "latest"))
        await first.value
        await superseded.value
        await latest.value

        #expect(await gate.maximumActive == 1)
        #expect(model.bannerEntries.first?.banner.title == "latest")
    }

    @Test("confirmed-empty request cannot clear a newer refresh after retirement wait")
    @MainActor
    func confirmedEmptyDoesNotWriteLate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = FetchGate(honorsCancellation: false)
        let model = PluginHomeFeedModel(
            service: PluginHomeFeedService { pluginId, _ in try await gate.fetch(pluginId: pluginId) },
            cacheStore: fixture.store, now: { Date(timeIntervalSince1970: 2_000_000_000) },
            platformProvider: { ids in ids.isEmpty ? [] : [platform("source-a")] }
        )

        let first = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r1"])
        ) }
        await gate.waitForStarted(1)
        let empty = Task { await model.refresh(installedPluginIds: [], availabilityConfirmed: true) }
        await Task.yield()
        let latest = Task { await model.refresh(
            installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r2"])
        ) }
        await gate.resume(call: 1, response: try responseDTO(revision: "retired"))
        await gate.waitForStarted(2)
        await gate.resume(call: 2, response: try responseDTO(revision: "latest"))
        await first.value
        await empty.value
        await latest.value

        #expect(model.bannerEntries.first?.banner.title == "latest")
        #expect(await fixture.store.load().count == 1)
    }
}

private enum FixtureError: Error { case failed }

private actor FetchCounter {
    private(set) var count = 0
    let response: PluginHomeFeedDTO
    init(response: PluginHomeFeedDTO) { self.response = response }
    func fetch() -> PluginHomeFeedDTO { count += 1; return response }
}

private actor FetchGate {
    private let honorsCancellation: Bool
    private var calls = 0
    private var active = 0
    private(set) var maximumActive = 0
    private var continuations: [Int: CheckedContinuation<PluginHomeFeedDTO, Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var startedCount: Int { calls }

    init(honorsCancellation: Bool = true) {
        self.honorsCancellation = honorsCancellation
    }

    func fetch(pluginId: String) async throws -> PluginHomeFeedDTO {
        calls += 1
        active += 1
        maximumActive = max(maximumActive, active)
        let call = calls
        notifyWaiters()
        if honorsCancellation {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuations[call] = $0 }
            } onCancel: {
                Task { await self.cancel(call: call) }
            }
        }
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }

    func waitForStarted(_ count: Int) async {
        guard calls < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func resume(call: Int, response: PluginHomeFeedDTO) {
        guard let continuation = continuations.removeValue(forKey: call) else { return }
        active -= 1
        continuation.resume(returning: response)
    }

    func resumeAll(response: PluginHomeFeedDTO) {
        for call in continuations.keys.sorted() { resume(call: call, response: response) }
    }

    private func cancel(call: Int) {
        guard let continuation = continuations.removeValue(forKey: call) else { return }
        active -= 1
        continuation.resume(throwing: CancellationError())
    }

    private func notifyWaiters() {
        let ready = waiters.filter { calls >= $0.0 }
        waiters.removeAll { calls >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private struct Fixture {
    let directory: URL
    let store: PluginHomeFeedCacheStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = PluginHomeFeedCacheStore(fileURL: directory.appendingPathComponent("home-feed.json"))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private func makeModel(
    fixture: Fixture, counter: FetchCounter, now: Date, ids: [String]
) -> PluginHomeFeedModel {
    PluginHomeFeedModel(
        service: PluginHomeFeedService { _, _ in await counter.fetch() },
        cacheStore: fixture.store, now: { now }, platformProvider: { _ in ids.map(platform) }
    )
}

private func platform(_ id: String) -> LiveParseJSPlatform {
    LiveParseJSPlatform(pluginId: id, liveTypes: [.placeholder], platformName: id)
}

private func responseDTO(revision: String = "fresh") throws -> PluginHomeFeedDTO {
    try JSONDecoder().decode(PluginHomeFeedDTO.self, from: Data("""
    {"schemaVersion":1,"revision":"\(revision)","ttlSeconds":60,"banners":[{"id":"banner","title":"\(revision)","target":{"type":"category","category":{"id":"category","parentId":"","title":"Category","icon":""}}}],"sections":[]}
    """.utf8))
}

private func makeModelFeed(pluginId: String, ttl: Int) -> PluginHomeFeed {
    PluginHomeFeed(
        pluginId: pluginId, pluginDisplayName: pluginId,
        schemaVersion: PluginHomeFeedRequest.supportedSchemaVersion, revision: "cached",
        generatedAt: nil, ttlSeconds: ttl, banners: [], sections: [],
        diagnostics: .init(droppedBanners: 0, droppedSections: 0, droppedItems: 0)
    )
}
