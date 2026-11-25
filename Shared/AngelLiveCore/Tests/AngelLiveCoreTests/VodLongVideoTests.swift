import Foundation
import Testing
@testable import AngelLiveCore

@MainActor
struct VodLongVideoTests {
    @Test(arguments: [
        ("longVideo", "landscape", HostContentOrientation.landscape),
        ("shortDrama", "portrait", .portrait),
        ("vod", "  landscape\n", .landscape),
        ("futureContent", "futureOrientation", nil),
        ("longVideo", "auto", nil),
        ("shortDrama", nil, nil),
        (nil, "Landscape", nil),
        (nil, " ", nil),
        (nil, nil, nil)
    ] as [(String?, String?, HostContentOrientation?)])
    func manifestDecodesKnownAndFutureHostBehavior(contentKind: String?, orientation: String?,
                                                  expected: HostContentOrientation?) throws {
        var json: [String: String] = [:]
        json["contentKind"] = contentKind
        json["orientation"] = orientation
        let data = try JSONSerialization.data(withJSONObject: json)
        let behavior = try JSONDecoder().decode(ManifestHostBehavior.self, from: data)
        #expect(behavior.contentKind == contentKind)
        #expect(behavior.orientation == orientation)
        #expect(behavior.declaredOrientation == expected)
    }

    @Test(arguments: [
        ("longVideo", "qualityList", "landscape", true, true),
        ("longVideo", nil, nil, true, true),
        ("longVideo", nil, "portrait", true, true),
        ("longVideo", "futureSource", "landscape", false, false),
        ("shortDrama", "qualityList", "portrait", false, true),
        ("shortDrama", "qualityList", nil, false, true),
        ("shortDrama", nil, nil, false, false),
        ("vod", nil, nil, true, true),
        ("futureContent", nil, "futureOrientation", false, false),
        (nil, nil, nil, false, false)
    ] as [(String?, String?, String?, Bool, Bool)])
    func selectedManifestDeterminesRoutingAndLiveStateAdmission(
        kind: String?, episodeSelection: String?, orientation: String?, declaresVod: Bool, onDemand: Bool
    ) throws {
        let behavior = ManifestHostBehavior(contentKind: kind, episodeSelection: episodeSelection, orientation: orientation)
        let fixture = try Fixture(behavior: behavior)
        let manifest = fixture.plugin.manifest
        let direct = kind == "longVideo" && declaresVod
        #expect(VodHostRouting.declaresVod(manifest) == declaresVod)
        #expect(VodHostRouting.usesDirectPlayer(manifest) == direct)
        #expect(VodHostRouting.isVod(fixture.plugin) == (direct || kind == "vod"))
        #expect(VodHostRouting.preferredOrientation(for: manifest) == (orientation == "portrait" ? .portrait : .landscape))
        #expect(manifest.hostBehavior?.selectsShortDramaEpisodes == (kind == "shortDrama" && episodeSelection == "qualityList"))
        #expect(manifest.hostBehavior?.declaredOrientation == behavior.declaredOrientation)
        for state in ["0", "1", "2", "3", nil] as [String?] {
            var room = fixture.room
            room.liveState = state
            #expect(PlatformHostBehavior.isPlayableRoom(room, manifest: manifest) == (onDemand || state == "1"))
        }
    }

    @Test func directPlaybackUsesRealPluginAndKeepsDeferredEpisodes() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        await model.loadAndPlayInitialEpisode()
        let detail = try #require(model.detail)
        #expect(detail.kind == .series && !detail.hasExplicitSeasons && detail.seasons.isEmpty)
        #expect(detail.episodes.map(\.number) == [1, 2, 3, 4, 5, 6, 7])
        let first = try #require(model.playback)
        #expect(first.rawEpisodeID == "1")
        #expect(first.quality.headers == ["X-Fixture": "initial"])
        #expect(first.quality.userAgent == "fixture-agent")
        #expect(first.quality.playbackHints?.preferredEngines == [.mePlayer])
        #expect(try await fixture.refreshCalls().isEmpty)

