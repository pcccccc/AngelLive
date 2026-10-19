import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin home section presentation policy")
struct PluginHomeFeedSectionPolicyTests {
    @Test("short drama keeps every nonempty section in plugin order with section scoped item identities")
    @MainActor
    func shortDramaSections() async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let response = try sectionResponse()
        let model = makeSectionModel(fixture: fixture, response: response, ids: ["source-a"]) { _ in "shortDrama" }

        await model.refresh(installedPluginIds: ["source-a"])

        #expect(model.sectionEntries.map(\.section.title) == ["First", "Personalized", "Last"])
        #expect(model.sectionEntries.flatMap(\.section.items).map(\.room.roomId) == ["shared-room", "shared-room", "shared-room"])
        let entries = model.sectionEntries
        #expect(Set(entries.map(\.id)).count == 3)
        #expect(Set(entries.flatMap(\.section.items).map(\.id)).count == 3)
    }

    @Test("live and unknown content retain the personalized recommendation strategy", arguments: [nil, "live", "futureContent"] as [String?])
    @MainActor
    func liveSections(contentKind: String?) async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let model = makeSectionModel(fixture: fixture, response: try sectionResponse(), ids: ["source-a"]) { _ in contentKind }

        await model.refresh(installedPluginIds: ["source-a"])

        #expect(model.sectionEntries.map(\.section.title) == ["Personalized"])
    }

    @Test("live fallback still uses the first section and does not skip an empty first section")
    @MainActor
    func liveFirstSectionFallback() async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let response = try sectionResponse(personalized: false)
        let model = makeSectionModel(fixture: fixture, response: response, ids: ["source-a"]) { _ in nil }
        await model.refresh(installedPluginIds: ["source-a"])
        #expect(model.sectionEntries.map(\.section.title) == ["First"])

        let emptyFirst = makeSectionModel(fixture: fixture, response: try sectionResponse(personalized: false, emptyFirst: true), ids: ["source-a"]) { _ in nil }
        await emptyFirst.refresh(installedPluginIds: ["source-a"], force: true)
        #expect(emptyFirst.sectionEntries.isEmpty)
    }

    @Test("selected source filters all of its sections and removal clears its policy")
    @MainActor
    func sourceSelection() async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let model = makeSectionModel(fixture: fixture, response: try sectionResponse(), ids: ["source-a", "source-b"]) {
            $0 == "source-a" ? "shortDrama" : nil
        }
        await model.refresh(installedPluginIds: ["source-a", "source-b"])
        #expect(model.sectionEntries.map(\.pluginId) == ["source-a", "source-a", "source-a", "source-b"])
        model.selectPlatform(pluginId: "source-a")
        #expect(model.sectionEntries.map(\.section.title) == ["First", "Personalized", "Last"])
        model.selectPlatform(pluginId: "source-b")
        #expect(model.sectionEntries.map(\.section.title) == ["Personalized"])
        #expect(model.sectionEntries.allSatisfy { $0.pluginId == "source-b" })
        model.selectPlatform(pluginId: nil)
        #expect(model.sectionEntries.count == 4)
        model.selectPlatform(pluginId: "source-a")
        await model.refresh(installedPluginIds: ["source-b"])
        #expect(model.selectedPluginId == nil)
        #expect(model.sectionEntries.map(\.pluginId) == ["source-b"])
    }

    @Test("cache restore applies resolved content kind before availability is confirmed", arguments: [true, false])
    @MainActor
    func cachedSections(resolved: Bool) async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let response = try sectionResponse()
        let cached = try await PluginHomeFeedService { _, _ in response }.fetch(platform: sectionPlatform("source-a"))
        #expect(await fixture.store.save([cached]))
        let model = PluginHomeFeedModel(
            service: PluginHomeFeedService { _, _ in
                Issue.record("Unconfirmed availability must not fetch")
                return response
            },
            cacheStore: fixture.store, now: Date.init,
            platformProvider: { _ in [] },
            contentKindProvider: { _ in resolved ? "shortDrama" : nil }
        )

        await model.refresh(installedPluginIds: [], availabilityConfirmed: false)

        #expect(model.hasRestoredCache)
        #expect(model.sectionEntries.map(\.section.title) == (resolved ? ["First", "Personalized", "Last"] : ["Personalized"]))
        #expect(await fixture.store.load().count == 1)
    }

    @Test("resolved version metadata refreshes policy even when fresh cache skips fetching")
    @MainActor
    func metadataChanges() async throws {
        let fixture = try SectionFixture()
        defer { fixture.remove() }
        let kinds = ContentKinds()
        kinds.values["source-a"] = "shortDrama"
        let counter = SectionFetchCounter(response: try sectionResponse())
        let model = PluginHomeFeedModel(
            service: PluginHomeFeedService { _, _ in await counter.fetch() },
            cacheStore: fixture.store, now: { Date(timeIntervalSince1970: 2_000_000_000) },
            platformProvider: { _ in [sectionPlatform("source-a")] },
            contentKindProvider: { kinds.values[$0] }
        )
        let context = PluginHomeFeedRefreshContext(pluginRevisions: ["source-a": "r1"])
        await model.refresh(installedPluginIds: ["source-a"], context: context)
        #expect(model.sectionEntries.count == 3)
        #expect(await counter.count == 1)

        kinds.values["source-a"] = nil
        await model.refresh(installedPluginIds: ["source-a"], context: context)
        #expect(model.sectionEntries.map(\.section.title) == ["Personalized"])
        #expect(await counter.count == 1)

        kinds.values["source-a"] = "shortDrama"
        await model.refresh(installedPluginIds: ["source-a"], context: .init(pluginRevisions: ["source-a": "r2"]))
        #expect(model.sectionEntries.map(\.section.title) == ["First", "Personalized", "Last"])
        #expect(await counter.count == 2)
    }
}

