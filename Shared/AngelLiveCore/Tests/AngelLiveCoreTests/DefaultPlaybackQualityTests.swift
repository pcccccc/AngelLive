import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Default playback quality")
struct DefaultPlaybackQualityTests {
    private func quality(
        _ title: String,
        qn: Int = 0,
        url: String = "https://stream.example.invalid/live.m3u8",
        locked: Bool = false,
        refresh: Bool = false
    ) -> LiveQualityDetail {
        LiveQualityDetail(
            roomId: "room", title: title, qn: qn, url: url,
            liveCodeType: .hls, liveType: .placeholder,
            playbackHints: LivePlaybackHints(
                selectionBehavior: refresh ? .refreshOnSelect : .direct,
                authLimit: locked ? .init(reason: LivePlaybackAuthLimitReason.loginRequired) : nil
            )
        )
    }

    private func line(_ qualities: [LiveQualityDetail], id: String = "source-a") -> LiveQualityModel {
        LiveQualityModel(cdn: id, qualitys: qualities)
    }

    @Test("resolution order ignores opaque qn identifiers")
    func unorderedResolution() {
        let args = [line([quality("360p", qn: 800), quality("4K", qn: 1), quality("720p", qn: 999), quality("2K", qn: 2), quality("1080p", qn: 0)])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 4)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 0)
    }

    @Test("generic named quality levels sort together")
    func namedLevels() {
        let args = [line([quality("高清"), quality("流畅"), quality("原画"), quality("标清"), quality("蓝光"), quality("超清")])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 0)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 1)
    }

    @Test("unknown and mixed signals keep plugin order", arguments: [
        ["source-a", "source-b", "source-c"],
        ["360p", "source-a", "1080p"],
        ["360p", "原画", "1080p"]
    ])
    func unknownKeepsOrder(_ titles: [String]) {
        let args = [line(titles.map { quality($0) })]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 1)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 2)
    }

    @Test("format alternatives count as one quality and retain first usable format")
    func repeatedFormats() {
        let args = [line([
            quality("1080p (HLS)", locked: true), quality("1080p [FLV]"), quality("1080p DASH"),
            quality("720p HLS"), quality("720p FLV"), quality("360p HLS"), quality("360p FLV")
        ])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 3)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 5)
        let onlyHighest = [line(Array(args[0].qualitys.prefix(3)))]
        #expect(RoomPlaybackResolver.initialSelection(in: onlyHighest, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 1)
    }

    @Test("same resolution preserves distinct frame rate and HDR tiers")
    func frameRateAndHDRRemainDistinct() {
        let args = [line([quality("1080p 60fps"), quality("1080p 30fps"), quality("1080p HDR")])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 1)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 2)
    }

    @Test("format substring inside a title is preserved")
    func formatTokensMustBeIndependent() {
        let args = [line([quality("source-hlsvariant"), quality("source-flvvariant"), quality("source-dashvariant")])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 2)
    }

    @Test("blank titles with qn zero remain independent entries")
    func blankTitlesRemainDistinct() {
        let args = [line([quality(""), quality(""), quality("")])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 1)
    }

    @Test("locked, blank, and invalid direct URLs are excluded but refresh tiers remain available")
    func unavailableAndRefreshTiers() {
        let args = [line([
            quality("4K", locked: true), quality("1080p", url: " "),
            quality("720p", url: "https://["), quality("540p", url: "relative/source"),
            quality("360p", url: "", refresh: true)
        ])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == 4)
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver).qualityIndex == 4)
    }

    @Test("preferred CDN wins when usable and other lines supply fallback candidates")
    func preferredAndFallbackLines() {
        let args = [line([]), line([quality("720p"), quality("360p")], id: "source-b"), line([quality("1080p"), quality("720p")], id: "source-c")]
        let preferred = RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 2, preference: .balanced)
        #expect(preferred.cdnIndex == 2)
        #expect(preferred.qualityIndex == 1)
        let fallback = RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .dataSaver)
        #expect(fallback.cdnIndex == 1)
        #expect(fallback.qualityIndex == 1)
        var lockedArgs = args
        lockedArgs[2].qualitys = [quality("1080p", locked: true)]
        #expect(RoomPlaybackResolver.initialSelection(in: lockedArgs, preferredCdnIndex: 2, preference: .balanced).cdnIndex == 1)
    }

    @Test("learned CDN selection composes with quality preference")
    func learnedCDN() async throws {
        let suite = "DefaultPlaybackQualityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = CDNPreferenceStore(defaults: defaults)
        let args = [line([quality("1080p"), quality("360p")]), line([quality("1080p"), quality("360p")], id: "source-b")]
        for _ in 0..<3 {
            await store.recordFailure(lineID: "source-a", pluginID: "fixture.plugin")
            await store.recordSuccess(lineID: "source-b", pluginID: "fixture.plugin", startupMilliseconds: 500)
        }
        let learned = try #require(await store.preferredIndex(in: args, pluginID: "fixture.plugin"))
        let selected = RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: learned, preference: .balanced)
        #expect(selected.cdnIndex == 1)
        #expect(selected.qualityIndex == 1)
    }

    @Test("single and double tiers select middle toward lower", arguments: [1, 2])
    func smallLists(_ count: Int) {
        let args = [line([quality("1080p"), quality("360p")].prefix(count).map { $0 })]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .balanced).qualityIndex == count - 1)
    }

    @Test("highest and missing candidates retain existing automatic behavior", arguments: DefaultPlaybackQuality.allCases)
    func legacyFallback(_ preference: DefaultPlaybackQuality) {
        let examples: [[LiveQualityModel]] = [[], [line([])], [line([quality("1080p", locked: true), quality("360p", locked: true)])]]
        for args in examples {
            let expected = RoomPlaybackResolver.automaticSelection(in: args, preferredCdnIndex: 10, preferredQualityIndex: 0)
            let selected = RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 10, preference: preference)
            #expect(selected.cdnIndex == expected.cdnIndex)
            #expect(selected.qualityIndex == expected.qualityIndex)
        }
        let args = [line([quality("360p"), quality("1080p")])]
        #expect(RoomPlaybackResolver.initialSelection(in: args, preferredCdnIndex: 0, preference: .highest).qualityIndex == 0)
    }

    @Test("stored preference defaults safely and round trips all values")
    @MainActor func preferencePersistence() {
        let key = PlayerSettingModel.globalDefaultPlaybackQuality
        let original = UserDefaults.shared.object(forKey: key)
        defer {
            if let original { UserDefaults.shared.set(original, forKey: key) }
            else { UserDefaults.shared.removeObject(forKey: key) }
        }
        UserDefaults.shared.removeObject(forKey: key)
        let settings = PlayerSettingModel()
        #expect(settings.defaultPlaybackQuality == .highest)
        UserDefaults.shared.set(999, forKey: key)
        #expect(settings.defaultPlaybackQuality == .highest)
        UserDefaults.shared.set("invalid", forKey: key)
        #expect(settings.defaultPlaybackQuality == .highest)
        for preference in DefaultPlaybackQuality.allCases {
            settings.defaultPlaybackQuality = preference
            #expect(PlayerSettingModel().defaultPlaybackQuality == preference)
        }
    }
}
