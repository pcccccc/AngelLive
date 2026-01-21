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
        return vc
    }

    func updateUIViewController(_ uiViewController: FavoriteListViewController, context: Context) {
        // 当应用在后台时跳过 UI 更新，避免 iOS 18 的 DiffableDataSource 崩溃
        // 这是 iOS 18 的已知问题：后台 UI 更新会触发 reconfigureItemsWithIdentifiers 崩溃
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

        let shouldReload = context.coordinator.lastListVersion != currentListVersion ||
            context.coordinator.lastSignature != currentSignature
        if shouldReload {
            // 当 viewModel 数据变化时（如 isLoading、groupedRoomList 变化），需要刷新
            uiViewController.reloadData()
            context.coordinator.lastListVersion = currentListVersion
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
