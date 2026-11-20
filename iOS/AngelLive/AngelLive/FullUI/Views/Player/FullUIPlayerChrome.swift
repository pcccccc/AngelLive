import AngelLiveCore
import Kingfisher
import SharedAssets
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

enum FullUIPlayerDetailChrome {
    static let inset: CGFloat = 16
    static let pillHeight: CGFloat = 32
    static let pillFill = Color.primary.opacity(0.075)
    static var accent: Color { SharedAssets.Colors.appAccent }
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

    func fullUIPlayerCircularControl() -> some View {
        let diameter = FullUIPlayerChrome.controlSize
        let circle = Circle()
        return frame(width: diameter, height: diameter)
            .background {
                // Give the glass its own square surface and bound its rim to the circle.
                Color.clear
                    .frame(width: diameter, height: diameter)
                    .fullUIPlayerGlass(in: circle.size(width: diameter, height: diameter))
                    .clipShape(circle)
            }
    }

    func fullUIPlayerMediaText() -> some View {
        shadow(color: .black.opacity(0.85), radius: 3, y: 1)
    }
}

struct FullUIPlayerBackButton: View {
    @Environment(\.layoutDirection) private var layoutDirection

    // White glyph bounds in the 3× raster of the 18 pt semibold symbol.
    static let visibleGlyphWidth: CGFloat = 28.0 / 3.0

    var centersSymbol = false
    var label: LocalizedStringKey = "返回"
    var width = FullUIPlayerChrome.controlSize
    var symbolLeadingInset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        // At 18 pt semibold, chevron.backward has 1 pt leading and 3 pt
        // trailing side bearings. Remove the leading bearing at the edge,
        // or shift by half their difference to center the visible glyph.
        let leadingBearing: CGFloat = 1
        let trailingBearing: CGFloat = 3
        let opticalShift = centersSymbol ? (trailingBearing - leadingBearing) / 2 : -leadingBearing

        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(FullUIPlayerChrome.symbolFont)
                .foregroundStyle(.white)
                .fullUIPlayerMediaText()
                .offset(x: layoutDirection == .leftToRight ? opticalShift : -opticalShift)
                .padding(.leading, symbolLeadingInset)
                .frame(width: width, height: FullUIPlayerChrome.controlSize,
                       alignment: centersSymbol ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FullUIPlayerTimeLabel: View {
    let time: Double

    var body: some View {
        Text(fullUIPlayerTime(time))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .fullUIPlayerMediaText()
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

private struct FullUIPlayerGlassModifier<GlassShape: Shape>: ViewModifier {
    let glassShape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass = Glass.regular.tint(.black.opacity(0.45)).interactive(interactive)
            content.background {
                Color.clear.glassEffect(glass, in: glassShape)
            }
        } else {
            content.background(.ultraThinMaterial, in: glassShape)
        }
    }
}

struct FullUIPlayerGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // A glass container makes this single capsule refract its own labels.
        HStack(spacing: 0, content: content)
            .fullUIPlayerGlass(in: Capsule())
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
                    .padding(.bottom, controlsVisible ? 52 + controlBottomInset : 24)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: status != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
