#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import SwiftUI

extension View {
    func fullUIPlayerContrast(
        while controlsAreVisible: Bool,
        player: @escaping () -> (any MediaPlayerProtocol)?
    ) -> some View {
        modifier(PlayerContrastModifier(controlsAreVisible: controlsAreVisible, player: player))
    }
}

private struct PlayerContrastModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var usesRegularGlass = false

    let controlsAreVisible: Bool
    let player: () -> (any MediaPlayerProtocol)?

    func body(content: Content) -> some View {
        content
            .environment(\.fullUIPlayerPrefersRegularGlass, usesRegularGlass)
            .task(id: controlsAreVisible && scenePhase == .active) {
                guard #available(iOS 26.0, *), controlsAreVisible, scenePhase == .active else { return }
                let probe = PlaybackLuminanceProbe()
                defer { probe.detach() }

                var consecutiveDarkFrames = 0
                var unreadableFrames = 0
                var nextConversion = ContinuousClock.now
                while !Task.isCancelled {
                    let source = player()
                    let frame = probe.frame(from: source)
                    var brightCells = frame.flatMap { probe.brightCells(in: $0) }
                    var attemptedSample = true
                    if brightCells == nil, let frame {
                        let now = ContinuousClock.now
                        attemptedSample = now >= nextConversion
                        if attemptedSample {
                            nextConversion = now + .milliseconds(1200)
                            brightCells = probe.convertedBrightCells(in: frame)
                        }
                    }

                    if let brightCells {
                        unreadableFrames = 0
                        // Use the same material for all groups. Two dark samples prevent
                        // brief cuts away from a bright scene from flashing the controls.
                        if brightCells >= 4 {
                            usesRegularGlass = true
                            consecutiveDarkFrames = 0
                        } else if usesRegularGlass {
                            consecutiveDarkFrames += 1
                            if consecutiveDarkFrames >= 2 { usesRegularGlass = false }
                        }
                    } else if attemptedSample, source?.isReadyToPlay == true {
                        consecutiveDarkFrames = 0
                        unreadableFrames = min(unreadableFrames + 1, 4)
                        // Some streams do not expose CPU-readable luma. Keep controls
                        // legible once a ready decoder repeatedly returns no sample.
                        if unreadableFrames == 3 {
                            usesRegularGlass = true
                            #if DEBUG
                            Logger.debug("播放器玻璃使用深色回退，帧格式：\(probe.formatDescription(for: frame))", category: .ui)
                            #endif
                        }
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(400))
                    } catch {
                        return
                    }
                }
            }
    }
}
#endif
