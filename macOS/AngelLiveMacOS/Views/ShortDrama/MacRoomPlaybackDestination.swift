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
            if MacShortDramaRouting.isShortDrama(routedRoom) {
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
        .background(PlayerWindowReferenceView(window: $playerWindow))
        .fullUIArcLoadingStyle(isEnabled: isKnownPlugin)
        .onChange(of: playerWindow, initial: true) { _, window in
            closeCoordinator.bind(to: isKnownPlugin ? window : nil)
        }
        .onChange(of: isKnownPlugin) { _, enabled in
            closeCoordinator.bind(to: enabled ? playerWindow : nil)
        }
        .onChange(of: routedRoom.id) { _, _ in closeCoordinator.cancelPendingClose() }
        .onChange(of: room) { _, newRoom in routedRoom = newRoom }
        .onDisappear { closeCoordinator.invalidate() }
    }

    private var isKnownPlugin: Bool {
        SandboxPluginCatalog.platform(for: routedRoom.liveType) != nil
    }

    /// Shell playback keeps its existing dismissal path.
    private var legacyClose: (@MainActor () -> Void)? {
        if case let .embedded(close) = presentation { return close }
        return nil
    }

    private func requestClose() {
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
            categoryRooms: categoryRooms,
            onClose: isKnownPlugin ? requestClose : legacyClose,
            onExitFullscreen: isKnownPlugin ? closeCoordinator.requestExitFullscreen : nil,
            onRouteShortDrama: { routedRoom = $0 }
        )
        .id(routedRoom.id)
    }
}
