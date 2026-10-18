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
    let trackOffset: CGFloat
    let onCancel: () -> Void

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool,
        accessibilityLabel: String,
        accessibilityValue: String,
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping (Double) -> Void,
        trackOffset: CGFloat = 0,
        onCancel: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
        self.trackOffset = trackOffset
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ShortDramaAccessibleSlider,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: 44)
    }

    func makeUIView(context: Context) -> ShortDramaAccessibleSlider {
        let slider = ShortDramaAccessibleSlider()
        slider.updateRange(range, trackOffset: trackOffset)
        slider.setProgressValue(value, notify: false)
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue
        slider.isEnabled = isEnabled

        slider.onValueChanged = { [weak coordinator = context.coordinator] value in
            coordinator?.valueChanged(value)
        }
        slider.onEditingChanged = { [weak coordinator = context.coordinator] isEditing in
            coordinator?.editingChanged(isEditing)
        }
        slider.onCommit = { [weak coordinator = context.coordinator] value in
            coordinator?.commit(value)
        }
        slider.onCancel = { [weak coordinator = context.coordinator] in
            coordinator?.cancel()
        }
        return slider
    }

    func updateUIView(_ slider: ShortDramaAccessibleSlider, context: Context) {
        context.coordinator.parent = self
        slider.updateRange(range, trackOffset: trackOffset)
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue

        if !isEnabled {
            slider.cancelActiveInteraction()
        }
        slider.isEnabled = isEnabled

        // Playback sampling can continue while the user drags. Keep the value
        // owned by the active touch until the interaction ends or is cancelled.
        if !slider.isEditing {
            slider.setProgressValue(value, notify: false)
        }
    }

    static func dismantleUIView(_ slider: ShortDramaAccessibleSlider, coordinator: Coordinator) {
        slider.cancelActiveInteraction()
        slider.onValueChanged = nil
        slider.onEditingChanged = nil
        slider.onCommit = nil
        slider.onCancel = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShortDramaProgressSlider

        init(_ parent: ShortDramaProgressSlider) {
            self.parent = parent
        }

        func valueChanged(_ value: Double) {
            parent.value = value
        }

        func editingChanged(_ isEditing: Bool) {
            parent.onEditingChanged(isEditing)
        }

        func commit(_ value: Double) {
            parent.onCommit(value)
        }

        func cancel() {
            parent.onCancel()
        }
    }
}

