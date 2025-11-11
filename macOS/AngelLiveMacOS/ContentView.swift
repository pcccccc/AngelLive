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
    case allPlatforms
    case platform(Platformdescription)
    case settings
    case search
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .favorite

    // 创建全局 ViewModels
    @State private var platformViewModel = PlatformViewModel()
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var searchViewModel = SearchViewModel()

    // 动态获取 TabSection 标题
    private var platformSectionTitle: String {
        if case .platform(let platform) = selectedTab {
            return platform.title
        }
        return "平台"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: TabSelection.favorite) {
                NavigationStack {
                    FavoriteView()
                        .navigationDestination(for: LiveModel.self) { room in
                            RoomPlayerView(room: room)
                        }
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }

            TabSection(platformSectionTitle) {
                // 在侧边栏中显示"全部平台"
                Tab("全部平台", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    NavigationStack {
                        PlatformView()
                            .navigationDestination(for: LiveModel.self) { room in
                                RoomPlayerView(room: room)
                            }
                    }
                }

                ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
                    Tab(platform.title, systemImage: "play.tv", value: TabSelection.platform(platform)) {
                        NavigationStack {
                            PlatformDetailView()
                                .environment(PlatformDetailViewModel(platform: platform))
                                .navigationDestination(for: LiveModel.self) { room in
                                    RoomPlayerView(room: room)
                                }
                        }
                    }
                }
            }

            Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                NavigationStack {
                    SettingView()
                }
            }

            Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                NavigationStack {
                    SearchView()
                        .navigationDestination(for: LiveModel.self) { room in
                            RoomPlayerView(room: room)
                        }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .onAppear {
            BiliBiliCookie.cookie = ""
        }
    }
}

#Preview {
    ContentView()
}

