import SwiftUI
#if canImport(KSPlayer)
import AngelLiveDependencies

struct TVPlayerTimeline: View {
    static let height: CGFloat = 70
    static let buttonGap: CGFloat = 13

    static func trackHeight(isScrubbing: Bool) -> CGFloat { isScrubbing ? 6 : 4 }

    let elapsed: Double
    let duration: Double
    let target: Double?
    let isFocused: Bool
    var cues: [Double] = []

    private var isScrubbing: Bool { target != nil }
    private var fraction: CGFloat { CGFloat(min(max((target ?? elapsed) / duration, 0), 1)) }

    var body: some View {
        HStack(spacing: 8) {
            time(elapsed)
            GeometryReader { geometry in
                let playedWidth = geometry.size.width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.38))
                    Capsule().fill(.white).frame(width: playedWidth)
                    ForEach(Array(cues.enumerated()), id: \.offset) { _, cue in
                        if cue.isFinite, duration > 0, (0...duration).contains(cue) {
                            let size: CGFloat = isScrubbing ? 6 : 4
                            Circle().fill(.white).frame(width: size, height: size)
                                .position(x: geometry.size.width * CGFloat(cue / duration),
                                          y: geometry.size.height / 2)
                                .accessibilityHidden(true)
                        }
                    }
                    if isFocused {
                        Capsule().strokeBorder(.white.opacity(0.75), lineWidth: 2).padding(-6)
                    }
                    if isScrubbing {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .position(x: playedWidth, y: geometry.size.height / 2)
                    }
                }
            }
            .frame(height: Self.trackHeight(isScrubbing: isScrubbing))
            time(duration)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
    }

    private func time(_ value: Double) -> some View {
        Text(tvPlayerTimeLabel(value))
            .font(.system(size: 20, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: .black.opacity(0.85), radius: 3, y: 1)
            .opacity(isScrubbing ? 0 : 1)
            .accessibilityHidden(true)
    }
}

struct TVPlayerSeekReadout: View {
    // Use the same television scale as the 70 pt controls versus 44 pt on iOS.
    private static let timeFontSize: CGFloat = 45
    private static let previewLongEdge: CGFloat = 204
    private static let previewSpacing: CGFloat = 8

    let time: Double
    let duration: Double
    let preview: SeekPreviewModel

    var body: some View {
        HStack(spacing: 0) {
            Text(tvPlayerTimeLabel(time))
            Text(" / \(tvPlayerTimeLabel(duration))")
                .foregroundStyle(.white.opacity(0.68))
        }
        .font(.system(size: Self.timeFontSize, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .tvPlayerMediaText()
        .overlay(alignment: .top) {
            if case .frame(let image, _) = preview.state {
                let scale = Self.previewLongEdge / CGFloat(max(image.width, image.height))
                let previewWidth = CGFloat(image.width) * scale
                let previewHeight = CGFloat(image.height) * scale
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: previewWidth, height: previewHeight)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16))
                    }
                    // The overlay starts at the time row's top edge. Keep the row centered as frames arrive.
                    .offset(y: -(previewHeight + Self.previewSpacing))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#endif

func tvPlayerTimeLabel(_ seconds: Double) -> String {
    let value = Int(exactly: max(0, seconds).rounded(.towardZero)) ?? 0
    if value >= 3_600 {
        return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
    }
    return String(format: "%02d:%02d", value / 60, value % 60)
}
