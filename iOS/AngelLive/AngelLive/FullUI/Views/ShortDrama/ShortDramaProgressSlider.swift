import SwiftUI
import UIKit

struct ShortDramaProgressSlider: UIViewRepresentable {
    static let hitHeight: CGFloat = 44
    static let visibleTrackHeight: CGFloat = 4

    @Binding var value: Double
    @Environment(\.layoutDirection) private var layoutDirection
    let range: ClosedRange<Double>
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void
    let showsCompactTrack: Bool
    let onCancel: () -> Void

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool,
        accessibilityLabel: String,
        accessibilityValue: String,
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping (Double) -> Void,
        showsCompactTrack: Bool,
        onCancel: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
        self.showsCompactTrack = showsCompactTrack
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
        CGSize(width: proposal.width ?? uiView.bounds.width, height: Self.hitHeight)
    }

    func makeUIView(context: Context) -> ShortDramaAccessibleSlider {
        let slider = ShortDramaAccessibleSlider()
        slider.updateRange(range, showsCompactTrack: showsCompactTrack)
        slider.setProgressValue(value, notify: false)
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue
        slider.isEnabled = isEnabled
        slider.isUserInteractionEnabled = isEnabled
        slider.layoutDirection = layoutDirection

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
        slider.updateRange(range, showsCompactTrack: showsCompactTrack)
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue

        if !isEnabled {
            slider.cancelActiveInteraction()
        }
        slider.isEnabled = isEnabled
        slider.isUserInteractionEnabled = isEnabled
        slider.layoutDirection = layoutDirection

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
    var layoutDirection: LayoutDirection = .leftToRight
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onCommit: ((Double) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isEditing = false {
        didSet {
            thumb.isHidden = !isEditing
            setNeedsDisplay()
        }
    }
    private var minimumValue = 0.0
    private var maximumValue = 1.0
    private var value = 0.0
    private var showsCompactTrack = false
    private let thumb = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
    private var suspendedNavigationGestures: [SuspendedGesture] = []
    private weak var suspendedPresentation: UIViewController?
    private var wasModalInPresentation = false

    private struct SuspendedGesture {
        weak var recognizer: UIGestureRecognizer?
        let wasEnabled: Bool
    }

    private var trackThickness: CGFloat {
        if isEditing { return 6 }
        return showsCompactTrack ? 2 : ShortDramaProgressSlider.visibleTrackHeight
    }

    private var trackRect: CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.midY - trackThickness / 2,
            width: bounds.width,
            height: trackThickness
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func updateRange(_ range: ClosedRange<Double>, showsCompactTrack: Bool) {
        minimumValue = range.lowerBound
        maximumValue = range.upperBound
        self.showsCompactTrack = showsCompactTrack
        setNeedsDisplay()
        if isEditing { setNeedsLayout() }
    }

    @discardableResult
    func setProgressValue(_ proposedValue: Double, notify: Bool) -> Bool {
        let nextValue = clamp(proposedValue)
        guard nextValue != value else { return false }

        value = nextValue
        setNeedsDisplay()
        if isEditing { setNeedsLayout() }
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
        let showsEnabledColors = isEnabled || showsCompactTrack
        let inactiveAlpha: CGFloat = showsEnabledColors ? 0.38 : 0.18
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
            context.setFillColor(UIColor.white.withAlphaComponent(showsEnabledColors ? 1 : 0.55).cgColor)
            context.addPath(UIBezierPath(roundedRect: progress, cornerRadius: cornerRadius).cgPath)
            context.fillPath()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let track = trackRect
        thumb.center = CGPoint(x: track.minX + track.width * valueFraction, y: track.midY)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }

        suspendNavigationGestures()
        isEditing = true
        setNeedsLayout()
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

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = thumb.bounds.width / 2
        thumb.isUserInteractionEnabled = false
        thumb.isHidden = true
        // Keep the whole thumb visible when its center is at either endpoint.
        addSubview(thumb)
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
