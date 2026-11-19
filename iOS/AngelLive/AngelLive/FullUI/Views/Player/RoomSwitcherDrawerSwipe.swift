import SwiftUI
import UIKit

struct RoomSwitcherDrawerSwipe: ViewModifier {
    let width: CGFloat
    let trailingSafeArea: CGFloat
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var offset: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @State private var settlement: Settlement?
    @State private var rejectedLegacyDrag = false
    @GestureState private var legacyDragActive = false

    private var direction: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }
    private var travel: CGFloat { width + trailingSafeArea }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: settlement == nil)) { timeline in
            draggable(content)
                .offset(x: direction * clamped(settlement?.offset(at: timeline.date) ?? offset))
                .onChange(of: settlement?.hasFinished(at: timeline.date) == true) { _, finished in
                    if finished { finishSettlement() }
                }
        }
    }

    @ViewBuilder
    private func draggable(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(DrawerPan(
                shouldBegin: { canBegin(x: $0.x, y: $0.y) },
                onBegan: { beginDrag(translation: $0 * direction) },
                onChanged: { updateDrag(translation: $0 * direction) },
                onEnded: { endDrag(translation: $0 * direction, velocity: $1 * direction) },
                onCancelled: cancelDrag
            ))
        } else {
            content
                .simultaneousGesture(legacyDrag)
                .onChange(of: legacyDragActive) { _, active in
                    if !active {
                        rejectedLegacyDrag = false
                        cancelDrag()
                    }
                }
        }
    }

    private var legacyDrag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($legacyDragActive) { _, active, _ in active = true }
            .onChanged { value in
                let x = value.translation.width
                guard !rejectedLegacyDrag else { return }
                if dragOrigin != nil {
                    updateDrag(translation: x * direction)
                } else if canBegin(x: x, y: value.translation.height) {
                    beginDrag(translation: x * direction)
                } else {
                    rejectedLegacyDrag = true
                }
            }
            .onEnded { value in
                endDrag(translation: value.translation.width * direction, velocity: value.velocity.width * direction)
                rejectedLegacyDrag = false
            }
    }

    private func canBegin(x: CGFloat, y: CGFloat) -> Bool {
        abs(x) > abs(y) * 1.25 && (x * direction > 0 || settlement != nil)
    }

    private func beginDrag(translation: CGFloat) {
        if let settlement {
            // Catch the drawer at its current on-screen position during a return or dismissal.
            dragOrigin = clamped(settlement.offset(at: .now)) - translation
            self.settlement = nil
        } else {
            dragOrigin = offset
        }
        updateDrag(translation: translation)
    }

    private func updateDrag(translation: CGFloat) {
        guard let dragOrigin else { return }
        offset = clamped(dragOrigin + translation)
    }

    private func endDrag(translation: CGFloat, velocity: CGFloat) {
        guard dragOrigin != nil else { return }
        updateDrag(translation: translation)
        // Keep a slow half-width drag reversible. A flick gets up to 130 pt of projected travel.
        let projectedOffset = offset + min(130, max(-130, velocity * 0.15))
        settle(to: projectedOffset > width * 0.55 ? travel : 0, velocity: velocity)
    }

    private func cancelDrag() {
        guard dragOrigin != nil else { return }
        settle(to: 0, velocity: 0)
    }

    private func settle(to target: CGFloat, velocity: CGFloat) {
        dragOrigin = nil
        if reduceMotion || offset == target {
            offset = target
            if target > 0 { onDismiss() }
        } else {
            settlement = Settlement(from: offset, target: target, velocity: velocity)
        }
    }

    private func finishSettlement() {
        guard let settlement, settlement.hasFinished(at: .now) else { return }
        offset = settlement.target
        self.settlement = nil
        if offset > 0 { onDismiss() }
    }

    private func clamped(_ position: CGFloat) -> CGFloat {
        min(travel, max(0, position))
    }

    private struct Settlement {
        private static let spring = Spring(duration: 0.28, bounce: 0)
        private let start = Date.now
        let from: CGFloat
        let target: CGFloat
        let velocity: CGFloat
        private let duration: TimeInterval

        init(from: CGFloat, target: CGFloat, velocity: CGFloat) {
            self.from = from
            self.target = target
            self.velocity = velocity
            duration = Self.spring.settlingDuration(
                target: target - from, initialVelocity: velocity, epsilon: 0.5
            )
        }

        func hasFinished(at date: Date) -> Bool {
            date.timeIntervalSince(start) >= duration
        }

        func offset(at date: Date) -> CGFloat {
            guard !hasFinished(at: date) else { return target }
            return from + Self.spring.value(
                target: target - from,
                initialVelocity: velocity,
                time: max(0, date.timeIntervalSince(start))
            )
        }
    }
}

@available(iOS 18.0, *)
private struct DrawerPan: UIGestureRecognizerRepresentable {
    let shouldBegin: (CGPoint) -> Bool
    let onBegan: (CGFloat) -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(shouldBegin: shouldBegin)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.shouldBegin = shouldBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let window = recognizer.view?.window
        let translation = recognizer.translation(in: window).x
        switch recognizer.state {
        case .began: onBegan(translation)
        case .changed: onChanged(translation)
        case .ended: onEnded(translation, recognizer.velocity(in: window).x)
        case .cancelled: onCancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBegin: (CGPoint) -> Bool

        init(shouldBegin: @escaping (CGPoint) -> Bool) {
            self.shouldBegin = shouldBegin
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            return shouldBegin(pan.translation(in: pan.view?.window))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            // Let the scroll view pan proceed once the drawer pan rejects the vertical direction.
            (other.view as? UIScrollView)?.panGestureRecognizer === other
        }
    }
}
