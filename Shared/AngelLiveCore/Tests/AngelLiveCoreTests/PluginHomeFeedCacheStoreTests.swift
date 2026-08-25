import Foundation
import Testing
@testable import AngelLiveCore

struct PluginHomeFeedCacheStoreTests {
    @Test("home feed cache round-trips validated content")
    func roundTrip() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let imageURL = try #require(URL(string: "https://example.invalid/banner.jpg"))
        let room = LiveModel(
            userName: "Streamer",
            roomTitle: "Cached room",
            roomCover: "https://example.invalid/cover.jpg",
            userHeadImg: "https://example.invalid/avatar.jpg",
            liveType: "fixture",
            liveState: LiveState.live.rawValue,
            userId: "user-1",
            roomId: "room-1",
            liveWatchedCount: "100"
        )
        let category = LiveCategoryModel(
            id: "category-1",
            parentId: "",
            title: "Popular",
            icon: "",
            biz: nil
        )
        let feed = PluginHomeFeed(
            pluginId: "fixture.plugin",
            pluginDisplayName: "Fixture",
            schemaVersion: PluginHomeFeedRequest.supportedSchemaVersion,
            revision: "revision-1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ttlSeconds: 900,
            banners: [
                PluginHomeBanner(
                    id: "fixture.plugin:banner:1",
                    imageURL: imageURL,
                    title: "Cached banner",
                    subtitle: "Available immediately",
                    badge: "LIVE",
                    target: .room(room)
                )
            ],
            sections: [
                PluginHomeSection(
                    id: "fixture.plugin:section:popular",
                    title: "Popular",
                    subtitle: nil,
                    personalized: false,
                    items: [
                        PluginHomeRoomItem(
                            id: "fixture.plugin:section:popular:item:1",
                            room: room,
                            reason: "Cached"
                        )
                    ],
                    seeAllTarget: category
                )
            ],
            diagnostics: PluginHomeFeedDiagnostics(
                droppedBanners: 0,
                droppedSections: 0,
                droppedItems: 0
            )
        )

        let store = PluginHomeFeedCacheStore(
            fileURL: directoryURL.appendingPathComponent("home-feed.json")
        )
        #expect(await store.save([feed]))

        let restoredFeeds = await store.load()
        let restored = try #require(restoredFeeds.first)
        #expect(restored.pluginId == feed.pluginId)
        #expect(restored.revision == feed.revision)
        #expect(restored.banners.first?.imageURL == imageURL)
        #expect(restored.sections.first?.items.first?.room == room)
        let restoredCategory = try #require(restored.sections.first?.seeAllTarget)
        #expect(restoredCategory.id == category.id)
        #expect(restoredCategory.parentId == category.parentId)
        #expect(restoredCategory.title == category.title)

        guard case .room(let restoredRoom) = try #require(restored.banners.first?.target) else {
            Issue.record("Expected cached room banner target")
            return
        }
        #expect(restoredRoom == room)
    }

    @Test("corrupted home feed cache is ignored")
    func corruptedCache() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("home-feed.json")
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        let store = PluginHomeFeedCacheStore(fileURL: fileURL)
        #expect(await store.load().isEmpty)
    }
}
