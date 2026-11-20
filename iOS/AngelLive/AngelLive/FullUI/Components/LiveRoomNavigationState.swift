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

/// 直播间导航状态管理器
/// 将导航状态从视图的 @State 移到外部可观察对象，确保在 PiP 背景/前台切换时不会丢失
@Observable
class LiveRoomNavigationState {
    /// 是否显示播放器
    private(set) var showPlayer = false
    private var entryAnimation: RoomEntryAnimation = .zoom
    let returnSource = RoomPlayerReturnSource()
    @ObservationIgnored fileprivate private(set) var returnPreview: RoomPlayerReturnPreview?

    /// 当前选中的房间
    var currentRoom: LiveModel?

    /// Identifies a particular card when the same room appears in several home sections.
    var transitionSourceID: String?

    /// 从分区列表进入时保留当时的房间快照，供播放页连续换台。
    var categoryRooms: [LiveModel] = []

    /// 房间快照对应的分区位置，用于播放页换台面板继续上拉分页。
    var categoryContext: LiveRoomCategoryContext?

    /// 导航到指定房间
    func navigate(
        to room: LiveModel,
        categoryRooms: [LiveModel] = [],
        categoryContext: LiveRoomCategoryContext? = nil,
        transitionSourceID: String? = nil
    ) {
        if #available(iOS 18.0, *) {
            entryAnimation = GeneralSettingModel().roomEntryAnimation
        } else {
            entryAnimation = .push
        }
        if !showPlayer {
            // Capture the rendered source before the player covers it or the stack detaches it.
            returnPreview = returnSource.capture()
        }
        currentRoom = room
        self.categoryRooms = categoryRooms
        self.categoryContext = categoryContext
        self.transitionSourceID = transitionSourceID
        showPlayer = true
    }

    func playerBinding(for animation: RoomEntryAnimation) -> Binding<Bool> {
        Binding(
            get: { self.showPlayer && self.entryAnimation == animation },
            set: { isPresented in
                if !isPresented, self.entryAnimation == animation { self.dismiss() }
            }
        )
    }

    /// 关闭播放器
    func dismiss() {
        showPlayer = false
        returnPreview = nil
        currentRoom = nil
        categoryRooms = []
        categoryContext = nil
        transitionSourceID = nil
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
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        roomPlayerReturnSource(navigationState.returnSource)
            .navigationDestination(isPresented: navigationState.playerBinding(for: .push)) {
                destination()
                    .environment(\.fullUIRoomPlayerReturnPreview, navigationState.returnPreview)
            }
    }

    func roomPlayerZoomCover<Destination: View>(
        _ navigationState: LiveRoomNavigationState,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        fullScreenCover(isPresented: navigationState.playerBinding(for: .zoom)) {
            destination()
                .environment(\.fullUIRoomPlayerReturnPreview, navigationState.returnPreview)
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
