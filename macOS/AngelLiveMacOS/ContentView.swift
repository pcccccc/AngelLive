//
//  ContentView.swift
//  AngelLiveMacOS
//
//  Created by pc on 10/17/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore

// 定义 Tab 选择类型
enum TabSelection: Hashable {
    case favorite
    case allPlatforms
    case platform(Platformdescription)
    case history
    case settings
    case search
}

// 平台错误页「去登录」→ 跳转到设置 Tab 的通知（与 iOS 端同名同语义）
extension Notification.Name {
    static let switchToSettings = Notification.Name("switchToSettings")
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .favorite
    // 首次启动管理器
    @Environment(WelcomeManager.self) private var welcomeManager
    // 从环境获取全局 ViewModels
    @Environment(AppFavoriteModel.self) private var favoriteViewModel
    @Environment(ToastManager.self) private var toastManager
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    // 插件与壳 UI 服务
    @State private var pluginAvailability = PluginAvailabilityService()
    @State private var bookmarkService = StreamBookmarkService()
    @State private var pluginSourceManager = PluginSourceManager()
    // CloudKit 插件源同步
    @State private var pluginSourceSyncService = PluginSourceSyncService()
    @State private var showPluginSyncPrompt = false
    // 插件订阅 / 安装确认请求器
    @State private var consentService = PluginInstallConsentService()
    // 创建局部 ViewModels
    @State private var platformViewModel = PlatformViewModel()
    @State private var searchViewModel = SearchViewModel()

