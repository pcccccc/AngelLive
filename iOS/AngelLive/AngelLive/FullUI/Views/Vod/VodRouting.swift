import AngelLiveCore

@MainActor
enum VodRouting {
    static func declaresVod(_ room: LiveModel) -> Bool {
        VodHostRouting.declaresVod(room)
    }

    static func isVod(_ room: LiveModel) -> Bool {
        VodHostRouting.isVod(room)
    }

    static func model(for room: LiveModel) -> VodPlaybackModel {
        VodHostRouting.model(for: room)
    }

    static func sources(for detail: VodWorkDetail, episode: VodEpisode) async throws -> [VodPlaybackSource] {
        try await VodHostRouting.sources(for: detail, episode: episode)
    }
}
