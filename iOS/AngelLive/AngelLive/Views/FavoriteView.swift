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
    @State private var selectedRoom: LiveModel?
    @State private var showPlayer = false
    private static var lastLeaveTimestamp: Date?

    var body: some View {
        NavigationStack {
            FavoriteListViewControllerWrapper(
                searchText: searchText,
                onRoomSelected: { room in
                    selectedRoom = room
                    showPlayer = true
                }
            )
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showPlayer) {
                if let room = selectedRoom {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
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
