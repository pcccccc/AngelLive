//
//  HistoryContentListViewController.swift
//  AngelLive
//
//  历史记录列表 UICollectionView 实现
//

import UIKit
import SwiftUI
import SharedAssets
import AngelLiveCore
import AngelLiveDependencies
import JXSegmentedView


/// Uses the same category strip and interactive paging container as the platform room list.
final class HistoryListViewController: UIViewController {
    private let historyModel: HistoryModel
    private let navigationState: LiveRoomNavigationState
    private let namespace: Namespace.ID
    private weak var favoriteModel: AppFavoriteModel?
    private let dataSource = JXSegmentedTitleDataSource()
    private let segmentedView = JXSegmentedView()
    private lazy var listContainer = JXSegmentedListContainerView(dataSource: self)
    private var pages: [Int: HistoryContentListViewController] = [:]
    var onSelectionChanged: ((Int) -> Void)?
    var onOpenShortDrama: ((LiveModel) -> Void)?
    var toastPresenter: ((ToastValue) -> Void)? {
        didSet { pages.values.forEach { $0.toastPresenter = toastPresenter } }
    }

    init(historyModel: HistoryModel, navigationState: LiveRoomNavigationState,
         namespace: Namespace.ID, favoriteModel: AppFavoriteModel? = nil) {
        self.historyModel = historyModel
        self.navigationState = navigationState
        self.namespace = namespace
        self.favoriteModel = favoriteModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        FullUIMainCategoryStyle.configure(segmentedView, dataSource: dataSource)
        dataSource.titles = ["直播", "短剧"]
        segmentedView.delegate = self
        segmentedView.listContainer = listContainer
        segmentedView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedView)
        view.addSubview(listContainer)
        NSLayoutConstraint.activate([
            segmentedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            segmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedView.heightAnchor.constraint(equalToConstant: FullUIMainCategoryStyle.height),
            listContainer.topAnchor.constraint(equalTo: segmentedView.bottomAnchor),
            listContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedView.reloadData()
        listContainer.reloadData()
    }

    func reloadData() { pages.values.forEach { $0.reloadData() } }
}

extension HistoryListViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        pages.values.forEach { $0.cancelPendingNavigation() }
        onSelectionChanged?(index)
    }
}

extension HistoryListViewController: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int { 2 }

    func listContainerView(_ listContainerView: JXSegmentedListContainerView,
                           initListAt index: Int) -> JXSegmentedListContainerViewListDelegate {
        let page = HistoryContentListViewController(
            historyModel: historyModel, navigationState: navigationState,
            namespace: namespace, favoriteModel: favoriteModel, isShortDrama: index == 1
        )
        page.toastPresenter = toastPresenter
        page.onOpenShortDrama = { [weak self] room in self?.onOpenShortDrama?(room) }
        pages[index] = page
        return page
    }
}

final class HistoryContentListViewController: UIViewController {

    // MARK: - Properties

    private var historyModel: HistoryModel
    private let isShortDrama: Bool
    private let progressStore = ShortDramaProgressStore.shared
    private var liveCheckTask: Task<Void, Never>?
    private var liveCheckToken = UUID()
    var onOpenShortDrama: ((LiveModel) -> Void)?

    private var liveRooms: [LiveModel] {
        historyModel.watchList.filter { !progressStore.isShortDramaHistory($0) }
    }

    private var itemCount: Int { isShortDrama ? progressStore.historyEntries.count : liveRooms.count }
    private let navigationState: LiveRoomNavigationState
    private let namespace: Namespace.ID
    private weak var favoriteModel: AppFavoriteModel?
    private var lastKnownCollectionWidth: CGFloat = 0
    private var lastKnownHorizontalSizeClass: UIUserInterfaceSizeClass?

    private var effectiveCollectionWidth: CGFloat {
        max(0, collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right)
    }
    /// 由 SwiftUI wrapper 注入,用来弹 swiftui-toasts 的 toast。
    var toastPresenter: ((ToastValue) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        FullUINavigationStyle.configure(cv)
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(LiveRoomCollectionViewCell.self, forCellWithReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier)
        cv.translatesAutoresizingMaskIntoConstraints = false
        // 见 RoomListViewController:同样的 SwiftUI Button 卡 tap 修复(iOS 专属,macOS 不需要)
        cv.delaysContentTouches = false
        cv.panGestureRecognizer.delaysTouchesBegan = false
        cv.alwaysBounceVertical = true
        return cv
    }()

