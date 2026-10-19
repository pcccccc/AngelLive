/// Browsing ranges preserve the catalog's identities and playback order.
public struct ShortDramaEpisodeGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let episodes: [ShortDramaEpisode]

    public static func make(from episodes: [ShortDramaEpisode]) -> [Self] {
        stride(from: 0, to: episodes.count, by: 20).map { start in
            let end = min(start + 20, episodes.count)
            let items = Array(episodes[start..<end])
            let first = items[0]
            let isConsecutive = zip(items, items.dropFirst()).allSatisfy { previous, next in
                let successor = previous.number.addingReportingOverflow(1)
                return !successor.overflow && next.number == successor.partialValue
            }
            let title: String
            if isConsecutive {
                title = items.count == 1
                    ? "第 \(first.number) 集"
                    : "第 \(first.number)–\(items[items.count - 1].number) 集"
            } else {
                title = "第 \(start + 1)–\(end) 项"
            }
            return Self(id: first.id, title: title, episodes: items)
        }
    }

    public func contains(episodeID: String?) -> Bool {
        guard let episodeID else { return false }
        return episodes.contains { $0.id == episodeID }
    }
}
