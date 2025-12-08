//
//  FavoriteView.swift
//  AngelLive
//
//  收藏列表 - 使用 UICollectionView 实现
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    @State private var searchText = ""
    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace
    private static var lastLeaveTimestamp: Date?

    var body: some View {
        NavigationStack {
            FavoriteListViewControllerWrapper(
                searchText: searchText,
                navigationState: navigationState,
                namespace: roomTransitionNamespace
            )
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: Binding(
                get: { navigationState.showPlayer },
                set: { navigationState.showPlayer = $0 }
            )) {
                if let room = navigationState.currentRoom {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                        .navigationTransition(.zoom(sourceID: room.roomId, in: roomTransitionNamespace))
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索主播名或房间标题")
        .task {
            await loadIfNeeded()
        }
        .onDisappear {
            FavoriteView.lastLeaveTimestamp = Date()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
