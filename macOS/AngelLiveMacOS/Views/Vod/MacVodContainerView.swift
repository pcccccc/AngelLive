#if canImport(KSPlayer)
import AngelLiveCore
import SwiftUI

struct MacVodContainerView: View {
    let room: LiveModel
    let presentation: MacPlaybackPresentation
    let onClose: @MainActor () -> Void
    let onExitFullscreen: @MainActor () -> Bool

    @State private var model: VodPlaybackModel
    @State private var activeLaunch: Launch?
    @State private var reloadRevision = 0

    private struct Launch {
        let episode: VodEpisode
        let sourceID: String?
    }

    init(room: LiveModel, presentation: MacPlaybackPresentation, onClose: @escaping @MainActor () -> Void,
         onExitFullscreen: @escaping @MainActor () -> Bool) {
        self.room = room
        self.presentation = presentation
        self.onClose = onClose
        self.onExitFullscreen = onExitFullscreen
        _model = State(initialValue: VodHostRouting.model(for: room))
    }

    var body: some View {
        Group {
            if let launch = activeLaunch {
                MacVodPlayerView(
                    model: model, episode: launch.episode, sourceID: launch.sourceID, onReturn: returnToDetail,
                    onClose: onClose, onExitFullscreen: onExitFullscreen
                )
            } else {
                MacVodWorkDetailView(
                    model: model, isSupported: VodHostRouting.isVod(room), presentation: presentation,
                    onClose: onClose, onRetry: { reloadRevision += 1 },
                    onPlay: { activeLaunch = Launch(episode: $0, sourceID: $1) }
                )
                .task(id: reloadRevision) {
                    guard VodHostRouting.isVod(room) else { return }
                    await model.loadDetail()
                }
            }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .navigationBarBackButtonHidden()
        .onDisappear { model.cancel() }
    }

    private func returnToDetail() {
        reloadRevision += 1
        activeLaunch = nil
    }
}
#endif
