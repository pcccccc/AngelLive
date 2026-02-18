//
//  AngelLiveApp.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
internal import AVFoundation

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
                .environment(playerManager)
                .environment(welcomeManager)
                .installToast(position: .top)
                .setupBilibiliCookieIfNeeded()
                .onAppear {
                    GeneralSettingModel().globalGeneralSettingFavoriteStyle = AngelLiveFavoriteStyle.liveState.rawValue
                }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 配置音频会话以支持后台播放
        configureAudioSession()

        Task {
            await PlatformSessionLiveParseBridge.syncFromPersistedSessionsOnLaunch()
        }

        // 初始化屏幕方向设置
        if AppConstants.Device.isIPad {
            KSOptions.supportedInterfaceOrientations = .all
        } else {
            // iPhone 初始只支持竖屏，播放器页面会动态修改
            KSOptions.supportedInterfaceOrientations = .portrait
        }
        return true
    }

    /// 配置音频会话以支持后台播放
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try audioSession.setActive(true)
        } catch {
            print("配置音频会话失败: \(error)")
        }
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
