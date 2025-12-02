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

/// 全屏播放器管理器
/// 用于检测主窗口全屏状态，并在全屏时使用 fullScreenCover 打开播放器
@Observable
final class FullscreenPlayerManager {
    /// 当前要播放的房间（用于 fullScreenCover）
    var currentRoom: LiveModel?

    /// 是否显示全屏播放器
    var showFullscreenPlayer: Bool = false

    /// 检测主窗口是否处于全屏状态
    var isMainWindowFullscreen: Bool {
        guard let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first else {
            return false
        }
        return window.styleMask.contains(.fullScreen)
    }

    /// 打开直播间
    /// - Parameters:
    ///   - room: 直播间信息
    ///   - openWindow: 新窗口打开方法
    func openRoom(_ room: LiveModel, openWindow: OpenWindowAction) {
        if isMainWindowFullscreen {
            // 全屏状态下使用 fullScreenCover
            currentRoom = room
            showFullscreenPlayer = true
        } else {
            // 非全屏状态下使用新窗口
            openWindow(value: room)
        }
    }

    /// 关闭全屏播放器
    func closeFullscreenPlayer() {
        showFullscreenPlayer = false
        currentRoom = nil
    }
}
