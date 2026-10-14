//
//  FullscreenPlayerManager.swift
//  AngelLiveMacOS
//
//  Created by Claude on 12/2/25.
//

import SwiftUI
import AppKit
import AngelLiveCore
import AngelLiveDependencies

enum MacPlaybackPresentationPreference {
    static let singlePageModeKey = "AngelLive.macOS.singlePagePlayback"
}

/// 每个浏览窗口拥有自己的播放路由，窗口间不共享呈现状态。
@MainActor
@Observable
final class FullscreenPlayerManager {
    /// 当前在浏览窗口内播放的房间。
    var currentRoom: LiveModel?

    /// 是否显示全屏播放器
    var showFullscreenPlayer: Bool = false

    @ObservationIgnored weak var mainWindow: NSWindow?
    var categoryRooms: CategoryRoomListModel?

    /// 检测主窗口是否处于全屏状态
    var isMainWindowFullscreen: Bool {
        guard let window = mainWindow else {
            return false
        }
        return window.styleMask.contains(.fullScreen)
    }

    /// 打开直播间
    /// - Parameters:
    ///   - room: 直播间信息
    ///   - openWindow: 新窗口打开方法
    func openRoom(
        _ room: LiveModel,
        openWindow: OpenWindowAction,
        categoryRooms: CategoryRoomListModel? = nil
    ) {
        let isFullUI = SandboxPluginCatalog.platform(for: room.liveType) != nil
        let usesSinglePage = isFullUI && UserDefaults.standard.bool(
            forKey: MacPlaybackPresentationPreference.singlePageModeKey
        )
        if usesSinglePage || isMainWindowFullscreen {
            self.categoryRooms = categoryRooms
            currentRoom = room
            showFullscreenPlayer = true
        } else {
            MacPlayerCategoryHandoff.shared.register(categoryRooms, for: room)
            openWindow(value: room)
        }
    }

    /// 关闭全屏播放器
    func closeFullscreenPlayer() {
        showFullscreenPlayer = false
        currentRoom = nil
        categoryRooms = nil
    }
}

/// WindowGroup 的值是 LiveModel；仅把同分区模型交给新开的播放器，不序列化闭包或房间列表。
@MainActor
@Observable
final class MacPlayerCategoryHandoff {
    static let shared = MacPlayerCategoryHandoff()
    struct Entry {
        let id = UUID()
        weak var model: CategoryRoomListModel?
    }
    private var pending: [LiveModel: Entry] = [:]

    func register(_ model: CategoryRoomListModel?, for room: LiveModel) {
        pending[room] = Entry(model: model)
    }

    func requestID(for room: LiveModel) -> UUID? {
        pending[room]?.id
    }

    func take(for room: LiveModel) -> Entry? {
        pending.removeValue(forKey: room)
    }
}
