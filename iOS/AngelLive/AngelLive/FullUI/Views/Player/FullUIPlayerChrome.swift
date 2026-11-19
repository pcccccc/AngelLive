import AngelLiveCore
import Kingfisher
import SharedAssets
import SwiftUI
import UIKit

enum FullUIPlayerChrome {
    static let controlSize: CGFloat = 44
    static let symbolFont: Font = .system(size: 18, weight: .semibold)
    static let glassTransitionAnimation = Animation.easeInOut(duration: 0.35)

    static var inset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16
    }

    static func visibilityAnimation(_ visible: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        return visible ? .easeOut(duration: 0.22) : .easeIn(duration: 0.28)
    }
}

enum FullUIPlayerDetailChrome {
    static let inset: CGFloat = 16
    static let pillHeight: CGFloat = 32
    static let pillFill = Color.primary.opacity(0.075)
    static var accent: Color { SharedAssets.Colors.appAccent }
}

extension EnvironmentValues {
    @Entry var fullUIPlayerPrefersRegularGlass = false
}

extension View {
    @ViewBuilder
    func fullUIPlayerGlassContainer(spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    func fullUIPlayerGlass(in shape: some Shape, interactive: Bool = true) -> some View {
        modifier(FullUIPlayerGlassModifier(glassShape: shape, interactive: interactive))
    }

    func fullUIPlayerShadow(in shape: some Shape, opacity: Double = 0.22) -> some View {
        background {
            shape
                .fill(.black.opacity(opacity))
                .padding(-8)
                .blur(radius: 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    func fullUIPlayerMediaText() -> some View {
        modifier(FullUIPlayerMediaTextModifier())
            .fullUIPlayerShadow(in: Capsule())
    }
}

struct FullUIPlayerTimeLabel: View {
    @Environment(\.fullUIPlayerPrefersRegularGlass) private var brightScene
    @Environment(\.colorSchemeContrast) private var contrast
    let time: Double

    var body: some View {
        let strong = brightScene || contrast == .increased
        Text(fullUIPlayerTime(time))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: .black.opacity(strong ? 0.85 : 0.6), radius: strong ? 3 : 2, y: 1)
            .fullUIPlayerShadow(in: Capsule(), opacity: strong ? 0.32 : 0.22)
            .animation(FullUIPlayerChrome.glassTransitionAnimation, value: strong)
    }
}

func fullUIPlayerTime(_ time: Double) -> String {
    let seconds = Int(exactly: max(0, time).rounded(.down)) ?? 0
    if seconds >= 3_600 {
        return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

struct FullUIPlayerRoomIdentity: View {
    let room: LiveModel

    var body: some View {
        HStack(spacing: 8) {
            KFImage(URL(string: room.userHeadImg))
                .placeholder {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.white.opacity(0.7))
                }
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if !room.userName.isEmpty {
                    FullUIPlayerName(room.userName, font: .systemFont(ofSize: 15, weight: .semibold))
                }
                let title = RoomTitleTranslationService.shared.displayTitle(for: room.roomTitle)
                if !title.isEmpty {
                    Text(verbatim: title)
                        .font(.system(size: 13))
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

private struct FullUIPlayerMediaTextModifier: ViewModifier {
    @Environment(\.fullUIPlayerPrefersRegularGlass) private var needsContrast

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if needsContrast {
                    Color.clear
                        .fullUIPlayerGlass(in: Capsule(), interactive: false)
                        .padding(.horizontal, -4)
                        .padding(.vertical, -2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(FullUIPlayerChrome.glassTransitionAnimation, value: needsContrast)
        }
    }
}

private struct FullUIPlayerGlassModifier<GlassShape: Shape>: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.fullUIPlayerPrefersRegularGlass) private var prefersRegularGlass
    let glassShape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let regular = prefersRegularGlass || contrast == .increased
            let glass: Glass = regular ? .regular.tint(.black.opacity(0.45)) : .clear
            content.background {
                // Only the material is replaced. Keep the controls, labels
                // and hit targets mounted for the entire transition.
                ZStack {
                    Color.clear
                        .glassEffect(glass.interactive(interactive), in: glassShape)
                        .glassEffectTransition(.materialize)
                        .id(regular)
                        .transition(.opacity)
                }
                .animation(FullUIPlayerChrome.glassTransitionAnimation, value: regular)
            }
        } else {
            content.background(.ultraThinMaterial, in: glassShape)
        }
    }
}

struct FullUIPlayerGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0, content: content)
            .fullUIPlayerGlass(in: Capsule())
            .fullUIPlayerGlassContainer(spacing: 8)
            .fullUIPlayerShadow(in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

struct FullUIPlayerDanmakuStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: DanmakuConnectionStatus?
    let controlsVisible: Bool
    var controlBottomInset: CGFloat = 0

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let status {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .fullUIPlayerGlass(in: Capsule(), interactive: false)
                    .fullUIPlayerShadow(in: Capsule())
                    .padding(.bottom, controlsVisible ? 52 + controlBottomInset : 24)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: status != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
