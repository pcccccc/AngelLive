import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin home feed protocol")
struct PluginHomeFeedTests {
    private let platform = LiveParseJSPlatform(
        pluginId: "fixture.plugin",
        liveTypes: ["fixture"],
        platformName: "Fixture Plugin"
    )

    @Test("homeFeed is optional and discoverable without changing the runtime API version")
    func capabilityDetection() {
        #expect(PlatformFeature.allCases.contains(.homeFeed))
        #expect(!PlatformCapability.containsFunction(named: "getHomeFeed", in: "function getRooms() {}"))
        #expect(PlatformCapability.containsFunction(named: "getHomeFeed", in: "async function getHomeFeed(request) {}"))
        #expect(PlatformCapability.containsFunction(named: "getHomeFeed", in: "const api = { getHomeFeed: () => ({}) }"))

        let oldManifest = Data(#"{"apiVersion":1}"#.utf8)
        #expect(PlatformCapability.parseCapabilities(from: oldManifest) == nil)

        let newManifest = Data(#"{"apiVersion":1,"capabilities":{"homeFeed":"available"}}"#.utf8)
        guard let homeStatus = PlatformCapability.parseCapabilities(from: newManifest)?[.homeFeed] else {
            Issue.record("Expected the explicit homeFeed capability")
            return
        }
        #expect(homeStatus.isSupported)
    }

    @Test("missing optional collections decode as empty for old-style responses")
    func missingCollectionsDefaultToEmpty() throws {
        let response = try decode(#"{"schemaVersion":1}"#)

        #expect(response.banners.isEmpty)
        #expect(response.sections.isEmpty)
        #expect(response.rejectedBannerCount == 0)
        #expect(response.rejectedSectionCount == 0)
    }

    @Test("valid plugin data is normalized, namespaced, and privacy-limited")
    func validFeedIsPreparedForTheHost() async throws {
        let response = try decode("""
        {
          "schemaVersion": 1,
          "revision": " revision-1 ",
          "generatedAt": "2026-08-21T14:00:00Z",
          "ttlSeconds": 30,
          "banners": [{
            "id": " banner-1 ",
            "imageURL": "https://example.invalid/banner.jpg",
            "title": " Tonight ",
            "target": {
              "type": "room",
              "room": {
                "userName": "Alice",
                "roomTitle": "Live",
                "roomCover": "http://example.invalid/insecure.jpg",
                "userHeadImg": "https://example.invalid/avatar.jpg",
                "liveState": 1,
                "userId": 42,
                "roomId": 1001,
                "liveWatchedCount": 12345
              }
            }
          }],
          "sections": [{
            "id": "for-you",
            "kind": "rooms",
            "title": " For You ",
            "personalized": true,
            "items": [{
              "id": "item-1",
              "room": {
                "userName": "Bob",
                "roomTitle": "Now",
                "roomCover": "https://example.invalid/cover.jpg",
                "userHeadImg": "",
                "roomId": "room-2",
                "userId": "user-2"
              },
              "reason": " Because you watched similar rooms "
            }],
            "seeAllTarget": {
              "type": "category",
              "category": {
                "id": 7,
                "parentId": 3,
                "title": "Popular",
                "icon": "file:///tmp/icon.png",
                "biz": "opaque"
              }
            }
          }],
          "futureTopLevel": true
        }
        """)
        let recorder = CallRecorder()
        let service = PluginHomeFeedService { pluginId, request in
            await recorder.record(pluginId: pluginId, request: request)
            return response
        }
        let request = PluginHomeFeedRequest(locale: "zh-Hans-CN", region: "CN")

        let feed = try await service.fetch(platform: platform, request: request)
        let recorded = try #require(await recorder.snapshot())

        #expect(recorded.pluginId == "fixture.plugin")
        #expect(recorded.request == request)
        #expect(Set(request.pluginPayload.keys) == ["schemaVersion", "locale", "region"])
        #expect(feed.pluginDisplayName == "Fixture Plugin")
        #expect(feed.ttlSeconds == 60)
        #expect(feed.revision == "revision-1")
        #expect(feed.generatedAt != nil)
        #expect(feed.banners.first?.id == "fixture.plugin:banner:banner-1")
        #expect(feed.banners.first?.title == "Tonight")

        guard case .room(let bannerRoom) = try #require(feed.banners.first?.target) else {
            Issue.record("Expected a room banner target")
            return
        }
        #expect(bannerRoom.liveType == "fixture")
        #expect(bannerRoom.roomId == "1001")
        #expect(bannerRoom.userId == "42")
        #expect(bannerRoom.roomCover.isEmpty)
        #expect(bannerRoom.userHeadImg == "https://example.invalid/avatar.jpg")

        let section = try #require(feed.sections.first)
        #expect(section.id == "fixture.plugin:section:for-you")
        #expect(section.title == "For You")
        #expect(section.personalized)
        #expect(section.items.first?.id == "fixture.plugin:section:for-you:item:item-1")
        #expect(section.items.first?.room.liveType == "fixture")
        #expect(section.seeAllTarget?.id == "7")
        #expect(section.seeAllTarget?.icon.isEmpty == true)
        #expect(feed.diagnostics == PluginHomeFeedDiagnostics(droppedBanners: 0, droppedSections: 0, droppedItems: 0))
    }

    @Test("future types and malformed siblings are dropped without losing valid content")
    func badElementsAreIsolated() async throws {
        let response = try decode("""
        {
          "schemaVersion": 1,
          "ttlSeconds": 999999,
          "banners": [
            {
              "id": "kept",
              "imageURL": "javascript:alert(1)",
              "title": "Kept",
              "target": {"type":"category","category":{"id":"cat","parentId":"","title":"Cat","icon":""}}
            },
            {"id":"future","title":"Future","target":{"type":"externalURL","url":"https://example.invalid"}},
            {"id":"","title":"No ID","target":{"type":"category","category":{"id":"cat","parentId":"","title":"Cat","icon":""}}}
          ],
          "sections": [
            {
              "id": "kept-section",
              "kind": "rooms",
              "title": "Kept",
              "items": [
                {"id":"kept-item","room":{"roomId":"room","userId":"user"}},
                {"id":"missing-room"},
                {"id":"","room":{"roomId":"room-2","userId":"user-2"}}
              ]
            },
            {"id":"future-section","kind":"grid","title":"Future","items":[]},
            {"id":"","kind":"rooms","title":"No ID","items":[{"id":"nested","room":{"roomId":"nested-room","userId":"nested-user"}}]}
          ]
        }
        """)
        let service = PluginHomeFeedService { _, _ in response }

        let feed = try await service.fetch(platform: platform)

        #expect(feed.ttlSeconds == 86_400)
        #expect(feed.banners.count == 1)
        #expect(feed.banners.first?.imageURL == nil)
        #expect(feed.sections.count == 1)
        #expect(feed.sections.first?.items.count == 1)
        #expect(feed.diagnostics.droppedBanners == 2)
        #expect(feed.diagnostics.droppedSections == 2)
        #expect(feed.diagnostics.droppedItems == 3)
    }

    @Test("a future schema version is rejected before it reaches the UI")
    func futureSchemaIsRejected() async throws {
        let response = try decode(#"{"schemaVersion":2,"banners":[],"sections":[]}"#)
        let service = PluginHomeFeedService { _, _ in response }

        await #expect(throws: PluginHomeFeedError.unsupportedSchemaVersion(2)) {
            try await service.fetch(platform: platform)
        }
    }

    @Test("all valid banners are preserved while section and room limits are enforced")
    func collectionLimits() async throws {
        let room = #"{"userName":"User","roomTitle":"Room","roomId":"room","userId":"user"}"#
        let banners = (0..<12).map { index in
            #"{"id":"banner-\#(index)","imageURL":"","title":"Banner","target":{"type":"room","room":\#(room)}}"#
        }.joined(separator: ",")
        let items = (0..<21).map { index in
            #"{"id":"item-\#(index)","room":\#(room)}"#
        }.joined(separator: ",")
        let sections = (0..<9).map { index in
            #"{"id":"section-\#(index)","kind":"rooms","title":"Section","items":[\#(items)]}"#
        }.joined(separator: ",")
        let response = try decode(
            #"{"schemaVersion":1,"banners":[\#(banners)],"sections":[\#(sections)]}"#
        )
        let service = PluginHomeFeedService { _, _ in response }

        let feed = try await service.fetch(platform: platform)

        #expect(feed.banners.count == 12)
        #expect(feed.sections.count == 8)
        #expect(feed.sections.allSatisfy { $0.items.count == 20 })
        #expect(feed.diagnostics.droppedBanners == 0)
        #expect(feed.diagnostics.droppedSections == 1)
        #expect(feed.diagnostics.droppedItems == 29)
    }

    private func decode(_ json: String) throws -> PluginHomeFeedDTO {
        try JSONDecoder().decode(PluginHomeFeedDTO.self, from: Data(json.utf8))
    }
}

private actor CallRecorder {
    private var recordedCall: (pluginId: String, request: PluginHomeFeedRequest)?

    func record(pluginId: String, request: PluginHomeFeedRequest) {
        recordedCall = (pluginId, request)
    }

    func snapshot() -> (pluginId: String, request: PluginHomeFeedRequest)? {
        recordedCall
    }
}
