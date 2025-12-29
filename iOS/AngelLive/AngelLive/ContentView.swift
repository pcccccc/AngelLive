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
    case favorite
    case allPlatforms
    case platform(Platformdescription)
    case settings
    case search
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .favorite
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // 首次启动管理器
    @Environment(WelcomeManager.self) private var welcomeManager

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
        return "平台"
    }

    var body: some View {
        @Bindable var manager = welcomeManager

        Group {
            if #available(iOS 18.0, *) {
                if AppConstants.Device.isIPad {
                    iPadTabView
                } else {
                    iPhoneTabView
                }
            } else {
                // iOS 17 兼容版本
                if AppConstants.Device.isIPad {
                    iOS17iPadTabView
                } else {
                    iOS17iPhoneTabView
                }
            }
        }
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .environment(historyViewModel)
        .onChange(of: selectedTab) { _, newValue in
            hapticFeedback.selectionChanged()
            if case .platform(let platform) = newValue, platform.liveType == .youtube {
                Task { @MainActor in
                    searchViewModel.searchTypeIndex = 2
                    selectedTab = .search
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToYouTubeSearch)) { _ in
            selectedTab = .search
            searchViewModel.searchTypeIndex = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettings)) { _ in
            selectedTab = .settings
        }
        .sheet(isPresented: $manager.showWelcome) {
            WelcomeView {
                welcomeManager.completeWelcome()
            }
            .modifier(WelcomePresentationModifier())
        }
    }

    // iPad 专用 TabView (iOS 18+)
    @available(iOS 18.0, *)
    private var iPadTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(value: TabSelection.favorite) {
                FavoriteView()
            } label: {
                Label {
                    Text("收藏")
                } icon: {
                    CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                }
            }

            TabSection(platformSectionTitle) {
                // 在侧边栏中显示"全部平台"
                Tab(value: TabSelection.allPlatforms) {
                    PlatformView()
                } label: {
                    Label {
                        Text("全部平台")
                    } icon: {
                        Image(systemName: "square.grid.2x2.fill")
                            .resizable()
                            .frame(width: 25, height: 25)
                    }
                }

                ForEach(platformViewModel.platformInfo) { platform in
                    Tab(value: TabSelection.platform(platform)) {
                        NavigationStack {
                            PlatformDetailViewControllerWrapper()
                                .environment(PlatformDetailViewModel(platform: platform))
                        }
                    } label: {
                        Label {
                            Text(platform.title)
                        } icon: {
                            Image(getImage(platform: platform))
                                .resizable()
                                .frame(width: 25, height: 25)
                                
                        }
                    }
                }
            }

            Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                SettingView()
            }

            // iOS 26+ 支持 search role，iOS 18 需要普通 Tab
            if #available(iOS 26.0, *) {
                Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                    SearchView()
                }
            } else {
                Tab(value: TabSelection.search) {
                    SearchView()
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // iPhone 专用 TabView (iOS 18+)
    @available(iOS 18.0, *)
    private var iPhoneTabView: some View {
        if #available(iOS 26.0, *) {
            return TabView(selection: $selectedTab) {
                Tab(value: TabSelection.favorite) {
                    FavoriteView()
                } label: {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }

                Tab("平台", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    PlatformView()
                }

                Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                    SettingView()
                }

                Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                    SearchView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
           return TabView(selection: $selectedTab) {
                Tab(value: TabSelection.favorite) {
                    FavoriteView()
                } label: {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }

                Tab("平台", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    PlatformView()
                }

                Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                    SettingView()
                }

                // iOS 18 不支持 search role
                Tab(value: TabSelection.search) {
                    SearchView()
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
        }
    }

    // MARK: - iOS 17 兼容版本

    // iPad iOS 17 TabView
    private var iOS17iPadTabView: some View {
        TabView(selection: $selectedTab) {
            FavoriteView()
                .tabItem {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }
                .tag(TabSelection.favorite)

            PlatformView()
                .tabItem {
                    Label("平台", systemImage: "square.grid.2x2.fill")
                }
                .tag(TabSelection.allPlatforms)

            SettingView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(TabSelection.settings)

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(TabSelection.search)
        }
    }

    // iPhone iOS 17 TabView
    private var iOS17iPhoneTabView: some View {
        TabView(selection: $selectedTab) {
            FavoriteView()
                .tabItem {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }
                .tag(TabSelection.favorite)

            PlatformView()
                .tabItem {
                    Label("平台", systemImage: "square.grid.2x2.fill")
                }
                .tag(TabSelection.allPlatforms)

            SettingView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(TabSelection.settings)

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(TabSelection.search)
        }
    }

    func getImage(platform: Platformdescription) -> String {
        switch platform.liveType {
            case .bilibili:
                return "pad_live_card_bili"
            case .douyu:
                return "pad_live_card_douyu"
            case .huya:
                return "pad_live_card_huya"
            case .douyin:
                return "pad_live_card_douyin"
            case .yy:
                return "pad_live_card_yy"
            case .cc:
                return "pad_live_card_cc"
            case .ks:
                return "pad_live_card_ks"
            case .youtube:
                return "pad_live_card_youtube"
        }
    }
}

#Preview {
    ContentView()
}
