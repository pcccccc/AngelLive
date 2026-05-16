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
    private let navigationState: LiveRoomNavigationState?
    private let namespace: Namespace.ID?
    private weak var favoriteModel: AppFavoriteModel?
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
        // iOS UIScrollView 默认 delaysContentTouches=true 会让 SwiftUI Button 的 gesture 卡 150ms,
        // 在 UIHostingController-in-cell 这种场景下会导致 tap 经常被吞。macOS Catalyst 不存在这个机制,所以那边都正常。
        cv.delaysContentTouches = false
        cv.panGestureRecognizer.delaysTouchesBegan = false
        // 关键修复:内容不足时强制可垂直滚,锁定 gesture 优先级。
        // 否则当 contentSize.height <= bounds.height,JX 外层横向 pan 会把内层 tap 吞掉(场次少时点不动的根因)。
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private var errorHostingController: UIHostingController<ErrorView>?
    private var isLoadingMore = false
    private var lastKnownCollectionWidth: CGFloat = 0

    // MARK: - Initialization

    init(viewModel: PlatformDetailViewModel, mainCategoryIndex: Int, subCategoryIndex: Int, navigationState: LiveRoomNavigationState? = nil, namespace: Namespace.ID? = nil, favoriteModel: AppFavoriteModel? = nil) {
        self.viewModel = viewModel
        self.mainCategoryIndex = mainCategoryIndex
        self.subCategoryIndex = subCategoryIndex
        self.navigationState = navigationState
        self.namespace = namespace
        self.favoriteModel = favoriteModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSOOPPreviewSnapshotUpdate(_:)),
            name: .soopPreviewSnapshotDidUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSOOPAdultRoomFilterUpdate(_:)),
            name: .soopAdultRoomFilterDidUpdate,
            object: nil
        )
        loadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
            self?.collectionView.layoutIfNeeded()
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
        let cachedRooms = viewModel.roomListCache[cacheKey] ?? []
        rooms = viewModel.filteredRoomList(
            mainCategoryIndex: mainCategoryIndex,
            subCategoryIndex: subCategoryIndex
        )

        // 如果缓存中没有数据，则加载
        if cachedRooms.isEmpty {
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
        rooms = viewModel.filteredRoomList(
            mainCategoryIndex: mainCategoryIndex,
            subCategoryIndex: subCategoryIndex
        )

        // 检查是否有错误需要显示
        if let error = viewModel.roomError, rooms.isEmpty {
            showErrorView(error: error)
        } else {
            hideErrorView()
        }

        collectionView.reloadData()
        // reloadData 后立刻 layoutIfNeeded,把 cells 注册进 visibleCells,
        // 否则 cv 在内容不足 + JX 嵌套场景下可能直到下次 layout pass 才注册,didSelectItemAt 失效。
        collectionView.layoutIfNeeded()
    }

    @objc private func handleSOOPPreviewSnapshotUpdate(_ notification: Notification) {
        let cacheKey = "\(mainCategoryIndex)-\(subCategoryIndex)"
        guard notification.userInfo?["cacheKey"] as? String == cacheKey else { return }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        if visibleIndexPaths.isEmpty {
            collectionView.reloadData()
        } else {
            collectionView.reloadItems(at: visibleIndexPaths)
        }
    }

    @objc private func handleSOOPAdultRoomFilterUpdate(_ notification: Notification) {
        guard let source = notification.object as? PlatformDetailViewModel,
              source === viewModel else { return }
        if let notificationCacheKey = notification.userInfo?["cacheKey"] as? String {
            let cacheKey = "\(mainCategoryIndex)-\(subCategoryIndex)"
            guard notificationCacheKey == cacheKey else { return }
        }
        updateRooms()
    }

    // MARK: - Error Handling

    private func showErrorView(error: Error) {
        // 如果已经显示错误视图，先移除
        hideErrorView()

        let authTitle: String
        if error.isAuthRequired, let liveType = viewModel?.platform.liveType {
            let platformName = LiveParseTools.getLivePlatformName(liveType)
            authTitle = "加载失败-请登录\(platformName)账号"
        } else {
            authTitle = "加载失败"
        }

        let errorView = ErrorView(
            title: authTitle,
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showRetry: true,
            showLoginButton: error.isAuthRequired,
            showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
            onRetry: { [weak self] in
                self?.hideErrorView()
                self?.handleRefresh()
            },
            onLogin: error.isAuthRequired ? {
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
            } : nil
        )

        let hostingController = UIHostingController(rootView: errorView)
        hostingController.view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        errorHostingController = hostingController

        // 隐藏 collectionView
        collectionView.isHidden = true
    }

    private func hideErrorView() {
        guard let errorHostingController = errorHostingController else { return }

        errorHostingController.willMove(toParent: nil)
        errorHostingController.view.removeFromSuperview()
        errorHostingController.removeFromParent()
        self.errorHostingController = nil

        // 显示 collectionView
        collectionView.isHidden = false
    }
}

