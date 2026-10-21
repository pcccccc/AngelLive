//
//  HistoryListView.swift
//  AngelLive
//
//  历史记录列表 - 使用 UICollectionView 实现
//

import SwiftUI
import SharedAssets
import AngelLiveCore
import AngelLiveDependencies

struct HistoryListView: View {
    @Environment(HistoryModel.self) private var historyModel
    @State private var showClearAlert = false
    @State private var selectedType = 0
    @State private var progressStore = ShortDramaProgressStore.shared
    @State private var shortDramaRoom: LiveModel?
    @State private var historyError: String?

    private var liveRooms: [LiveModel] {
        historyModel.watchList.filter { !progressStore.isShortDramaHistory($0) }
    }

    private var hasCurrentHistory: Bool {
        selectedType == 0 ? !liveRooms.isEmpty : !progressStore.historyEntries.isEmpty
    }

    private func clearCurrentHistory() {
        if selectedType == 0 {
            historyModel.removeHistories(ids: Set(liveRooms.map(\.id)))
        } else {
            do { try progressStore.clearHistory() }
            catch { historyError = "清空短剧历史失败，请重试。" }
        }
    }

    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace

    var body: some View {
        playerPresentation
    }

    private var historyErrorPresented: Binding<Bool> {
        Binding(get: { historyError != nil }, set: { if !$0 { historyError = nil } })
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
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .fullUITabBarHidden()
        }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        let baseView = HistoryListViewControllerWrapper(
            navigationState: navigationState,
            namespace: roomTransitionNamespace,
            historyEntries: progressStore.historyEntries,
            selectedType: $selectedType,
            onOpenShortDrama: { room in
                #if canImport(KSPlayer)
                shortDramaRoom = room
                #else
                historyError = "当前播放器不支持短剧播放。"
                #endif
            }
        )
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasCurrentHistory {
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
        .alert(selectedType == 0 ? "清空直播历史" : "清空短剧历史", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                clearCurrentHistory()
            }
        } message: {
            Text(selectedType == 0 ? "确定要清空直播观看记录吗？" : "确定要清空短剧观看记录吗？续播进度仍会保留。")
        }

        .onAppear {
            progressStore.loadHistory(legacyRooms: historyModel.watchList)
            historyError = progressStore.historyWarning
        }
        .onChange(of: progressStore.historyWarning) { _, warning in
            if let warning { historyError = warning }
        }
        .alert("历史记录", isPresented: historyErrorPresented) {
            Button("好的") { historyError = nil }
        } message: {
            Text(historyError ?? "")
        }
        #if canImport(KSPlayer)
        .fullScreenCover(item: $shortDramaRoom) { room in
            ShortDramaPlayerView(room: room)
                .fullUITabBarHidden()
                .fullUIArcLoadingStyle()
        }
        #endif

        if #available(iOS 18.0, *) {
            baseView
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            baseView
                .navigationDestination(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        }
    }
}

// MARK: - UIKit Wrapper

struct HistoryListViewControllerWrapper: UIViewControllerRepresentable {
    @Environment(HistoryModel.self) private var historyModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentToast) private var presentToast
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID
    let historyEntries: [ShortDramaHistoryEntry]
    @Binding var selectedType: Int
    let onOpenShortDrama: (LiveModel) -> Void

    func makeUIViewController(context: Context) -> HistoryListViewController {
        let vc = HistoryListViewController(
            historyModel: historyModel,
            navigationState: navigationState,
            namespace: namespace,
            favoriteModel: favoriteModel
        )
        vc.toastPresenter = { presentToast($0) }
        vc.onSelectionChanged = { selectedType = $0 }
        vc.onOpenShortDrama = onOpenShortDrama
        return vc
    }

    func updateUIViewController(_ uiViewController: HistoryListViewController, context: Context) {
        uiViewController.toastPresenter = { presentToast($0) }
        uiViewController.onSelectionChanged = { selectedType = $0 }
        uiViewController.onOpenShortDrama = onOpenShortDrama
        // 避免后台状态触发 UICollectionView 更新导致 iOS 18 崩溃
        guard scenePhase == .active else { return }
        uiViewController.reloadData()
    }
}
