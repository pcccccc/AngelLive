import SwiftUI
import UIKit

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
    @Environment(\.fullUIRoomPlayerPushed) private var isPushed
    @Environment(\.finishRoomPlayerSwipe) private var finishPresentation
    @State private var dismissalTarget: RoomPlayerDismissalTarget?
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

    private var isDismissing: Bool {
        if case .dismissing = motion { return true }
        return false
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
        .allowsHitTesting(!isDismissing)
        .environment(\.playerBackAction, enabled && !isDismissing ? PlayerPanAction(
            kind: .back, axis: .horizontal, sign: direction,
            begin: begin, update: update, end: end, cancel: cancel
        ) : nil)
        .environment(\.playerBackIsSettling, spring != nil)
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
        if !exitsFullscreen, finishPresentation != nil {
            dismissalTarget = RoomPlayerDismissalTarget(host: windowContext?.hostViewController, isPushed: isPushed)
        }
        let current = position(at: .now)
        // Subtract the recognition slop when regrabbing so the page doesn't jump.
        let origin = spring == nil ? 0 : current - travel
        motion = .dragging(origin: origin, position: tracksPage ? clamped(origin + travel) : 0)
    }

    private func update(_ travel: CGFloat) {
        guard tracksPage, case let .dragging(origin, _) = motion else { return }
        motion = .dragging(origin: origin, position: clamped(origin + travel))
    }

    // If UIKit cannot identify the owning container, leave the whole return to SwiftUI.
    private var tracksPage: Bool {
        !reduceMotion && (exitsFullscreen || (dismissalTarget != nil && showsSource))
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
        if !tracksPage {
            finish(returns: returns, position: 0)
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
        #if DEBUG
        PlayerPagePan.trace(returns ? (exitsFullscreen ? "exit fullscreen" : "return") : "rebound")
        #endif
        guard returns else {
            dismissalTarget = nil
            return
        }
        if position > 0, !exitsFullscreen, let dismissalTarget, let finishPresentation {
            // The custom transition has already reached the source. Retire only its actual controller.
            dismissalTarget.finish(completion: finishPresentation)
        } else {
            onReturn()
        }
    }
}

@MainActor
private final class RoomPlayerDismissalTarget {
    private weak var controller: UIViewController?
    private let isPushed: Bool

    init?(host: UIViewController?, isPushed: Bool) {
        self.isPushed = isPushed
        var ancestor = host
        while let current = ancestor {
            if isPushed, let navigation = current.parent as? UINavigationController,
               navigation.topViewController === current, navigation.viewControllers.first !== current {
                controller = current
                return
            }
            if !isPushed, current.parent == nil,
               current.presentingViewController?.presentedViewController === current {
                controller = current
                return
            }
            ancestor = current.parent
        }
        return nil
    }

    func finish(completion: @escaping @MainActor () -> Void) {
        if let controller, isPushed, let navigation = controller.navigationController,
           navigation.topViewController === controller {
            navigation.popViewController(animated: false)
        } else if let controller, !isPushed,
                  controller.presentingViewController?.presentedViewController === controller {
            controller.dismiss(animated: false, completion: completion)
            return
        }
        completion()
    }
}

private struct PlayerBackSourcePreview: UIViewRepresentable {
    let snapshot: UIView

    func makeUIView(context: Context) -> UIView { snapshot }
    func updateUIView(_ view: UIView, context: Context) {}
}

extension EnvironmentValues {
    @Entry var playerBackAction: PlayerPanAction?
    @Entry var playerBackIsSettling = false
}
