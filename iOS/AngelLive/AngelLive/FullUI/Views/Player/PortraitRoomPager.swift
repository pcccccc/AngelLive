import AngelLiveCore
import Kingfisher
import SharedAssets
import SwiftUI
import UIKit

struct PortraitRoomPager: ViewModifier {
    struct Playback: Equatable {
        let room: LiveModel
        let hasProgress: Bool
        let hasFailed: Bool
    }

    typealias Direction = RoomSwitchCandidates.Direction
    let enabled: Bool
    let viewportHeight: CGFloat
    let availableHeight: CGFloat
    let playback: Playback
    let currentPlayback: () -> Playback
    let source: RoomSwitchSource
    let adjacentRoom: (Direction, LiveModel) -> LiveModel?
    let canLoadMore: () -> Bool
    let loadNextRoom: (LiveModel) async -> LiveModel?
    let switchRoom: (LiveModel, Bool, @escaping (Bool) -> Void) -> Void
    let reportStartupFailure: (LiveModel) -> Void
    let showBoundary: (Direction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fullUIWindowContext) private var windowContext
    @State private var motion = PortraitPageMotion()
    @State private var pages: AdjacentPages?
    @State private var cover: Cover?
    @State private var categoryTask: Task<Void, Never>?
    @State private var prefetcher: ImagePrefetcher?
    @State private var hasRejectedLegacyDrag = false
    @GestureState private var legacyDragActive = false

    func body(content: Content) -> some View {
        let pageAction: ((Direction) -> Void)? = enabled && cover == nil ? { turnPage($0) } : nil
        let actions = PortraitRoomPageActions(
            turnPage: pageAction,
            isMoving: { motion.dragOrigin != nil || motion.settlement != nil }
        )
        let movingPage = ZStack {
            content
                .allowsHitTesting(cover == nil)
                .accessibilityHidden(cover != nil)
            if let cover {
                PortraitRoomPreview(room: cover.room)
                    .id(cover.id)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("正在加载 \(cover.room.userName.orDash)")
                    .accessibilityActions {
                        if enabled {
                            Button("下一个房间") { turnPage(.next) }
                            Button("上一个房间") { turnPage(.previous) }
                        }
                    }
            }
            if !reduceMotion, let pages {
                if let previous = pages.previous {
                    PortraitRoomPreview(room: previous)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .offset(y: -viewportHeight)
                }
                if let next = pages.next {
                    PortraitRoomPreview(room: next)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .offset(y: viewportHeight)
                }
            }
        }
        .environment(\.portraitRoomPageActions, actions)
        .modifier(PortraitPageOffset(motion: motion, onSettled: finishSettlement))
        .contentShape(Rectangle())

        return withPan(movingPage)
        .background {
            if pages != nil || cover != nil {
                Color.black.ignoresSafeArea()
            }
        }
        .onChange(of: playback) { _, _ in updateCover() }
        .onChange(of: enabled) { _, enabled in
            if !enabled { resetPaging() }
        }
        .onChange(of: source) { _, _ in resetPaging() }
        .onChange(of: viewportHeight) { _, _ in resetPaging() }
        .onDisappear {
            resetPaging()
            cover = nil
        }
    }

    private var displayedRoom: LiveModel { cover?.room ?? currentPlayback().room }

    private var canStartDrag: Bool {
        enabled && GeneralSettingModel().enablePlayerGesture && categoryTask == nil
    }

