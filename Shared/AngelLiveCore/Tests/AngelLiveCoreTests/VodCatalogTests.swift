import Foundation
import Testing
@testable import AngelLiveCore

struct VodCatalogTests {
    #if DEBUG
    @Test @MainActor func demoSeriesKeepsDistinctEpisodeStoriesAndSixRotatingStills() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = VodDemoWork.series.makeModel(progressStore: VodProgressStore(directory: folder))
        await model.loadDetail()
        let detail = try #require(model.detail)
        let backdrop = try #require(detail.backdropURL.flatMap(URL.init(string:)))
        #expect(backdrop.lastPathComponent == "series-hero.jpg")
        #expect(FileManager.default.fileExists(atPath: backdrop.path))
        let episodes = detail.episodes
        let counts = detail.seasons.map { season in episodes.filter { $0.seasonID == season.id }.count }
        #expect(counts == [22, 2])
        #expect(Set(episodes.map(\.title)).count == 24)
        #expect(Set(episodes.compactMap(\.synopsis)).count == 24)
        for (index, episode) in episodes.enumerated() {
            let still = try #require(episode.stillURL.flatMap(URL.init(string:)))
            #expect(still.lastPathComponent == "still-\(index % 6 + 1).jpg")
            #expect(FileManager.default.fileExists(atPath: still.path))
            #expect(episode.durationHint == 60)
        }
        let first = try #require(episodes.first)
        await model.selectEpisode(id: first.id)
        let playback = try #require(model.playback)
        #expect(playback.sources.map(\.id) == ["source-a", "source-b"])
        #expect(playback.introMarker == VodMarker(kind: .intro, start: 0, end: 8))
        #expect(playback.creditsMarker == VodMarker(kind: .credits, start: 50, end: 60))
    }
    #endif

    @Test func detailSeparatesCatalogMetadataFromCapabilities() throws {
        let series = try VodCatalog.detail(from: Data("""
        {"kind":"series","year":2026,"seasons":[{"id":"a","number":1,"title":"第一季"},{"id":"b","number":2,"title":"第二季"}],
         "episodes":[{"id":"e","seasonId":"a","number":1,"title":"作品"}]}
        """.utf8), pluginID: "fixture.plugin", workID: "work-a")
        #expect(series.displayMetadata { _ in "" } == "2026 · 剧集 · 共 2 季 · 1 集")
        #expect(series.displayTags(sourceCount: 2) == ["多线路"])
        let movie = try VodCatalog.detail(from: Data("""
        {"kind":"movie","year":2026,"episodes":[{"id":"e","number":1,"title":"作品","durationHint":60}]}
        """.utf8), pluginID: "fixture.plugin", workID: "work-b")
        #expect(movie.displayMetadata { $0 == 60 ? "01:00" : "" } == "2026 · 电影 · 01:00")
        #expect(movie.displayTags(sourceCount: 1).isEmpty)
    }

    @Test func unknownWorkKindsDoNotDiscardValidWork() throws {
        let works = try VodCatalog.works(from: Data("""
        {"works":[{"id":"work-a","title":"雾港回声","kind":"series"},
                  {"id":"work-b","title":"远山来信","kind":"future"},
                  {"id":"work-c","title":"远山来信","kind":"movie"}]}
        """.utf8))
        #expect(works.map(\.id) == ["work-a", "work-c"])
    }

    @Test(arguments: ["backdropURL", "bannerURL", "landscapeURL"])
    func landscapeArtworkAliasesWorkForBothCatalogResponses(_ key: String) throws {
        let fields = #""id":"work-a","kind":"movie","title":"作品","posterURL":" portrait ","\#(key)":" landscape ""#
        let works = try VodCatalog.works(from: Data(#"{"works":[{\#(fields)}]}"#.utf8))
        let work = try #require(works.first)
        #expect(work.posterURL == "portrait" && work.backdropURL == "landscape")
        let detail = try VodCatalog.detail(from: Data(#"{\#(fields),"episodes":[]}"#.utf8),
                                           pluginID: "fixture.plugin", workID: work.id)
        #expect(detail.heroArtwork(portrait: true, preferredEpisode: nil).url == "portrait")
        #expect(detail.heroArtwork(portrait: false, preferredEpisode: nil).url == "landscape")
    }

    @Test func wideHeroUsesEpisodeStillBeforeUncroppedPoster() throws {
        let data = Data(#"{"posterURL":"cover","backdropURL":42,"episodes":[{"id":"a","number":1,"title":"A","stillURL":"still"}]}"#.utf8)
        let detail = try VodCatalog.detail(from: data, pluginID: "fixture.plugin", workID: "work-a")
        #expect(detail.backdropURL == nil)
        #expect(detail.heroArtwork(portrait: false, preferredEpisode: nil).url == "still")
        let posterOnly = try VodCatalog.detail(from: Data(#"{"posterURL":"cover","episodes":[]}"#.utf8),
                                               pluginID: "fixture.plugin", workID: "work-b")
        #expect(posterOnly.heroArtwork(portrait: false, preferredEpisode: nil).fitsPoster)
    }

    @Test func movieSynthesizesOneInvisibleSeason() throws {
        let data = Data("""
        {"episodes":[{"id":"episode-a","number":1,"title":"远山来信"}]}
        """.utf8)
        let detail = try VodCatalog.detail(from: data, pluginID: "fixture.plugin", workID: "work-a",
                                          fallbackTitle: "远山来信")
        #expect(detail.kind == .movie && !detail.hasExplicitSeasons)
        #expect(detail.title == "远山来信" && detail.workID == "work-a")
        #expect(detail.seasons.map(\.id) == [VodCatalog.movieSeasonID])
        #expect(detail.episodes.map(\.seasonID) == [VodCatalog.movieSeasonID])
        #expect(detail.episodes.map(\.id) == ["14:fixture.plugin6:work-aepisode-a"])
    }

    @Test func seriesRetainsAllEpisodesInSeasonAndEpisodeOrder() throws {
        let episodes = (1...125).reversed().map {
            #"{"id":"episode-\#($0)","seasonId":"season-a","number":\#($0),"title":"雾港回声"}"#
        }.joined(separator: ",")
        let data = Data("""
        {"kind":"series","seasons":[{"id":"season-b","number":2,"title":"远山来信"},
                                   {"id":"season-a","number":1,"title":"雾港回声"}],
         "episodes":[{"id":"episode-last","seasonId":"season-b","number":1,"title":"远山来信"},\(episodes)]}
        """.utf8)
        let detail = try VodCatalog.detail(from: data, pluginID: "fixture.plugin", workID: "work-a")
        #expect(detail.seasons.map(\.id) == ["season-a", "season-b"])
        #expect(detail.hasExplicitSeasons && detail.episodes.count == 126)
        #expect(detail.episodes.first?.episodeID == "episode-1")
        #expect(detail.episodes.last?.episodeID == "episode-last")
    }

    @Test(arguments: [
        """
        {"seasons":[{"id":"season-a","number":1,"title":"雾港回声"},
                    {"id":"season-a","number":2,"title":"远山来信"}],"episodes":[]}
        """,
        """
        {"seasons":[{"id":"season-a","number":1,"title":"雾港回声"},
                    {"id":"season-b","number":2,"title":"远山来信"}],
         "episodes":[{"id":"episode-a","seasonId":"season-a","number":1,"title":"雾港回声"},
                     {"id":"episode-a","seasonId":"season-b","number":1,"title":"远山来信"}]}
        """
    ]) func duplicateIdentifiersRejectTheCatalog(_ json: String) {
        #expect(throws: VodCatalogError.duplicateIdentifier) {
            try VodCatalog.detail(from: Data(json.utf8), pluginID: "fixture.plugin", workID: "work-a")
        }
    }

    @Test(arguments: [
        (#"{"workId":"work-b","episodes":[]}"#, VodCatalogError.mismatchedIdentity),
        (#"{"workId":"","episodes":[]}"#, VodCatalogError.missingIdentity),
        (#"{"kind":"future","episodes":[]}"#, VodCatalogError.unsupportedWorkKind)
    ]) func invalidDetailIsRejected(json: String, expected: VodCatalogError) {
        #expect(throws: expected) {
            try VodCatalog.detail(from: Data(json.utf8), pluginID: "fixture.plugin", workID: "work-a")
        }
    }

    @Test(arguments: [
        #"{"url":"https://fixture.example.invalid/media"}"#,
        #"{"url":"https://fixture.example.invalid/media","isLive":true}"#
    ]) func playbackRequiresExplicitOnDemandMedia(_ json: String) {
        #expect(throws: VodCatalogError.requiresOnDemandMedia) { try playback(json) }
    }

    @Test(arguments: ["", "/media", "ftp://fixture.example.invalid/media", "https:///media", "file:relative"])
    func playbackRequiresValidAbsoluteMediaURL(_ url: String) {
        #expect(throws: VodCatalogError.invalidPlaybackURL) {
            try playback(#"{"url":"\#(url)","isLive":false}"#)
        }
    }

    @Test func playbackPreservesRequestDataAndDropsInvalidAnnotations() throws {
        let result = try playback("""
        {"url":"https://fixture.example.invalid/media.m3u8","isLive":false,
         "sourceId":"source-a","sources":[{"id":"source-a","title":"雾港回声"}],
         "userAgent":"fixture-agent","headers":{"X-Fixture":"value"},
         "requestContext":{"state":"fixture-value"},"refreshOnSelect":true,
         "markers":[{"kind":"intro","start":-1,"end":5},{"kind":"intro","start":1,"end":4},
                    {"kind":"credits","start":8,"end":11},{"kind":"credits","start":9,"end":10},
                    {"kind":"intro","start":"bad","end":2},{"kind":"unknown","start":0,"end":1}],
         "subtitles":[{"id":"sub-a","name":"雾港回声","language":"zh","format":"VtT","url":"file:///tmp/cue.vtt"},
                      {"id":"sub-b","name":"远山来信","format":"unknown","url":"https://fixture.example.invalid/sub"},
                      {"id":"sub-c","name":"远山来信","format":"srt","url":"/relative"}]}
        """)
        #expect(result.introMarker == VodMarker(kind: .intro, start: 1, end: 4))
        #expect(result.creditsMarker == VodMarker(kind: .credits, start: 9, end: 10))
        #expect(result.subtitles.map(\.id) == ["ext:sub-a"])
        #expect(result.subtitles.first?.format == .vtt)
        #expect(result.quality.headers == ["X-Fixture": "value"])
        #expect(result.quality.requestContext == ["state": "fixture-value"])
        #expect(result.quality.userAgent == "fixture-agent")
        #expect(!RoomPlaybackResolver.resolvePlan(selectedQuality: result.quality).isLive)
        #expect(RoomPlaybackResolver.resolvePlan(selectedQuality: result.quality).streamFormat == .hlsVod)
        #expect(result.refreshOnSelect && result.sourceID == "source-a" && result.sources.count == 1)
    }

    @Test func emptyAndReversedMarkersDoNotPreventPlayback() throws {
        let result = try playback(#"{"url":"https://fixture.example.invalid/media","isLive":false,"markers":[{"kind":"intro","start":2,"end":2},{"kind":"credits","start":9,"end":8}]}"#)
        #expect(result.introMarker == nil && result.creditsMarker == nil)
    }

    private func playback(_ json: String) throws -> VodResolvedPlayback {
        let episode = VodEpisode(pluginID: "fixture.plugin", workID: "work-a", episodeID: "episode-a",
                                 seasonID: "season-a", number: 1, title: "雾港回声", durationHint: 10)
        return try VodCatalog.playback(from: Data(json.utf8), workID: "work-a", episode: episode,
                                       liveType: "fixture.plugin")
    }
}

struct VodPluginPolicyTests {
    @Test func callsRequireExplicitCapabilityOnTheSelectedVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        let id = "fixture.plugin"
        for (version, behavior, capability) in [
            ("1.0.0", #"{"contentKind":"vod"}"#, #"{}"#),
            ("2.0.0", #"{"contentKind":"vod","vodSchema":2}"#, #"{"vod":"available"}"#),
            ("3.0.0", #"{"contentKind":"vod","episodeSelection":"qualityList"}"#, #"{"vod":"available"}"#),
            ("4.0.0", #"{"contentKind":"vod","vodSchema":1}"#, #"{"vod":{"status":"partial"}}"#)
        ] {
            let dir = storage.pluginVersionDirectory(pluginId: id, version: version)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("""
            {"pluginId":"\(id)","version":"\(version)","apiVersion":1,"entry":"index.js",
             "liveTypes":["fixture.plugin"],"hostBehavior":\(behavior),"capabilities":\(capability)}
            """.utf8).write(to: dir.appendingPathComponent("manifest.json"))
            try Data("""
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              getVodWorks: function() {
                console.log("fixture sensitive response");
                return {works: [{id: "work-a", title: "雾港回声", kind: "series"}]};
              },
              probe: function() { console.log("fixture public diagnostic"); return {}; }
            };
            """.utf8).write(to: dir.appendingPathComponent("index.js"))
        }
        let (logs, logSink) = AsyncStream.makeStream(of: String.self)
        let manager = LiveParsePluginManager(storage: storage, logHandler: { logSink.yield($0) })
        let current = try manager.resolve(pluginId: id)
        #expect(current.manifest.version == "4.0.0")
        #expect(VodPluginPolicy.isSupported(current))
        let response: VodWorksResponse = try await manager.callDecodable(pluginId: id, function: "getVodWorks")
        #expect(response.normalized.map(\.id) == ["work-a"])
        _ = try await manager.call(pluginId: id, function: "probe")
        logSink.finish()
        var messages: [String] = []
        for await line in logs { messages.append(line) }
        #expect(messages == ["fixture public diagnostic"])
        for version in ["1.0.0", "2.0.0", "3.0.0"] {
            try manager.pin(pluginId: id, version: version)
            let pinned = try manager.resolve(pluginId: id)
            #expect(pinned.manifest.version == version)
            #expect(VodPluginPolicy.declaresVodContent(pinned.manifest))
            #expect(!VodPluginPolicy.isSupported(pinned))
            await #expect(throws: VodCatalogError.unsupportedPlugin) {
                let _: VodWorksResponse = try await manager.callDecodable(pluginId: id, function: "getVodWorks")
            }
        }
    }
}
