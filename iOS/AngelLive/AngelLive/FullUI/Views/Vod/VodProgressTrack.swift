#if canImport(KSPlayer)
import SwiftUI

struct VodProgressTrack: View {
    // A 4 pt rail ends 14 pt above the transport row inside its 44 pt hit target.
    static let baselineOffset = (FullUIPlayerChrome.controlSize - 4) / 2 - 14

    let time: Double
    let duration: Double
    let cues: [Double]
    let isScrubbing: Bool
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onEnd: (Double?) -> Void

    @GestureState private var dragging = false
    @State private var editing = false

    var body: some View {
        GeometryReader { geometry in
            let thickness: CGFloat = isScrubbing ? 6 : 4
            let width = geometry.size.width
            let progress = width * fraction(of: time)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.38 : 0.18))
                    .frame(height: thickness)
                Capsule()
                    .fill(.white)
                    .frame(width: progress, height: thickness)
                ForEach(cues, id: \.self) { cue in
                    Circle()
                        .fill(.white)
                        .frame(width: thickness, height: thickness)
                        .position(x: width * fraction(of: cue), y: geometry.size.height / 2)
                }
                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .position(x: progress, y: geometry.size.height / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .offset(y: Self.baselineOffset)
            .contentShape(.rect)
            .gesture(seekGesture(width: width))
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: FullUIPlayerChrome.controlSize)
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(fullUIPlayerTime(time)) / \(fullUIPlayerTime(duration))")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onEnd(min(time + 10, duration))
            case .decrement: onEnd(max(time - 10, 0))
            @unknown default: break
            }
        }
        .onChange(of: dragging) { _, active in
            if !active && editing { finish(nil) }
        }
        .onDisappear {
            if editing { finish(nil) }
        }
    }

    private func fraction(of time: Double) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragging) { _, active, _ in active = true }
            .onChanged { value in
                guard isEnabled, width > 0 else { return }
                editing = true
                onChange(duration * min(max(value.location.x / width, 0), 1))
            }
            .onEnded { value in
                guard editing, width > 0 else { return }
                finish(duration * min(max(value.location.x / width, 0), 1))
            }
    }

    private func finish(_ target: Double?) {
        editing = false
        onEnd(target)
    }
}
#endif
