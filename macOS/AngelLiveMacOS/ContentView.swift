//
//  ContentView.swift
//  AngelLiveMacOS
//
//  Created by pc on 10/17/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import LiveParse

// 定义 Tab 选择类型
enum TabSelection: Hashable {
    case favorite
    case platform(Platformdescription)
    case settings
    case search
    case youtube  // YouTube 特殊处理，跳转到搜索页面并选中 YouTube
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .favorite
    // 首次启动管理器
    @Environment(WelcomeManager.self) private var welcomeManager
    // 从环境获取全局 ViewModels
    @Environment(AppFavoriteModel.self) private var favoriteViewModel
    @Environment(ToastManager.self) private var toastManager
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
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
                            FavoriteView()
                        } label: {
                            Label("收藏", systemImage: "heart.fill")
                        }

                        TabSection("平台") {
                            ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
                                // YouTube 特殊处理：跳转到搜索页面并选中 YouTube
                                if platform.liveType == .youtube {
                                    Tab(value: TabSelection.youtube) {
                                        SearchView()
                                    } label: {
                                        Label {
                                            Text(platform.title)
                                        } icon: {
                                            Image(getImage(platform: platform))
                                                .frame(width: 25, height: 25)
                                        }
                                    }
                                } else {
                                    Tab(value: TabSelection.platform(platform)) {
                                        PlatformDetailTab(platform: platform)
                                    } label: {
                                        Label {
                                            Text(platform.title)
                                        } icon: {
                                            Image(getImage(platform: platform))
                                                .frame(width: 25, height: 25)
                                        }
                                    }
                                }
                            }
                        }

                        // macOS 26+ 支持 search role，macOS 15 需要普通 Tab
                        if #available(macOS 26.0, *) {
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

                        Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                            SettingView()
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .navigationDestination(for: LiveModel.self) { room in
                        RoomPlayerView(room: room)
                    }
                    .sheet(isPresented: $manager.showWelcome) {
                        WelcomeView {
                            welcomeManager.completeWelcome()
                        }
                        .presentationSizing(.page.fitted(horizontal: true, vertical: false))
                    }
                    .onChange(of: selectedTab) { _, newValue in
                        // 点击 YouTube tab 时，自动选中 YouTube 搜索类型
                        if newValue == .youtube {
                            searchViewModel.searchTypeIndex = 2
                        }
                    }
                }
            }
        }
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .environment(toastManager)
        .environment(fullscreenPlayerManager)
        .overlay(alignment: .top) {
            if let toast = toastManager.currentToast, !fullscreenPlayerManager.showFullscreenPlayer {
                ToastView(toast: toast)
                    .padding(.top, 16)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: toastManager.currentToast)
    }
    
    func getImage(platform: Platformdescription) -> String {
        switch platform.liveType {
            case .bilibili:
                return "mini_live_card_bili"
            case .douyu:
                return "mini_live_card_douyu"
            case .huya:
                return "mini_live_card_huya"
            case .douyin:
                return "mini_live_card_douyin"
            case .yy:
                return "mini_live_card_yy"
            case .cc:
                return "mini_live_card_cc"
            case .ks:
                return "mini_live_card_ks"
            case .youtube:
                return "mini_live_card_youtube"
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