@MainActor
final class ShortDramaAccessibleSlider: UIControl {
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onCommit: ((Double) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isEditing = false
    private var minimumValue = 0.0
    private var maximumValue = 1.0
    private var value = 0.0
    private var trackOffset: CGFloat = 0
    private var suspendedNavigationGestures: [SuspendedGesture] = []
    private weak var suspendedPresentation: UIViewController?
    private var wasModalInPresentation = false

    private struct SuspendedGesture {
        weak var recognizer: UIGestureRecognizer?
        let wasEnabled: Bool
    }

    private var trackThickness: CGFloat { isEditing ? 3 : 2 }
    private var trackRect: CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.midY + trackOffset - trackThickness / 2,
            width: bounds.width,
            height: trackThickness
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    func updateRange(_ range: ClosedRange<Double>, trackOffset: CGFloat) {
        minimumValue = range.lowerBound
        maximumValue = range.upperBound
        self.trackOffset = trackOffset
        setNeedsDisplay()
    }

    @discardableResult
    func setProgressValue(_ proposedValue: Double, notify: Bool) -> Bool {
        let nextValue = clamp(proposedValue)
        guard nextValue != value else { return false }

        value = nextValue
        setNeedsDisplay()
        if notify {
            onValueChanged?(nextValue)
        }
        return true
    }

    func cancelActiveInteraction() {
        guard isEditing else { return }
        finishEditing(committing: false)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let track = trackRect
        let cornerRadius = track.height / 2
        let inactiveAlpha: CGFloat = isEnabled ? 0.34 : 0.18
        context.setFillColor(UIColor.white.withAlphaComponent(inactiveAlpha).cgColor)
        context.addPath(UIBezierPath(roundedRect: track, cornerRadius: cornerRadius).cgPath)
        context.fillPath()

        let fraction = valueFraction
        if fraction > 0 {
            let progress = CGRect(
                x: track.minX,
                y: track.minY,
                width: track.width * fraction,
                height: track.height
            )
            context.setFillColor(UIColor.white.withAlphaComponent(isEnabled ? 1 : 0.55).cgColor)
            context.addPath(UIBezierPath(roundedRect: progress, cornerRadius: cornerRadius).cgPath)
            context.fillPath()
        }

        if isEditing {
            let markerWidth: CGFloat = 3
            let markerHeight: CGFloat = 8
            let marker = CGRect(
                x: track.minX + track.width * fraction - markerWidth / 2,
                y: track.midY - markerHeight / 2,
                width: markerWidth,
                height: markerHeight
            )
            context.setFillColor(UIColor.white.cgColor)
            context.fill(marker)
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }

        suspendNavigationGestures()
        isEditing = true
        setNeedsDisplay()
        onEditingChanged?(true)
        guard isEditing else { return true }
        updateValue(at: touch.location(in: self))
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEditing else { return false }
        updateValue(at: touch.location(in: self))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let touch else {
            // UIKit may route cancellation through endTracking with a nil touch.
            // Only a real touch-up is allowed to submit a seek.
            super.endTracking(touch, with: event)
            cancelActiveInteraction()
            return
        }

        if isEditing {
            updateValue(at: touch.location(in: self))
        }
        super.endTracking(touch, with: event)
        finishEditing(committing: true)
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        cancelActiveInteraction()
    }

    override func accessibilityIncrement() {
        adjustAccessibilityValue(by: 5)
    }

    override func accessibilityDecrement() {
        adjustAccessibilityValue(by: -5)
    }

    @objc private func jumpToBeginning() -> Bool {
        guard isEnabled else { return false }
        setProgressValue(minimumValue, notify: true)
        onCommit?(value)
        return true
    }

    @objc private func jumpToEnd() -> Bool {
        guard isEnabled else { return false }
        setProgressValue(maximumValue, notify: true)
        onCommit?(value)
        return true
    }

    private var valueFraction: CGFloat {
        let span = maximumValue - minimumValue
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - minimumValue) / span, 0), 1))
    }

    private func configureAccessibility() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "跳到开头",
                target: self,
                selector: #selector(jumpToBeginning)
            ),
            UIAccessibilityCustomAction(
                name: "跳到结尾",
                target: self,
                selector: #selector(jumpToEnd)
            )
        ]
    }

    private func updateValue(at point: CGPoint) {
        let track = trackRect
        guard track.width > 0, maximumValue > minimumValue else {
            setProgressValue(minimumValue, notify: true)
            return
        }

        // Both drawing and touch mapping use the same full-width track bounds.
        // Values outside the control during a drag stay clamped to the endpoints.
        let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
        let nextValue = minimumValue + Double(fraction) * (maximumValue - minimumValue)
        setProgressValue(nextValue, notify: true)
    }

    private func adjustAccessibilityValue(by delta: Double) {
        guard isEnabled else { return }
        let nextValue = clamp(value + delta)
        guard setProgressValue(nextValue, notify: true) else { return }
        onCommit?(nextValue)
    }

    private func finishEditing(committing: Bool) {
        guard isEditing else { return }
        isEditing = false
        restoreNavigationGestures()
        setNeedsDisplay()
        onEditingChanged?(false)

        if committing {
            onCommit?(value)
        } else {
            onCancel?()
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, minimumValue), maximumValue)
    }

    private func suspendNavigationGestures() {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                var presentation = controller
                while let parent = presentation.parent { presentation = parent }
                if presentation.presentingViewController != nil {
                    suspendedPresentation = presentation
                    wasModalInPresentation = presentation.isModalInPresentation
                    presentation.isModalInPresentation = true
                }
                var gestures: [UIGestureRecognizer] = []
                if let navigation = controller.navigationController {
                    if let edgePop = navigation.interactivePopGestureRecognizer { gestures.append(edgePop) }
                    if #available(iOS 26.0, *), let contentPop = navigation.interactiveContentPopGestureRecognizer {
                        gestures.append(contentPop)
                    }
                }
                // A horizontal scrub must not become an interactive page return.
                // Restore each recognizer's original setting when this touch ends.
                suspendedNavigationGestures = gestures.map {
                    SuspendedGesture(recognizer: $0, wasEnabled: $0.isEnabled)
                }
                gestures.forEach { $0.isEnabled = false }
                return
            }
            responder = current.next
        }
    }

    private func restoreNavigationGestures() {
        let suspended = suspendedNavigationGestures
        suspendedNavigationGestures = []
        suspended.forEach { $0.recognizer?.isEnabled = $0.wasEnabled }
        suspendedPresentation?.isModalInPresentation = wasModalInPresentation
        suspendedPresentation = nil
    }
}
