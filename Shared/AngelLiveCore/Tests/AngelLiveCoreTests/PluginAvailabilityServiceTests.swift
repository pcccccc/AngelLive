import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin availability observation", .serialized)
struct PluginAvailabilityServiceTests {
    @Test("root presentation uses the local snapshot before asynchronous checking",
          arguments: [[], ["fixture.plugin"], ["source-b", "source-a"]])
    func initialSnapshotDeterminesPresentation(installedPluginIds: [String]) {
        let service = PluginAvailabilityService(initialInstalledPluginIds: installedPluginIds)

        #expect(service.installedPluginIds == installedPluginIds.sorted())
        #expect(service.hasAvailablePlugins == !installedPluginIds.isEmpty)
        #expect(!service.hasCheckedAvailability)
        #expect(!service.isChecking)
        #expect(service.catalogRevision == 0)
    }

    @Test("host root initializes from the same local catalog as availability checking")
    @MainActor
    func rootInitializerUsesLocalCatalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try pluginManager(at: root)
        let manifest = LiveParsePluginManifest(
            pluginId: "fixture.plugin", version: "1.0.0", apiVersion: 1,
            displayName: "Fixture", liveTypes: ["fixture.plugin"], entry: "index.js"
        )
        let directory = fixture.storage.pluginVersionDirectory(pluginId: manifest.pluginId, version: manifest.version)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data("globalThis.LiveParsePlugin = { apiVersion: 1 };".utf8)
            .write(to: directory.appendingPathComponent("index.js"))

        var initialPolicy: Bool?
        let service = PluginAvailabilityService(
            pluginManager: fixture,
            initializeHostPolicy: { initialPolicy = $0 },
            updateHostPolicy: { _ in }
        )

        #expect(service.installedPluginIds == [manifest.pluginId])
        #expect(service.hasAvailablePlugins)
        #expect(initialPolicy == true)
        #expect(!service.hasCheckedAvailability)
    }

    @Test("rechecking an unchanged plugin catalog still advances its revision")
    @MainActor
    func unchangedCatalogAdvancesRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try pluginManager(at: root)
        let service = PluginAvailabilityService(initialInstalledPluginIds: [], pluginManager: { fixture })

        await service.checkAvailability()
        let installedPluginIds = service.installedPluginIds
        let firstRevision = service.catalogRevision

        await service.checkAvailability()

        #expect(service.installedPluginIds == installedPluginIds)
        #expect(service.catalogRevision == (firstRevision &+ 1))
    }

    private func pluginManager(at root: URL) throws -> LiveParsePluginManager {
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        return LiveParsePluginManager(storage: storage, session: URLSession(configuration: .ephemeral))
    }
}