    @ViewBuilder
    private func withPan(_ content: some View) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(PortraitRoomPan(
                shouldBegin: { canStartDrag },
                onBegan: beginDrag,
                onChanged: updateDrag,
                onEnded: endDrag,
                onCancelled: cancelDrag
            ))
        } else {
            content
                .simultaneousGesture(legacyDrag)
                .onChange(of: legacyDragActive) { _, active in
                    if !active {
                        hasRejectedLegacyDrag = false
                        cancelDrag()
                    }
                }
        }
    }

    private var legacyDrag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($legacyDragActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !hasRejectedLegacyDrag else { return }
                if motion.dragOrigin != nil {
                    updateDrag(value.translation.height)
                    return
                }
                guard canStartDrag, let bounds = windowContext?.window?.bounds,
                      value.startLocation.y > bounds.minY + 44,
                      value.startLocation.y < bounds.maxY - 44,
                      abs(value.translation.height) > abs(value.translation.width) * 1.25 else {
                    hasRejectedLegacyDrag = true
                    return
                }
                beginDrag(value.translation.height)
            }
            .onEnded { value in
                endDrag(value.translation.height, value.velocity.height)
                hasRejectedLegacyDrag = false
            }
    }

    private func preparePages() {
        guard pages == nil else { return }
        let previous = adjacentRoom(.previous, displayedRoom)
        let next = adjacentRoom(.next, displayedRoom)
        pages = AdjacentPages(previous: previous, next: next)
        prefetcher?.stop()
        let urls = [previous, next].compactMap { room -> URL? in
            guard let cover = room?.roomCover, !cover.isEmpty else { return nil }
            return URL(string: cover)
        }
        if !urls.isEmpty {
            let prefetcher = ImagePrefetcher(urls: urls)
            self.prefetcher = prefetcher
            prefetcher.start()
        }
    }

    private func beginDrag(_ translation: CGFloat) {
        preparePages()
        if let settlement = motion.settlement {
            let position = settlement.position(at: .now)
            let factor = resistance(for: position)
            motion.dragOrigin = position / factor - translation
            motion.settlement = nil
        } else {
            motion.dragOrigin = 0
        }
        updateDrag(translation)
    }

    private func updateDrag(_ translation: CGFloat) {
        guard let origin = motion.dragOrigin else { return }
        let position = origin + translation
        if !reduceMotion {
            motion.offset = min(viewportHeight, max(-viewportHeight, position * resistance(for: position)))
        }
    }

    private func resistance(for position: CGFloat) -> CGFloat {
        pages?[position < 0 ? .next : .previous] == nil ? 0.3 : 1
    }

    private func endDrag(_ translation: CGFloat, _ velocity: CGFloat) {
        guard let origin = motion.dragOrigin else { return }
        updateDrag(translation)
        motion.dragOrigin = nil
        let travel = origin + translation
        let crossesThreshold = abs(travel) > availableHeight * 0.25
        let isFlick = abs(velocity) > 800 && velocity * travel > 0
        let direction: Direction = (isFlick ? velocity : travel) < 0 ? .next : .previous
        let target = pages?[direction]
        if target == nil, abs(translation) > 0 {
            // At the end of a category, the next page may not have been fetched yet.
            settle(to: 0, velocity: velocity * 0.3)
            reachBoundary(direction, mayTurn: crossesThreshold || isFlick)
        } else if (crossesThreshold || isFlick), let target {
            turnPage(direction, to: target, velocity: velocity)
        } else {
            settle(to: 0, velocity: velocity)
        }
    }

    private func cancelDrag() {
        guard motion.dragOrigin != nil else { return }
        motion.dragOrigin = nil
        settle(to: 0, velocity: 0)
    }

    private func turnPage(_ direction: Direction) {
        guard enabled, GeneralSettingModel().enablePlayerGesture, categoryTask == nil,
              motion.dragOrigin == nil, motion.settlement == nil else { return }
        preparePages()
        if let target = pages?[direction] {
            turnPage(direction, to: target, velocity: 0)
        } else {
            pages = nil
            reachBoundary(direction, mayTurn: true)
        }
    }

    private func turnPage(_ direction: Direction, to target: LiveModel, velocity: CGFloat) {
        if reduceMotion {
            finishPaging()
            showCover(for: target)
        } else {
            settle(to: direction == .next ? -viewportHeight : viewportHeight, velocity: velocity, target: target)
        }
    }

    private func reachBoundary(_ direction: Direction, mayTurn: Bool) {
        guard direction == .next, source == .category, canLoadMore(), categoryTask == nil else {
            showBoundary(direction)
            return
        }
        let room = displayedRoom
        categoryTask = Task { @MainActor in
            let next = await loadNextRoom(room)
            guard !Task.isCancelled else { return }
            categoryTask = nil
            guard displayedRoom == room else { return }
            guard let next else {
                showBoundary(.next)
                return
            }
            guard mayTurn else { return }
            if motion.settlement != nil {
                // Retarget the rebound from its current presentation position.
                motion.offset = motion.settlement?.position(at: .now) ?? motion.offset
                motion.settlement = nil
            }
            pages = AdjacentPages(previous: pages?.previous, next: next)
            turnPage(.next, to: next, velocity: 0)
        }
    }

    private func settle(to offset: CGFloat, velocity: CGFloat, target: LiveModel? = nil) {
        if motion.offset == offset {
            finishPaging()
            if let target { showCover(for: target) }
            return
        }
        motion.settlement = .init(from: motion.offset, to: offset, velocity: velocity, room: target)
    }

    private func finishSettlement() {
        guard let settlement = motion.settlement, settlement.isFinished(at: .now) else { return }
        finishPaging()
        if let room = settlement.room { showCover(for: room) }
    }

    private func finishPaging() {
        motion.offset = 0
        motion.settlement = nil
        pages = nil
    }

    private func resetPaging() {
        categoryTask?.cancel()
        categoryTask = nil
        prefetcher?.stop()
        prefetcher = nil
        motion.dragOrigin = nil
        finishPaging()
    }

    private func showCover(for room: LiveModel) {
        let nextCover = Cover(room: room, fallback: currentPlayback().room)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { cover = nextCover }
        } else {
            cover = nextCover
        }
        switchRoom(room, true) { success in
            guard cover?.id == nextCover.id else { return }
            if success {
                updateCover()
            } else {
                // Resolving the new source failed before replacing the active room.
                restoreCover()
            }
        }
        // A reverse swipe can land on the active stream while a newer request is unwinding.
        updateCover()
    }

    private func updateCover() {
        let playback = currentPlayback()
        guard let cover, cover.room == playback.room else { return }
        if playback.hasFailed, let fallback = cover.fallback, fallback != cover.room {
            resetPaging()
            let restoration = Cover(room: fallback, fallback: nil)
            withAnimation(.easeInOut(duration: 0.2)) { self.cover = restoration }
            switchRoom(fallback, false) { success in
                guard self.cover?.id == restoration.id else { return }
                if success {
                    updateCover()
                } else {
                    fadeCover()
                }
            }
            reportStartupFailure(cover.room)
        } else if playback.hasProgress || playback.hasFailed {
            fadeCover()
        }
    }

    private func restoreCover() {
        let playback = currentPlayback()
        resetPaging()
        withAnimation(.easeInOut(duration: 0.2)) {
            cover = playback.hasProgress || playback.hasFailed ? nil : Cover(room: playback.room, fallback: nil)
        }
    }

    private func fadeCover() {
        withAnimation(.easeOut(duration: 0.2)) { cover = nil }
    }

    private struct AdjacentPages {
        let previous: LiveModel?
        let next: LiveModel?

        subscript(_ direction: Direction) -> LiveModel? {
            direction == .next ? next : previous
        }
    }

    private struct Cover {
        let id = UUID()
        let room: LiveModel
        let fallback: LiveModel?
    }
}