    private var emptyHostingController: UIHostingController<AnyView>?

    // MARK: - Initialization

    init(historyModel: HistoryModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID, favoriteModel: AppFavoriteModel? = nil, isShortDrama: Bool) {
        self.historyModel = historyModel
        self.isShortDrama = isShortDrama
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
        updateViewState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelPendingNavigation()
    }

    func cancelPendingNavigation() {
        liveCheckToken = UUID()
        liveCheckTask?.cancel()
        liveCheckTask = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let currentWidth = effectiveCollectionWidth
        let currentHorizontalSizeClass = traitCollection.horizontalSizeClass
        if abs(currentWidth - lastKnownCollectionWidth) > 1 || currentHorizontalSizeClass != lastKnownHorizontalSizeClass {
            lastKnownCollectionWidth = currentWidth
            lastKnownHorizontalSizeClass = currentHorizontalSizeClass
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

        var columns: CGFloat = traitCollection.horizontalSizeClass == .regular ? 3 : 2
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

    // MARK: - Data

    func reloadData() {
        updateViewState()
    }

    private func updateViewState() {
        hideAllStateViews()

        if itemCount == 0 {
            showEmptyView()
        } else {
            collectionView.isHidden = false
            collectionView.reloadData()
        }
    }

    // MARK: - State Views

    private func hideAllStateViews() {
        emptyHostingController?.view.removeFromSuperview()
        emptyHostingController?.removeFromParent()
        emptyHostingController = nil

        collectionView.isHidden = true
    }

    private func showEmptyView() {
        let emptyView = AnyView(
            ErrorView.empty(
                title: "暂无观看记录",
                message: isShortDrama ? "开始观看短剧后，最近播放的剧集和进度会显示在这里。" : "开始观看直播后，最近打开的内容会显示在这里。",
                symbolName: "clock.badge.questionmark",
                tint: .orange
            )
        )

        let hostingController = UIHostingController(rootView: AnyView(emptyView.fullUIArcLoadingStyle()))
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
        emptyHostingController = hostingController
    }

    /// 收藏/取消收藏失败时通过 SwiftUI wrapper 注入的 toast 通道反馈,避免静默失败。
    @MainActor
    fileprivate func presentFavoriteFailureToast(title: String, error: Error) {
        let detail = FavoriteService.formatErrorCode(error: error)
        toastPresenter?(ToastValue(
            icon: Image(systemName: "xmark.circle.fill"),
            message: "\(title):\(detail)"
        ))
        Logger.warning("\(title): \(error)", category: .general)
    }
}

// MARK: - UICollectionViewDataSource

extension HistoryContentListViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return itemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier, for: indexPath) as? LiveRoomCollectionViewCell else {
            return UICollectionViewCell()
        }

