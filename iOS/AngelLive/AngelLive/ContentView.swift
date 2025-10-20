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
    @State private var platformViewModel = PlatformViewModel()

    // 检测是否为 iPad
    private var isIPad: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    // 动态获取 TabSection 标题
    private var platformSectionTitle: String {
        if case .platform(let platform) = selectedTab {
            return platform.title
        }
        return "平台"
    }

    var body: some View {
        if isIPad {
            iPadTabView
        } else {
            iPhoneTabView
        }
    }

    // iPad 专用 TabView
    private var iPadTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("收藏", systemImage: "star.fill", value: TabSelection.favorite) {
                FavoriteView()
            }

            TabSection(platformSectionTitle) {
                // 在侧边栏中显示"全部平台"
                Tab("全部平台", systemImage: "square.grid.2x2.fill", value: TabSelection.allPlatforms) {
                    PlatformView()
                }

                ForEach(platformViewModel.platformInfo) { platform in
                    Tab(platform.title, systemImage: "play.tv", value: TabSelection.platform(platform)) {
                        PlatformDetailView(platform: platform)
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
        TabView {
            Tab("收藏", systemImage: "star.fill") {
                FavoriteView()
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
    }
}

#Preview {
    ContentView()
}
