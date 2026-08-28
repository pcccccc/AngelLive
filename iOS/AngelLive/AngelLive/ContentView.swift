//
//  ContentView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

// 定义 Tab 选择类型
enum TabSelection: Hashable {
    case home
    case favorites
    case allPlatforms
    case platform(Platformdescription)
    case settings
    case search
}

private enum HomeRecommendationAvailability {
    case unconfirmed
    case available
    case unavailable
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .home
    @State private var homeRecommendationAvailability = HomeRecommendationAvailability.unconfirmed
    @AppStorage(HomePagePreference.storageKey, store: .shared)
    private var homePagePreference = HomePagePreference.recommendations
    @AppStorage(HomePagePreference.selectedPluginStorageKey, store: .shared)
    private var selectedHomePluginId = ""
    @Environment(\.presentToast) private var presentToast

    // 首次启动管理器
    @Environment(WelcomeManager.self) private var welcomeManager

    // 插件检测服务
    @State private var pluginAvailability = PluginAvailabilityService()

    // 壳 UI 服务
    @State private var bookmarkService = StreamBookmarkService()
    @State private var pluginSourceManager = PluginSourceManager()
    @State private var shellHistoryService = ShellHistoryService()

    // CloudKit 插件源同步
    @State private var pluginSourceSyncService = PluginSourceSyncService()
    @State private var showPluginSyncPrompt = false

    // 插件订阅 / 安装确认请求器
    @State private var consentService = PluginInstallConsentService()

    // 创建全局 ViewModels
    @State private var platformViewModel = PlatformViewModel()
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var searchViewModel = SearchViewModel()
    @State private var historyViewModel = HistoryModel()

    // 触觉反馈生成器
    private let hapticFeedback = UISelectionFeedbackGenerator()

    // 动态获取 TabSection 标题
    private var platformSectionTitle: String {
        if case .platform(let platform) = selectedTab {
            return platform.title
        }
        return "配置"
    }

    /// FullUI 首页切到收藏时，tab 图标跟随收藏同步状态。
    private var favoriteTabSyncStatus: CloudSyncStatus {
        favoriteViewModel.syncStatus
    }

    private var homePlatformOptions: [HomePlatformOption] {
        platformViewModel.platformInfo.compactMap { platform in
            guard PlatformCapability.supports(.homeFeed, for: platform.liveType) else {
                return nil
            }
            return HomePlatformOption(
                pluginId: platform.pluginId,
                displayName: platform.title,
                liveType: platform.liveType
            )
        }
    }

    /// FullUI 中只有确认所有插件都不支持 homeFeed 时才回退到收藏。
    /// 不覆盖持久化偏好，以便以后安装支持推荐页的插件后恢复用户原选择。
    private var effectiveHomePagePreference: HomePagePreference {
        guard pluginAvailability.hasAvailablePlugins else {
            return homePagePreference
        }

        switch homeRecommendationAvailability {
        case .unconfirmed, .available:
            return homePagePreference
        case .unavailable:
            return .favorites
        }
    }

    @ViewBuilder
    private var iPhoneHomeTabIcon: some View {
        if effectiveHomePagePreference == .favorites {
            // UIKit 动画器会接管这个占位符，避免 SwiftUI 重建 tab 图标时打断效果。
            Image(systemName: "checkmark.icloud.fill")
        } else {
            Image(systemName: "house.fill")
        }
    }

    private var iPhoneHomeTabTitle: String {
        effectiveHomePagePreference == .favorites ? "收藏" : "首页"
    }

    private var recommendationsAvailableForMenu: Bool {
        homeRecommendationAvailability != .unavailable
    }

    @ViewBuilder
    private var preferredHomePage: some View {
        switch effectiveHomePagePreference {
        case .recommendations:
            HomeView()
        case .favorites:
            AdaptiveFavoriteView()
        }
    }

