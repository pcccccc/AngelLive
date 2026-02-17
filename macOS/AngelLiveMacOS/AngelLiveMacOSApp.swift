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
        let cookie = BilibiliCookieSyncService.shared.getCurrentCookie()
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
                    .background(PlayerWindowChromeView(hidesWindowButtons: true, allowsBackgroundDrag: false))
            }
        }
        // .windowStyle(.hiddenTitleBar)
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

private struct PlayerWindowChromeView: NSViewRepresentable {
    let hidesWindowButtons: Bool
    let allowsBackgroundDrag: Bool

    func makeNSView(context: Context) -> PlayerWindowChromeNSView {
        PlayerWindowChromeNSView(
            hidesWindowButtons: hidesWindowButtons,
            allowsBackgroundDrag: allowsBackgroundDrag
        )
    }

    func updateNSView(_ nsView: PlayerWindowChromeNSView, context: Context) {
        nsView.hidesWindowButtons = hidesWindowButtons
        nsView.allowsBackgroundDrag = allowsBackgroundDrag
        nsView.applyIfPossible()
    }
}

private final class PlayerWindowChromeNSView: NSView {
    var hidesWindowButtons: Bool
    var allowsBackgroundDrag: Bool
    private var previousState: WindowChromeState?

    init(hidesWindowButtons: Bool, allowsBackgroundDrag: Bool) {
        self.hidesWindowButtons = hidesWindowButtons
        self.allowsBackgroundDrag = allowsBackgroundDrag
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfPossible()
    }

    func applyIfPossible() {
        guard let window = window else { return }
        if previousState == nil {
            let closeButton = window.standardWindowButton(.closeButton)
            let miniButton = window.standardWindowButton(.miniaturizeButton)
            let zoomButton = window.standardWindowButton(.zoomButton)
            previousState = WindowChromeState(
                window: window,
                closeHidden: closeButton?.isHidden ?? false,
                miniHidden: miniButton?.isHidden ?? false,
                zoomHidden: zoomButton?.isHidden ?? false,
                isMovableByWindowBackground: window.isMovableByWindowBackground
            )
        }
        if let state = previousState {
            window.standardWindowButton(.closeButton)?.isHidden = hidesWindowButtons ? true : state.closeHidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = hidesWindowButtons ? true : state.miniHidden
            window.standardWindowButton(.zoomButton)?.isHidden = hidesWindowButtons ? true : state.zoomHidden
        }
        window.isMovableByWindowBackground = allowsBackgroundDrag
    }

    deinit {
        guard let state = previousState else { return }
        state.window.standardWindowButton(.closeButton)?.isHidden = state.closeHidden
        state.window.standardWindowButton(.miniaturizeButton)?.isHidden = state.miniHidden
        state.window.standardWindowButton(.zoomButton)?.isHidden = state.zoomHidden
        state.window.isMovableByWindowBackground = state.isMovableByWindowBackground
    }
}

private struct WindowChromeState {
    let window: NSWindow
    let closeHidden: Bool
    let miniHidden: Bool
    let zoomHidden: Bool
    let isMovableByWindowBackground: Bool
}
