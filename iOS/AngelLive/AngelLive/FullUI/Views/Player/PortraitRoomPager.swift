import AngelLiveCore
import Kingfisher
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
    let openDrawerSwipe: ((CGPoint, UIWindow) -> PlayerPanAction?)?
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let availableHeight: CGFloat
    let playback: Playback
    let loadingDiagnostics: PlayerLoadingDiagnostics
    let currentPlayback: () -> Playback
    let source: RoomSwitchSource
    let adjacentRoom: (Direction, LiveModel) -> LiveModel?
    let canLoadMore: () -> Bool
    let loadNextRoom: (LiveModel) async -> LiveModel?
    let switchRoom: (LiveModel, Bool, @escaping (Bool) -> Void) -> Void
    let reportStartupFailure: (LiveModel) -> Void
    let showBoundary: (Direction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.verticalLiveControlsVisible) private var controlsVisible
    @State private var motion = PortraitPageMotion()
    @State private var controlsMotion = PortraitControlsMotion()
    @State private var pages: AdjacentPages?
    @State private var cover: Cover?
    @State private var categoryTask: Task<Void, Never>?
    @State private var prefetcher: ImagePrefetcher?

    func body(content: Content) -> some View {
        let pageAction: ((Direction) -> Void)? = enabled && cover == nil ? { turnPage($0) } : nil
        let actions = PortraitRoomPageActions(
            turnPage: pageAction,
            isMoving: { motion.dragOrigin != nil || motion.settlement != nil },
            setControlsVisible: { setControlsVisible($0) }
        )
        let movingPage = ZStack {
            content
                .allowsHitTesting(cover == nil)
                .accessibilityHidden(cover != nil)
            // Keep the target's view identity as it moves from adjacent preview to cover.
            ForEach(loadingPages) { page in
                let isCover = page.offset == 0
                let diagnostics = isCover && page.room == playback.room ? loadingDiagnostics : PlayerLoadingDiagnostics()
                PlayerLoadingScreen(room: page.room, diagnostics: diagnostics, verticalCenter: PlayerLoadingScreen.portraitCenter)
                    .ignoresSafeArea(.container)
                    .offset(y: page.offset)
                    .transition(.opacity)
                    .accessibilityHidden(!isCover)
                    .allowsHitTesting(isCover)
                    .accessibilityActions {
                        if isCover && enabled {
                            Button("下一个房间") { turnPage(.next) }
                            Button("上一个房间") { turnPage(.previous) }
                        }
                    }
                    .zIndex(isCover ? 1 : 2)
            }
        }
        .environment(\.portraitRoomPageActions, actions)
        .environment(\.portraitControlsMotion, controlsMotion)
        .environment(\.portraitRoomLoadingCovered, cover != nil)
        .modifier(PortraitPageOffset(motion: motion, onSettled: finishSettlement))
        .contentShape(Rectangle())

        let route: PlayerPagePan.Route? = if enabled || openDrawerSwipe != nil {
            { direction, start, window, back in routeSwipe(direction, start, window, back) }
        } else {
            nil
        }
        let swipePage = movingPage.modifier(PlayerPagePan(route: route))

        return swipePage
        .background {
            if pages != nil || cover != nil {
                Color.black.ignoresSafeArea()
            }
        }
        .onChange(of: playback) { _, _ in updateCover() }
        .onChange(of: playback.room.id) { _, _ in controlsMotion.reset() }
        .onChange(of: enabled) { _, enabled in
            if !enabled {
                resetPaging()
                controlsMotion.reset()
            }
        }
        .onChange(of: source) { _, _ in resetPaging() }
        .onChange(of: viewportWidth) { _, _ in controlsMotion.reset() }
        .onChange(of: viewportHeight) { _, _ in resetPaging() }
        .onDisappear {
            resetPaging()
            controlsMotion.reset()
            cover = nil
        }
    }

    private var displayedRoom: LiveModel { cover?.room ?? currentPlayback().room }

    private var loadingPages: [LoadingPage] {
        var result: [LoadingPage] = []
        if let cover { result.append(LoadingPage(room: cover.room, offset: 0)) }
        if !reduceMotion, let pages {
            if let previous = pages.previous, previous != cover?.room {
                result.append(LoadingPage(room: previous, offset: -viewportHeight))
            }
            if let next = pages.next, next != cover?.room {
                result.append(LoadingPage(room: next, offset: viewportHeight))
            }
        }
        return result
    }

    private func routeSwipe(
        _ direction: PlayerPagePan.Direction, _ start: CGPoint, _ window: UIWindow, _ back: PlayerPanAction?
    ) -> PlayerPanAction? {
        guard enabled else {
            if direction == .back { return back }
            return direction == .forward ? openDrawerSwipe?(start, window) : nil
        }

        let visible = controlsVisible.wrappedValue
        if direction == .vertical {
            let viewport = window.bounds
            guard GeneralSettingModel().enablePlayerGesture, categoryTask == nil,
                  start.y > viewport.minY + 44, start.y < viewport.maxY - 44 else { return nil }
            return PlayerPanAction(
                kind: .page, axis: .vertical,
                begin: {
                    controlsMotion.reset()
                    beginDrag($0)
                },
                update: updateDrag, end: endDrag, cancel: cancelDrag
            )
        }

        guard motion.dragOrigin == nil, motion.settlement == nil else { return nil }
        if direction == .back && visible { return back }

        guard cover == nil, visible == (direction == .forward) else { return nil }
        let sign: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return PlayerPanAction(
            kind: visible ? .hideControls : .restoreControls, axis: .horizontal, sign: sign,
            begin: { translation in
                controlsMotion.begin(translation: translation, width: viewportWidth, visible: visible)
                updateControlsDrag(translation)
            },
            update: updateControlsDrag,
            end: { endControlsDrag($0, $1, wasVisible: visible) },
            cancel: {
                guard controlsMotion.dragOrigin != nil else { return }
                setControlsVisible(controlsVisible.wrappedValue)
            }
        )
    }

    private func updateControlsDrag(_ translation: CGFloat) {
        if !reduceMotion { controlsMotion.update(translation: translation, width: viewportWidth) }
    }

    private func endControlsDrag(_ translation: CGFloat, _ velocity: CGFloat, wasVisible: Bool) {
        guard let position = controlsMotion.dragPosition(translation: translation, width: viewportWidth) else {
            return
        }
        // Only the current drag counts, even when it interrupts a spring midway.
        let distance = wasVisible ? -translation : translation
        let releaseSpeed = wasVisible ? -velocity : velocity
        let commits = distance > viewportWidth * 0.30 || releaseSpeed >= 600
        setControlsVisible(commits ? !wasVisible : wasVisible, from: position, velocity: velocity)
    }

    private func setControlsVisible(_ visible: Bool, from position: CGFloat? = nil, velocity: CGFloat = 0) {
        if reduceMotion {
            controlsMotion.reset()
        } else {
            let from = position ?? controlsMotion.position(width: viewportWidth, visible: controlsVisible.wrappedValue)
            controlsMotion.settle(from: from, to: visible ? 0 : -viewportWidth, velocity: velocity)
        }
        controlsVisible.wrappedValue = visible
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
        withAnimation(PlayerLoadingScreen.fade) { cover = nil }
    }

    private struct LoadingPage: Identifiable {
        let room: LiveModel
        let offset: CGFloat

        var id: LiveModel.ID { room.id }
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
        let spring: PortraitPlayerSpring
        let room: LiveModel?

        init(from: CGFloat, to: CGFloat, velocity: CGFloat, room: LiveModel?) {
            spring = PortraitPlayerSpring(from: from, to: to, velocity: velocity)
            self.room = room
        }

        func isFinished(at date: Date) -> Bool {
            spring.isFinished(at: date)
        }

        func position(at date: Date) -> CGFloat {
            let value = spring.position(at: date)
            // Prevent an overshoot past a fully revealed page.
            guard room != nil else { return value }
            return spring.to < 0 ? max(spring.to, value) : min(spring.to, value)
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

struct PortraitRoomPageActions {
    let turnPage: ((RoomSwitchCandidates.Direction) -> Void)?
    let isMoving: () -> Bool
    let setControlsVisible: (Bool) -> Void
}

extension EnvironmentValues {
    @Entry var portraitRoomPageActions: PortraitRoomPageActions?
    @Entry var portraitRoomLoadingCovered = false
}
