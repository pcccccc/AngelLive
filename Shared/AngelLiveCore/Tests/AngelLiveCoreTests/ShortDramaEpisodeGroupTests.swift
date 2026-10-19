import Testing
@testable import AngelLiveCore

@Suite("Short drama episode browsing ranges")
struct ShortDramaEpisodeGroupTests {
    @Test("ranges preserve every entry at boundaries and across hundreds of episodes", arguments: [0, 1, 20, 21, 40, 41, 387])
    func boundaries(count: Int) {
        let episodes = makeEpisodes(numbers: Array(1..<(count + 1)))
        let groups = ShortDramaEpisodeGroup.make(from: episodes)

        #expect(groups.count == (count + 19) / 20)
        #expect(groups.allSatisfy { !$0.episodes.isEmpty && $0.episodes.count <= 20 })
        let flattened = groups.flatMap(\.episodes)
        #expect(flattened.map(\.id) == episodes.map(\.id))
        #expect(flattened.map(\.number) == episodes.map(\.number))
        #expect(flattened.map(\.title) == episodes.map(\.title))
        #expect(flattened.map(\.quality.url) == episodes.map(\.quality.url))
        #expect(flattened.map(\.cdn.cdn) == episodes.map(\.cdn.cdn))
        for (index, group) in groups.enumerated() {
            #expect(group.id == episodes[index * 20].id)
            #expect(group.episodes.map(\.id) == Array(episodes.dropFirst(index * 20).prefix(20)).map(\.id))
        }
    }

    @Test("continuous ranges show episode numbers and a single tail episode")
    func consecutiveTitles() {
        let groups = ShortDramaEpisodeGroup.make(from: makeEpisodes(numbers: Array(1...41)))
        #expect(groups.map(\.title) == ["第 1–20 集", "第 21–40 集", "第 41 集"])
        let offset = ShortDramaEpisodeGroup.make(from: makeEpisodes(numbers: Array(81...100)))
        #expect(offset.map(\.title) == ["第 81–100 集"])
    }

    @Test("gaps use catalog positions rather than claiming missing episodes")
    func gaps() {
        let numbers = Array(1...20) + Array(stride(from: 30, through: 68, by: 2)) + [100, 102]
        let groups = ShortDramaEpisodeGroup.make(from: makeEpisodes(numbers: numbers))
        #expect(groups.map(\.title) == ["第 1–20 集", "第 21–40 项", "第 41–42 项"])
        #expect(groups.flatMap(\.episodes).map(\.number) == numbers)
    }

    @Test("descending and irregular input retains its exact slice and order")
    func preservesInputOrder() {
        let numbers = Array((1...46).reversed())
        let episodes = makeEpisodes(numbers: numbers)
        let groups = ShortDramaEpisodeGroup.make(from: episodes)
        #expect(groups.map(\.title) == ["第 1–20 项", "第 21–40 项", "第 41–46 项"])
        #expect(groups.flatMap(\.episodes).map(\.id) == episodes.map(\.id))
        #expect(groups.flatMap(\.episodes).map(\.number) == numbers)
    }

    @Test("membership uses unchanged episode identities and safely handles no selection")
    func contains() {
        let episodes = makeEpisodes(numbers: Array(1...21))
        let groups = ShortDramaEpisodeGroup.make(from: episodes)
        #expect(groups[0].contains(episodeID: episodes[0].id))
        #expect(groups[0].contains(episodeID: episodes[19].id))
        #expect(!groups[0].contains(episodeID: episodes[20].id))
        #expect(groups[1].contains(episodeID: episodes[20].id))
        #expect(!groups[0].contains(episodeID: nil))
        #expect(!groups[0].contains(episodeID: "missing"))
    }

    private func makeEpisodes(numbers: [Int]) -> [ShortDramaEpisode] {
        numbers.enumerated().map { index, number in
            let quality = LiveQualityDetail(
                roomId: "room", title: "Episode \(number)", qn: number,
                url: "https://media.example.invalid/\(index).m3u8",
                liveCodeType: .hls, liveType: "fixture.plugin"
            )
            return ShortDramaEpisode(
                id: "fixture.plugin:room:\(index)", number: number, title: quality.title,
                cdn: LiveQualityModel(cdn: "source-a", qualitys: [quality]), quality: quality
            )
        }
    }
}
