//
//  ContentView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

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
        Group {
            if AppConstants.Device.isIPad {
                iPadTabView
            } else {
                iPhoneTabView
            }
        }
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
    }

    // iPad 专用 TabView
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
                Tab("全部平台", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    PlatformView()
                }

                ForEach(platformViewModel.platformInfo) { platform in
                    Tab(platform.title, systemImage: "play.tv", value: TabSelection.platform(platform)) {
                        NavigationStack {
                            PlatformDetailViewControllerWrapper()
                                .environment(PlatformDetailViewModel(platform: platform))
                        }
                    }
                }
            }

            Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                SettingView()
            }

            Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // iPhone 专用 TabView
    private var iPhoneTabView: some View {
        if #available(iOS 26.0, *) {
            return TabView {
                Tab {
                    FavoriteView()
                } label: {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }
                
                Tab("平台", systemImage: "square.grid.2x2.fill") {
                    PlatformView()
                }
                
                Tab("设置", systemImage: "gearshape.fill") {
                    SettingView()
                }
                
                Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                    SearchView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
           return TabView {
                Tab {
                    FavoriteView()
                } label: {
                    Label {
                        Text("收藏")
                    } icon: {
                        CloudSyncTabIcon(syncStatus: favoriteViewModel.syncStatus)
                    }
                }
                
                Tab("平台", systemImage: "square.grid.2x2.fill") {
                    PlatformView()
                }
                
                Tab("设置", systemImage: "gearshape.fill") {
                    SettingView()
                }
                
                Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                    SearchView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
