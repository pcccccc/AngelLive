import SwiftUI

extension View {
    func tvPlayerPanelFrame(in size: CGSize, clampsHeight: Bool = true) -> some View {
        frame(width: min(size.width * 0.4, 640), height: clampsHeight ? max(0, size.height - 80) : size.height - 80)
            .padding(.vertical, 40)
            .padding(.trailing, 48)
    }

    func tvPanelRowHighlight(_ focused: Bool, idleOpacity: Double = 0) -> some View {
        background(.white.opacity(focused ? 0.25 : idleOpacity), in: .rect(cornerRadius: 16))
            .background(.black.opacity(focused ? 0.8 : 0), in: .rect(cornerRadius: 16))
    }

    func tvPlayerPanelSurface() -> some View {
        padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .focusSection()
    }
}

struct TVPlayerPanelHeader<Close: View>: View {
    let title: Text
    var subtitle: Text? = nil
    @ViewBuilder var close: () -> Close

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                title.font(.system(size: 38, weight: .bold)).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle.font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            close()
        }
        .foregroundStyle(.white)
    }
}

struct TVPlayerPanelCloseButton: View {
    let isFocused: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(TVPanelCloseButtonStyle(isFocused: isFocused, reduceMotion: reduceMotion))
        .accessibilityLabel("关闭")
    }
}

struct TVPlayerLockBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.orange, in: Capsule())
            .lineLimit(1)
    }
}
