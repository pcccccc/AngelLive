import SwiftUI

/// The player's existing 22%-circle loading mark, shared by opt-in FullUI surfaces.
/// Inherits `.tint`; use `.tint(.white)` for the original white-at-90% player appearance.
public struct ArcSpinner: View {
    public let size: CGFloat
    public let lineWidth: CGFloat
    public let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat, lineWidth: CGFloat, isAnimating: Bool = true) {
        self.size = size
        self.lineWidth = lineWidth
        self.isAnimating = isAnimating
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion || !isAnimating)) { context in
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(0.9)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(reduceMotion || !isAnimating ? 0 : angle(at: context.date)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载"))
        .allowsHitTesting(false)
    }

    private func angle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.95) / 0.95 * 360
    }
}

/// Changes only indeterminate loading. Determinate progress keeps native linear semantics.
/// The disabled branch invokes the native default style without changing the host view's identity.
public struct ArcProgressViewStyle: ProgressViewStyle {
    public let isEnabled: Bool
    public let size: CGFloat?
    public let lineWidth: CGFloat?
    @Environment(\.controlSize) private var controlSize

    public init(isEnabled: Bool = true, size: CGFloat? = nil, lineWidth: CGFloat? = nil) {
        self.isEnabled = isEnabled
        self.size = size
        self.lineWidth = lineWidth
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if !isEnabled {
            DefaultProgressViewStyle().makeBody(configuration: configuration)
        } else if configuration.fractionCompleted != nil {
            LinearProgressViewStyle().makeBody(configuration: configuration)
        } else {
            VStack(spacing: 8) {
                ArcSpinner(size: size ?? metrics.size, lineWidth: lineWidth ?? metrics.lineWidth)
                    .accessibilityHidden(configuration.label != nil)
                if let label = configuration.label { label }
                if let currentValueLabel = configuration.currentValueLabel { currentValueLabel }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var metrics: (size: CGFloat, lineWidth: CGFloat) {
        // Compact indicators keep compact control footprints; large uses each existing player.
        #if os(macOS)
        switch controlSize {
        case .mini: return (10, 1)
        case .small: return (12, 1.2)
        case .regular: return (16, 1.3)
        default: return (34, 1.5)
        }
        #elseif os(tvOS)
        switch controlSize {
        case .mini: return (24, 1.5)
        case .small: return (32, 1.8)
        case .regular: return (48, 2)
        default: return (64, 2.5)
        }
        #else
        switch controlSize {
        case .mini: return (12, 1)
        case .small: return (16, 1.2)
        case .regular: return (20, 1.5)
        default: return (42, 1.8)
        }
        #endif
    }
}

public extension View {
    /// Install outside presentation modifiers so sheets inherit the same style.
    /// Pass the FullUI availability condition directly; do not conditionally wrap the content.
    func fullUIArcLoadingStyle(
        isEnabled: Bool = true,
        size: CGFloat? = nil,
        lineWidth: CGFloat? = nil
    ) -> some View {
        progressViewStyle(ArcProgressViewStyle(isEnabled: isEnabled, size: size, lineWidth: lineWidth))
    }
}
