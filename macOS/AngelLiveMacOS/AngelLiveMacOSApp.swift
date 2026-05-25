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
#if !APPSTORE
import Sparkle
#endif
import Combine

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
#endif
}

#if !APPSTORE
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
#endif

// 应用程序代理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        KSOptions.logLevel = .error
        KSOptions.hudLog = false

        Task {
            await PlatformSessionLiveParseBridge.syncFromPersistedSessionsOnLaunch()
            if PlatformCredentialSyncService.shared.iCloudSyncEnabled {
                await PlatformCredentialSyncService.shared.syncAllFromICloud()
            }
        }
    }
}

@main
struct AngelLiveMacOSApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #if !APPSTORE
    // Sparkle 更新管理器
    @StateObject private var updaterViewModel = UpdaterViewModel()
    #endif
    // 首次启动管理器
    @State private var welcomeManager = WelcomeManager()
    // 全局 ViewModels（用于共享到所有窗口）
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var historyViewModel = HistoryModel()
    @State private var toastManager = ToastManager()
    @State private var fullscreenPlayerManager = FullscreenPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(welcomeManager)
                .environment(favoriteViewModel)
                .environment(historyViewModel)
                .environment(toastManager)
                .environment(fullscreenPlayerManager)
                #if !APPSTORE
                .environmentObject(updaterViewModel)
                #endif
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                #if !APPSTORE
                Button("检查更新...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)

                Divider()
                #endif

                Button("刷新") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshContent"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            #if DEBUG
            // Debug 菜单 + ⌘⇧D 召出插件控制台,仅 DEBUG 构建可见。
            DevConsoleCommands()
            #endif
        }
        .defaultSize(width: 1024, height: 960)

        #if DEBUG
        DevConsoleScene()
        #endif

        WindowGroup(for: LiveModel.self) { $room in
            if let room = room {
                RoomPlayerView(room: room)
                    .environment(favoriteViewModel)
                    .environment(historyViewModel)
                    .environment(toastManager)
                    .background(PlayerWindowChromeView(hidesWindowButtons: true, allowsBackgroundDrag: false))
            }
        }
        // 仅作"首次打开"的提示尺寸 —— 真正强制每次新开都用 16:9 默认值
        // 由 PlayerWindowChromeNSView.viewDidMoveToWindow 内的 setFrame 完成,
        // 避免 macOS 状态恢复把上一次拖大/拖小的尺寸"记住"用到下一个房间。
        .defaultSize(width: 1280, height: 720)
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

    /// macOS WindowGroup 会持久化用户拖动后的窗口尺寸,导致下一次开新房间还沿用上次大小。
    /// 这里在首次挂到 window 时把 contentSize 强制重置为 16:9 默认值,在屏幕内居中。
    /// 用户后续拖动不影响当前窗口 —— 只有"新打开"的窗口才会被重置。
    private static let defaultContentSize = NSSize(width: 1280, height: 720)
    private func resetWindowFrameIfNeeded(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let target = Self.defaultContentSize
        let contentRect = NSRect(origin: .zero, size: target)
        let frameRect = window.frameRect(forContentRect: contentRect)
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frameRect.width / 2,
            y: visible.midY - frameRect.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameRect.size), display: true)
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
            // 仅首次挂载时重置 frame,避免每次 SwiftUI 触发 updateNSView 都重置覆盖用户拖动。
            resetWindowFrameIfNeeded(window)
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
