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
    let searchText: String
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID

    func makeUIViewController(context: Context) -> FavoriteListViewController {
        let vc = FavoriteListViewController(
            viewModel: viewModel,
            navigationState: navigationState,
            namespace: namespace
        )
        return vc
    }

    func updateUIViewController(_ uiViewController: FavoriteListViewController, context: Context) {
        uiViewController.updateSearchText(searchText)
        // 当 viewModel 数据变化时（如 isLoading、groupedRoomList 变化），需要刷新
        uiViewController.reloadData()
    }
}
