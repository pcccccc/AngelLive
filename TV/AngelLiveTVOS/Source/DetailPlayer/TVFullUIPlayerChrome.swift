import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
import SwiftUI
import UIKit
#if canImport(KSPlayer)
import KSPlayer
#endif

extension EnvironmentValues {
    @Entry var tvPlayerPrefersRegularGlass = false
    @Entry var tvPlayerControlsAreCovered = false
}

extension View {
    func tvPlayerShadow(in shape: some Shape, opacity: Double = 0.22) -> some View {
        background {
            shape.fill(.black.opacity(opacity))
                .padding(-8)
                .blur(radius: 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    func tvPlayerGlass(in shape: some Shape, interactive: Bool = true) -> some View {
        modifier(TVPlayerGlassModifier(shape: shape, interactive: interactive))
    }

    func tvPlayerMediaText() -> some View {
        modifier(TVPlayerMediaTextModifier())
            .tvPlayerShadow(in: Capsule())
    }
}

struct TVLivePlayerRoomIdentity: View {
    let room: LiveModel

    var body: some View {
        HStack(spacing: 14) {
            KFImage(URL(string: room.userHeadImg))
                .placeholder {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.white.opacity(0.7))
                }
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !room.userName.isEmpty {
                    TVPlayerName(name: room.userName, font: .systemFont(ofSize: 38, weight: .semibold))
                }
                let title = RoomTitleTranslationService.shared.displayTitle(for: room.roomTitle)
                if !title.isEmpty {
                    Text(verbatim: title)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .roomTitleTranslationTask(room.roomTitle)
    }
}

private struct TVPlayerGlassModifier<GlassShape: Shape>: ViewModifier {
    @Environment(\.tvPlayerPrefersRegularGlass) private var prefersRegularGlass
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(tvOS 26.0, *) {
            let glass: Glass = prefersRegularGlass || contrast == .increased
                ? .regular.tint(.black.opacity(0.45))
                : .clear
            content.glassEffect(glass.interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct TVPlayerMediaTextModifier: ViewModifier {
    @Environment(\.tvPlayerPrefersRegularGlass) private var needsContrast
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if needsContrast || contrast == .increased {
                Color.clear
                    .tvPlayerGlass(in: Capsule(), interactive: false)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct TVPlayerName: View {
    let name: String
    let font: UIFont
    var maximumWidth: CGFloat? = nil

    var body: some View {
        let displayName = BracketSafeName(name)
        let idealWidth = ceil((displayName.fullTitle as NSString).size(withAttributes: [.font: font]).width)
        Text(verbatim: displayName.fullTitle)
            .font(Font(font))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: max(0, min(idealWidth, maximumWidth ?? idealWidth)))
            .overlay {
                GeometryReader { geometry in
                    let fitted = displayName.title { candidate in
                        (candidate as NSString).size(withAttributes: [.font: font]).width <= geometry.size.width + 0.5
                    }
                    Text(verbatim: fitted)
                        .font(Font(font))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}

#if canImport(KSPlayer)
extension View {
    func tvPlayerContrast(
        while controlsAreVisible: Bool,
        sourceID: AnyHashable?,
        player: @escaping () -> (any MediaPlayerProtocol)?
    ) -> some View {
        modifier(TVPlayerContrastModifier(controlsAreVisible: controlsAreVisible, sourceID: sourceID, player: player))
    }
}

private struct TVPlayerContrastModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var prefersRegularGlass = false

    let controlsAreVisible: Bool
    let sourceID: AnyHashable?
    let player: () -> (any MediaPlayerProtocol)?

    func body(content: Content) -> some View {
        content
            .environment(\.tvPlayerPrefersRegularGlass, prefersRegularGlass)
            .onChange(of: sourceID) { _, _ in prefersRegularGlass = false }
            .task(id: controlsAreVisible && scenePhase == .active ? sourceID : nil) {
                guard #available(tvOS 26.0, *), sourceID != nil,
                      controlsAreVisible, scenePhase == .active else { return }
                await sampleContrast()
            }
    }

    private func sampleContrast() async {
        let probe = PlaybackLuminanceProbe()
        defer { probe.detach() }
        var darkSamples = 0
        var unreadableSamples = 0
        var nextConversion = ContinuousClock.now
        while !Task.isCancelled {
            let source = player()
            let frame = probe.frame(from: source)
            var brightCells = frame.flatMap { probe.brightCells(in: $0) }
            var didSample = true
            if brightCells == nil, let frame {
                let now = ContinuousClock.now
                didSample = now >= nextConversion
                if didSample {
                    nextConversion = now + .milliseconds(1200)
                    brightCells = probe.convertedBrightCells(in: frame)
                }
            }
            if let brightCells {
                unreadableSamples = 0
                if brightCells >= 4 {
                    prefersRegularGlass = true
                    darkSamples = 0
                } else if prefersRegularGlass {
                    darkSamples += 1
                    if darkSamples >= 2 { prefersRegularGlass = false }
                }
            } else if didSample, source?.isReadyToPlay == true {
                darkSamples = 0
                unreadableSamples += 1
                if unreadableSamples == 3 { prefersRegularGlass = true }
            }
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
        }
    }
}
#endif
