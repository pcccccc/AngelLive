import Testing
@testable import AngelLiveCore

@Suite("Plugin availability observation", .serialized)
struct PluginAvailabilityServiceTests {
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
