//
//  SimpleLiveTVOSApp.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore
import TipKit

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
#endif
}

@main
struct SimpleLiveTVOSApp: App {

    var appViewModel = AppState()

    init() {
        // 启动时将 Caches 中的插件同步到 App Group 容器（供 TopShelf 使用）
        PluginAppGroupSync.syncToAppGroup()

        KSOptions.logLevel = .error
        KSOptions.hudLog = false

        KingfisherManager.shared.defaultOptions += [
            .processor(WebPProcessor.default),
            .cacheSerializer(WebPSerializer.default)
        ]
        // tvOS 设备存储更紧张,缓存上限更严格
        let imageCache = ImageCache.default
        imageCache.diskStorage.config.sizeLimit = 150 * 1024 * 1024  // 150 MB
        imageCache.diskStorage.config.expiration = .days(3)
        imageCache.memoryStorage.config.totalCostLimit = 80 * 1024 * 1024  // 80 MB
        imageCache.memoryStorage.config.expiration = .seconds(300)
        imageCache.cleanExpiredDiskCache()

        BugsnagBootstrap.start(platform: .tvOS)

        // 配置 TipKit
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appViewModel: appViewModel)
                .task {
                    // 启动时同步所有平台的 Cookie 到 JS 插件
                    await PlatformSessionLiveParseBridge.syncFromPersistedSessionsOnLaunch()
                    // tvOS 启动时尝试从 iCloud 同步 Cookie
                    if PlatformCredentialSyncService.shared.iCloudSyncEnabled {
                        await PlatformCredentialSyncService.shared.syncAllFromICloud()
                    }
                }
                .onOpenURL { url in
                    appViewModel.handleDeepLink(url: url)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { appViewModel.showDeepLinkPlayer },
                    set: { appViewModel.showDeepLinkPlayer = $0 }
                )) {
                    DeepLinkPlayerView(appViewModel: appViewModel)
                }
        }
    }
}
