import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVVodContainerView: View {
    let room: LiveModel
    let settings: GeneralSettingModel
    let onExit: () -> Void

    @State private var model: VodPlaybackModel
    @State private var launch: Launch?
    @State private var returnEpisodeID: String?

    private struct Launch {
        let episode: VodEpisode
        let sourceID: String?
    }

    init(room: LiveModel, settings: GeneralSettingModel, onExit: @escaping () -> Void) {
        self.room = room
        self.settings = settings
        self.onExit = onExit
        _model = State(initialValue: VodHostRouting.model(for: room))
    }

    var body: some View {
        Group {
            #if canImport(KSPlayer)
            if VodHostRouting.usesDirectPlayer(room) {
                TVVodPlayerView(model: model, sourceID: nil, settings: settings) { _ in
                    onExit()
                }
            } else if let launch {
                TVVodPlayerView(model: model, episode: launch.episode, sourceID: launch.sourceID,
                                settings: settings) { episodeID in
                    returnEpisodeID = episodeID
                    self.launch = nil
                }
            } else {
                detailPage
            }
            #else
            detailPage
            #endif
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .onDisappear { model.cancel() }
    }

    private var detailPage: some View {
        TVVodWorkDetailView(room: room, model: model, returnEpisodeID: returnEpisodeID, onExit: onExit) {
            launch = Launch(episode: $0, sourceID: $1)
        }
        .tvFullUIBackCommand(perform: onExit)
    }
}
