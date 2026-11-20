import Testing
@testable import AngelLiveCore

struct PlaybackDisplayTests {
    @Test(arguments: [
        ("蓝光_4M", "蓝光"),
        ("超清 1080P", "超清"),
        ("高清", "高清"),
        ("1080P60", "1080P60"),
        ("原画(推荐)", "原画"),
        ("原画（推荐）", "原画"),
        ("高清-高帧率", "高清"),
        ("流畅·省流", "流畅"),
        ("超清/高帧率_4M", "超清"),
        ("_备用", "_备用"),
        ("", "")
    ])
    func compactQualityTitleUsesFirstSegmentOrKeepsEmptyPrefix(_ title: String, expected: String) {
        #expect(PlaybackDisplay.compactQualityTitle(title) == expected)
    }

    @Test func popularityHidesZeroAndFormatsPositiveValues() {
        #expect(PlaybackDisplay.popularityTitle(nil) == nil)
        #expect(PlaybackDisplay.popularityTitle("  ") == nil)
        #expect(PlaybackDisplay.popularityTitle("0") == nil)
        #expect(PlaybackDisplay.popularityTitle(" 0.0 ") == nil)
        #expect(PlaybackDisplay.popularityTitle("-1") == nil)
        #expect(PlaybackDisplay.popularityTitle("12000") == "1.2万")
        #expect(PlaybackDisplay.popularityTitle(" 1.2万 ") == "1.2万")
    }

    @Test func shortenedNamesKeepCompletePairsAndDropUnmatchedDelimiters() {
        let name = BracketSafeName("林夏（港口[夜班]电台）")
        #expect(name.title { $0.count <= 20 } == "林夏（港口[夜班]电台）")
        #expect(name.title { $0.count <= 7 } == "林夏…")
        #expect(name.title { $0.count <= 0 }.isEmpty)
        #expect(BracketSafeName("【林夏】").title { $0.count <= 2 } == "林…")
        #expect(BracketSafeName("林夏（夜班]").fullTitle == "林夏夜班")
        #expect(BracketSafeName("O’Neil").fullTitle == "O’Neil")
    }

    @Test func lineTitlesHideInternalIdentifiersAndUseReadableLabels() {
        let named = LiveQualityModel(cdn: "edge-a", displayName: " 备用线路 ", qualitys: [])
        let legacy = LiveQualityModel(cdn: " East Relay ", displayName: "edge_b", qualitys: [])
        let tagged = LiveQualityModel(cdn: "primary", displayName: "edge-a", qualitys: [])
        let empty = LiveQualityModel(cdn: "", displayName: " ", qualitys: [])
        #expect(PlaybackDisplay.lineTitle(for: named, index: 0) == "备用线路")
        #expect(PlaybackDisplay.lineTitle(for: legacy, index: 1) == "East Relay")
        #expect(PlaybackDisplay.lineTitle(for: tagged, index: 2) == "线路 3")
        #expect(PlaybackDisplay.lineTitle(for: empty, index: 0) == "线路 1")
    }
}
