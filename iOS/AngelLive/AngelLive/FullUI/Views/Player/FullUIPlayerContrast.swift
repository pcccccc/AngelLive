#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import Observation
import SwiftUI

struct FullUIPlayerContrastSource: Equatable {
    let roomID: String
    let url: URL?
    let kernel: PlayerKernel
    var episodeID: String? = nil
}

@MainActor
@Observable
final class FullUIPlayerContrastState {
    private var regularSource: FullUIPlayerContrastSource?
    @ObservationIgnored private var source: FullUIPlayerContrastSource?
    @ObservationIgnored private var lastChange = ContinuousClock.now

    func usesRegularGlass(for source: FullUIPlayerContrastSource) -> Bool {
        regularSource == source
    }

    func select(_ source: FullUIPlayerContrastSource, at now: ContinuousClock.Instant = .now) {
        guard source.url != nil, self.source != source else { return }
        self.source = source
        lastChange = now
        regularSource = nil
    }

    @discardableResult
    func switchGlass(toRegular regular: Bool, for source: FullUIPlayerContrastSource,
                     at now: ContinuousClock.Instant) -> Bool {
        guard self.source == source, regular != usesRegularGlass(for: source),
              lastChange.duration(to: now) >= .seconds(3) else { return false }
        lastChange = now
        regularSource = regular ? source : nil
        return true
    }
}

private struct PlayerContrastSamples {
    private var consecutiveBrightSamples = 0
    private var darkSince: ContinuousClock.Instant?
    private var unreadableSamples = 0

    mutating func record(brightCells: Int, at now: ContinuousClock.Instant) -> Bool? {
        unreadableSamples = 0
        // The probe samples 48 cells. Five bright cells exceed the old cutoff
        // of four, while two or fewer leave room for isolated highlights.
        consecutiveBrightSamples = brightCells >= 5 ? min(consecutiveBrightSamples + 1, 2) : 0
        darkSince = brightCells <= 2 ? (darkSince ?? now) : nil
        if consecutiveBrightSamples == 2 { return true }
        if let darkSince, darkSince.duration(to: now) >= .milliseconds(2500) { return false }
        return nil
    }

    mutating func recordUnreadable(isReady: Bool) -> Bool {
        consecutiveBrightSamples = 0
        darkSince = nil
        unreadableSamples = isReady ? min(unreadableSamples + 1, 3) : 0
        return unreadableSamples == 3
    }
}

extension EnvironmentValues {
    @Entry var fullUIPlayerContrastState: FullUIPlayerContrastState? = nil
}

extension View {
    func fullUIPlayerContrast(
        while controlsAreVisible: Bool,
        source: FullUIPlayerContrastSource,
        player: @escaping () -> (any MediaPlayerProtocol)?
    ) -> some View {
        modifier(PlayerContrastModifier(controlsAreVisible: controlsAreVisible, source: source, player: player))
    }
}

private struct PlayerContrastModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fullUIPlayerContrastState) private var presentationContrast
    @State private var localContrast = FullUIPlayerContrastState()

    let controlsAreVisible: Bool
    let source: FullUIPlayerContrastSource
    let player: () -> (any MediaPlayerProtocol)?

    func body(content: Content) -> some View {
        let contrast = presentationContrast ?? localContrast
        return content
            .environment(\.fullUIPlayerPrefersRegularGlass, contrast.usesRegularGlass(for: source))
            .onChange(of: source, initial: true) { contrast.select(source) }
            .task(id: controlsAreVisible && scenePhase == .active ? source : nil) {
                guard #available(iOS 26.0, *), controlsAreVisible, scenePhase == .active,
                      source.url != nil, !Task.isCancelled else { return }
                contrast.select(source)
                await sampleContrast(contrast)
            }
    }

    private func sampleContrast(_ contrast: FullUIPlayerContrastState) async {
        let probe = PlaybackLuminanceProbe()
        defer { probe.detach() }

        var samples = PlayerContrastSamples()
        var nextConversion = ContinuousClock.now
        while !Task.isCancelled {
            let mediaPlayer = player()
            let frame = probe.frame(from: mediaPlayer)
            let now = ContinuousClock.now
            var brightCells = frame.flatMap { probe.brightCells(in: $0) }
            var attemptedSample = true
            if brightCells == nil, let frame {
                attemptedSample = now >= nextConversion
                if attemptedSample {
                    nextConversion = now + .milliseconds(1200)
                    brightCells = probe.convertedBrightCells(in: frame)
                }
            }

            if let brightCells {
                if let regular = samples.record(brightCells: brightCells, at: now) {
                    contrast.switchGlass(toRegular: regular, for: source, at: now)
                }
            } else if attemptedSample, samples.recordUnreadable(isReady: mediaPlayer?.isReadyToPlay == true),
                      contrast.switchGlass(toRegular: true, for: source, at: now) {
                // Keep controls legible when a ready decoder does not expose luma.
                #if DEBUG
                Logger.debug("播放器玻璃使用深色回退，帧格式：\(probe.formatDescription(for: frame))", category: .ui)
                #endif
            }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        }
    }
}
#endif
