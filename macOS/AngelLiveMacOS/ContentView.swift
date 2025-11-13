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
}

struct ContentView: View {
    @State private var selectedTab: TabSelection = .favorite

    // 创建全局 ViewModels
    @State private var platformViewModel = PlatformViewModel()
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var searchViewModel = SearchViewModel()
    @State private var platformDetailViewModels: [LiveType: PlatformDetailViewModel] = [:]

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

            TabSection("平台") {
                ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
                    Tab(value: TabSelection.platform(platform)) {
                        PlatformDetailTab(platform: platform, viewModels: $platformDetailViewModels)
                    } label: {
                        Label {
                            Text(platform.title)
                        } icon: {
                            Image(getImage(platform: platform))
                                .frame(width: 18, height: 18)
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
    @Binding var viewModels: [LiveType: PlatformDetailViewModel]

    var body: some View {
        NavigationStack {
            PlatformDetailView()
                .environment(viewModel)
                .navigationDestination(for: LiveModel.self) { room in
                    RoomPlayerView(room: room)
                }
        }
    }

    private var viewModel: PlatformDetailViewModel {
        if let existing = viewModels[platform.liveType] {
            return existing
        }
        let new = PlatformDetailViewModel(platform: platform)
        viewModels[platform.liveType] = new
        return new
    }
}

#Preview {
    ContentView()
}
