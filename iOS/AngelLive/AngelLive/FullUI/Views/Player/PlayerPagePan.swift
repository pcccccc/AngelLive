import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct PlayerPanAction {
    enum Kind: String {
        case back, page, hideControls, restoreControls, episode, openDrawer
    }

    let kind: Kind
    let axis: Axis
    var sign: CGFloat = 1
    let begin: (CGFloat) -> Void
    let update: (CGFloat) -> Void
    var canEnd: (CGPoint) -> Bool = { _ in true }
    let end: (CGFloat, CGFloat) -> Void
    let cancel: () -> Void

    func component(of point: CGPoint) -> CGFloat {
        (axis == .horizontal ? point.x : point.y) * sign
    }
}

/// The FullUI presentation dismissal guard permits the player page's own pan.
final class PlayerPagePanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var start: CGPoint?
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

struct PlayerPagePan: ViewModifier {
    typealias Route = (Direction, CGPoint, UIWindow, PlayerPanAction?) -> PlayerPanAction?

    enum Direction {
        case back, forward, vertical

        init?(_ travel: CGPoint, layoutDirection: LayoutDirection, verticalRatio: CGFloat) {
            if abs(travel.x) > abs(travel.y) * 1.25 {
                let sign: CGFloat = layoutDirection == .leftToRight ? 1 : -1
                self = travel.x * sign > 0 ? .back : .forward
            } else if abs(travel.y) > abs(travel.x) * verticalRatio {
                self = .vertical
            } else {
                return nil
            }
        }
    }

    var route: Route?
    var verticalRatio: CGFloat = 1.25
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.playerBackAction) private var backAction
    @Environment(\.playerBackIsSettling) private var backIsSettling

    func body(content: Content) -> some View {
        content.background {
            PlayerPagePanAnchor(
                enabled: route != nil || backAction != nil,
                routesAdditionalSwipes: route != nil,
                layoutDirection: layoutDirection,
                verticalRatio: verticalRatio,
                route: { direction, start, window in
                    if backIsSettling && direction != .back { return nil }
                    if let route {
                        return route(direction, start, window, backAction)
                    }
                    return direction == .back ? backAction : nil
                }
            )
            .ignoresSafeArea(.container)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    #if DEBUG
    private static let tracing = ProcessInfo.processInfo.arguments.contains("-AngelLivePlayerSwipeTrace")

    static func trace(_ message: @autoclosure () -> String) {
        if tracing { print("[PlayerSwipe] \(message())") }
    }
    #endif
}

private struct PlayerPagePanAnchor: UIViewRepresentable {
    let enabled: Bool
    let routesAdditionalSwipes: Bool
    let layoutDirection: LayoutDirection
    let verticalRatio: CGFloat
    let route: (PlayerPagePan.Direction, CGPoint, UIWindow) -> PlayerPanAction?

    func makeUIView(context: Context) -> Anchor {
        Anchor(configuration: self)
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.update(self)
        view.attach()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        view.detach()
    }

    final class Anchor: UIView, UIGestureRecognizerDelegate {
        private let pan = PlayerPagePanGestureRecognizer()
        private var configuration: PlayerPagePanAnchor
        private weak var controller: UIViewController?
        private var action: PlayerPanAction?

        init(configuration: PlayerPagePanAnchor) {
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

        func update(_ configuration: PlayerPagePanAnchor) {
            let needsReset = self.configuration.routesAdditionalSwipes != configuration.routesAdditionalSwipes
                || self.configuration.layoutDirection != configuration.layoutDirection
            #if DEBUG
            if self.configuration.enabled != configuration.enabled {
                PlayerPagePan.trace("enabled=\(configuration.enabled)")
            }
            #endif
            self.configuration = configuration
            if needsReset { pan.isEnabled = false }
            pan.isEnabled = configuration.enabled
        }

        func attach() {
            guard window != nil else { return }
            // Observe the viewport from its host so UIKit controls and SwiftUI share the same touch sequence.
            var responder = next
            while let current = responder {
                if let controller = current as? UIViewController,
                   let host = controller.viewIfLoaded, isDescendant(of: host) {
                    self.controller = controller
                    if pan.view !== host {
                        host.addGestureRecognizer(pan)
                        #if DEBUG
                        PlayerPagePan.trace("attached to \(type(of: host))")
                        #endif
                    }
                    return
                }
                responder = current.next
            }
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
            controller = nil
            action = nil
        }

        private var hasPresentedOverlay: Bool {
            var presenter = controller
            while let current = presenter {
                if current.presentedViewController != nil { return true }
                presenter = current.parent
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard configuration.enabled, window != nil, bounds.contains(touch.location(in: self)) else { return false }
            if hasPresentedOverlay {
                #if DEBUG
                PlayerPagePan.trace("excluded presented overlay")
                #endif
                return false
            }
            var hitView = touch.view
            while let view = hitView {
                if view is ShortDramaAccessibleSlider || view is UISlider {
                    #if DEBUG
                    PlayerPagePan.trace("excluded slider")
                    #endif
                    return false
                }
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
                   (scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 0.5) {
                    #if DEBUG
                    PlayerPagePan.trace("excluded horizontal scroll")
                    #endif
                    return false
                }
                if view === pan.view { break }
                hitView = view.superview
            }
            return true
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            action = nil
            guard configuration.enabled, !hasPresentedOverlay, let window, let start = pan.start,
                  let direction = PlayerPagePan.Direction(
                    pan.travel, layoutDirection: configuration.layoutDirection, verticalRatio: configuration.verticalRatio
                  )
            else { return false }
            action = configuration.route(direction, start, window)
            #if DEBUG
            PlayerPagePan.trace("direction=\(direction) action=\(action?.kind.rawValue ?? "passthrough")")
            #endif
            return action != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard configuration.enabled, other is UIPanGestureRecognizer,
                  !(other is PlayerPagePanGestureRecognizer), let host = pan.view, let view = other.view
            else { return false }

            // Zoom may install its dismissal pan above the content host. Let the player's
            // direction router decide first, only inside this presentation's own container.
            if host.isDescendant(of: view) {
                var owner = controller
                while let parent = owner?.parent { owner = parent }
                if let owner, owner.presentingViewController != nil,
                   let container = owner.presentationController?.containerView,
                   view === container || view.isDescendant(of: container) {
                    return true
                }
            }

            guard !(other is UIScreenEdgePanGestureRecognizer) else { return false }
            return view === host || view.isDescendant(of: host)
        }

        @objc private func handlePan() {
            guard let action else { return }
            let travel = action.component(of: pan.travel)
            switch pan.state {
            case .began:
                #if DEBUG
                PlayerPagePan.trace("began \(action.kind.rawValue)")
                #endif
                action.begin(travel)
            case .changed: action.update(travel)
            case .ended:
                self.action = nil
                #if DEBUG
                PlayerPagePan.trace("ended \(action.kind.rawValue)")
                #endif
                if configuration.enabled && !hasPresentedOverlay && action.canEnd(pan.travel) {
                    action.end(travel, action.component(of: pan.velocity(in: window)))
                } else {
                    action.cancel()
                }
            case .cancelled:
                self.action = nil
                #if DEBUG
                PlayerPagePan.trace("cancelled \(action.kind.rawValue)")
                #endif
                action.cancel()
            default: break
            }
        }
    }
}