        await model.selectEpisode(id: detail.episodes[2].id)
        let refreshed = try #require(model.playback)
        #expect(refreshed.url.absoluteString == "https://media.example.invalid/relay/ep-3.m3u8")
        #expect(refreshed.rawEpisodeID == "3" && !refreshed.refreshOnSelect)
        #expect(refreshed.quality.headers == ["X-Fixture": "refreshed"])
        #expect(refreshed.quality.userAgent == "fixture-agent")
        #expect(refreshed.quality.audioUrl == "https://media.example.invalid/audio")
        #expect(refreshed.quality.audioHeaders == ["X-Fixture": "audio"])
        #expect(refreshed.quality.audioUserAgent == "fixture-audio-agent")
        #expect(refreshed.quality.decryption?.method == .cenc)
        #expect(refreshed.quality.requestContext == ["source": "fixture"])
        #expect(refreshed.quality.playbackHints?.preferredEngines == [.mePlayer])
        #expect(refreshed.quality.playbackHints?.requiresCustomSegmentLoader == true)
        #expect(refreshed.quality.playbackHints?.mediaTransform?.scope.periodBytes == 16)
        #expect(refreshed.quality.playbackHints?.selectionBehavior == .refreshOnSelect)
        #expect(refreshed.quality.playbackHints?.isLive == false)
        #expect(refreshed.quality.playbackHints?.streamFormat == .hlsVod)
        #expect(try await fixture.refreshCalls() == [3])

