//
//  HistoryListView.swift
//  AngelLive
//
//  历史记录列表 - 使用 UICollectionView 实现
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct HistoryListView: View {
    @Environment(HistoryModel.self) private var historyModel
    @State private var showClearAlert = false

    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace

    var body: some View {
        HistoryListViewControllerWrapper(
            navigationState: navigationState,
            namespace: roomTransitionNamespace
        )
        .fullScreenCover(isPresented: playerPresentedBinding) {
            playerDestination
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !historyModel.watchList.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearAlert = true
                    } label: {
                        Text("清空")
                            .foregroundStyle(AppConstants.Colors.error)
                    }
                }
            }
        }
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                historyModel.clearAll()
            }
        } message: {
            Text("确定要清空所有观看记录吗？此操作不可恢复。")
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
}

// MARK: - UIKit Wrapper

struct HistoryListViewControllerWrapper: UIViewControllerRepresentable {
    @Environment(HistoryModel.self) private var historyModel
    @Environment(\.scenePhase) private var scenePhase
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID

    func makeUIViewController(context: Context) -> HistoryListViewController {
        return HistoryListViewController(
            historyModel: historyModel,
            navigationState: navigationState,
            namespace: namespace
        )
    }

    func updateUIViewController(_ uiViewController: HistoryListViewController, context: Context) {
        // 避免后台状态触发 UICollectionView 更新导致 iOS 18 崩溃
        guard scenePhase == .active else { return }
        uiViewController.reloadData()
    }
}
