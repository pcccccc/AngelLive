import SwiftUI

struct PortraitPlayerSpring {
    static let response = 0.35
    static let dampingRatio = 0.9
    private static let spring = Spring(response: response, dampingRatio: dampingRatio)
    private let start = Date.now
    private let from: CGFloat
    let to: CGFloat
    private let velocity: CGFloat
    private let duration: TimeInterval

    init(from: CGFloat, to: CGFloat, velocity: CGFloat) {
        self.from = from
        self.to = to
        self.velocity = velocity
        duration = Self.spring.settlingDuration(target: to - from, initialVelocity: velocity, epsilon: 0.5)
    }

    func isFinished(at date: Date) -> Bool {
        date.timeIntervalSince(start) >= duration
    }

    func position(at date: Date) -> CGFloat {
        if isFinished(at: date) { return to }
        return from + Self.spring.value(
            target: to - from, initialVelocity: velocity, time: max(0, date.timeIntervalSince(start))
        )
    }
}

@MainActor @Observable
final class PortraitControlsMotion {
    private var offset: CGFloat?
    private(set) var settlement: PortraitPlayerSpring?
    @ObservationIgnored private(set) var dragOrigin: CGFloat?

    func position(width: CGFloat, visible: Bool, at date: Date = .now) -> CGFloat {
        let position = settlement?.position(at: date) ?? offset ?? (visible ? 0 : -width)
        return min(0, max(-width, position))
    }

    func begin(translation: CGFloat, width: CGFloat, visible: Bool) {
        let currentPosition = position(width: width, visible: visible)
        // Regrab a moving layer at the position currently on screen.
        dragOrigin = settlement == nil ? currentPosition : currentPosition - translation
        offset = currentPosition
        settlement = nil
    }

    func dragPosition(translation: CGFloat, width: CGFloat) -> CGFloat? {
        dragOrigin.map { min(0, max(-width, $0 + translation)) }
    }

    func update(translation: CGFloat, width: CGFloat) {
        guard let position = dragPosition(translation: translation, width: width) else { return }
        offset = position
    }

    func settle(from: CGFloat, to: CGFloat, velocity: CGFloat) {
        dragOrigin = nil
        offset = nil
        settlement = from == to ? nil : PortraitPlayerSpring(from: from, to: to, velocity: velocity)
    }

    func finishSettlement() {
        if settlement?.isFinished(at: .now) == true { settlement = nil }
    }

    func reset() {
        dragOrigin = nil
        offset = nil
        settlement = nil
    }
}

struct PortraitControlsOffset: ViewModifier {
    @Environment(\.layoutDirection) private var layoutDirection
    let motion: PortraitControlsMotion?
    let width: CGFloat
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if let motion, !reduceMotion {
            TimelineView(.animation(paused: motion.settlement == nil)) { timeline in
                let position = motion.position(width: width, visible: visible, at: timeline.date)
                content
                    .offset(x: layoutDirection == .leftToRight ? position : -position)
                    .onChange(of: motion.settlement?.isFinished(at: timeline.date) == true) { _, finished in
                        if finished { motion.finishSettlement() }
                    }
            }
        } else {
            content
                .opacity(visible ? 1 : 0)
                .animation(
                    motion == nil
                        ? FullUIPlayerChrome.visibilityAnimation(visible, reduceMotion: reduceMotion)
                        : .easeInOut(duration: 0.2),
                    value: visible
                )
        }
    }
}

extension EnvironmentValues {
    @Entry var portraitControlsMotion: PortraitControlsMotion?
}
