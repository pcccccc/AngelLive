import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Short drama qualityList contract")
struct ShortDramaCatalogTests {
    private func quality(_ number: Int, title: String = "Episode", url: String = "https://media.example.invalid/episode.m3u8", hints: LivePlaybackHints? = nil) -> LiveQualityDetail {
        LiveQualityDetail(roomId: "room", title: title, qn: number, url: url,
                          liveCodeType: .hls, liveType: "fixture.plugin", playbackHints: hints)
    }

    private func args(_ qualities: [LiveQualityDetail], cdn: String = "source-a") -> [LiveQualityModel] {
        [LiveQualityModel(cdn: cdn, qualitys: qualities)]
    }

    @Test("sort keeps gaps and every returned episode")
    func sortAndGaps() throws {
        let episodes = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(8), quality(2), quality(5)]))
        #expect(episodes.map(\.number) == [2, 5, 8])
    }

    @Test("episode identity ignores URL and title changes")
    func stableIdentity() throws {
        let original = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(1)]))
        let changed = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(1, title: "Renamed", url: "https://media.example.invalid/refreshed.m3u8")]))
        #expect(original[0].id == changed[0].id)
    }

    @Test("plugin and room tuple cannot collide through separators")
    func tupleIdentity() throws {
        let first = try ShortDramaCatalog.episodes(pluginID: "source-a", roomID: "source-b:room", playArgs: args([quality(1)]))
        let otherPlugin = try ShortDramaCatalog.episodes(pluginID: "source-b", roomID: "source-b:room", playArgs: args([quality(1)]))
        let ambiguousTuple = try ShortDramaCatalog.episodes(pluginID: "source-a:source-b", roomID: "room", playArgs: args([quality(1)]))
        #expect(Set([first[0].id, otherPlugin[0].id, ambiguousTuple[0].id]).count == 3)
    }

    @Test("missing plugin or room identity is rejected", arguments: [("", "room"), ("fixture.plugin", " ")])
    func missingIdentity(pluginID: String, roomID: String) {
        #expect(throws: ShortDramaCatalogError.missingIdentity) {
            try ShortDramaCatalog.episodes(pluginID: pluginID, roomID: roomID, playArgs: args([quality(1)]))
        }
    }

    @Test("qn must be positive", arguments: [0, -1])
    func missingNumber(number: Int) {
        #expect(throws: ShortDramaCatalogError.invalidEpisodeNumber(number)) {
            try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(number)]))
        }
    }

    @Test("duplicate qn rejects the catalog instead of dropping an episode")
    func duplicateNumber() {
        #expect(throws: ShortDramaCatalogError.duplicateEpisodeNumber(2)) {
            try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(2), quality(2)]))
        }
    }

    @Test("qualityList requires exactly one nonempty CDN")
    func invalidCDNs() throws {
        #expect(throws: ShortDramaCatalogError.invalidCDNCount) {
            try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(1)]) + args([quality(2)]))
        }
        #expect(try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: []).isEmpty)
        #expect(try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([])).isEmpty)
        let unnamed = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([]) + args([quality(1)], cdn: ""))
        #expect(unnamed.map(\.number) == [1])
    }

    @Test("blank titles use public episode numbers")
    func blankTitle() throws {
        let episodes = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(3, title: " ")]))
        #expect(episodes[0].title == "第 3 集")
    }

    @Test("old host behavior and unknown optional values remain decodable")
    func manifestCompatibility() throws {
        let old = try JSONDecoder().decode(ManifestHostBehavior.self, from: Data(##"{"themeColor":"#FFFFFF"}"##.utf8))
        #expect(old.contentKind == nil)
        #expect(old.episodeSelection == nil)
        let future = try JSONDecoder().decode(ManifestHostBehavior.self, from: Data(#"{"contentKind":"futureContent","episodeSelection":"futureSource","futureField":true}"#.utf8))
        #expect(future.contentKind == "futureContent")
        #expect(future.episodeSelection == "futureSource")
        let declared = ManifestHostBehavior(contentKind: "shortDrama", episodeSelection: "qualityList")
        let roundTrip = try JSONDecoder().decode(ManifestHostBehavior.self, from: JSONEncoder().encode(declared))
        #expect(roundTrip == declared)
    }

    @Test("one playback UUID handles a finish only once and rejects stale finishes")
    func duplicateAndStaleFinish() {
        var policy = ShortDramaCompletionPolicy()
        let first = UUID(), second = UUID()
        policy.startPlayback(id: first)
        #expect(policy.finish(id: first, failed: false) == .completed)
        #expect(policy.finish(id: first, failed: false) == .ignored)
        policy.startPlayback(id: second)
        #expect(policy.finish(id: first, failed: true) == .ignored)
        #expect(policy.finish(id: second, failed: true) == .failed)
        #expect(policy.finish(id: second, failed: false) == .ignored)
        policy.invalidate()
        #expect(policy.finish(id: second, failed: false) == .ignored)
    }

    @Test("sheet defers normal EOF and dismissal releases it once")
    func modalCompletion() {
        var policy = ShortDramaCompletionPolicy()
        let id = UUID()
        policy.startPlayback(id: id)
        #expect(policy.setPresented(true) == nil)
        #expect(policy.finish(id: id, failed: false) == .deferred)
        #expect(policy.finish(id: id, failed: false) == .ignored)
        #expect(policy.setPresented(false) == id)
        #expect(policy.setPresented(false) == nil)
    }

    @Test("selection and cancel discard pending EOF but preserve modal state")
    func discardPendingEOF() {
        var policy = ShortDramaCompletionPolicy()
        let first = UUID(), second = UUID()
        policy.startPlayback(id: first)
        _ = policy.setPresented(true)
        #expect(policy.finish(id: first, failed: false) == .deferred)
        policy.invalidate()
        policy.startPlayback(id: second)
        #expect(policy.setPresented(false) == nil)
        #expect(policy.finish(id: second, failed: false) == .completed)
    }

    @Test("failure is immediate even while sheet is presented")
    func modalError() {
        var policy = ShortDramaCompletionPolicy()
        let id = UUID()
        policy.startPlayback(id: id)
        _ = policy.setPresented(true)
        #expect(policy.finish(id: id, failed: true) == .failed)
        #expect(policy.setPresented(false) == nil)
    }

    @Test("autoplay follows available list, skips declared locks, and stops at its end")
    func continuation() throws {
        let gapped = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(2), quality(7)]))
        #expect(ShortDramaCompletionPolicy.nextEpisode(in: gapped, after: gapped[0].id, autoplay: true)?.number == 7)
        let locked = LivePlaybackHints(authLimit: LivePlaybackAuthLimit(reason: LivePlaybackAuthLimitReason.membershipRequired))
        let refresh = LivePlaybackHints(selectionBehavior: .refreshOnSelect)
        let episodes = try ShortDramaCatalog.episodes(pluginID: "fixture.plugin", roomID: "room", playArgs: args([quality(1), quality(4, hints: locked), quality(6, url: ""), quality(8, url: "", hints: refresh)]))
        #expect(ShortDramaCompletionPolicy.firstPlayableEpisode(in: episodes)?.number == 1)
        #expect(ShortDramaCompletionPolicy.firstPlayableEpisode(in: Array(episodes.dropFirst()))?.number == 8)
        #expect(ShortDramaCompletionPolicy.firstPlayableEpisode(in: Array(episodes[1...2])) == nil)
        #expect(ShortDramaCompletionPolicy.nextEpisode(in: episodes, after: episodes[0].id, autoplay: true)?.number == 8)
        #expect(ShortDramaCompletionPolicy.nextEpisode(in: episodes, after: episodes[0].id, autoplay: false) == nil)
        #expect(ShortDramaCompletionPolicy.nextEpisode(in: episodes, after: episodes[3].id, autoplay: true) == nil)
        #expect(ShortDramaCompletionPolicy.nextEpisode(in: episodes, after: "missing", autoplay: true) == nil)
    }
}
