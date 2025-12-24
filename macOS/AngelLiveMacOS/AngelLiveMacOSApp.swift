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
import Sparkle
import Combine

// Sparkle 更新控制器
final class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// 应用程序代理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 打印当前 Bilibili Cookie
        let cookie = UserDefaults.standard.string(forKey: "SimpleLive.Setting.BilibiliCookie") ?? ""
        print("[App Launch] Bilibili Cookie: \(cookie.isEmpty ? "(空)" : cookie)")
    }
}

@main
struct AngelLiveMacOSApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Sparkle 更新管理器
    @StateObject private var updaterViewModel = UpdaterViewModel()
    // 首次启动管理器
    @State private var welcomeManager = WelcomeManager()
    // 全局 ViewModels（用于共享到所有窗口）
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var toastManager = ToastManager()
    @State private var fullscreenPlayerManager = FullscreenPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(welcomeManager)
                .environment(favoriteViewModel)
                .environment(toastManager)
                .environment(fullscreenPlayerManager)
                .environmentObject(updaterViewModel)
                .setupBilibiliCookieIfNeeded()
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)

                Divider()

                Button("刷新") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshContent"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .defaultSize(width: 1024, height: 960)

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

