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
    // 首次启动管理器
    @Environment(WelcomeManager.self) private var welcomeManager
    // 创建全局 ViewModels
    @State private var platformViewModel = PlatformViewModel()
    @State private var favoriteViewModel = AppFavoriteModel()
    @State private var searchViewModel = SearchViewModel()
    @State private var toastManager = ToastManager()

    var body: some View {
        @Bindable var manager = welcomeManager

        NavigationStack {
            TabView(selection: $selectedTab) {
                Tab(value: TabSelection.favorite) {
                    FavoriteView()
                } label: {
                    Label("收藏", systemImage: "heart.fill")
                }

                TabSection("平台") {
                    ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
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

                Tab("设置", systemImage: "gearshape.fill", value: TabSelection.settings) {
                    SettingView()
                }

                Tab("搜索", systemImage: "magnifyingglass", value: TabSelection.search, role: .search) {
                    SearchView()
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
        }
        .environment(platformViewModel)
        .environment(favoriteViewModel)
        .environment(searchViewModel)
        .environment(toastManager)
        .overlay(alignment: .top) {
            if let toast = toastManager.currentToast {
                ToastView(toast: toast)
                    .padding(.top, 16)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastManager.currentToast != nil)
            }
        }
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
