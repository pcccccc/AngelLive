#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import SwiftUI

typealias FullUIPlayerContrastState = PlaybackGlassContrastState

extension EnvironmentValues {
    @Entry var fullUIPlayerContrastState: FullUIPlayerContrastState? = nil
}

extension View {
    func fullUIPlayerContrast(
        while controlsAreVisible: Bool,
        source: PlaybackGlassContrastSource?,
        player: @escaping @MainActor () -> (any MediaPlayerProtocol)?
    ) -> some View {
        modifier(PlayerContrastModifier(controlsAreVisible: controlsAreVisible, source: source, player: player))
    }
}

private struct PlayerContrastModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fullUIPlayerContrastState) private var presentationContrast
    @State private var localContrast = FullUIPlayerContrastState()

    let controlsAreVisible: Bool
    let source: PlaybackGlassContrastSource?
    let player: @MainActor () -> (any MediaPlayerProtocol)?

    func body(content: Content) -> some View {
        let contrast = presentationContrast ?? localContrast
        return content
            .environment(\.fullUIPlayerPrefersRegularGlass, contrast.usesRegularGlass(for: source))
            .onChange(of: source, initial: true) { contrast.select(source) }
            .task(id: controlsAreVisible && scenePhase == .active ? source : nil) {
                guard #available(iOS 26.0, *), controlsAreVisible, scenePhase == .active, let source else { return }
                await contrast.sample(for: source, player: player)
            }
    }
}
#endif
