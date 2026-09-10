import SwiftUI
import UIKit

/// FullUI-only presentation. Native scroll views own the refresh threshold.
struct LiquidRefreshIndicator: View {
    let pullDistance: CGFloat
    let isRefreshing: Bool
    var refreshCycle: Int = 0
    var accessibilityTitle = "正在刷新"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var anchor: LiquidRefreshAnchor?
    @State private var startedAt: Date?
    @State private var completedAt: Date?
    @State private var initialPull: CGFloat = 0
    @State private var observedCycle: Int?
    @State private var pullState = LiquidRefreshPullState()

    private var progress: CGFloat { min(max((pullDistance - 8) / 100, 0), 1) }

    var body: some View {
        Color.clear
            .frame(height: 120)
            .background(LiquidRefreshAnchorProbe(anchor: $anchor))
            .overlay(alignment: .topLeading) {
                if let anchor {
                    TimelineView(.animation(paused: startedAt == nil || reduceMotion || scenePhase != .active)) { timeline in
                        let pose = LiquidRefreshPose.resolve(
                            now: timeline.date, startedAt: startedAt, completedAt: completedAt,
                            initialPull: initialPull,
                            pull: pullState.visibleProgress(for: pullDistance),
                            reducedMotion: reduceMotion
                        )
                        LiquidRefreshArtwork(
                            pose: pose,
                            attached: anchor.attached && !reduceMotion,
                            reducedMotion: reduceMotion,
                            darkAppearance: colorScheme == .dark
                        )
                        .frame(width: 120, height: 120)
                    }
                    .offset(x: anchor.point.x - 60, y: anchor.point.y)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isRefreshing ? accessibilityTitle : "下拉刷新")
            .accessibilityHidden(!isRefreshing)
            .onChange(of: pullDistance, initial: true) { _, distance in
                pullState.observe(distance: distance, refreshPresented: isRefreshing || startedAt != nil)
            }
            .onChange(of: startedAt) { _, start in
                // Read the current drag after the return task completes, not
                // the distance its closure captured before suspending.
                pullState.observe(distance: pullDistance, refreshPresented: isRefreshing || start != nil)
            }
            .task(id: RefreshTrigger(cycle: refreshCycle, active: isRefreshing)) {
                let newCycle = observedCycle != nil && observedCycle != refreshCycle
                observedCycle = refreshCycle
                if isRefreshing || newCycle {
                    initialPull = pullState.isHovering ? 1 : progress
                    pullState.consume()
                    completedAt = nil
                    startedAt = .now
                }
                if !isRefreshing, let startedAt {
                    let completion = Date.now
                    completedAt = completion
                    // The circle is already detached while waiting for release.
                    // Briefly show loading even when the request finishes fast.
                    let end = max(completion.timeIntervalSinceReferenceDate,
                                  startedAt.timeIntervalSinceReferenceDate + 0.20) + 0.40
                    let remaining = max(0, end - Date.now.timeIntervalSinceReferenceDate)
                    do { try await Task.sleep(for: .seconds(remaining)) }
                    catch { return }
                    self.startedAt = nil
                    completedAt = nil
                }
            }
            .onDisappear {
                startedAt = nil
                completedAt = nil
                observedCycle = nil
                pullState = LiquidRefreshPullState()
            }
    }

    private struct RefreshTrigger: Equatable {
        let cycle: Int
        let active: Bool
    }
}

/// A held drag belongs to the refresh it triggered. Once consumed, it must
/// return to rest before it can draw a new pull preview.
struct LiquidRefreshPullState {
    private(set) var waitsForRest = false
    private(set) var isHovering = false

    mutating func consume() {
        waitsForRest = true
    }

    mutating func observe(distance: CGFloat, refreshPresented: Bool) {
        guard !refreshPresented else { return }
        if distance <= 1 {
            waitsForRest = false
            isHovering = false
        } else if !waitsForRest && distance >= 108 {
            isHovering = true
        }
    }

    func visibleProgress(for distance: CGFloat) -> CGFloat {
        waitsForRest ? 0 : (isHovering ? 1 : min(max((distance - 8) / 100, 0), 1))
    }
}

/// Pulling drives the whole separation directly. A detached circle waits at
/// its anchor until release; the return is translation/fade, never a liquid neck.
struct LiquidRefreshPose {
    var progress: CGFloat
    var separation: CGFloat
    var centerY: CGFloat
    var loading: CGFloat
    var rotation: Double
    var opacity: CGFloat = 1

    static func pulling(_ progress: CGFloat) -> Self {
        let p = clamp(progress)
        let stretch = min(p / 0.75, 1)
        let separation = smooth(clamp((p - 0.75) / 0.25))
        return .init(progress: stretch, separation: separation,
                     centerY: -8 + 44 * stretch + 14 * separation,
                     loading: separation, rotation: 0)
    }