        await model.selectEpisode(id: detail.episodes[0].id)
        await model.selectEpisode(id: detail.episodes[2].id)
        #expect(try await fixture.refreshCalls() == [3, 3])
    }

    @Test func eofSkipsLockedAndUnplayableEpisodesAndRefreshesTheNextSelection() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        await model.loadAndPlayInitialEpisode()
        let first = try #require(model.playback)
        model.playbackReady(id: first.id, duration: 60)
        await model.playbackFinished(id: first.id, error: nil)
        #expect(model.playback?.rawEpisodeID == "3")
        let third = try #require(model.playback)
        model.playbackReady(id: third.id, duration: 60)
        await model.playbackFinished(id: third.id, error: nil)
        #expect(model.selectedEpisode?.number == 5)
        #expect(model.errorMessage?.contains("暂时无法解析") == true)
        #expect(try await fixture.refreshCalls() == [3, 5])
    }

    @Test func disabledAutoplayDoesNotRefreshNextEpisodeAtEOF() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel(autoplay: false)
        await model.loadAndPlayInitialEpisode()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 60)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.playback?.id == id && model.hasFinished)
        #expect(try await fixture.refreshCalls().isEmpty)
    }

    @Test(arguments: [true, false])
    func eofWaitsForInteractionReleaseAndRefreshesOnce(overlay: Bool) async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        await model.loadAndPlayInitialEpisode()
        let id = try #require(model.playback?.id)
        model.playbackReady(id: id, duration: 60)
        if overlay { await model.setOverlayHoldPresented(true) }
        else { #expect(model.beginScrubbing(playbackID: id)) }
        await model.playbackFinished(id: id, error: nil)
        await model.playbackFinished(id: id, error: nil)
        #expect(model.playback?.id == id)
        #expect(try await fixture.refreshCalls().isEmpty)
        if overlay { await model.setOverlayHoldPresented(false) }
        else {
            await model.completeScrubbing(playbackID: id, targetTime: nil, duration: 60,
                                          seekSucceeded: false, resumePlayback: true)
        }
        #expect(model.playback?.rawEpisodeID == "3")
        #expect(try await fixture.refreshCalls() == [3])
    }

    @Test(arguments: ["", "resolve://ticket/unresolved"])
    func unresolvedRefreshThrowsInvalidPlaybackURL(_ refreshedURL: String) async throws {
        let fixture = try Fixture(refreshedURL: refreshedURL)
        let source = VodLongVideoSource(room: fixture.room, plugin: fixture.plugin, pluginManager: fixture.manager)
        let dependencies = source.dependencies
        let detail = try await dependencies.loadDetail()
        let episode = try #require(detail.episodes.first { $0.number == 3 })
        await #expect(throws: VodCatalogError.invalidPlaybackURL) {
            try await dependencies.resolvePlayback(detail, episode, nil)
        }
        #expect(try await fixture.refreshCalls() == [3])
    }

    @Test func longVideoDoesNotEnterShortDramaHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShortDramaProgressStore(directory: directory)
        let long = try Fixture().room
        let drama = LiveModel(userName: "", roomTitle: "Fixture", roomCover: "", userHeadImg: "",
                              liveType: "source-a", liveState: nil, userId: "", roomId: "drama", liveWatchedCount: nil)
        let rooms = [long, drama]
        let classification = ShortDramaHistoryClassification.make(for: rooms, platforms: {
            ["fixture.longvideo": .init(pluginId: "fixture.longvideo", liveTypes: ["fixture.longvideo"]),
             "source-a": .init(pluginId: "source-a", liveTypes: ["source-a"])]
        }, installedPluginIDs: { ["fixture.longvideo", "source-a"] }, resolveManifest: { id in
            LiveParsePluginManifest(pluginId: id, version: "1.0.0", apiVersion: 1, liveTypes: [id], entry: "index.js",
                hostBehavior: .init(contentKind: id == "source-a" ? "shortDrama" : "longVideo",
                                    episodeSelection: "qualityList", orientation: "portrait"))
        })
        #expect(store.liveHistory(from: rooms, classification: classification) == [long])
    }

    @Test func initialSelectionIgnoresLockedHistoryAndResumesDeferredEpisodes() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        await model.loadDetail()
        let episodes = try #require(model.detail?.episodes)
        let saved = VodEpisodeProgress(position: 18, duration: 60, completed: false, updatedAt: .now)
        try fixture.progress.updateEpisode(saved, episodeID: episodes[1].id, for: fixture.key)
        await model.loadAndPlayInitialEpisode()
        #expect(model.playback?.rawEpisodeID == "1")
        try fixture.progress.updateEpisode(saved, episodeID: episodes[2].id, for: fixture.key)
        await model.loadAndPlayInitialEpisode()
        #expect(model.playback?.rawEpisodeID == "3")
        #expect(model.playback?.resumePosition == 18)
        #expect(try await fixture.refreshCalls() == [3])
    }

    @Test func lockedAndFailedSelectionsKeepTheirEpisodeAndReportTheError() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        await model.loadAndPlayInitialEpisode()
        let episodes = try #require(model.detail?.episodes)
        await model.selectEpisode(id: episodes[1].id)
        #expect(model.selectedEpisode?.number == 2 && model.playback == nil)
        #expect(model.errorMessage == "本集需要登录")
        #expect(try await fixture.refreshCalls().isEmpty)

        await model.selectEpisode(id: episodes[4].id)
        #expect(model.selectedEpisode?.number == 5 && model.playback == nil)
        #expect(model.errorMessage?.contains("暂时无法解析") == true)
        await model.retry()
        #expect(model.playback?.rawEpisodeID == "5" && model.errorMessage == nil)
        #expect(try await fixture.refreshCalls() == [5, 5])

        await model.selectEpisode(id: episodes[5].id)
        #expect(model.errorMessage == "本集已锁定")
        await model.selectEpisode(id: episodes[6].id)
        #expect(model.errorMessage == VodCatalogError.requiresOnDemandMedia.errorDescription)
        #expect(try await fixture.refreshCalls() == [5, 5, 6, 7])
    }

    @Test func reloadsTheDirectCatalogAfterInitialFailure() async throws {
        let fixture = try Fixture()
        var shouldFail = true
        let model = fixture.makeModel {
            defer { shouldFail = false }
            return ["mode": shouldFail ? "fail" : "series"]
        }
        await model.loadAndPlayInitialEpisode()
        #expect(model.detail == nil && model.errorMessage?.contains("目录暂不可用") == true)
        await model.retry()
        #expect(model.playback?.rawEpisodeID == "1" && model.errorMessage == nil)
        #expect(!model.isLoadingDetail && !model.isLoadingPlayback)
    }

    @Test func cancelledDirectLoadCannotReplaceTheNewCatalogOrPlayback() async throws {
        let fixture = try Fixture()
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        var gate: CheckedContinuation<Void, Never>?
        var firstLoad = true
        let model = fixture.makeModel {
            if firstLoad {
                firstLoad = false
                await withCheckedContinuation {
                    gate = $0
                    signal.yield(())
                }
                return ["mode": "single"]
            }
            return [:]
        }
        let initial = Task { await model.loadAndPlayInitialEpisode() }
        for await _ in started { break }
        model.cancel()
        await model.loadAndPlayInitialEpisode()
        let playback = model.playback
        gate?.resume()
        await initial.value
        #expect(playback?.rawEpisodeID == "1" && model.playback == playback)
        #expect(model.detail?.kind == .series && model.errorMessage == nil)
        #expect(try await fixture.refreshCalls().isEmpty)
    }

    @Test func standardMovieUsesPlaybackFallbackAndOffersQualityAcrossLines() async throws {
        let fixture = try Fixture(behavior: .init(contentKind: "longVideo"), playbackFunction: "getPlayArgs")
        let model = fixture.makeModel { ["mode": "movie"] }
        await model.loadAndPlayInitialEpisode()
        let detail = try #require(model.detail)
        #expect(detail.kind == .movie && !detail.hasExplicitSeasons)
        #expect(detail.seasons.map(\.id) == [VodCatalog.movieSeasonID])
        let episode = try #require(detail.episodes.first)
        #expect(detail.episodes.count == 1 && episode.episodeID == "main")
        #expect(episode.title == fixture.room.roomTitle)
        let first = try #require(model.playback)
        #expect(first.sourceID == "0:1")
        #expect(first.sources.map(\.title) == ["线路一 · 1080p", "线路二 · 720p"])
        await model.selectEpisode(id: episode.id, sourceID: first.sources[1].id)
        #expect(model.playback?.sourceID == "1:0")
        #expect(model.playback?.rawEpisodeID == "main")
        #expect(try await fixture.refreshCalls() == [3])
    }

    @Test func oneQualityListItemIsAMovieAndRefreshesOnInitialSelection() async throws {
        let fixture = try Fixture()
        let model = fixture.makeModel { ["mode": "single"] }
        await model.loadAndPlayInitialEpisode()
        #expect(model.detail?.kind == .movie)
        #expect(model.detail?.seasons.map(\.id) == [VodCatalog.movieSeasonID])
        #expect(model.playback?.rawEpisodeID == "3")
        #expect(try await fixture.refreshCalls() == [3])
    }

    @Test func dedicatedCatalogEntryPointsStayGated() async throws {
        let fixture = try Fixture()
        #expect(!VodPluginPolicy.isSupported(fixture.plugin))
        for function in ["getVodWorks", "getVodDetail", "getVodPlayback"] {
            await #expect(throws: VodCatalogError.unsupportedPlugin) {
                _ = try await fixture.manager.call(pluginId: fixture.plugin.manifest.pluginId, function: function)
            }
        }
    }

    @Test(arguments: [
        (1, "第1集", "第 1 集"), (1, "第01集", "第 1 集"),
        (1, "第 01 集", "第 1 集"), (1, "第 1 集", "第 1 集"),
        (1, "", "第 1 集"), (1, " \n ", "第 1 集"),
        (1, " 末班渡船 ", "第 1 集 · 末班渡船"), (1, "第2集", "第 1 集 · 第2集"),
        (2, "选集 · 第2集", "第 2 集"), (2, " 选集 · 第 02 集 ", "第 2 集"),
        (2, "选集 · 第3集", "第 2 集 · 选集 · 第3集"),
        (2, "选集", "第 2 集 · 选集"),
        (2, "末班 · 渡船 · 第2集", "第 2 集 · 末班 · 渡船")
    ])
    func displayTitleUsesAQualifiedEpisodeNumberOnce(number: Int, raw: String, expected: String) {
        let episode = VodEpisode(pluginID: "fixture.plugin", workID: "work-a", episodeID: "1",
                                 seasonID: "", number: number, title: raw)
        #expect(episode.displayTitle == expected)
    }

    @Test func favoriteSwitchCandidatesIncludeOfflineOnDemandOnlyWhenOptedIn() {
        let liveOnline = LiveModel(userName: "", roomTitle: "Live", roomCover: "", userHeadImg: "",
                                   liveType: "source-a", liveState: "1", userId: "", roomId: "live-1", liveWatchedCount: nil)
        let liveOffline = LiveModel(userName: "", roomTitle: "Closed", roomCover: "", userHeadImg: "",
                                    liveType: "source-a", liveState: "0", userId: "", roomId: "live-2", liveWatchedCount: nil)
        let longVideoOffline = LiveModel(userName: "", roomTitle: "Movie", roomCover: "", userHeadImg: "",
                                         liveType: "fixture.longvideo", liveState: "0", userId: "", roomId: "vod-1", liveWatchedCount: nil)
        let favorites = [liveOnline, liveOffline, longVideoOffline]
        let shellFiltered = RoomSwitchCandidates.playableFavorites(favorites, includesOnDemand: false) {
            $0 == "fixture.longvideo"
        }
        let fullUIFiltered = RoomSwitchCandidates.playableFavorites(favorites, includesOnDemand: true) {
            $0 == "fixture.longvideo"
        }
        #expect(shellFiltered == [liveOnline])
        #expect(fullUIFiltered == [liveOnline, longVideoOffline])
    }
}

