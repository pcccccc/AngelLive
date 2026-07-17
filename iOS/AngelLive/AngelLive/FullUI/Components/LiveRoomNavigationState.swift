//
//  LiveRoomNavigationState.swift
//  AngelLive
//
//  管理直播间卡片的导航状态，解决 PiP 背景/前台切换时导航状态丢失的问题
//

import SwiftUI
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
    var showPlayer: Bool = false

    /// 当前选中的房间
    var currentRoom: LiveModel?

    /// 从分区列表进入时保留当时的房间快照，供播放页连续换台。
    var categoryRooms: [LiveModel] = []

    /// 房间快照对应的分区位置，用于播放页换台面板继续上拉分页。
    var categoryContext: LiveRoomCategoryContext?

    /// 导航到指定房间
    func navigate(
        to room: LiveModel,
        categoryRooms: [LiveModel] = [],
        categoryContext: LiveRoomCategoryContext? = nil
    ) {
        currentRoom = room
        self.categoryRooms = categoryRooms
        self.categoryContext = categoryContext
        showPlayer = true
    }

    /// 关闭播放器
    func dismiss() {
        showPlayer = false
        currentRoom = nil
        categoryRooms = []
        categoryContext = nil
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
