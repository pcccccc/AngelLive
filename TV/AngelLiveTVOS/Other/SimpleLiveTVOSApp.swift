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


extension EnvironmentValues {
    /// Presentation mode supplied by this host's FullUI/ShellUI entry point.
    @Entry var usesFullUI = false
}

#if DEBUG
@main
@MainActor
private enum SimpleLiveTVOSAppLauncher {
    static func main() {
        if PlatformAppearanceDemo.isEnabled {
            AppearanceDemoApp.main()
            return
        }
        SimpleLiveTVOSApp.main()
    }
}

private struct AppearanceDemoApp: App {
    var body: some Scene {
        WindowGroup {
            PlatformAppearanceDemoRoot { _, _ in
                TVAppearanceDemoPage()
            }
        }
    }
}
#endif

#if !DEBUG
@main
#endif
struct SimpleLiveTVOSApp: App {

    private let appViewModel: AppState
#if DEBUG
    private let historyTestContext: UITestHistoryContext?
    private let vodDemoSandbox: VodDemoSandbox?
#endif

    init() {
#if DEBUG
        if VodDemoSandbox.isEnabled {
            do {
                let sandbox = try VodDemoSandbox.current.get()
                vodDemoSandbox = sandbox
                historyTestContext = nil
                appViewModel = AppState(vodDemoSandbox: sandbox)
                KSOptions.logLevel = .error
                KSOptions.hudLog = false
                return
            } catch {
                fatalError("Cannot prepare isolated VOD demo")
            }
        }
        vodDemoSandbox = nil
        do {
            if let configuration = try UITestLaunchConfiguration.current() {
                let context = try UITestHistoryContext.prepare(configuration: configuration)
                historyTestContext = context
                appViewModel = AppState(historyTestContext: context)
                return
            }
            historyTestContext = nil
        } catch {
            fatalError("Cannot prepare isolated UI test history: \(error)")
        }
#endif
        appViewModel = AppState()
        MediaTransformSupport.registerHostCapability()
        DualStreamSupport.registerHostCapability()
        Task { await PlaylistSyncService.shared.start() }
        Task { await PlatformAppearanceSyncService.shared.start() }
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
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if let vodDemoSandbox {
            TVVodDemoRootView(appViewModel: appViewModel, sandbox: vodDemoSandbox)
                .environment(\.usesFullUI, true)
        } else if let historyTestContext {
            TVFullUIHistoryListView(appViewModel: appViewModel, progressStore: historyTestContext.progress)
        } else {
            productionRoot
        }
#else
        productionRoot
#endif
    }

    private var productionRoot: some View {
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
                .environment(\.usesFullUI, appViewModel.pluginAvailability.hasAvailablePlugins)
                .task(id: appViewModel.pluginAvailability.hasAvailablePlugins) {
                    await PlatformAppearanceSyncService.shared.setFullUIAvailable(appViewModel.pluginAvailability.hasAvailablePlugins)
                }
    }
}

#if DEBUG
private struct TVAppearanceDemoPage: View {
    @State private var platforms: PlatformViewModel = {
        let model = PlatformViewModel()
        model.platformInfo = PlatformAppearanceDemo.platforms.map {
            Platformdescription(
                title: $0.title,
                pluginId: $0.pluginId,
                bigPic: $0.bigPic,
                smallPic: $0.smallPic,
                descripiton: $0.descripiton,
                liveType: $0.liveType
            )
        }
        return model
    }()

    @State private var tab = 2

    var body: some View {
        TabView(selection: $tab) {
            Text("推荐")
                .tabItem { Label("推荐", systemImage: "house.fill") }
                .tag(0)

            Text("收藏")
                .tabItem { Label("收藏", systemImage: "star.fill") }
                .tag(1)

            TVFullPlatformGrid(
                platforms: platforms,
                catalogRevision: 0,
                usesSolidBackground: false,
                open: { _ in }
            )
            .tabItem { Label("配置", systemImage: "square.stack.3d.up.fill") }
            .tag(2)

            Text("搜索")
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(3)

            TVPlatformAppearanceControls(platforms: platforms, onClose: { tab = 2 })
                .safeAreaPadding(.horizontal, 80)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(4)
        }
    }
}
#endif