    @ViewBuilder
    private var iPhoneTabBarAccessories: some View {
        if pluginAvailability.hasAvailablePlugins {
            HomeTabContextMenuInstaller(
                options: homePlatformOptions,
                recommendationsAvailable: recommendationsAvailableForMenu,
                selectedPreference: effectiveHomePagePreference,
                selectedPluginId: selectedHomePluginId,
                onSelectRecommendations: selectRecommendations,
                onSelectFavorites: selectFavorites,
                onSelectPlatform: selectPlatform
            )
        }

        if pluginAvailability.hasAvailablePlugins
            && effectiveHomePagePreference == .favorites {
            FavoriteTabSymbolAnimator(syncStatus: favoriteTabSyncStatus)
        }
    }

    var body: some View {
        @Bindable var manager = welcomeManager

        Group {
            if #available(iOS 18.0, *) {
                if AppConstants.Device.isIPad {
                    iPadTabView
                } else {
                    iPhoneTabView
                        .background {
                            iPhoneTabBarAccessories
                        }
                }
            } else {
                if AppConstants.Device.isIPad {
                    iOS17iPadTabView
                } else {
                    iOS17iPhoneTabView
                        .background {
                            iPhoneTabBarAccessories
                        }
                }
            }
        }
        .environment(pluginAvailability)
        .environment(bookmarkService)
        .environment(pluginSourceManager)
        .environment(shellHistoryService)
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .environment(historyViewModel)
        .onChange(of: selectedTab) { _, newValue in
            hapticFeedback.selectionChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettings)) { _ in
            selectedTab = .settings
        }
        .sheet(isPresented: $manager.showWelcome) {
            WelcomeView {
                welcomeManager.completeWelcome()
                // 中国区 iOS 首次启动需要用户授权网络权限，
                // 此时 .task 中的 fetchKeys 可能已因无权限失败，
                // 用户点击欢迎页确认后重新拉取一次。
                Task { await PluginSourceKeyService.shared.fetchKeys() }
            }
            .modifier(WelcomePresentationModifier())
        }
        .task {
            // 注入插件安装确认请求器
            pluginSourceManager.consentRequester = consentService

            // 启动时拉取 key 映射（后台静默，不阻塞 UI）
            Task { await PluginSourceKeyService.shared.fetchKeys() }
            await pluginAvailability.checkAvailability()
            updateHomeRecommendationAvailability()

            // 自动检查插件更新（非阻塞，在 UI 就绪后后台运行）
            if pluginAvailability.hasAvailablePlugins && !pluginSourceManager.sourceURLs.isEmpty {
                await pluginSourceManager.refreshAvailableUpdates()
                let updatableIds = pluginAvailability.installedPluginIds.filter {
                    pluginSourceManager.hasUpdate(for: $0)
                }
                if !updatableIds.isEmpty {
                    presentToast(ToastValue(
                        icon: Image(systemName: "arrow.triangle.2.circlepath"),
                        message: "有 \(updatableIds.count) 个插件需要更新，正在更新..."
                    ))
                    var successCount = 0
                    for id in updatableIds {
                        if await pluginSourceManager.updatePlugin(pluginId: id) {
                            successCount += 1
                        }
                    }
                    await pluginAvailability.refresh()
                    updateHomeRecommendationAvailability()
                    if successCount > 0 {
                        presentToast(ToastValue(
                            icon: Image(systemName: "checkmark.circle.fill"),
                            message: "\(successCount) 个插件已更新完成"
                        ))
                    }
                }
            }

            // 无本地插件时，检查 CloudKit 是否有已保存的插件源
            if !pluginAvailability.hasAvailablePlugins {
                await pluginSourceSyncService.checkCloudForSources()
                if pluginSourceSyncService.hasSyncedSources {
                    showPluginSyncPrompt = true
                }
            }
        }
        .alert("检测到云端插件", isPresented: $showPluginSyncPrompt) {
            Button("一键安装") {
                Task {
                    await pluginSourceSyncService.performOneClickInstall(
                        pluginSourceManager: pluginSourceManager,
                        pluginAvailability: pluginAvailability,
                        consentRequester: consentService
                    )
                    updateHomeRecommendationAvailability()
                }
            }
            Button("取消", role: .cancel) {
                pluginSourceSyncService.dismissPrompt()
            }
        } message: {
            Text("检测到您已在其他设备安装过插件，是否一键安装？")
        }
        .alert(consentService.alertTitle, isPresented: $consentService.isPresenting) {
            Button(consentService.continueButtonTitle) { consentService.resolve(true) }
            Button("取消", role: .cancel) { consentService.resolve(false) }
        } message: {
            Text(consentService.alertMessage)
        }
        .onOpenURL { url in
            guard let link = AngelLiveDeepLink.parse(url) else { return }
            Task { await handleDeepLink(link) }
        }
        .overlay {
            if pluginSourceSyncService.isInstalling {
                cloudInstallProgressOverlay
            }
        }
        // 插件状态变化时刷新平台列表
        .onChange(of: pluginAvailability.installedPluginIds) { oldIds, newIds in
            platformViewModel.refreshPlatforms(installedPluginIds: newIds)
            updateHomeRecommendationAvailability()
            // 从无插件变为有插件时，主动触发收藏同步
            if oldIds.isEmpty && !newIds.isEmpty {
                Task {
                    await favoriteViewModel.syncWithActor()
                }
            }
            if newIds.isEmpty, selectedTab == .search {
                selectedTab = .home
            }
        }
        // 原地升级不会改变 pluginId 列表。以目录修订号重建平台元数据和
        // homeFeed 能力，避免长按 Tab 菜单继续使用更新前的能力快照。
        .onChange(of: pluginAvailability.catalogRevision) { _, _ in
            platformViewModel.refreshPlatforms(
                installedPluginIds: pluginAvailability.installedPluginIds
            )
            updateHomeRecommendationAvailability()
        }
        .onChange(of: pluginAvailability.isChecking) { _, isChecking in
            if !isChecking {
                updateHomeRecommendationAvailability()
            }
        }
        .onChange(of: platformViewModel.platformInfo) { _, newPlatforms in
            // 平台列表刷新后,选中平台可能已不存在(被移除,或元数据变更致
            // Platformdescription 合成 Hashable 不匹配旧值)。此时 sidebarAdaptable
            // TabView 的 selection 指向无效 tab,iPad resize/snapshot 时会 fatal error
            // "Tried to update with invalid selection value"。按稳定身份 pluginId 兜底。
            if case .platform(let selected) = selectedTab,
               !newPlatforms.contains(where: { $0.pluginId == selected.pluginId }) {
                selectedTab = .home
            }

            if !selectedHomePluginId.isEmpty,
               !newPlatforms.contains(where: {
                   $0.pluginId == selectedHomePluginId
                       && PlatformCapability.supports(.homeFeed, for: $0.liveType)
               }) {
                selectedHomePluginId = ""
            }
        }
    }

    // MARK: - Deep Link Handling

    @MainActor
    private func handleDeepLink(_ link: AngelLiveDeepLink) async {
        switch link {
        case .installSource(let input):
            presentToast(ToastValue(
                icon: Image(systemName: "icloud.and.arrow.down"),
                message: "正在添加订阅源..."
            ))
            let added = await pluginSourceManager.addSourceFromInput(input)
            guard !added.isEmpty else {
                let detail = pluginSourceManager.errorMessage ?? "无法识别的订阅源"
                presentToast(ToastValue(
                    icon: Image(systemName: "exclamationmark.triangle.fill"),
                    message: "添加失败:\(detail)"
                ))
                return
            }
            await pluginSourceManager.fetchAllSourceIndexes()
            let count = await pluginSourceManager.installAll()
            if count > 0 {
                await pluginAvailability.refresh()
                updateHomeRecommendationAvailability()
                presentToast(ToastValue(
                    icon: Image(systemName: "checkmark.circle.fill"),
                    message: "已通过 URL 安装 \(count) 个插件"
                ))
            } else {
                presentToast(ToastValue(
                    icon: Image(systemName: "info.circle"),
                    message: "订阅源已添加,未安装新插件"
                ))
            }
        }
    }

    @MainActor
    private func updateHomeRecommendationAvailability() {
        guard pluginAvailability.hasCheckedAvailability,
              pluginAvailability.hasAvailablePlugins else {
            homeRecommendationAvailability = .unconfirmed
            return
        }

        let supportsRecommendations = SandboxPluginCatalog
            .availablePlatforms(installedPluginIds: pluginAvailability.installedPluginIds)
            .contains { platform in
                PlatformCapability.supports(.homeFeed, for: platform.liveType)
            }

        if supportsRecommendations {
            homeRecommendationAvailability = .available
        } else {
            // iPad 的首页和收藏是两个独立栏目。没有推荐能力时仍保留首页栏目，
            // 但默认落到收藏，遵守“无推荐页时展示收藏”的产品规则。
            if AppConstants.Device.isIPad, selectedTab == .home {
                selectedTab = .favorites
            }
            homeRecommendationAvailability = .unavailable
        }
    }

    @MainActor
    private func selectRecommendations() {
        guard recommendationsAvailableForMenu else { return }
        selectedHomePluginId = ""
        homePagePreference = .recommendations
        selectedTab = .home
    }

    @MainActor
    private func selectFavorites() {
        homePagePreference = .favorites
        selectedTab = AppConstants.Device.isIPad ? .favorites : .home
    }

    @MainActor
    private func selectPlatform(_ option: HomePlatformOption) {
        selectedHomePluginId = option.pluginId
        homePagePreference = .recommendations
        selectedTab = .home
    }

    // MARK: - 云端一键安装进度

    private var cloudInstallProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                if let message = pluginSourceSyncService.installStatusMessage {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.white)
                }

                if pluginSourceManager.installTotalCount > 0 {
                    Text("\(pluginSourceManager.installCompletedCount)/\(pluginSourceManager.installTotalCount)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: pluginSourceSyncService.isInstalling)
    }

    // MARK: - iPad TabView (iOS 18+)

    @available(iOS 18.0, *)
    private var iPadTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house.fill", value: TabSelection.home) {
                HomeView(usesPersistedPlatformSelection: false)
            }

            Tab(value: TabSelection.favorites) {
                AdaptiveFavoriteView()
            } label: {
                Label {
                    Text("收藏")
                } icon: {
                    CloudSyncTabIcon(syncStatus: favoriteTabSyncStatus)
                }
            }

            TabSection(platformSectionTitle) {
                Tab(value: TabSelection.allPlatforms) {
                    AdaptivePlatformView()
                } label: {
                    Label {
                        Text("全部配置")
                    } icon: {
                        Image(systemName: "square.grid.2x2.fill")
                            .resizable()
                            .frame(width: 25, height: 25)
                    }
                }

                ForEach(platformViewModel.platformInfo) { platform in
                    Tab(value: TabSelection.platform(platform)) {
                        PlatformDetailTabContainer(platform: platform)
                    } label: {
                        Label {
                            Text(platform.title)
                        } icon: {
                            if let image = PlatformIconProvider.tabImage(for: platform.liveType) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 25, height: 25)
                            } else {
                                Image(systemName: "play.tv")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 25, height: 25)
                            }

                        }
                    }
                }
            }

            if pluginAvailability.hasAvailablePlugins {
                // iOS 26+ 支持 search role，iOS 18 需要普通 Tab
                if #available(iOS 26.0, *) {
                    Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                        AdaptiveSearchView()
                    }
                } else {
                    Tab(value: TabSelection.search) {
                        AdaptiveSearchView()
                    } label: {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
            }

            Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                SettingView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // MARK: - iPhone TabView (iOS 18+)

    @available(iOS 18.0, *)
    private var iPhoneTabView: some View {
        if #available(iOS 26.0, *) {
            return TabView(selection: $selectedTab) {
                if pluginAvailability.hasAvailablePlugins {
                    Tab(value: TabSelection.home) {
                        preferredHomePage
                    } label: {
                        Label {
                            Text(iPhoneHomeTabTitle)
                        } icon: {
                            iPhoneHomeTabIcon
                        }
                    }
                } else {
                    Tab("首页", systemImage: "house.fill", value: TabSelection.home) {
                        preferredHomePage
                    }
                }

                Tab("配置", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    AdaptivePlatformView()
                }

                if pluginAvailability.hasAvailablePlugins {
                    Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                        AdaptiveSearchView()
                    }
                }

                Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                    SettingView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
           return TabView(selection: $selectedTab) {
                if pluginAvailability.hasAvailablePlugins {
                    Tab(value: TabSelection.home) {
                        preferredHomePage
                    } label: {
                        Label {
                            Text(iPhoneHomeTabTitle)
                        } icon: {
                            iPhoneHomeTabIcon
                        }
                    }
                } else {
                    Tab("首页", systemImage: "house.fill", value: TabSelection.home) {
                        preferredHomePage
                    }
                }

                Tab("配置", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    AdaptivePlatformView()
                }

                if pluginAvailability.hasAvailablePlugins {
                    // iOS 18 不支持 search role
                    Tab(value: TabSelection.search) {
                        AdaptiveSearchView()
                    } label: {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }

                Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                    SettingView()
                }
            }
        }
    }

    // MARK: - iOS 17 兼容版本

    // iPad iOS 17 TabView
    private var iOS17iPadTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView(usesPersistedPlatformSelection: false)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(TabSelection.home)

            AdaptiveFavoriteView()
                .tabItem {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteTabSyncStatus)
                    }
                }
                .tag(TabSelection.favorites)

            AdaptivePlatformView()
                .tabItem {
                    Label("配置", systemImage: "square.grid.2x2.fill")
                }
                .tag(TabSelection.allPlatforms)

            if pluginAvailability.hasAvailablePlugins {
                AdaptiveSearchView()
                    .tabItem {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .tag(TabSelection.search)
            }

            SettingView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(TabSelection.settings)
        }
    }

    // iPhone iOS 17 TabView
    private var iOS17iPhoneTabView: some View {
        TabView(selection: $selectedTab) {
            if pluginAvailability.hasAvailablePlugins {
                preferredHomePage
                    .tabItem {
                        Label {
                            Text(iPhoneHomeTabTitle)
                        } icon: {
                            iPhoneHomeTabIcon
                        }
                    }
                    .tag(TabSelection.home)
            } else {
                preferredHomePage
                    .tabItem {
                        Label("首页", systemImage: "house.fill")
                    }
                    .tag(TabSelection.home)
            }

            AdaptivePlatformView()
                .tabItem {
                    Label("配置", systemImage: "square.grid.2x2.fill")
                }
                .tag(TabSelection.allPlatforms)

            if pluginAvailability.hasAvailablePlugins {
                AdaptiveSearchView()
                    .tabItem {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .tag(TabSelection.search)
            }

            SettingView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(TabSelection.settings)
        }
    }

}

private struct PlatformDetailTabContainer: View {
    let platform: Platformdescription
    @State private var showCapabilitySheet = false

    var body: some View {
        NavigationStack {
            PlatformDetailViewControllerWrapper()
                .environment(PlatformDetailViewModel(platform: platform))
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(platform.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCapabilitySheet = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
        }
        .sheet(isPresented: $showCapabilitySheet) {
            PlatformCapabilitySheet(liveType: platform.liveType)
        }
    }
}

#Preview {
    ContentView()
}
