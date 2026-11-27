//
//  LiveRoomNavigationState.swift
//  AngelLive
//
//  管理直播间卡片的导航状态，解决 PiP 背景/前台切换时导航状态丢失的问题
//

import SwiftUI
import UIKit
import AngelLiveCore
import AngelLiveDependencies

struct LiveRoomCategoryContext: Equatable {
    let mainCategoryIndex: Int
    let subCategoryIndex: Int
}

/// Each presentation owns its destination and source until the container releases it.
struct RoomPlayerRoute: Identifiable, Hashable {
    let id = UUID()
    let room: LiveModel
    let animation: RoomEntryAnimation
    let opensShortDramaHistory: Bool
    let sourceID: String
    let categoryRooms: [LiveModel]
    let categoryContext: LiveRoomCategoryContext?
    let returnPreview: RoomPlayerReturnPreview?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Observable
final class LiveRoomNavigationState {
    private var route: RoomPlayerRoute?
    let returnSource = RoomPlayerReturnSource()

    func navigate(
        to room: LiveModel,
        categoryRooms: [LiveModel] = [],
        categoryContext: LiveRoomCategoryContext? = nil,
        transitionSourceID: String? = nil,
        opensShortDramaHistory: Bool = false,
        hasNavigationStack: Bool = true
    ) {
        let animation: RoomEntryAnimation
        if #available(iOS 18.0, *) {
            animation = hasNavigationStack ? GeneralSettingModel().roomEntryAnimation : .zoom
        } else {
            animation = hasNavigationStack ? .push : .zoom
        }
        route = RoomPlayerRoute(
            room: room, animation: animation, opensShortDramaHistory: opensShortDramaHistory,
            sourceID: transitionSourceID ?? room.roomId,
            categoryRooms: categoryRooms, categoryContext: categoryContext,
            returnPreview: route?.returnPreview ?? returnSource.capture()
        )
    }

    fileprivate func binding(for animation: RoomEntryAnimation) -> Binding<RoomPlayerRoute?> {
        let presented = route?.animation == animation ? route : nil
        return Binding(get: { presented }, set: { selection in
            if selection == nil, let route = presented {
                self.finish(route)
            }
        })
    }

    fileprivate func finish(_ completed: RoomPlayerRoute) {
        guard route?.id == completed.id else { return }
        route = nil
    }
}

struct RoomPlayerReturnPreview {
    let view: UIView
    let size: CGSize

    init?(window: UIWindow) {
        guard let snapshot = window.snapshotView(afterScreenUpdates: false) else { return nil }
        view = snapshot
        size = window.bounds.size
    }
}

@MainActor
final class RoomPlayerReturnSource {
    fileprivate weak var view: UIView?

    func capture() -> RoomPlayerReturnPreview? {
        guard let window = view?.window else { return nil }
        return RoomPlayerReturnPreview(window: window)
    }
}

private struct RoomPlayerReturnSourceAnchor: UIViewRepresentable {
    let source: RoomPlayerReturnSource

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        source.view = view
    }
}

extension View {
    func roomPlayerReturnSource(_ source: RoomPlayerReturnSource?) -> some View {
        background {
            if let source {
                RoomPlayerReturnSourceAnchor(source: source)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    func roomPlayerPushDestination<Destination: View>(
        _ navigationState: LiveRoomNavigationState,
        @ViewBuilder destination: @escaping (RoomPlayerRoute) -> Destination
    ) -> some View {
        roomPlayerReturnSource(navigationState.returnSource)
            .navigationDestination(item: navigationState.binding(for: .push)) { route in
                destination(route)
                    .environment(\.fullUIRoomPlayerPushed, true)
                    .environment(\.fullUIRoomPlayerReturnPreview, route.returnPreview)
                    .environment(\.finishRoomPlayerSwipe, { navigationState.finish(route) })
            }
    }

    func roomPlayerZoomCover<Destination: View>(
        _ navigationState: LiveRoomNavigationState,
        @ViewBuilder destination: @escaping (RoomPlayerRoute) -> Destination
    ) -> some View {
        fullScreenCover(item: navigationState.binding(for: .zoom)) { route in
            destination(route)
                .environment(\.fullUIRoomPlayerReturnPreview, route.returnPreview)
                .environment(\.finishRoomPlayerSwipe, { navigationState.finish(route) })
        }
    }
}

// MARK: - Namespace 环境值

/// 用于在父视图和子视图之间共享 Namespace，实现 zoom 过渡动画
private struct RoomTransitionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var roomTransitionNamespace: Namespace.ID? {
        get { self[RoomTransitionNamespaceKey.self] }
        set { self[RoomTransitionNamespaceKey.self] = newValue }
    }
}

// MARK: - Navigation State 环境值

private struct LiveRoomNavigationStateKey: EnvironmentKey {
    static let defaultValue: LiveRoomNavigationState? = nil
}

extension EnvironmentValues {
    @Entry var finishRoomPlayerSwipe: (@MainActor () -> Void)?
    @Entry var fullUIRoomPlayerPushed = false
    @Entry var fullUIRoomPlayerReturnPreview: RoomPlayerReturnPreview?

    var liveRoomNavigationState: LiveRoomNavigationState? {
        get { self[LiveRoomNavigationStateKey.self] }
        set { self[LiveRoomNavigationStateKey.self] = newValue }
    }
}

extension DetailPlayerView {
    @ViewBuilder
    func roomEntryTransition(_ animation: RoomEntryAnimation, sourceID: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            if animation == .zoom {
                modifier(ZoomTransitionModifier(sourceID: sourceID, namespace: namespace))
            } else {
                environment(\.fullUIRoomPlayerPushed, true)
                    .toolbar(.hidden, for: .navigationBar)
            }
        } else {
            self
        }
    }
}