        guard indexPath.item < itemCount, let favoriteModel else { return cell }
        if isShortDrama {
            let entry = progressStore.historyEntries[indexPath.item]
            cell.configure(with: entry.historyDisplayRoom, favoriteModel: favoriteModel,
                           navigationState: navigationState, namespace: namespace,
                           subtitle: entry.historySubtitle)
        } else {
            let room = liveRooms[indexPath.item]
            cell.configure(with: room, favoriteModel: favoriteModel, navigationState: navigationState,
                           namespace: namespace, liveCheckMode: .remote, onDelete: { [weak self] in
                self?.historyModel.removeHistories(ids: [room.id])
                self?.updateViewState()
            }, showsCoverBadge: true)
        }
        cell.attachHostingController(to: self)

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension HistoryContentListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer { collectionView.deselectItem(at: indexPath, animated: true) }
        if isShortDrama {
            guard indexPath.item < progressStore.historyEntries.count else { return }
            let entry = progressStore.historyEntries[indexPath.item]
            guard let room = entry.room else {
                let alert = UIAlertController(title: "暂时无法播放", message: "此短剧的插件尚未安装或不可用。安装对应插件后可继续观看，观看进度仍会保留。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好的", style: .default))
                present(alert, animated: true)
                return
            }
            onOpenShortDrama?(room)
            return
        }
        let watchList = liveRooms
        guard indexPath.item < watchList.count else { return }
        let room = watchList[indexPath.item]
        // mode = .remote:异步请求 API 查询直播状态
        cancelPendingNavigation()
        let token = liveCheckToken
        liveCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let state = try await ApiManager.getCurrentRoomLiveState(
                    roomId: room.roomId,
                    userId: room.userId,
                    liveType: room.liveType
                )
                guard !Task.isCancelled, self.liveCheckToken == token,
                      self.viewIfLoaded?.window != nil else { return }
                if state == .live {
                    self.navigationState.navigate(to: room)
                } else {
                    let alert = UIAlertController(title: "主播已下播", message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好的", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                guard !Task.isCancelled, self.liveCheckToken == token,
                      self.viewIfLoaded?.window != nil else { return }
                // 查询失败仍放行,让播放页自行处理
                self.navigationState.navigate(to: room)
            }
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }

    /// 长按弹"收藏 / 取消收藏 + 删除记录"菜单(UICollectionView 接管,因为 cell-based 路径下
    /// hostingView 关掉了 isUserInteractionEnabled,SwiftUI .contextMenu 收不到事件)。
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        if isShortDrama {
            guard indexPath.item < progressStore.historyEntries.count else { return nil }
            let entry = progressStore.historyEntries[indexPath.item]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [UIAction(title: "删除记录", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    guard let self else { return }
                    do {
                        try self.progressStore.removeHistory(for: entry.key)
                        self.updateViewState()
                    } catch {
                        self.toastPresenter?(ToastValue(icon: Image(systemName: "xmark.circle.fill"), message: "删除记录失败，请重试"))
                    }
                }])
            }
        }
        let watchList = liveRooms
        guard indexPath.item < watchList.count else { return nil }
        let room = watchList[indexPath.item]
        let favoriteModel = self.favoriteModel
        let historyModel = self.historyModel

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            if let favoriteModel {
                let isFavorited = Self.isFavorited(room: room, in: favoriteModel)
                if isFavorited {
                    actions.append(UIAction(
                        title: "取消收藏",
                        image: UIImage(systemName: "heart.slash.fill"),
                        attributes: .destructive
                    ) { [weak self] _ in
                        let toastPresenter = self?.toastPresenter
                        Task { @MainActor in
                            do {
                                try await favoriteModel.removeFavoriteRoom(room: room)
                                toastPresenter?(ToastValue(
                                    icon: Image(systemName: "heart.slash.fill"),
                                    message: "已取消收藏"
                                ))
                            } catch {
                                self?.presentFavoriteFailureToast(title: "取消收藏失败", error: error)
                            }
                        }
                    })
                } else {
                    actions.append(UIAction(
                        title: "收藏",
                        image: UIImage(systemName: "heart.fill")
                    ) { [weak self] _ in
                        let toastPresenter = self?.toastPresenter
                        Task { @MainActor in
                            do {
                                try await favoriteModel.addFavorite(room: room)
                                toastPresenter?(ToastValue(
                                    icon: Image(systemName: "heart.fill"),
                                    message: "收藏成功"
                                ))
                            } catch {
                                self?.presentFavoriteFailureToast(title: "收藏失败", error: error)
                            }
                        }
                    })
                }
            }

            actions.append(UIAction(
                title: "删除记录",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                Task { @MainActor in
                    historyModel.removeHistories(ids: [room.id])
                    self?.updateViewState()
                }
            })

            return UIMenu(title: "", children: actions)
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

extension HistoryContentListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return calculateItemSize(for: effectiveCollectionWidth)
    }
}


extension HistoryContentListViewController: JXSegmentedListContainerViewListDelegate {
    func listView() -> UIView { view }
    func listWillDisappear() { cancelPendingNavigation() }
}


private extension ShortDramaHistoryEntry {
    var historyDisplayRoom: LiveModel {
        room ?? LiveModel(userName: "", roomTitle: title, roomCover: coverURL ?? "", userHeadImg: "",
                          liveType: .placeholder, liveState: nil, userId: "", roomId: key.roomID,
                          liveWatchedCount: nil)
    }

    var historySubtitle: String {
        let episode = episodeNumber.map { "第 \($0) 集" } ?? episodeTitle ?? "最近观看"
        if completed { return "\(episode) · 已看完" }
        let minutes = String(format: "%.0f", floor(position / 60))
        let seconds = String(format: "%02.0f", floor(position.truncatingRemainder(dividingBy: 60)))
        return "\(episode) · \(minutes):\(seconds)"
    }
}
