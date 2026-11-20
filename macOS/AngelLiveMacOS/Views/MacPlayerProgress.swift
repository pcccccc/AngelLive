import AppKit
import SwiftUI
import AngelLiveDependencies

func macPlayerTime(_ seconds: Double) -> String {
    let value = seconds >= 0 ? (Int(exactly: seconds.rounded(.down)) ?? 0) : 0
    if value >= 3600 {
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    return String(format: "%02d:%02d", value / 60, value % 60)
}

struct MacPlayerProgressRow: View {
    static let buttonGap: CGFloat = 8
    private static let hitHeight: CGFloat = 44

    let currentTime: Double
    let duration: Double
    @Binding var position: Double
    let isScrubbing: Bool
    let canSeek: Bool
    let onEditingChanged: (Bool) -> Void
    let onCancel: () -> Void
    let seekBy: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            progressLabel(currentTime)
            Color.clear
                .overlay {
                    GeometryReader { geometry in
                        let fraction = min(1, max(0, position / duration))
                        let x = geometry.size.width * fraction
                        let height: CGFloat = isScrubbing ? 6 : 4
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.38))
                            Capsule().fill(.white).frame(width: x)
                        }
                        .frame(height: height)
                        .overlay(alignment: .leading) {
                            if isScrubbing {
                                Circle().fill(.white).frame(width: 16, height: 16).offset(x: x - 8)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    MacPlayerTimelineSlider(
                        value: $position, maximum: duration, isEnabled: canSeek,
                        valueDescription: "\(macPlayerTime(position)) / \(macPlayerTime(duration))",
                        onEditingChanged: onEditingChanged, onCancel: onCancel, seekBy: seekBy
                    )
                    .frame(height: Self.hitHeight)
                }
            progressLabel(duration)
        }
        .frame(height: Self.hitHeight)
    }

    private func progressLabel(_ value: Double) -> some View {
        Text(macPlayerTime(value))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .macPlayerMediaText()
            .opacity(isScrubbing ? 0 : 1)
            .accessibilityHidden(isScrubbing)
    }
}

#if canImport(KSPlayer)
struct MacPlayerScrubPreview: View {
    let position: Double
    let duration: Double
    let state: SeekPreviewState

    var body: some View {
        HStack(spacing: 8) {
            Text(macPlayerTime(position))
            Text("/ \(macPlayerTime(duration))").foregroundStyle(.white.opacity(0.68))
        }
        .font(.system(size: 28, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .macPlayerMediaText()
        .overlay(alignment: .top) {
            scrubPreview
                .padding(.bottom, 8)
                .alignmentGuide(.top) { $0[.bottom] }
        }
    }

    private var scrubPreview: some View {
        ZStack(alignment: .bottom) {
            Color.black
            switch state {
            case .frame(let image, let actualTime):
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                if abs(actualTime - position) > 0.5 {
                    Text("预览约 \(macPlayerTime(actualTime))")
                        .font(.caption2.monospacedDigit())
                        .padding(4)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(4)
                }
            case .idle, .loading:
                ProgressView().controlSize(.small).frame(maxHeight: .infinity)
            case .unavailable:
                Text("暂无法预览").font(.caption).frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 128, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16)) }
    }
}
#endif

/// Native focus and accessibility for the custom progress track.
private struct MacPlayerTimelineSlider: NSViewRepresentable {
    @Binding var value: Double
    let maximum: Double
    let isEnabled: Bool
    let valueDescription: String
    let onEditingChanged: (Bool) -> Void
    let onCancel: () -> Void
    let seekBy: (Double) -> Void

    func makeNSView(context: Context) -> MacPlayerNativeTimeline {
        let slider = MacPlayerNativeTimeline(value: value, minValue: 0, maxValue: maximum,
                                              target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.focusRingType = .exterior
        return slider
    }

    func updateNSView(_ slider: MacPlayerNativeTimeline, context: Context) {
        context.coordinator.parent = self
        slider.maxValue = maximum
        if !slider.isTrackingEdit { slider.doubleValue = value }
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(String(localized: "播放进度"))
        slider.spokenValue = valueDescription
        slider.onEditingChanged = onEditingChanged
        slider.onPointerValue = { value = $0 }
        slider.onCancel = onCancel
        slider.seekBy = seekBy
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MacPlayerTimelineSlider
        init(_ parent: MacPlayerTimelineSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: MacPlayerNativeTimeline) {
            let discreteEdit = !sender.isTrackingEdit
            if discreteEdit { parent.onEditingChanged(true) }
            parent.value = sender.doubleValue
            if discreteEdit { parent.onEditingChanged(false) }
        }
    }
}

private final class MacPlayerNativeTimeline: NSSlider {
    var isTrackingEdit = false
    var spokenValue = ""
    var onEditingChanged: ((Bool) -> Void)?
    var onPointerValue: ((Double) -> Void)?
    var onCancel: (() -> Void)?
    var seekBy: ((Double) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func accessibilityValueDescription() -> String? { spokenValue }
    override func draw(_ dirtyRect: NSRect) {}
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 12) / 2)) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if isTrackingEdit && event.charactersIgnoringModifiers == "\u{1B}" {
            isTrackingEdit = false
            onCancel?()
        } else if isEnabled, modifiers.isEmpty || modifiers == .shift,
                  let key = event.specialKey, key == .leftArrow || key == .rightArrow {
            let step = modifiers == .shift ? 15.0 : 5.0
            seekBy?(key == .leftArrow ? -step : step)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isTrackingEdit = true
        onEditingChanged?(true)
        updatePointerValue(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isTrackingEdit && isEnabled { updatePointerValue(event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingEdit else { return }
        if isEnabled { updatePointerValue(event) }
        isTrackingEdit = false
        onEditingChanged?(false)
    }

    private func updatePointerValue(_ event: NSEvent) {
        guard bounds.width > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fraction = min(1, max(0, (point.x - bounds.minX) / bounds.width))
        doubleValue = Double(fraction) * maxValue
        onPointerValue?(doubleValue)
    }
}
