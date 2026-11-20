import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct PlayerBackSwipe: ViewModifier {
    let enabled: Bool
    let width: CGFloat
    let exitsFullscreen: Bool
    let revealsRoomList: Bool
    let onReturn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.fullUIRoomPlayerReturnPreview) private var returnPreview
    @Environment(\.fullUIWindowContext) private var windowContext
    @State private var motion: Motion = .idle

    private enum Motion {
        case idle
        case dragging(origin: CGFloat, position: CGFloat)
        case settling(spring: PortraitPlayerSpring, returns: Bool)
        case dismissing(position: CGFloat)
    }

    private var direction: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }

    private var sourcePreview: RoomPlayerReturnPreview? {
        guard !exitsFullscreen, let returnPreview, returnPreview.size == windowContext?.window?.bounds.size else {
            return nil
        }
        return returnPreview
    }

    private var showsSource: Bool { revealsRoomList || sourcePreview != nil }

    private var spring: PortraitPlayerSpring? {
        guard case let .settling(spring, _) = motion else { return nil }
        return spring
    }

    private var canStart: Bool {
        if case .dismissing = motion { return false }
        return enabled
    }

    static func isAtLeadingEdge(_ point: CGPoint, in window: UIWindow, layoutDirection: LayoutDirection) -> Bool {
        let distance = layoutDirection == .leftToRight
            ? point.x - window.bounds.minX : window.bounds.maxX - point.x
        return distance >= 0 && distance < LiveRoomNavigationState.playerBackEdgeWidth
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: spring == nil)) { timeline in
            let offset = position(at: timeline.date)
            let progress = width > 0 ? offset / width : 0
            let source = sourcePreview
            let showsSource = revealsRoomList || source != nil
            content
                .background(alignment: .leading) {
                    if showsSource && progress > 0 {
                        Rectangle()
                            .fill(.black)
                            .shadow(color: .black.opacity(0.25 * (1 - 0.3 * progress)), radius: 10, x: -4 * direction)
                            .frame(width: 24)
                            .ignoresSafeArea(edges: .vertical)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .offset(x: direction * offset)
                .background {
                    ZStack {
                        if let source {
                            PlayerBackSourcePreview(snapshot: source.view)
                                .frame(width: source.size.width, height: source.size.height)
                                .offset(x: -direction * width * 0.3 * (1 - progress))
                                .opacity(progress > 0 ? 1 : 0)
                        }
                        if progress > 0 {
                            Color.black.opacity(showsSource ? 0.1 * (1 - progress) : 1)
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onChange(of: spring.map { reachedTarget($0, at: timeline.date) } == true) { _, finished in
                    if finished { finishSettlement() }
                }
        }
        // The anchor stays in the viewport while the page moves. It doesn't take taps from the page.
        .background {
            PlayerBackPanAnchor(
                enabled: canStart,
                layoutDirection: layoutDirection,
                canReverse: spring != nil,
                onBegan: begin,
                onChanged: update,
                onEnded: end,
                onCancelled: cancel
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: enabled) { _, enabled in
            if !enabled { motion = .idle }
        }
        .onChange(of: width) { motion = .idle }
        .onChange(of: layoutDirection) { motion = .idle }
        .onChange(of: exitsFullscreen) { motion = .idle }
        .onChange(of: reduceMotion) { motion = .idle }
    }

    private func position(at date: Date) -> CGFloat {
        switch motion {
        case .idle: 0
        case let .dragging(_, position): position
        case let .settling(spring, _): clamped(spring.position(at: date))
        case let .dismissing(position): position
        }
    }

    private func clamped(_ position: CGFloat) -> CGFloat {
        min(width, max(0, position))
    }

    private func begin(_ travel: CGFloat) {
        let current = position(at: .now)
        // Subtract the recognition slop when regrabbing so the page doesn't jump.
        let origin = spring == nil ? 0 : current - travel
        motion = .dragging(origin: origin, position: reduceMotion ? 0 : clamped(origin + travel))
    }

    private func update(_ travel: CGFloat) {
        guard !reduceMotion, case let .dragging(origin, _) = motion else { return }
        motion = .dragging(origin: origin, position: clamped(origin + travel))
    }

    private func end(_ travel: CGFloat, _ velocity: CGFloat) {
        guard case let .dragging(origin, _) = motion else { return }
        // Only this swipe counts when it interrupts a spring midway.
        let returns = travel > width * 0.5 || velocity > 800
        settle(from: clamped(origin + travel), velocity: velocity, returns: returns)
    }

    private func cancel() {
        guard case let .dragging(_, position) = motion else { return }
        settle(from: position, velocity: 0, returns: false)
    }

    private func settle(from position: CGFloat, velocity: CGFloat, returns: Bool) {
        // Without a visible source, commit at the current position instead of sliding to a blank page.
        if returns && !exitsFullscreen && !showsSource {
            finish(returns: true, position: reduceMotion ? 0 : position)
            return
        }

        // Fullscreen returns to the same player. Restore its position before rotating.
        let target = returns && !exitsFullscreen ? width : 0
        if reduceMotion || position == target {
            finish(returns: returns, position: reduceMotion ? 0 : target)
        } else {
            motion = .settling(
                spring: PortraitPlayerSpring(from: position, to: target, velocity: velocity),
                returns: returns
            )
        }
    }

    private func finishSettlement() {
        guard case let .settling(spring, returns) = motion, reachedTarget(spring, at: .now) else { return }
        finish(returns: returns, position: spring.to)
    }

    private func reachedTarget(_ spring: PortraitPlayerSpring, at date: Date) -> Bool {
        // Commit as soon as the page moves offscreen, including a spring that briefly overshoots.
        spring.isFinished(at: date) || (spring.to > 0 && spring.position(at: date) >= spring.to)
    }

    private func finish(returns: Bool, position: CGFloat) {
        motion = returns && !exitsFullscreen ? .dismissing(position: position) : .idle
        if returns { onReturn() }
    }
}

private struct PlayerBackSourcePreview: UIViewRepresentable {
    let snapshot: UIView

    func makeUIView(context: Context) -> UIView { snapshot }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// The presentation dismissal guard permits this recognizer on the player canvas.
final class PlayerBackPanGestureRecognizer: UIPanGestureRecognizer {
    private var start: CGPoint?
    private var end: CGPoint?

    var travel: CGPoint {
        guard let start, let window = view?.window else { return .zero }
        let point = end ?? location(in: window)
        return CGPoint(x: point.x - start.x, y: point.y - start.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil, let touch = touches.first, let window = view?.window {
            start = touch.location(in: window)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let window = view?.window {
            end = touch.location(in: window)
        }
        super.touchesEnded(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
        end = nil
    }
}

private struct PlayerBackPanAnchor: UIViewRepresentable {
    let enabled: Bool
    let layoutDirection: LayoutDirection
    let canReverse: Bool
    let onBegan: (CGFloat) -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
    let onCancelled: () -> Void

    func makeUIView(context: Context) -> Anchor {
        Anchor(configuration: self)
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.configuration = self
        view.attach()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        view.detach()
    }

    final class Anchor: UIView, UIGestureRecognizerDelegate {
        private let pan = PlayerBackPanGestureRecognizer()
        var configuration: PlayerBackPanAnchor

        init(configuration: PlayerBackPanAnchor) {
            self.configuration = configuration
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.addTarget(self, action: #selector(handlePan))
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        func attach() {
            guard window != nil else { return }
            // Use the hosting controller so the pan can observe touches on UIKit and SwiftUI children.
            var responder = next
            while let current = responder {
                if let controller = current as? UIViewController,
                   let host = controller.viewIfLoaded, isDescendant(of: host) {
                    if pan.view !== host { host.addGestureRecognizer(pan) }
                    return
                }
                responder = current.next
            }
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
        }

        private var direction: CGFloat { configuration.layoutDirection == .leftToRight ? 1 : -1 }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard configuration.enabled, let window, bounds.contains(touch.location(in: self)) else { return false }
            return PlayerBackSwipe.isAtLeadingEdge(touch.location(in: window), in: window,
                                                   layoutDirection: configuration.layoutDirection)
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let travel = pan.travel
            return configuration.enabled && abs(travel.x) > abs(travel.y) * 1.25
                && (travel.x * direction > 0 || configuration.canReverse)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            // UIKit scroll pans and the drawer wait for the edge pan to fail.
            other is UIPanGestureRecognizer
        }

        @objc private func handlePan() {
            let travel = pan.travel.x * direction
            switch pan.state {
            case .began: configuration.onBegan(travel)
            case .changed: configuration.onChanged(travel)
            case .ended where configuration.enabled:
                configuration.onEnded(travel, pan.velocity(in: window).x * direction)
            case .ended, .cancelled: configuration.onCancelled()
            default: break
            }
        }
    }
}
