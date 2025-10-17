//
//  ContentView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: TabItem = .favorite

    var body: some View {
        TabView {
            Tab("收藏", systemImage: "star.fill") {
                FavoriteView()
                    .tag(TabItem.favorite)
            }
            Tab("平台", systemImage: "square.grid.2x2.fill") {
                PlatformView()
                    .tag(TabItem.platform)
            }
            Tab("设置", systemImage: "gearshape.fill") {
                SettingView()
                .tag(TabItem.setting)
            }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

enum TabItem: Hashable {
    case favorite
    case platform
    case search
    case setting
}

#Preview {
    ContentView()
}