    var body: some View {
        @Bindable var manager = welcomeManager

        Group {
            if fullscreenPlayerManager.showFullscreenPlayer,
               let room = fullscreenPlayerManager.currentRoom {
                // 全屏播放器
                RoomPlayerView(room: room)
                    .background(Color.black)
            } else {
                // 正常内容
                NavigationStack {
                    TabView(selection: $selectedTab) {
                        Tab(value: TabSelection.favorite) {
                            if pluginAvailability.hasAvailablePlugins {
                                FavoriteView()
                            } else {
                                MacShellFavoriteView()
                            }
                        } label: {
                            Label("收藏", systemImage: "heart.fill")
                        }

                        TabSection("平台") {
                            if !pluginAvailability.hasAvailablePlugins {
                                Tab(value: TabSelection.allPlatforms) {
                                    MacShellConfigView()
                                } label: {
                                    Label("配置", systemImage: "square.grid.2x2.fill")
                                }
                            }

                            if pluginAvailability.hasAvailablePlugins {
                                ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
                                    Tab(value: TabSelection.platform(platform)) {
                                        PlatformDetailTab(platform: platform)
                                    } label: {
                                        Label {
                                            Text(platform.title)
                                        } icon: {
                                            if let icon = MacPlatformIconProvider.tabImage(for: platform.liveType) {
                                                Image(nsImage: icon)
                                            } else {
                                                Image(systemName: "puzzlepiece.extension")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if pluginAvailability.hasAvailablePlugins {
                            Tab(value: TabSelection.search) {
                                SearchView()
                            } label: {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                        }

                        Tab("历史记录", systemImage: "clock.arrow.circlepath", value: TabSelection.history) {
                            MacHistoryView()
                        }

                        Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                            SettingView()
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .background(SidebarWidthEnforcer(min: 180, ideal: 200, max: 260))
                    .navigationDestination(for: LiveModel.self) { room in
                        RoomPlayerView(room: room)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .switchToSettings)) { _ in
                        selectedTab = .settings
                    }
                    .sheet(isPresented: $manager.showWelcome) {
                        WelcomeView {
                            welcomeManager.completeWelcome()
                        }
                        .presentationSizing(.page.fitted(horizontal: true, vertical: true))
                    }
                }
            }
        }
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .environment(pluginAvailability)
        .environment(bookmarkService)
        .environment(pluginSourceManager)
        .environment(consentService)
        .environment(toastManager)
        .environment(fullscreenPlayerManager)
        .task {
            // 注入插件安装确认请求器
            pluginSourceManager.consentRequester = consentService

            // 启动时拉取 key 映射（后台静默，不阻塞 UI）
            Task { await PluginSourceKeyService.shared.fetchKeys() }
            await pluginAvailability.checkAvailability()
            platformViewModel.refreshPlatforms(installedPluginIds: pluginAvailability.installedPluginIds)

            // 自动检查插件更新（非阻塞，在 UI 就绪后后台运行）
            if pluginAvailability.hasAvailablePlugins && !pluginSourceManager.sourceURLs.isEmpty {
                await pluginSourceManager.refreshAvailableUpdates()
                let updatableIds = pluginAvailability.installedPluginIds.filter {
                    pluginSourceManager.hasUpdate(for: $0)
                }
                if !updatableIds.isEmpty {
                    toastManager.show(
                        icon: "arrow.triangle.2.circlepath",
                        message: "有 \(updatableIds.count) 个插件需要更新，正在更新..."
                    )
                    var successCount = 0
                    for id in updatableIds {
                        if await pluginSourceManager.updatePlugin(pluginId: id) {
                            successCount += 1
                        }
                    }
                    await pluginAvailability.refresh()
                    platformViewModel.refreshPlatforms(installedPluginIds: pluginAvailability.installedPluginIds)
                    if successCount > 0 {
                        toastManager.show(
                            icon: "checkmark.circle.fill",
                            message: "\(successCount) 个插件已更新完成",
                            type: .success
                        )
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
        .onChange(of: pluginAvailability.installedPluginIds) { oldIds, installedPluginIds in
            platformViewModel.refreshPlatforms(installedPluginIds: installedPluginIds)
            // 从无插件变为有插件时，主动触发收藏同步
            if oldIds.isEmpty && !installedPluginIds.isEmpty {
                Task {
                    await favoriteViewModel.syncWithActor()
                }
            }
            if installedPluginIds.isEmpty {
                if case .platform = selectedTab {
                    selectedTab = .allPlatforms
                } else if selectedTab == .search {
                    selectedTab = .favorite
                }
            } else if selectedTab == .allPlatforms,
                      let firstPlatform = platformViewModel.platformInfo.first {
                selectedTab = .platform(firstPlatform)
            }
        }
        .onChange(of: platformViewModel.platformInfo) { _, newPlatforms in
            // 平台列表刷新后,选中平台可能已不存在(被移除,或元数据变更致
            // Platformdescription 合成 Hashable 不匹配旧值)。此时 sidebarAdaptable
            // TabView 的 selection 指向无效 tab,会 fatal error "invalid selection value"。
            // 按稳定身份 pluginId 兜底,回退到恒存在的 .favorite。
            if case .platform(let selected) = selectedTab,
               !newPlatforms.contains(where: { $0.pluginId == selected.pluginId }) {
                selectedTab = .favorite
            }
        }
        .overlay(alignment: .top) {
            if let toast = toastManager.currentToast, !fullscreenPlayerManager.showFullscreenPlayer {
                ToastView(toast: toast)
                    .padding(.top, 16)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: toastManager.currentToast)
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

    // MARK: - Deep Link Handling

    @MainActor
    private func handleDeepLink(_ link: AngelLiveDeepLink) async {
        switch link {
        case .installSource(let input):
            toastManager.show(icon: "icloud.and.arrow.down", message: "正在添加订阅源...")
            let added = await pluginSourceManager.addSourceFromInput(input)
            guard !added.isEmpty else {
                let detail = pluginSourceManager.errorMessage ?? "无法识别的订阅源"
                toastManager.show(
                    icon: "exclamationmark.triangle.fill",
                    message: "添加失败:\(detail)",
                    type: .error
                )
                return
            }
            await pluginSourceManager.fetchAllSourceIndexes()
            let count = await pluginSourceManager.installAll()
            if count > 0 {
                await pluginAvailability.refresh()
                platformViewModel.refreshPlatforms(installedPluginIds: pluginAvailability.installedPluginIds)
                toastManager.show(
                    icon: "checkmark.circle.fill",
                    message: "已通过 URL 安装 \(count) 个插件",
                    type: .success
                )
            } else {
                toastManager.show(icon: "info.circle", message: "订阅源已添加,未安装新插件")
            }
        }
    }
}

struct PlatformDetailTab: View {
    let platform: Platformdescription
    @State private var viewModel: PlatformDetailViewModel

    init(platform: Platformdescription) {
        self.platform = platform
        _viewModel = State(initialValue: PlatformDetailViewModel(platform: platform))
    }

    var body: some View {
        PlatformDetailView()
            .environment(viewModel)
    }
}

#Preview {
    ContentView()
}

// MARK: - Sidebar Width Enforcer (TabView .sidebarAdaptable workaround)

/// 通过 AppKit 直接对窗口里的 NSSplitView 施加宽度约束。
/// 用于绕开 SwiftUI 对 TabView(.sidebarAdaptable) sidebar 宽度的内部限制。
private struct SidebarWidthEnforcer: NSViewRepresentable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.min = min
        view.ideal = ideal
        view.max = max
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? ProbeView else { return }
        probe.min = min
        probe.ideal = ideal
        probe.max = max
        probe.applySoon()
    }

    private final class ProbeView: NSView {
        var min: CGFloat = 180
        var ideal: CGFloat = 200
        var max: CGFloat = 260
        private var hasApplied = false
        private var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            if let window = self.window {
                installObservers(for: window)
            }
            applySoon()
        }

        deinit {
            removeObservers()
        }

        private func installObservers(for window: NSWindow) {
            observedWindow = window
            let nc = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willEnterFullScreenNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.willExitFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didResizeNotification
            ]
            for name in names {
                let token = nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.apply()
                }
                observers.append(token)
            }
        }

        private func removeObservers() {
            let nc = NotificationCenter.default
            for token in observers { nc.removeObserver(token) }
            observers.removeAll()
            observedWindow = nil
        }

        func applySoon() {
            // 多次重试,覆盖 SwiftUI 不同阶段的回写
            for delay in [0.0, 0.1, 0.3, 0.6, 1.0, 2.0, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.apply()
                }
            }
        }

        private func apply() {
            guard let window = self.window ?? observedWindow else { return }
            // 关掉 titlebar 下方分隔线(NSContainerConcentricGlassEffectView 的边缘高光治不了,接受它)
            window.titlebarSeparatorStyle = .none

            // 1) 优先尝试通过 NSSplitViewController 配置
            if let svc = findSplitVC(in: window),
               let sidebarItem = svc.splitViewItems.first {
                sidebarItem.minimumThickness = min
                sidebarItem.maximumThickness = max
                sidebarItem.canCollapse = false
                // 关闭每个 split item 自己的 toolbar 顶部分隔条
                for item in svc.splitViewItems {
                    item.titlebarSeparatorStyle = .none
                }
                if !hasApplied {
                    svc.splitView.setPosition(ideal, ofDividerAt: 0)
                    hasApplied = true
                }
                return
            }

            // 2) 找不到 controller 时,直接操作 NSSplitView
            guard let contentView = window.contentView,
                  let split = findSplitView(in: contentView),
                  let sidebar = split.arrangedSubviews.first else { return }

            // 直接给 sidebar 加一对宽度约束
            sidebar.translatesAutoresizingMaskIntoConstraints = false
            // 移除之前可能加过的同名约束
            sidebar.constraints
                .filter { $0.identifier == "SidebarWidthEnforcer.min" || $0.identifier == "SidebarWidthEnforcer.max" }
                .forEach { sidebar.removeConstraint($0) }

            let minC = sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: min)
            minC.identifier = "SidebarWidthEnforcer.min"
            minC.priority = .required
            minC.isActive = true

            let maxC = sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: max)
            maxC.identifier = "SidebarWidthEnforcer.max"
            maxC.priority = .required
            maxC.isActive = true

            if !hasApplied {
                split.setPosition(ideal, ofDividerAt: 0)
                hasApplied = true
            }
        }

        private func findSplitVC(in window: NSWindow) -> NSSplitViewController? {
            if let root = window.contentViewController, let vc = searchControllers(in: root) {
                return vc
            }
            return nil
        }

        private func searchControllers(in vc: NSViewController) -> NSSplitViewController? {
            if let svc = vc as? NSSplitViewController { return svc }
            for child in vc.children {
                if let found = searchControllers(in: child) { return found }
            }
            return nil
        }

        private func findSplitView(in view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView, split.arrangedSubviews.count >= 2 {
                return split
            }
            for sub in view.subviews {
                if let found = findSplitView(in: sub) { return found }
            }
            return nil
        }

    }
}
