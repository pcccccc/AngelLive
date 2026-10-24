//
//  AngelLiveApp.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import SharedAssets
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
    // Keep production dependencies shared across windows, as in the original App-level state.
    @State private var launch = AppLaunch.current

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .production(let models):
                ProductionAppRoot(models: models)
            #if DEBUG
            case .history(let context):
                NavigationStack {
                    HistoryListView(progressStore: context.progress)
                }
                .environment(context.history)
                .environment(context.favorite)
                .installToast(position: .top)
            case .invalid:
                Text("UI 测试启动配置无效")
                    .accessibilityIdentifier("uitest.launch.invalid")
            #endif
            }
        }
    }
}

/// One instance belongs to App state; each window keeps its original scene-local history.
private final class ProductionAppModels {
    let playerManager = PlayerCoordinatorManager()
    let welcomeManager = WelcomeManager()
    let favoriteViewModel = AppFavoriteModel()
    let pluginAvailability = PluginAvailabilityService(managesAPICredentialPolicy: true)
}

private enum AppLaunch {
    case production(ProductionAppModels)
    #if DEBUG
    case history(UITestHistoryContext)
    case invalid
    #endif

    /// Resolve once before creating any production dependency or preparing fixture storage.
    static let current: AppLaunch = {
        #if DEBUG
        do {
            if let configuration = try UITestLaunchConfiguration.current() {
                return .history(try UITestHistoryContext.prepare(configuration: configuration))
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test") }) {
                return .invalid
            }
        } catch {
            // A malformed test launch must never fall through to personal application data.
            return .invalid
        }
        #endif
        return .production(ProductionAppModels())
    }()
}

private struct ProductionAppRoot: View {
    let models: ProductionAppModels

    var body: some View {
        AngelLiveSceneView()
            .environment(models.favoriteViewModel)
            .developerModeConsoleOverlay()
            .environment(models.pluginAvailability)
            .environment(models.playerManager)
            .environment(models.welcomeManager)
            .installToast(position: .top)
            // 旧单平台凭证管理已删除，凭证同步由 PlatformCredentialSyncService 管理
            .onAppear {
                GeneralSettingModel().globalGeneralSettingFavoriteStyle = AngelLiveFavoriteStyle.liveState.rawValue
            }
            .fullUIArcLoadingStyle(isEnabled: models.pluginAvailability.hasAvailablePlugins)
    }
}

/// 每个窗口独立持有历史模型，并在 ContentView 的 presentation / navigation 边界外注入。
private struct AngelLiveSceneView: View {
    @State private var historyModel = HistoryModel()

    var body: some View {
        ContentView()
            .environment(historyModel)
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
        #if DEBUG
        // Match all reserved test arguments, including malformed configurations.
        // This gate runs before analytics, image cleanup, plugin and credential services.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test") }) {
            return true
        }
        #endif
        MediaTransformSupport.registerHostCapability()
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
        // 将 KSPlayer 日志同时打印到 Xcode 控制台和 App 内开发者控制台
        KSOptions.logger = KSPlayerConsoleBridge()
        KSOptions.logLevel = .debug
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
            // `.playback` 本身支持 AirPlay；`.allowAirPlay` 只用于需要显式放宽
            // 路由的录放类别，在部分系统版本上与 playback 组合会返回 paramErr(-50)。
            try audioSession.setCategory(.playback, mode: .moviePlayback)
        } catch {
            Logger.warning("配置音频会话失败: \(error)", category: .app)
        }
    }

    private func logPluginInstallLocation() {
        let storage = LiveParsePlugins.shared.storage
        Logger.debug("[iOS] 插件根目录: \(storage.pluginsRootDirectory.path)", category: .app)
        Logger.debug("[iOS] 插件状态文件: \(storage.stateFileURL.path)", category: .app)
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