@MainActor
private final class ContentKinds {
    var values: [String: String] = [:]
}

private actor SectionFetchCounter {
    private(set) var count = 0
    let response: PluginHomeFeedDTO

    init(response: PluginHomeFeedDTO) { self.response = response }

    func fetch() -> PluginHomeFeedDTO {
        count += 1
        return response
    }
}

private struct SectionFixture {
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
private func makeSectionModel(
    fixture: SectionFixture,
    response: PluginHomeFeedDTO,
    ids: [String],
    contentKindProvider: @escaping @MainActor @Sendable (String) -> String?
) -> PluginHomeFeedModel {
    PluginHomeFeedModel(
        service: PluginHomeFeedService { _, _ in response }, cacheStore: fixture.store,
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
        platformProvider: { installed in ids.filter { installed.contains($0) }.map(sectionPlatform) },
        contentKindProvider: contentKindProvider
    )
}

private func sectionPlatform(_ id: String) -> LiveParseJSPlatform {
    // Catalog metadata intentionally differs: only the selected resolver controls policy.
    LiveParseJSPlatform(pluginId: id, liveTypes: ["fixture.plugin"], platformName: id, hostBehavior: .init(contentKind: "live"))
}

private func sectionResponse(personalized: Bool = true, emptyFirst: Bool = false) throws -> PluginHomeFeedDTO {
    let item = #"{"id":"shared-item","room":{"roomId":"shared-room","userId":"user","roomTitle":"Room"}}"#
    return try JSONDecoder().decode(PluginHomeFeedDTO.self, from: Data("""
    {"schemaVersion":1,"ttlSeconds":60,"sections":[
      {"id":"first","kind":"rooms","title":"First","items":[\(emptyFirst ? "" : item)]},
      {"id":"empty","kind":"rooms","title":"Empty","personalized":true,"items":[]},
      {"id":"personalized","kind":"rooms","title":"Personalized","personalized":\(personalized),"items":[\(item)]},
      {"id":"last","kind":"rooms","title":"Last","items":[\(item)]}
    ]}
    """.utf8))
}
