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
    let onRoomSelected: (LiveModel) -> Void

    func makeUIViewController(context: Context) -> FavoriteListViewController {
        let vc = FavoriteListViewController(viewModel: viewModel)
        vc.onRoomSelected = onRoomSelected
        return vc
    }

    func updateUIViewController(_ uiViewController: FavoriteListViewController, context: Context) {
        uiViewController.updateSearchText(searchText)
        uiViewController.reloadData()
    }
}
