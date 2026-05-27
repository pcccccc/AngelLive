//
//  AngelLiveApp.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
internal import AVFoundation

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
#endif
}

@main
struct AngelLiveApp: App {
    // 连接 AppDelegate 以支持屏幕方向控制
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 全局播放器协调器管理器
    @State private var playerManager = PlayerCoordinatorManager()

    // 首次启动管理器
    @State private var welcomeManager = WelcomeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .developerModeConsoleOverlay()
                .environment(playerManager)
                .environment(welcomeManager)
                .installToast(position: .top)
                // 旧单平台凭证管理已删除，凭证同步由 PlatformCredentialSyncService 管理
                .onAppear {
                    GeneralSettingModel().globalGeneralSettingFavoriteStyle = AngelLiveFavoriteStyle.liveState.rawValue
                }
        }
    }
}

private extension View {
    /// 始终编译 DevConsoleOverlay,运行时是否显示由 GeneralSettingModel.developerModeEnabled 控制。
    /// App Store 构建只是常驻一个未激活的 overlay 容器,用户不开"开发者模式"就完全感知不到。
    func developerModeConsoleOverlay() -> some View {
        self.overlay { DevConsoleOverlay() }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BugsnagBootstrap.start(platform: .iOS)
        // 仅预配置播放类别，避免应用启动时立刻打断其他 App 的音频。
        configureAudioSessionForPlayback()
        configureImageCache()
        #if DEBUG
        logPluginInstallLocation()
        #endif

        Task {
            await PlatformSessionLiveParseBridge.syncFromPersistedSessionsOnLaunch()
        }

        // 初始化屏幕方向设置
        KSOptions.logLevel = .error
        KSOptions.hudLog = false
        if AppConstants.Device.isIPad {
            KSOptions.supportedInterfaceOrientations = .all
        } else {
            // iPhone 初始只支持竖屏，播放器页面会动态修改
            KSOptions.supportedInterfaceOrientations = .portrait
        }
        return true
    }

    /// 限制 Kingfisher 磁盘缓存上限,避免直播封面图无限堆积导致 Documents & Data 膨胀。
    private func configureImageCache() {
        let cache = ImageCache.default
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024  // 200 MB
        cache.diskStorage.config.expiration = .days(3)
        cache.memoryStorage.config.totalCostLimit = 60 * 1024 * 1024  // 60 MB
        cache.memoryStorage.config.expiration = .seconds(300)
        // 启动后异步清理过期文件,不阻塞主线程
        cache.cleanExpiredDiskCache()
    }

    /// 预配置音频会话类别，真正播放时再由系统激活会话。
    private func configureAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        } catch {
            print("配置音频会话失败: \(error)")
        }
    }

    private func logPluginInstallLocation() {
        let storage = LiveParsePlugins.shared.storage
        print("[iOS] 插件根目录: \(storage.pluginsRootDirectory.path)")
        print("[iOS] 插件状态文件: \(storage.stateFileURL.path)")
    }

    // MARK: - Orientation Support

    /// 控制应用支持的屏幕方向
    /// 这是控制方向的唯一正确方法，SwiftUI 项目也需要这个 AppDelegate 方法
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // 返回当前支持的屏幕方向
        if let orientation = KSOptions.supportedInterfaceOrientations {
            return orientation
        }

        // 如果没有设置，根据设备类型返回默认值
        if AppConstants.Device.isIPad {
            return .all
        } else {
            return .allButUpsideDown  // iPhone 默认支持所有方向（除了倒置）
        }
    }
}
