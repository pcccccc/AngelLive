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
        TabView(selection: $selectedTab) {
            FavoriteView()
                .tabItem {
                    Label("收藏", systemImage: "star.fill")
                }
                .tag(TabItem.favorite)

            PlatformView()
                .tabItem {
                    Label("平台", systemImage: "square.grid.2x2.fill")
                }
                .tag(TabItem.platform)

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(TabItem.search)

            SettingView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(TabItem.setting)
        }
        .preferredColorScheme(.dark)
    }
}

enum TabItem {
    case favorite
    case platform
    case search
    case setting
}

#Preview {
    ContentView()
}
