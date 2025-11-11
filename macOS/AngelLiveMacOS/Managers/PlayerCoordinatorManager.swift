//
//  PlayerCoordinatorManager.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import Foundation
import SwiftUI
import KSPlayer

/// 全局播放器协调器管理器
/// 确保整个 APP 只有一个播放器实例，避免重复创建
@MainActor
@Observable
final class PlayerCoordinatorManager {
    /// 全局共享的播放器协调器
    let coordinator: KSVideoPlayer.Coordinator

    /// 是否已检测到视频尺寸（用于控制播放器可见性）
    var hasDetectedSize: Bool = false

    init() {
        self.coordinator = KSVideoPlayer.Coordinator()
        print("🟢 PlayerCoordinatorManager init - 创建全局播放器协调器")
    }

    deinit {
        print("🔴 PlayerCoordinatorManager deinit")
    }

    /// 重置播放器状态
    /// 在退出播放页面时调用，清理播放器状态
    func reset() {
        print("🔄 PlayerCoordinatorManager reset - 重置播放器状态")

        // 停止播放并完全重置 playerLayer
        if let playerLayer = coordinator.playerLayer {
            playerLayer.pause()
            playerLayer.reset()

            // 清理播放器资源
            playerLayer.player.shutdown()
        }

        // 重置状态
        coordinator.isMuted = false
        coordinator.playbackRate = 1.0
        coordinator.isScaleAspectFill = false
        coordinator.isRecord = false
        coordinator.isMaskShow = false
        hasDetectedSize = false
    }

    /// 准备播放器
    /// 在进入播放页面时调用，确保播放器状态干净
    func prepare() {
        print("🟢 PlayerCoordinatorManager prepare - 准备播放器")
        print("   当前 playerLayer 状态: \(coordinator.playerLayer != nil ? "存在" : "不存在")")
        print("   当前 hasDetectedSize: \(hasDetectedSize)")
    }
}
