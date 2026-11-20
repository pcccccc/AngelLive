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
    private let catalogRevision: UInt
    @State private var showClearAlert = false
    @State private var selectedType = 0
    @State private var progressStore: ShortDramaProgressStore
    @State private var shortDramaRoom: LiveModel?
    @State private var shortDramaReturnPreview: RoomPlayerReturnPreview?
    @State private var historyError: String?
    @State private var liveRooms: [LiveModel] = []
    @State private var classification: ShortDramaHistoryClassification?

    init(progressStore: ShortDramaProgressStore = .shared, catalogRevision: UInt = 0) {
        _progressStore = State(initialValue: progressStore)
        self.catalogRevision = catalogRevision
    }

    private func refreshHistory() {
        let rooms = historyModel.watchList
        let snapshot = progressStore.historyClassification(for: rooms)
        classification = snapshot
        progressStore.loadHistory(legacyRooms: rooms, classification: snapshot)
        liveRooms = progressStore.liveHistory(from: rooms, classification: snapshot)
        historyError = progressStore.historyWarning
    }

    private func refreshLiveRooms() {
        guard let classification else { return }
        liveRooms = progressStore.liveHistory(from: historyModel.watchList, classification: classification)
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

    @ViewBuilder
    private func playerDestination(_ animation: RoomEntryAnimation) -> some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms,
                entryRoomSource: .history
            )
                .roomEntryTransition(animation, sourceID: room.roomId, namespace: roomTransitionNamespace)
                .fullUITabBarHidden()
        }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        let baseView = HistoryListViewControllerWrapper(
            navigationState: navigationState,
            namespace: roomTransitionNamespace,
            progressStore: progressStore,
            liveRooms: liveRooms,
            historyEntries: progressStore.historyEntries,
            selectedType: $selectedType,
            onOpenShortDrama: { room in
                #if canImport(KSPlayer)
                shortDramaReturnPreview = navigationState.returnSource.capture()
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
                    .accessibilityIdentifier("history.clear")
                }
            }
        }
        .alert(selectedType == 0 ? "清空直播历史" : "清空短剧历史", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
                .accessibilityIdentifier("history.clear.cancel")
            Button("清空", role: .destructive) {
                clearCurrentHistory()
            }
            .accessibilityIdentifier("history.clear.confirm")
        } message: {
            Text(selectedType == 0 ? "确定要清空直播观看记录吗？" : "确定要清空短剧观看记录吗？续播进度仍会保留。")
        }

        .onAppear {
            refreshHistory()
        }
        .onChange(of: historyModel.watchList) { _, _ in refreshHistory() }
        .onChange(of: catalogRevision) { _, _ in refreshHistory() }
        .onChange(of: progressStore.historyRevision) { _, _ in refreshLiveRooms() }
        .onChange(of: progressStore.historyWarning) { _, warning in
            if let warning { historyError = warning }
        }
        .alert("历史记录", isPresented: historyErrorPresented) {
            Button("好的") { historyError = nil }
        } message: {
            Text(historyError ?? "")
        }
        #if canImport(KSPlayer)
        .fullScreenCover(item: $shortDramaRoom, onDismiss: { shortDramaReturnPreview = nil }) { room in
            ShortDramaPlayerView(room: room, presentsOverSource: true)
                .presentationBackground(.clear)
                .environment(\.fullUIRoomPlayerReturnPreview, shortDramaReturnPreview)
                .fullUIWindowContext()
                .fullUITabBarHidden()
                .fullUIArcLoadingStyle()
        }
        #endif

        baseView
            .roomPlayerPushDestination(navigationState) {
                playerDestination(.push)
            }
            .roomPlayerZoomCover(navigationState) {
                playerDestination(.zoom)
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
    let progressStore: ShortDramaProgressStore
    let liveRooms: [LiveModel]
    let historyEntries: [ShortDramaHistoryEntry]
    @Binding var selectedType: Int
    let onOpenShortDrama: (LiveModel) -> Void

    func makeUIViewController(context: Context) -> HistoryListViewController {
        let vc = HistoryListViewController(
            historyModel: historyModel,
            navigationState: navigationState,
            namespace: namespace,
            progressStore: progressStore,
            liveRooms: liveRooms,
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
        uiViewController.reloadData(liveRooms: liveRooms)
    }
}
