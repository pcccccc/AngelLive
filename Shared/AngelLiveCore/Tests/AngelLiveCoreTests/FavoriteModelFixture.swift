import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
struct FavoriteModelFixture {
    private let directory: URL
    private let suiteName: String
    private let defaults: UserDefaults
    let store: FavoriteLocalStore

    init() throws {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.resolvingSymlinksInPath()
        let name = "FavoriteModelFixture.\(UUID().uuidString)"
        let directory = temp.appendingPathComponent(name, isDirectory: true)
        let path = directory.resolvingSymlinksInPath().pathComponents
        try #require(path.starts(with: temp.pathComponents))
        for searchPath in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            for userDirectory in fileManager.urls(for: searchPath, in: .userDomainMask) {
                try #require(!path.starts(with: userDirectory.resolvingSymlinksInPath().pathComponents))
            }
        }
        let defaults = try #require(UserDefaults(suiteName: name))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        self.directory = directory
        self.suiteName = name
        self.defaults = defaults
        // A delayed refresh save must not recreate the directory after teardown.
        self.store = FavoriteLocalStore(directory: directory, createDirectoryIfNeeded: false)
    }

    func makeModel(
        refreshSession: FavoriteRefreshSession = FavoriteRefreshSession(),
        refreshNow: @escaping @MainActor () -> Date = { Date() }
    ) -> AppFavoriteModel {
        let model = AppFavoriteModel(
            refreshSession: refreshSession, refreshNow: refreshNow, defaults: defaults, localStore: store
        )
        model.favoriteICloudSyncEnabled = false
        return model
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) }
    }
}