@MainActor
private final class Fixture {
    nonisolated let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manager: LiveParsePluginManager
    let plugin: LiveParseLoadedPlugin
    let progress: VodProgressStore
    let key = VodProgressKey(pluginID: "fixture.longvideo", workID: "work-a")
    let room = LiveModel(userName: "", roomTitle: "海岬列车", roomCover: "", userHeadImg: "",
                         liveType: "fixture.longvideo", liveState: nil, userId: "", roomId: "work-a", liveWatchedCount: nil)

    init(behavior: ManifestHostBehavior = .init(contentKind: "longVideo", episodeSelection: "qualityList"),
         playbackFunction: String = "getPlayback", refreshedURL: String? = nil) throws {
        let storage = try LiveParsePluginStorage(baseDirectory: directory.appendingPathComponent("plugins"))
        let version = "1.0.0"
        let id = "fixture.longvideo"
        let folder = storage.pluginVersionDirectory(pluginId: id, version: version)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = LiveParsePluginManifest(pluginId: id, version: version, apiVersion: 1,
                                               liveTypes: [id], entry: "index.js", hostBehavior: behavior)
        let behaviorJSON = try JSONEncoder().encode(manifest)
        var manifestJSON = try #require(JSONSerialization.jsonObject(with: behaviorJSON) as? [String: Any])
        manifestJSON["capabilities"] = behavior.contentKind == "vod" ? ["vod": "available"] : ["playback": "available"]
        try JSONSerialization.data(withJSONObject: manifestJSON).write(to: folder.appendingPathComponent("manifest.json"))
        let urlOverride: String
        if let refreshedURL {
            urlOverride = try #require(String(data: JSONEncoder().encode(refreshedURL), encoding: .utf8))
        } else {
            urlOverride = "null"
        }
        let script = Self.script.replacingOccurrences(of: "__playbackFunction__", with: playbackFunction)
            .replacingOccurrences(of: "__refreshedURL__", with: urlOverride)
        try Data(script.utf8)
            .write(to: folder.appendingPathComponent("index.js"))
        manager = LiveParsePluginManager(storage: storage)
        plugin = try manager.resolve(pluginId: id)
        progress = VodProgressStore(directory: directory.appendingPathComponent("progress"))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func makeModel(autoplay: Bool = true, loadContext: @escaping @MainActor () async throws -> [String: String] = { [:] }) -> VodPlaybackModel {
        let source = VodLongVideoSource(room: room, plugin: plugin, pluginManager: manager, loadContext: loadContext)
        return VodPlaybackModel(dependencies: source.dependencies, progressStore: progress, autoplayEnabled: { autoplay })
    }

    func refreshCalls() async throws -> [Int] {
        try await manager.callDecodable(pluginId: plugin.manifest.pluginId, function: "refreshCalls")
    }

    private static let script = #"""
    const calls = [];
    const media = "https://media.example.invalid";
    function quality(roomId, qn, title, url, playbackHints) {
      return {
        roomId, qn, title, url, playbackHints, liveCodeType: "m3u8", liveType: "fixture.longvideo",
        headers: { "X-Fixture": "initial" }, userAgent: "fixture-agent"
      };
    }
    function ticketURL(ticket) {
      if (ticket.startsWith("resolve://ticket/")) throw new Error("票据解析失败");
      return ticket;
    }
    const transform = {
      scope: { offsetInPeriod: 0, lengthPerPeriod: 4, periodBytes: 16, periodCount: 1 },
      keygen: {
        algorithm: "xorshift32", seed: 5, saltBias: 1, saltMultiplier: 3,
        shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5, zeroState: 1, zeroKeyByte: 0, resetPerPeriod: true
      }
    };
    globalThis.LiveParsePlugin = {
      apiVersion: 1,
      __playbackFunction__({ roomId, mode }) {
        if (mode === "fail") throw new Error("目录暂不可用");
        const hints = { isLive: false, preferredEngines: ["mePlayer"], streamFormat: "hlsLive" };
        const direct = quality(roomId, 1, "第01集", media + "/ep-1.m3u8", hints);
        const locked = quality(roomId, 2, "第2集", media + "/ep-2.m3u8", {
          ...hints, authLimit: { reason: "loginRequired", message: "本集需要登录" }
        });
        const deferred = (number, title) => quality(roomId, number, title, "", {
          ...hints, selectionBehavior: "refreshOnSelect", mediaTransform: transform,
          requiresCustomSegmentLoader: true
        });
        const unavailable = quality(roomId, 4, "第4集", "", hints);
        if (mode === "movie") {
          return [
            { cdn: "source-a", displayName: "线路一", qualitys: [unavailable, { ...direct, title: "1080p" }] },
            { cdn: "source-b", displayName: "线路二", qualitys: [deferred(3, "720p")] }
          ];
        }
        const episodes = mode === "single" ? [deferred(3, "")] : [
          deferred(7, "第7集"), direct, locked, deferred(3, "第 03 集"), unavailable,
          deferred(5, "末班渡船"), deferred(6, "第6集")
        ];
        return [{ cdn: "source-a", qualitys: episodes }];
      },
      refreshPlayback({ quality }) {
        calls.push(quality.qn);
        if (quality.qn === 5 && calls.filter(qn => qn === 5).length === 1) throw new Error("暂时无法解析");
        let url;
        try {
          url = ticketURL("resolve://ticket/ep-" + quality.qn);
        } catch (_) {
          url = media + "/relay/ep-" + quality.qn + ".m3u8";
        }
        const overrideURL = __refreshedURL__;
        if (overrideURL !== null) url = overrideURL;
        const playbackHints = quality.qn === 6
          ? { authLimit: { reason: "restricted", message: "本集已锁定" } }
          : quality.qn === 7 ? { isLive: true } : { streamFormat: "unknown" };
        return {
          ...quality, url, playbackHints, headers: { "X-Fixture": "refreshed" },
          requestContext: { source: "fixture" }, audioUrl: media + "/audio",
          audioHeaders: { "X-Fixture": "audio" }, audioUserAgent: "fixture-audio-agent",
          decryption: { method: "cenc", key: "00112233445566778899aabbccddeeff" }
        };
      },
      refreshCalls() { return calls; }
    };
    """#
}
