import SwiftUI
import UIKit

enum FullUIPlayerChrome {
    static let controlSize: CGFloat = 44
    static let symbolFont: Font = .system(size: 18, weight: .semibold)

    static var inset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16
    }

    static func visibilityAnimation(_ visible: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        return visible ? .easeOut(duration: 0.22) : .easeIn(duration: 0.28)
    }
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

    func fullUIPlayerShadow(in shape: some Shape) -> some View {
        background {
            shape
                .fill(.black.opacity(0.22))
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

private struct FullUIPlayerMediaTextModifier: ViewModifier {
    @Environment(\.fullUIPlayerPrefersRegularGlass) private var needsContrast

    func body(content: Content) -> some View {
        content.background {
            if needsContrast {
                Color.clear
                    .fullUIPlayerGlass(in: Capsule(), interactive: false)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
            let glass: Glass = prefersRegularGlass || contrast == .increased
                ? .regular.tint(.black.opacity(0.45))
                : .clear
            content.glassEffect(glass.interactive(interactive), in: glassShape)
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
