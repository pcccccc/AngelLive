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
    private static let syncCooldown: TimeInterval = 180

    var body: some View {
        playerPresentation
            .searchable(text: $searchText, prompt: "搜索主播名或房间标题")
            .task {
                await loadIfNeeded()
            }
            .onDisappear {
                FavoriteView.lastLeaveTimestamp = Date()
            }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        if #available(iOS 18.0, *) {
            baseNavigation
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            // iOS 17: navigationDestination 必须在 NavigationStack 内部
            NavigationStack {
                FavoriteListViewControllerWrapper(
                    searchText: searchText,
                    navigationState: navigationState,
                    namespace: roomTransitionNamespace
                )
                // 安全区域处理 - 同时支持 TabBar 透视和大标题动画
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .navigationTitle("收藏")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(isPresented: playerPresentedBinding) {
                    playerDestination
                }
            }
        }
    }

    private var baseNavigation: some View {
        NavigationStack {
            FavoriteListViewControllerWrapper(
                searchText: searchText,
                navigationState: navigationState,
                namespace: roomTransitionNamespace
            )
            // 安全区域处理 - 同时支持 TabBar 透视和大标题动画
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { navigationState.showPlayer = $0 }
        )
    }

    @ViewBuilder
    private var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .toolbar(.hidden, for: .tabBar)
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if shouldSkipSyncAfterReturn() {
            return
        }
        if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }

    private func shouldSkipSyncAfterReturn() -> Bool {
        guard let lastLeave = FavoriteView.lastLeaveTimestamp else {
            return false
        }
        let timeSinceLeave = Date().timeIntervalSince(lastLeave)
        return timeSinceLeave < FavoriteView.syncCooldown
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
