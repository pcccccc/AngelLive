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
    func rootInitializerUsesLocalCatalog() {
        let installedPluginIds = SandboxPluginCatalog.installedPluginIds()
        let service = PluginAvailabilityService(managesAPICredentialPolicy: true)

        #expect(service.installedPluginIds == installedPluginIds)
        #expect(service.hasAvailablePlugins == !installedPluginIds.isEmpty)
        #expect(!service.hasCheckedAvailability)
    }

    @Test("rechecking an unchanged plugin catalog still advances its revision")
    @MainActor
    func unchangedCatalogAdvancesRevision() async {
        let service = PluginAvailabilityService()

        await service.checkAvailability()
        let installedPluginIds = service.installedPluginIds
        let firstRevision = service.catalogRevision

        await service.checkAvailability()

        #expect(service.installedPluginIds == installedPluginIds)
        #expect(service.catalogRevision == (firstRevision &+ 1))
    }
}
