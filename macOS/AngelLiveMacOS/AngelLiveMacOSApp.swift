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
import AppKit

// 应用程序代理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct AngelLiveMacOSApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // 首次启动管理器
    @State private var welcomeManager = WelcomeManager()
    // 全局 ViewModels（用于共享到所有窗口）
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var toastManager = ToastManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(welcomeManager)
                .environment(favoriteViewModel)
                .environment(toastManager)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("刷新") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshContent"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        WindowGroup(for: LiveModel.self) { $room in
            if let room = room {
                RoomPlayerView(room: room)
                    .environment(favoriteViewModel)
                    .environment(toastManager)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .windowSize) {
                EmptyView()
            }
            CommandGroup(replacing: .windowArrangement) {
                EmptyView()
            }
        }
    }
}