    static func resolve(
        now: Date, startedAt: Date?, completedAt: Date?,
        initialPull: CGFloat, pull: CGFloat, reducedMotion: Bool
    ) -> Self {
        guard let start = startedAt else {
            return pulling(pull)
        }
        if reducedMotion {
            return .init(progress: completedAt == nil ? 1 : 0, separation: 1, centerY: 26, loading: 1, rotation: 0)
        }
        let elapsed = max(0, now.timeIntervalSince(start))
        let rotation = elapsed * 2 * Double.pi
        if let completedAt {
            let returnStart = max(0.20, completedAt.timeIntervalSince(start))
            if elapsed >= returnStart {
                let t = clamp((elapsed - returnStart) / 0.40)
                let y = 50 - 58 * smooth(t)
                return .init(
                    progress: 1, separation: 1,
                    centerY: y, loading: 1 - smooth(clamp(t / 0.3)), rotation: rotation,
                    opacity: 1 - smooth(clamp((t - 0.55) / 0.45))
                )
            }
        }
        // Native thresholds can differ from the visual threshold. Finish only
        // the remaining separation on release; a hovering circle never jumps.
        let from = pulling(initialPull)
        let settle = smooth(clamp(elapsed / 0.18))
        return .init(progress: from.progress + (1 - from.progress) * settle,
                     separation: from.separation + (1 - from.separation) * settle,
                     centerY: from.centerY + (50 - from.centerY) * settle,
                     loading: 1, rotation: rotation)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    private static func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}

/// A small drawing surface avoids filtering the entire screen to merge liquid.
private struct LiquidRefreshArtwork: View {
    let pose: LiquidRefreshPose
    let attached: Bool
    let reducedMotion: Bool
    let darkAppearance: Bool

    var body: some View {
        Canvas { context, size in
            let p = pose.progress
            let s = pose.separation
            let x = size.width / 2
            let radius = 6 + 7 * p
            let y = reducedMotion ? 26 : pose.centerY + (attached ? 0 : 22)
            let rx = radius * (1 - 0.10 * p * (1 - s))
            let drop = Path(ellipseIn: CGRect(x: x - rx, y: y - radius, width: rx * 2, height: radius * 2))
            context.opacity = min(p * 5, 1) * pose.opacity

            if attached && s < 0.98 && y + radius > 0 && y < 49 && p > 0.015 {
                let base = (13 - 3 * p) * (1 - s)
                let thin = max(0.15, (4 - 2.5 * p) * (1 - s))
                let join = y - radius * 0.40
                let waist = 2 + max(0, join - 2) * 0.47
                let shoulder = rx * 0.9 * (1 - s)
                var neck = Path()
                neck.move(to: CGPoint(x: x - base, y: 0))
                neck.addCurve(to: CGPoint(x: x - thin, y: waist + 3),
                              control1: CGPoint(x: x - base * 0.45, y: 3),
                              control2: CGPoint(x: x - thin, y: waist))
                neck.addCurve(to: CGPoint(x: x - shoulder, y: join + 3),
                              control1: CGPoint(x: x - thin, y: join - 4),
                              control2: CGPoint(x: x - shoulder, y: join - 3))
                neck.addLine(to: CGPoint(x: x + shoulder, y: join + 3))
                neck.addCurve(to: CGPoint(x: x + thin, y: waist + 3),
                              control1: CGPoint(x: x + shoulder, y: join - 3),
                              control2: CGPoint(x: x + thin, y: join - 4))
                neck.addCurve(to: CGPoint(x: x + base, y: 0),
                              control1: CGPoint(x: x + thin, y: waist),
                              control2: CGPoint(x: x + base * 0.45, y: 3))
                neck.closeSubpath()
                context.fill(neck, with: .color(.black))
            }
            context.fill(drop, with: .color(.black))
            if darkAppearance {
                context.stroke(drop, with: .color(.white.opacity(0.16 * s)), lineWidth: 0.5)
            }
            if pose.loading > 0 {
                context.opacity *= pose.loading
                let ringRect = CGRect(x: x - 6, y: y - 6, width: 12, height: 12)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.2)), lineWidth: 1.4)
                var arc = Path()
                arc.addArc(center: CGPoint(x: x, y: y), radius: 6,
                           startAngle: .radians(pose.rotation), endAngle: .radians(pose.rotation + 4.2), clockwise: false)
                context.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }
}

private struct LiquidRefreshAnchor: Equatable {
    let point: CGPoint
    let attached: Bool
}

/// Reads the containing window, never another scene's key window. UIKit does
/// not expose the cutout outline. Overlap inside the safe-area margin connects
/// common sensor housings without drawing a fake island.
private struct LiquidRefreshAnchorProbe: UIViewRepresentable {
    @Binding var anchor: LiquidRefreshAnchor?

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.publish = { value in
            if anchor != value { anchor = value }
        }
        view.scheduleMeasurement()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) {
        view.pending?.cancel()
        view.publish = nil
    }

    final class ProbeView: UIView {
        var publish: ((LiquidRefreshAnchor) -> Void)?
        var pending: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleMeasurement()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleMeasurement()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleMeasurement()
        }

        func scheduleMeasurement() {
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, let window, bounds.width > 0 else { return }
                let top = window.safeAreaInsets.top
                let frameInWindow = convert(bounds, to: window)
                let fullWidth = abs(frameInWindow.width - window.bounds.width) < 2
                let attached = traitCollection.userInterfaceIdiom == .phone
                    && window.bounds.height > window.bounds.width && top >= 44 && fullWidth
                let windowPoint = CGPoint(
                    x: attached ? window.bounds.midX : frameInWindow.midX,
                    y: attached ? top - 20 : max(top, frameInWindow.minY) + 8
                )
                publish?(LiquidRefreshAnchor(point: convert(windowPoint, from: window), attached: attached))
            }
        }
    }
}
