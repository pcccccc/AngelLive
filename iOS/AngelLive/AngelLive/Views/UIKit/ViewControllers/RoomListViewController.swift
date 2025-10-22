//
//  RoomListViewController.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import UIKit
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import JXSegmentedView

class RoomListViewController: UIViewController {

    // MARK: - Properties

    private weak var viewModel: PlatformDetailViewModel?
    private let mainCategoryIndex: Int
    private let subCategoryIndex: Int
    private var rooms: [LiveModel] = []

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        cv.delegate = self
        cv.dataSource = self
        cv.register(LiveRoomCollectionViewCell.self, forCellWithReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier)
        cv.refreshControl = refreshControl
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private var isLoadingMore = false
    private var lastKnownCollectionWidth: CGFloat = 0

    // MARK: - Initialization

    init(viewModel: PlatformDetailViewModel, mainCategoryIndex: Int, subCategoryIndex: Int) {
        self.viewModel = viewModel
        self.mainCategoryIndex = mainCategoryIndex
        self.subCategoryIndex = subCategoryIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let currentWidth = collectionView.bounds.width
        if abs(currentWidth - lastKnownCollectionWidth) > 1 {
            lastKnownCollectionWidth = currentWidth
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: { [weak self] _ in
            self?.collectionView.reloadData()
        })
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 15
        layout.minimumLineSpacing = 24
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return layout
    }

    private func calculateItemSize(for width: CGFloat) -> CGSize {
        guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return .zero
        }

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        var columns: CGFloat = isIPad ? 3 : 2
        let horizontalSpacing = flowLayout.minimumInteritemSpacing
        let insets = flowLayout.sectionInset

        let availableWidth = max(0, width - insets.left - insets.right)

        while columns > 1 {
            let totalSpacing = horizontalSpacing * (columns - 1)
            let remainingWidth = availableWidth - totalSpacing
            if remainingWidth > 0 {
                break
            }
            columns -= 1
        }

        columns = max(1, columns)

        let totalSpacing = horizontalSpacing * max(0, columns - 1)
        let itemWidth = (availableWidth - totalSpacing) / columns
        let normalizedItemWidth = max(0, itemWidth)

        guard normalizedItemWidth > 0 else {
            return .zero
        }

        let itemHeight = normalizedItemWidth / AppConstants.AspectRatio.card(width: normalizedItemWidth)

        return CGSize(width: normalizedItemWidth, height: itemHeight)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let viewModel = viewModel else { return }

        let cacheKey = "\(mainCategoryIndex)-\(subCategoryIndex)"
        rooms = viewModel.roomListCache[cacheKey] ?? []

        // 如果缓存中没有数据，则加载
        if rooms.isEmpty {
            Task { @MainActor in
                // 临时保存当前选择的索引
                let oldMainIndex = viewModel.selectedMainCategoryIndex
                let oldSubIndex = viewModel.selectedSubCategoryIndex

                // 设置索引以便 ViewModel 加载正确的数据
                viewModel.selectedMainCategoryIndex = mainCategoryIndex
                viewModel.selectedSubCategoryIndex = subCategoryIndex

                await viewModel.loadRoomList()

                // 恢复原来的索引
                viewModel.selectedMainCategoryIndex = oldMainIndex
                viewModel.selectedSubCategoryIndex = oldSubIndex

                // 更新数据
                updateRooms()
            }
        }
    }

    @objc private func handleRefresh() {
        guard let viewModel = viewModel else {
            refreshControl.endRefreshing()
            return
        }

        Task { @MainActor in
            let oldMainIndex = viewModel.selectedMainCategoryIndex
            let oldSubIndex = viewModel.selectedSubCategoryIndex

            viewModel.selectedMainCategoryIndex = mainCategoryIndex
            viewModel.selectedSubCategoryIndex = subCategoryIndex

            await viewModel.loadRoomList()

            viewModel.selectedMainCategoryIndex = oldMainIndex
            viewModel.selectedSubCategoryIndex = oldSubIndex

            updateRooms()
            refreshControl.endRefreshing()
        }
    }

    private func loadMore() {
        guard !isLoadingMore, let viewModel = viewModel else { return }

        isLoadingMore = true

        Task { @MainActor in
            let oldMainIndex = viewModel.selectedMainCategoryIndex
            let oldSubIndex = viewModel.selectedSubCategoryIndex

            viewModel.selectedMainCategoryIndex = mainCategoryIndex
            viewModel.selectedSubCategoryIndex = subCategoryIndex

            await viewModel.loadMore()

            viewModel.selectedMainCategoryIndex = oldMainIndex
            viewModel.selectedSubCategoryIndex = oldSubIndex

            updateRooms()
            isLoadingMore = false
        }
    }

    func updateRooms() {
        guard let viewModel = viewModel else { return }
        let cacheKey = "\(mainCategoryIndex)-\(subCategoryIndex)"
        rooms = viewModel.roomListCache[cacheKey] ?? []
        collectionView.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension RoomListViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return rooms.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier, for: indexPath) as? LiveRoomCollectionViewCell else {
            return UICollectionViewCell()
        }

        let room = rooms[indexPath.item]
        cell.configure(with: room)

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension RoomListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // 加载更多逻辑
        if indexPath.item == rooms.count - 1 {
            loadMore()
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension RoomListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return calculateItemSize(for: collectionView.bounds.width)
    }
}

extension RoomListViewController: JXSegmentedListContainerViewListDelegate {
    func listView() -> UIView {
        return view
    }
}
