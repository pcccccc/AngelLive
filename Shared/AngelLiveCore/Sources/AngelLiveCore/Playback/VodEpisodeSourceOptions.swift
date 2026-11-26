/// Source discovery belongs to the episode and detail load that requested it.
public struct VodEpisodeSourceOptions: Sendable {
    public struct Query: Equatable, Sendable {
        public let episodeID: String
        public let reload: Int

        public init(episodeID: String, reload: Int) {
            self.episodeID = episodeID
            self.reload = reload
        }
    }

    public let query: Query
    public let sources: [VodPlaybackSource]
    public private(set) var selectedID: String?

    public var selectedTitle: String? {
        sources.first { $0.id == selectedID }?.title
    }

    public init(query: Query, sources: [VodPlaybackSource], previous: Self? = nil) {
        self.query = query
        self.sources = sources
        if let previous, previous.query.episodeID == query.episodeID, let selectedID = previous.selectedID {
            select(selectedID)
        }
    }

    public mutating func select(_ sourceID: String) {
        guard sources.contains(where: { $0.id == sourceID }) else { return }
        selectedID = sourceID
    }

    public func sourceID(for episodeID: String) -> String? {
        query.episodeID == episodeID ? selectedID : nil
    }
}
