#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import SwiftUI

extension View {
    func macPlayerContrast(
        while controlsAreVisible: Bool,
        source: PlaybackGlassContrastSource?,
        player: @escaping @MainActor () -> (any MediaPlayerProtocol)?
    ) -> some View {
        modifier(PlayerContrastModifier(controlsAreVisible: controlsAreVisible, source: source, player: player))
    }
}

private struct PlayerContrastModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var contrast = PlaybackGlassContrastState()

    let controlsAreVisible: Bool
    let source: PlaybackGlassContrastSource?
    let player: @MainActor () -> (any MediaPlayerProtocol)?

    func body(content: Content) -> some View {
        content
            .environment(\.macPlayerPrefersRegularGlass, contrast.usesRegularGlass(for: source))
            .onChange(of: source, initial: true) { contrast.select(source) }
            .task(id: controlsAreVisible && scenePhase == .active ? source : nil) {
                guard #available(macOS 26.0, *), controlsAreVisible, scenePhase == .active, let source else { return }
                await contrast.sample(for: source, player: player)
            }
    }
}
#endif
