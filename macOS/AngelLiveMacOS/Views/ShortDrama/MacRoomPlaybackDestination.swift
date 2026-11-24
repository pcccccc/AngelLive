import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import AppKit

/// FullUI routing must happen before a live room model or player is created.
enum MacShortDramaRouting {
    static func isShortDrama(_ room: LiveModel) -> Bool {
        #if canImport(KSPlayer)
        guard let platform = SandboxPluginCatalog.platform(for: room.liveType),
              let plugin = try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId) else { return false }
        let behavior = plugin.manifest.hostBehavior
        return behavior?.contentKind == "shortDrama" && behavior?.episodeSelection == "qualityList"
        #else
        return false
        #endif
    }
}

enum MacPlaybackPresentation {
    case navigation
    case embedded(close: @MainActor () -> Void)
    case playerWindow
}

struct MacRoomPlaybackDestination: View {
    let room: LiveModel
    let categoryRooms: CategoryRoomListModel?
    let presentation: MacPlaybackPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesFullUI) private var usesFullUI
    @Environment(\.macPlayerAcceptsCommands) private var acceptsCommands
    @State private var playerWindow: NSWindow?
    @State private var closeCoordinator = MacPlayerCloseCoordinator()
    @State private var routedRoom: LiveModel

    init(
        room: LiveModel,
        categoryRooms: CategoryRoomListModel? = nil,
        presentation: MacPlaybackPresentation = .navigation
    ) {
        self.room = room
        self.categoryRooms = categoryRooms
        self.presentation = presentation
        _routedRoom = State(initialValue: room)
    }

    var body: some View {
        Group {
            #if canImport(KSPlayer)
            if usesFullUI && VodHostRouting.declaresVod(routedRoom) {
                MacVodContainerView(
                    room: routedRoom, presentation: presentation, onClose: requestClose,
                    onExitFullscreen: closeCoordinator.requestExitFullscreen
                )
                .id(routedRoom.id)
            } else if MacShortDramaRouting.isShortDrama(routedRoom) {
                MacShortDramaPlayerView(
                    room: routedRoom, onClose: requestClose,
                    onExitFullscreen: closeCoordinator.requestExitFullscreen
                )
                    .id(routedRoom.id)
            } else {
                livePlayer
            }
            #else
            livePlayer
            #endif
        }
        .background {
            if usesFullUI {
                MacFullUIWindowProbe(window: $playerWindow)
            } else {
                PlayerWindowReferenceView(window: $playerWindow)
            }
        }
        .fullUIArcLoadingStyle(isEnabled: usesFullUI)
        .onChange(of: playerWindow, initial: true) { _, window in
            closeCoordinator.bind(to: usesFullUI ? window : nil)
        }
        .onChange(of: usesFullUI) { _, enabled in
            closeCoordinator.bind(to: enabled ? playerWindow : nil)
        }
        .onChange(of: acceptsCommands, initial: true) { _, acceptsCommands in
            closeCoordinator.suppressesFullscreenToolbar = acceptsCommands
        }
        .onChange(of: routedRoom.id) { _, _ in closeCoordinator.cancelPendingClose() }
        .onChange(of: room) { _, newRoom in routedRoom = newRoom }
        .onDisappear { closeCoordinator.invalidate() }
    }

    /// Shell playback keeps its existing dismissal path.
    private var legacyClose: (@MainActor () -> Void)? {
        if case let .embedded(close) = presentation { return close }
        return nil
    }

    private func requestClose() {
        if usesFullUI {
            guard let playerWindow else {
                switch presentation {
                case .navigation, .playerWindow: dismiss()
                case let .embedded(close): close()
                }
                return
            }
            closeCoordinator.bind(to: playerWindow)
        }
        closeCoordinator.requestClose { window in
            switch presentation {
            case .navigation: dismiss()
            case let .embedded(close): close()
            case .playerWindow: window.performClose(nil)
            }
        }
    }

    private var livePlayer: some View {
        RoomPlayerView(
            room: routedRoom,
            usesFullUI: usesFullUI,
            categoryRooms: categoryRooms,
            onClose: usesFullUI ? requestClose : legacyClose,
            onExitFullscreen: usesFullUI ? closeCoordinator.requestExitFullscreen : nil,
            onRouteShortDrama: { routedRoom = $0 }
        )
        .id(routedRoom.id)
    }
}

struct MacFullUIWindowProbe: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> Probe { Probe(frame: .zero) }

    func updateNSView(_ view: Probe, context: Context) {
        view.binding = $window
        view.publishWindow()
    }

    static func dismantleNSView(_ view: Probe, coordinator: ()) {
        view.binding = nil
    }

    final class Probe: NSView {
        var binding: Binding<NSWindow?>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            publishWindow()
        }

        func publishWindow() {
            Task { @MainActor [weak self] in
                guard let self, let binding, binding.wrappedValue !== window else { return }
                binding.wrappedValue = window
            }
        }
    }
}
