import SwiftUI
import UIKit

struct ShortDramaProgressSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ShortDramaAccessibleSlider,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: 44)
    }

    func makeUIView(context: Context) -> ShortDramaAccessibleSlider {
        let slider = ShortDramaAccessibleSlider()
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.34)
        slider.setThumbImage(Self.thumbImage(diameter: 10), for: .normal)
        slider.setThumbImage(Self.thumbImage(diameter: 14), for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.beginEditing(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.endEditing(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        slider.onAccessibilityAdjustment = { [weak coordinator = context.coordinator] value in
            coordinator?.commitAccessibilityAdjustment(value: value)
        }
        return slider
    }

    func updateUIView(_ slider: ShortDramaAccessibleSlider, context: Context) {
        context.coordinator.parent = self
        slider.isEnabled = isEnabled
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue
        if !slider.isTracking {
            let nextValue = Float(min(max(value, range.lowerBound), range.upperBound))
            if slider.value != nextValue { slider.value = nextValue }
        }
    }

    static func dismantleUIView(_ slider: ShortDramaAccessibleSlider, coordinator: Coordinator) {
        slider.onAccessibilityAdjustment = nil
        slider.removeTarget(coordinator, action: nil, for: .allEvents)
    }

    private static func thumbImage(diameter: CGFloat) -> UIImage {
        let canvasDiameter: CGFloat = 44
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: canvasDiameter, height: canvasDiameter),
            format: format
        )
        let inset = (canvasDiameter - diameter) / 2
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: inset, y: inset, width: diameter, height: diameter)
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShortDramaProgressSlider
        private var isEditing = false

        init(_ parent: ShortDramaProgressSlider) {
            self.parent = parent
        }

        @objc func beginEditing(_ sender: UISlider) {
            guard !isEditing else { return }
            isEditing = true
            parent.onEditingChanged(true)
        }

        @objc func valueChanged(_ sender: UISlider) {
            let nextValue = Double(sender.value)
            parent.value = nextValue
        }

        @objc func endEditing(_ sender: UISlider) {
            guard isEditing else { return }
            isEditing = false
            parent.onEditingChanged(false)
            parent.onCommit(Double(sender.value))
        }

        func commitAccessibilityAdjustment(value: Float) {
            let nextValue = Double(value)
            parent.value = nextValue
            parent.onCommit(nextValue)
        }
    }
}

@MainActor
final class ShortDramaAccessibleSlider: UISlider {
    var onAccessibilityAdjustment: ((Float) -> Void)?

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let track = super.trackRect(forBounds: bounds)
        return CGRect(x: track.minX, y: track.midY - 1, width: track.width, height: 2)
    }

    override func accessibilityIncrement() {
        super.accessibilityIncrement()
        onAccessibilityAdjustment?(value)
    }

    override func accessibilityDecrement() {
        super.accessibilityDecrement()
        onAccessibilityAdjustment?(value)
    }
}
