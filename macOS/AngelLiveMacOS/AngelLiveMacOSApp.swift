//
//  AngelLiveMacOSApp.swift
//  AngelLiveMacOS
//
//  Created by pc on 10/17/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

@main
struct AngelLiveMacOSApp: App {
    // 全局播放器协调器管理器
    @State private var playerManager = PlayerCoordinatorManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playerManager)
        }
        .commands {
            // 添加刷新命令
            CommandGroup(after: .appInfo) {
                Button("刷新") {
                    // 发送刷新通知
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshContent"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