@MainActor @Observable
private final class PortraitPageMotion {
    var offset: CGFloat = 0
    var settlement: Settlement?
    @ObservationIgnored var dragOrigin: CGFloat?

    struct Settlement {
        private static let spring = Spring(response: 0.35, dampingRatio: 0.9)
        private let start: Date
        let from: CGFloat
        let to: CGFloat
        let velocity: CGFloat
        let room: LiveModel?

        private let duration: TimeInterval

        init(from: CGFloat, to: CGFloat, velocity: CGFloat, room: LiveModel?) {
            self.from = from
            self.to = to
            self.velocity = velocity
            self.room = room
            start = .now
            duration = Self.spring.settlingDuration(target: to - from, initialVelocity: velocity, epsilon: 0.5)
        }

        func isFinished(at date: Date) -> Bool {
            date.timeIntervalSince(start) >= duration
        }

        func position(at date: Date) -> CGFloat {
            if isFinished(at: date) { return to }
            let value = from + Self.spring.value(
                target: to - from, initialVelocity: velocity, time: max(0, date.timeIntervalSince(start))
            )
            // Prevent an overshoot past a fully revealed page.
            guard room != nil else { return value }
            return to < 0 ? max(to, value) : min(to, value)
        }
    }
}

private struct PortraitPageOffset: ViewModifier {
    let motion: PortraitPageMotion
    let onSettled: () -> Void

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: motion.settlement == nil)) { timeline in
            content
                .offset(y: motion.settlement?.position(at: timeline.date) ?? motion.offset)
                .onChange(of: motion.settlement?.isFinished(at: timeline.date) == true) { _, finished in
                    if finished { onSettled() }
                }
        }
    }
}

@available(iOS 18.0, *)
private struct PortraitRoomPan: UIGestureRecognizerRepresentable {
    let shouldBegin: () -> Bool
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
        let translation = recognizer.translation(in: window).y
        switch recognizer.state {
        case .began: onBegan(translation)
        case .changed: onChanged(translation)
        case .ended: onEnded(translation, recognizer.velocity(in: window).y)
        case .cancelled: onCancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBegin: () -> Bool

        init(shouldBegin: @escaping () -> Bool) {
            self.shouldBegin = shouldBegin
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard shouldBegin(), let window = gestureRecognizer.view?.window else { return false }
            let point = touch.location(in: window)
            return point.y > window.bounds.minY + 44 && point.y < window.bounds.maxY - 44
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard shouldBegin(), let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let translation = pan.translation(in: pan.view?.window)
            return abs(translation.y) > abs(translation.x) * 1.25
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The KSPlayer canvas keeps horizontal clear/restore and the left edge keeps back.
            true
        }
    }
}

private struct PortraitRoomPreview: View {
    let room: LiveModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                KFImage(URL(string: room.roomCover))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .scaleEffect(1.04)
                    .blur(radius: 8)
                Color.black.opacity(0.48)

                VStack(spacing: 8) {
                    KFImage(URL(string: room.userHeadImg))
                        .placeholder {
                            Image(systemName: "person.fill")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.white.opacity(0.15))
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    Text(room.userName.orDash)
                        .font(.headline)
                        .lineLimit(1)
                    Text(room.roomTitle.orDash)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                    ArcSpinner(size: 24, lineWidth: 1.5)
                        .tint(.white)
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.63)
            }
            .clipped()
        }
        .ignoresSafeArea(.container)
    }
}

struct PortraitRoomPageActions {
    let turnPage: ((RoomSwitchCandidates.Direction) -> Void)?
    let isMoving: () -> Bool
}

extension EnvironmentValues {
    @Entry var portraitRoomPageActions: PortraitRoomPageActions?
}