// MARK: - UICollectionViewDataSource

extension RoomListViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let currentRooms = rooms
        return currentRooms.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier, for: indexPath) as? LiveRoomCollectionViewCell else {
            return UICollectionViewCell()
        }

        // 使用局部快照避免数据竞争导致的崩溃
        let currentRooms = rooms
        guard indexPath.item < currentRooms.count else {
            return cell
        }
        let room = currentRooms[indexPath.item]
        if let navigationState, let namespace {
            cell.configure(with: room, navigationState: navigationState, namespace: namespace, liveCheckMode: .none)
        } else {
            cell.configure(with: room, liveCheckMode: .none)
        }
        cell.attachHostingController(to: self)

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension RoomListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // 只把滚动到的 SOOP 19+ 候选窗口交给 ViewModel 预加载;
        // ViewModel 会记住已检测/已截图的 roomId,避免刷新列表时重复拉流截图。
        if indexPath.item < rooms.count {
            viewModel?.preloadSOOPAdultPreviewSnapshots(
                around: rooms[indexPath.item],
                mainCategoryIndex: mainCategoryIndex,
                subCategoryIndex: subCategoryIndex
            )
        }

        // 加载更多逻辑
        let count = rooms.count
        if count > 0, indexPath.item == count - 1 {
            loadMore()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer { collectionView.deselectItem(at: indexPath, animated: true) }
        let currentRooms = rooms
        guard indexPath.item < currentRooms.count else { return }
        let room = currentRooms[indexPath.item]
        // mode = .none(房间列表):直接进入,不判断在播状态
        navigationState?.navigate(to: room)
    }

    /// 长按弹"收藏 / 取消收藏"菜单(UICollectionView 接管,因为 cell-based 路径下
    /// hostingView 关掉了 isUserInteractionEnabled,SwiftUI .contextMenu 收不到事件)。
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let favoriteModel else { return nil }
        let currentRooms = rooms
        guard indexPath.item < currentRooms.count else { return nil }
        let room = currentRooms[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let isFavorited = Self.isFavorited(room: room, in: favoriteModel)
            let action: UIAction
            if isFavorited {
                action = UIAction(
                    title: "取消收藏",
                    image: UIImage(systemName: "heart.slash.fill"),
                    attributes: .destructive
                ) { _ in
                    Task { @MainActor in
                        try? await favoriteModel.removeFavoriteRoom(room: room)
                    }
                }
            } else {
                action = UIAction(
                    title: "收藏",
                    image: UIImage(systemName: "heart.fill")
                ) { _ in
                    Task { @MainActor in
                        try? await favoriteModel.addFavorite(room: room)
                    }
                }
            }
            return UIMenu(title: "", children: [action])
        }
    }

    /// 与 LiveRoomCard.isFavorited 同源:优先按 (liveType, userId) 匹配,空 userId 退回 roomId。
    private static func isFavorited(room: LiveModel, in favoriteModel: AppFavoriteModel) -> Bool {
        favoriteModel.roomList.contains { item in
            if !room.userId.isEmpty, !item.userId.isEmpty {
                return item.liveType == room.liveType && item.userId == room.userId
            }
            return item.liveType == room.liveType && item.roomId == room.roomId
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

    /// 关键修复:JX 在 scrollView 模式下让 listVC.view 进入 page 后,不会主动触发 cv 的 layout closeloop。
    /// 表现:cells 已经 dequeue 进 subviews 且 frame 正确,但 cv.visibleCells = 0,
    /// 导致 didSelectItemAt 永远不派发(场次少时点不动的真凶)。
    /// 在 listDidAppear / listWillAppear 主动 layoutIfNeeded 把 visibleCells 注册起来即可。
    func listWillAppear() {
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
    }

    func listDidAppear() {
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
    }
}
