import Foundation
import os.lock
import Testing
@testable import AngelLiveCore

final class PlaylistFakeFetcher: PlaylistFetching {
    struct Response: Sendable {
        var data: Data
        var finalURL: URL?
        var error: PlaylistFetchError?
    }

    private let state = OSAllocatedUnfairLock<(responses: [String: Response], requests: [String])>(
        initialState: ([:], [])
    )

    func set(_ url: String, _ text: String, finalURL: String? = nil) {
        state.withLock { $0.responses[url] = Response(data: Data(text.utf8), finalURL: finalURL.flatMap(URL.init(string:))) }
    }

    func setBytes(_ url: String, _ data: Data) {
        state.withLock { $0.responses[url] = Response(data: data, finalURL: nil) }
    }

    func fail(_ url: String, status: Int) {
        state.withLock { $0.responses[url] = Response(data: Data(), finalURL: nil, error: .httpStatus(status)) }
    }

    func requestCount(_ url: String) -> Int {
        state.withLock { $0.requests.filter { $0 == url }.count }
    }

    func fetch(
        url: URL,
        userAgent: String?,
        headers: [String: String],
        limit: Int,
        allowTruncation: Bool,
        timeout: TimeInterval
    ) async throws -> PlaylistFetchResult {
        let response = state.withLock { state -> Response? in
            state.requests.append(url.absoluteString)
            return state.responses[url.absoluteString]
        }
        guard let response else { throw URLError(.cannotFindHost) }
        if let error = response.error { throw error }
        return PlaylistFetchResult(data: response.data, finalURL: response.finalURL ?? url, truncated: false)
    }
}

final class PlaylistTestClock: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
}

