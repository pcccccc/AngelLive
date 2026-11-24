import AngelLiveCore
import SwiftUI

struct TVVodContainerView: View {
    let room: LiveModel
    let settings: GeneralSettingModel
    let onExit: () -> Void

    @State private var model: VodPlaybackModel
    @State private var launch: Launch?
    @State private var returnEpisodeID: String?
    @State private var backInput = TVVodBackInput()

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
            if let launch {
                TVVodPlayerView(model: model, episode: launch.episode, sourceID: launch.sourceID,
                                settings: settings, backInput: backInput) { episodeID in
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
        .modifier(TVVodBackModifier(input: backInput, onBack: onExit))
    }
}

/// The same input state survives replacement of the detail and player views.
@MainActor
final class TVVodBackInput {
    private enum Source { case menu, escape }
    private var lastEvent: (Source, ContinuousClock.Instant)?
    private var escapeIsDown = false

    func menu(_ action: () -> Void) {
        guard !escapeIsDown else { return }
        perform(.menu, action)
    }

    func escape(_ press: KeyPress, action: () -> Void) -> KeyPress.Result {
        if press.phase == .down {
            escapeIsDown = true
        } else if press.phase == .up {
            escapeIsDown = false
            perform(.escape, action)
        }
        return .handled
    }

    private func perform(_ source: Source, _ action: () -> Void) {
        let now = ContinuousClock.now
        // A single native Escape can also arrive as Exit Command during a focus transition.
        if let (previous, time) = lastEvent, previous != source, time.duration(to: now) < .milliseconds(100) {
            return
        }
        lastEvent = (source, now)
        action()
    }
}

struct TVVodBackModifier: ViewModifier {
    let input: TVVodBackInput
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .onExitCommand { input.menu(onBack) }
            .onKeyPress(.escape, phases: .all) { input.escape($0, action: onBack) }
    }
}
