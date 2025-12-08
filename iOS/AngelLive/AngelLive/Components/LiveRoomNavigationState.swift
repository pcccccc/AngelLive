//
//  LiveRoomNavigationState.swift
//  AngelLive
//
//  管理直播间卡片的导航状态，解决 PiP 背景/前台切换时导航状态丢失的问题
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 直播间导航状态管理器
/// 将导航状态从视图的 @State 移到外部可观察对象，确保在 PiP 背景/前台切换时不会丢失
@Observable
class LiveRoomNavigationState {
    /// 是否显示播放器
    var showPlayer: Bool = false

    /// 当前选中的房间
    var currentRoom: LiveModel?

    /// 导航到指定房间
    func navigate(to room: LiveModel) {
        currentRoom = room
        showPlayer = true
    }

    /// 关闭播放器
    func dismiss() {
        showPlayer = false
        currentRoom = nil
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
    var liveRoomNavigationState: LiveRoomNavigationState? {
        get { self[LiveRoomNavigationStateKey.self] }
        set { self[LiveRoomNavigationStateKey.self] = newValue }
    }
}
