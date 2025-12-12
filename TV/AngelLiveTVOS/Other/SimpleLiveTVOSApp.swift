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

@main
struct SimpleLiveTVOSApp: App {

    var appViewModel = AppState()

    init() {
        KingfisherManager.shared.defaultOptions += [
            .processor(WebPProcessor.default),
            .cacheSerializer(WebPSerializer.default)
        ]
        Bugsnag.start()

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
                    // tvOS 启动时尝试从 iCloud 同步 Cookie
                    if BilibiliCookieSyncService.shared.iCloudSyncEnabled {
                        _ = await BilibiliCookieSyncService.shared.syncFromICloud()
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
