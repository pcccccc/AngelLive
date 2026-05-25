//
//  FavoriteListViewControllerWrapper.swift
//  AngelLive
//
//  收藏列表 UICollectionView 的 SwiftUI Wrapper
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct FavoriteListViewControllerWrapper: UIViewControllerRepresentable {
    @Environment(AppFavoriteModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentToast) private var presentToast
    let searchText: String
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID

    /// 触发 SwiftUI 感知 viewModel 变化的计算属性
    private var dataVersion: Int {
        viewModel.listVersion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> FavoriteListViewController {
        let vc = FavoriteListViewController(
            viewModel: viewModel,
            navigationState: navigationState,
            namespace: namespace
        )
        vc.toastPresenter = { presentToast($0) }
        return vc
    }

    func updateUIViewController(_ uiViewController: FavoriteListViewController, context: Context) {
        // presentToast 的 PresentToastAction 是值类型,刷新时同步最新引用
        uiViewController.toastPresenter = { presentToast($0) }
        // 当应用在后台时跳过 UI 更新，避免 iOS 18 的 DiffableDataSource 崩溃
        guard scenePhase == .active else { return }

        // 使用 dataVersion 确保 SwiftUI 感知到数据变化
        _ = dataVersion

        let currentSignature = ViewStateSignature(
            isLoading: viewModel.isLoading,
            cloudReturnError: viewModel.cloudReturnError,
            cloudKitReady: viewModel.cloudKitReady,
            cloudKitStateString: viewModel.cloudKitStateString,
            syncStatusID: syncStatusID(viewModel.syncStatus)
        )
        let currentListVersion = viewModel.listVersion
        let searchChanged = searchText != context.coordinator.lastSearchText

        if searchChanged {
            uiViewController.updateSearchText(searchText)
            context.coordinator.lastSearchText = searchText
            context.coordinator.lastListVersion = currentListVersion
            context.coordinator.lastSignature = currentSignature
            return
        }

        let dataChanged = context.coordinator.lastListVersion != currentListVersion
        let stateChanged = context.coordinator.lastSignature != currentSignature

        if dataChanged {
            // 数据变了 → 重刷 collection
            uiViewController.reloadData()
            context.coordinator.lastListVersion = currentListVersion
            context.coordinator.lastSignature = currentSignature
        } else if stateChanged {
            // 仅状态变了（syncStatus/isLoading/error）→ 轻量更新状态视图，不动 collection
            uiViewController.updateStateViewsOnly()
            context.coordinator.lastSignature = currentSignature
        }
    }
}

struct ViewStateSignature: Equatable {
    let isLoading: Bool
    let cloudReturnError: Bool
    let cloudKitReady: Bool
    let cloudKitStateString: String
    let syncStatusID: Int
}

func syncStatusID(_ status: CloudSyncStatus) -> Int {
    switch status {
    case .syncing:
        return 0
    case .success:
        return 1
    case .error:
        return 2
    case .notLoggedIn:
        return 3
    }
}

extension FavoriteListViewControllerWrapper {
    final class Coordinator {
        var lastSearchText: String = ""
        var lastListVersion: Int = -1
        var lastSignature: ViewStateSignature?
    }
}