@Suite("Playlist platform service")
struct PlaylistPlatformServiceTests {
    static let sourceURL = "https://source-a.example.invalid/list"
    static let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-logo="https://logo.example.invalid/a.png" group-title="分组 A",频道 A
    https://stream.example.invalid/a
    #EXTINF:-1 group-title="分组 A",频道 A
    https://backup.example.invalid/a.flv
    #EXTINF:-1 group-title="分组 B",频道 B
    #EXTVLCOPT:http-user-agent=fixture-agent/1.0
    https://stream.example.invalid/b
    """

    struct Harness {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        let fetcher = PlaylistFakeFetcher()
        let clock = PlaylistTestClock()
        let service: PlaylistPlatformService

        init() {
            let clock = self.clock
            service = PlaylistPlatformService(store: store, fetcher: fetcher, cacheDirectory: nil, now: { clock.now })
        }

        func addInstance(source: String = PlaylistPlatformServiceTests.sourceURL) throws -> PlaylistInstance {
            try store.add(name: "fixture", iconURL: nil, sourceURL: source)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    @Test("categories expose an all entry followed by groups")
    func categories() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()

        let data = try await harness.service.handle(.categories, instanceID: instance.id)
        let categories = try decode([LiveMainListModel].self, data)
        #expect(categories.count == 1)
        #expect(categories[0].subList.map(\.title) == ["全部", "分组 A", "分组 B"])
    }

    @Test("rooms filter by group, map logos and keep stable ids")
    func rooms() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()

        let categories = try decode([LiveMainListModel].self, try await harness.service.handle(.categories, instanceID: instance.id))
        let groupA = try #require(categories[0].subList.first { $0.title == "分组 A" })
        let rooms = try decode(
            [PluginRoomDTO].self,
            try await harness.service.handle(.rooms(categoryId: groupA.id, page: 1), instanceID: instance.id)
        )
        #expect(rooms.map(\.roomTitle) == ["频道 A"])
        #expect(rooms[0].roomCover == "https://logo.example.invalid/a.png")
        #expect(rooms[0].liveState == "1")

        // 线路变化不影响房间 ID。
        let reordered = Self.playlist.replacingOccurrences(of: "https://stream.example.invalid/a\n", with: "https://other.example.invalid/a\n")
        harness.fetcher.set(Self.sourceURL, reordered)
        _ = try await harness.service.refresh(instanceID: instance.id)
        let again = try decode(
            [PluginRoomDTO].self,
            try await harness.service.handle(.rooms(categoryId: groupA.id, page: 1), instanceID: instance.id)
        )
        #expect(again[0].roomId == rooms[0].roomId)

        let secondPage = try decode(
            [PluginRoomDTO].self,
            try await harness.service.handle(.rooms(categoryId: PlaylistPlatformService.allCategoryId, page: 2), instanceID: instance.id)
        )
        #expect(secondPage.isEmpty)
    }

    @Test("search matches channel names case-insensitively")
    func search() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()
        let rooms = try decode(
            [PluginRoomDTO].self,
            try await harness.service.handle(.search(keyword: "频道 b", page: 1), instanceID: instance.id)
        )
        #expect(rooms.map(\.roomTitle) == ["频道 B"])
    }

    @Test("playback exposes one cdn per line and expands master playlists")
    func playback() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        harness.fetcher.set(
            "https://stream.example.invalid/a",
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5000000\nhigh\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\nlow\n",
            finalURL: "https://edge.example.invalid/live/a"
        )
        harness.fetcher.setBytes("https://backup.example.invalid/a.flv", Data("FLV".utf8) + Data(count: 10))
        let instance = try harness.addInstance()
        let rooms = try decode([PluginRoomDTO].self, try await harness.service.handle(.search(keyword: "频道 A", page: 1), instanceID: instance.id))
        let roomId = try #require(rooms.first?.roomId)

        let cdns = try decode([LiveQualityModel].self, try await harness.service.handle(.playback(roomId: roomId), instanceID: instance.id))
        #expect(cdns.map(\.cdn) == ["线路 1", "线路 2"])
        #expect(cdns[0].qualitys.map(\.title) == ["自动", "5000kbps", "360p"])
        #expect(cdns[0].qualitys[1].url == "https://edge.example.invalid/live/high")
        #expect(cdns[0].qualitys.allSatisfy { $0.liveCodeType == .hls && $0.liveType == instance.liveType })
        #expect(cdns[1].qualitys.map(\.liveCodeType) == [.flv])
    }

    @Test("per-line user agent is passed to playback")
    func userAgent() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()
        let rooms = try decode([PluginRoomDTO].self, try await harness.service.handle(.search(keyword: "频道 B", page: 1), instanceID: instance.id))
        let cdns = try decode([LiveQualityModel].self, try await harness.service.handle(.playback(roomId: rooms[0].roomId), instanceID: instance.id))
        // 探测失败时按原地址透传。
        #expect(cdns[0].qualitys.map(\.url) == ["https://stream.example.invalid/b"])
        #expect(cdns[0].qualitys[0].userAgent == "fixture-agent/1.0")
    }

    @Test("expired cache is served while refreshing in the background")
    func staleWhileRevalidate() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()
        _ = try await harness.service.handle(.categories, instanceID: instance.id)
        #expect(harness.fetcher.requestCount(Self.sourceURL) == 1)

        _ = try await harness.service.handle(.categories, instanceID: instance.id)
        #expect(harness.fetcher.requestCount(Self.sourceURL) == 1)

        harness.fetcher.fail(Self.sourceURL, status: 503)
        harness.clock.advance(PlaylistPlatformService.cacheTTL + 1)
        let data = try await harness.service.handle(.categories, instanceID: instance.id)
        #expect(try decode([LiveMainListModel].self, data)[0].subList.count == 3)
    }

    @Test("first load failure surfaces a presentable error and status")
    func firstLoadFailure() async throws {
        let harness = Harness()
        harness.fetcher.fail(Self.sourceURL, status: 403)
        let instance = try harness.addInstance()
        await #expect(throws: LiveParseError.self) {
            _ = try await harness.service.handle(.categories, instanceID: instance.id)
        }
        let status = await harness.service.status(instanceID: instance.id)
        #expect(status.lastErrorMessage?.contains("403") == true)
    }

    @Test("unknown room after a forced refresh reports a missing channel")
    func missingChannel() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()
        await #expect(throws: LiveParseError.self) {
            _ = try await harness.service.handle(.playback(roomId: "missing"), instanceID: instance.id)
        }
        // 首次加载 + 未命中后的强制刷新。
        #expect(harness.fetcher.requestCount(Self.sourceURL) == 2)
        let state = try await harness.service.handle(.liveState(roomId: "missing"), instanceID: instance.id)
        #expect(String(data: state, encoding: .utf8)?.contains("\"0\"") == true)
    }

    @Test("preview validates and seeds the first cache")
    func previewAndSeed() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let preview = try await harness.service.preview(sourceURL: Self.sourceURL)
        #expect(preview.channelCount == 2)
        #expect(preview.groupCount == 2)

        let instance = try harness.addInstance()
        await harness.service.seed(preview, for: instance)
        _ = try await harness.service.handle(.categories, instanceID: instance.id)
        #expect(harness.fetcher.requestCount(Self.sourceURL) == 1)
    }

    @Test("preview rejects content that is not a playlist")
    func previewRejectsNonPlaylist() async {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, "{\"plugins\":[]}")
        await #expect(throws: M3UPlaylistError.notPlaylist) {
            _ = try await harness.service.preview(sourceURL: Self.sourceURL)
        }
    }

    @Test("deleted instances are unavailable")
    func deletedInstance() async throws {
        let harness = Harness()
        harness.fetcher.set(Self.sourceURL, Self.playlist)
        let instance = try harness.addInstance()
        try harness.store.remove(id: instance.id)
        await #expect(throws: LiveParseError.self) {
            _ = try await harness.service.handle(.categories, instanceID: instance.id)
        }
    }
}

@Suite("Playlist instances and identity")
struct PlaylistInstanceStoreTests {
    @Test("names are required and unique, URLs are validated")
    func validation() throws {
        let store = PlaylistInstanceStore(persistence: PlaylistInstanceMemoryPersistence())
        #expect(throws: PlaylistInstanceError.emptyName) {
            try store.add(name: "  ", iconURL: nil, sourceURL: "https://source-a.example.invalid/a")
        }
        #expect(throws: PlaylistInstanceError.invalidSourceURL) {
            try store.add(name: "A", iconURL: nil, sourceURL: "ftp://source-a.example.invalid/a")
        }
        #expect(throws: PlaylistInstanceError.invalidIconURL) {
            try store.add(name: "A", iconURL: "not a url", sourceURL: "https://source-a.example.invalid/a")
        }
        let first = try store.add(name: " 列表 A ", iconURL: "", sourceURL: "https://source-a.example.invalid/a")
        #expect(first.name == "列表 A")
        #expect(first.iconURL == nil)
        #expect(throws: PlaylistInstanceError.duplicateName) {
            try store.add(name: "列表 a", iconURL: nil, sourceURL: "https://source-b.example.invalid/b")
        }
        #expect(throws: PlaylistInstanceError.duplicateName) {
            try store.add(name: "Fixture Plugin", iconURL: nil, sourceURL: "https://source-b.example.invalid/b", reservedNames: ["fixture plugin"])
        }
        let updated = try store.update(id: first.id, name: "列表 A", iconURL: "https://logo.example.invalid/x.png", sourceURL: first.sourceURL)
        #expect(updated.iconURL == "https://logo.example.invalid/x.png")
    }

    @Test("instances persist and failed loads never overwrite stored data")
    func persistence() throws {
        let persistence = PlaylistInstanceMemoryPersistence()
        let store = PlaylistInstanceStore(persistence: persistence)
        let instance = try store.add(name: "A", iconURL: nil, sourceURL: "https://source-a.example.invalid/a")
        let reloaded = PlaylistInstanceStore(persistence: persistence)
        #expect(reloaded.all() == [instance])

        try persistence.save(Data("corrupted".utf8))
        let broken = PlaylistInstanceStore(persistence: persistence)
        #expect(broken.all().isEmpty)
        #expect(throws: PlaylistInstanceError.storage) {
            try broken.add(name: "B", iconURL: nil, sourceURL: "https://source-b.example.invalid/b")
        }
        #expect(try persistence.load() == Data("corrupted".utf8))
    }

    @Test("playlist live types use the reserved namespace")
    func identity() {
        let id = UUID()
        let liveType = PlaylistPlatformIdentity.liveType(for: id)
        #expect(liveType.rawValue == "playlist:" + id.uuidString.lowercased())
        #expect(PlaylistPlatformIdentity.instanceID(from: liveType.rawValue) == id)
        #expect(PlaylistPlatformIdentity.instanceID(from: "fixture.plugin") == nil)
        #expect(PlaylistPlatformIdentity.isPlaylist("playlist:anything"))
    }

    @Test("plugin function names map to playlist requests")
    func requestMapping() {
        #expect(PlaylistPlatformRequest.make(function: "getRooms", payload: ["id": "g1", "page": 2]) == .rooms(categoryId: "g1", page: 2))
        #expect(PlaylistPlatformRequest.make(function: "getPlayback", payload: ["roomId": "r1"]) == .playback(roomId: "r1"))
        #expect(PlaylistPlatformRequest.make(function: "searchRooms", payload: ["keyword": "k", "page": "3"]) == .search(keyword: "k", page: 3))
        #expect(PlaylistPlatformRequest.make(function: "getDanmaku", payload: [:]) == .unsupported(function: "getDanmaku"))
    }

    @Test("source diagnostics recognise playlists by content")
    func diagnosticsSniffing() {
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: "https://source-a.example.invalid/list")!,
            statusCode: 200,
            contentType: "application/octet-stream",
            bodyPreview: "",
            isPlaylist: M3UPlaylistParser.looksLikePlaylist(Data("#EXTM3U\n".utf8))
        )
        #expect(diagnostics.isPlaylist)
    }
}
