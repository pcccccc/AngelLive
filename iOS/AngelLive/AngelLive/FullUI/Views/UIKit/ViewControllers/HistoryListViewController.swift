//
//  HistoryListViewController.swift
//  AngelLive
//
//  历史记录列表 UICollectionView 实现
//

import UIKit
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

class HistoryListViewController: UIViewController {

    // MARK: - Properties

    private var historyModel: HistoryModel
    private let navigationState: LiveRoomNavigationState
    private let namespace: Namespace.ID
    private weak var favoriteModel: AppFavoriteModel?
    private var lastKnownCollectionWidth: CGFloat = 0
    /// 由 SwiftUI wrapper 注入,用来弹 swiftui-toasts 的 toast。
    var toastPresenter: ((ToastValue) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
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

    init(historyModel: HistoryModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID, favoriteModel: AppFavoriteModel? = nil) {
        self.historyModel = historyModel
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

    // MARK: - Data

    func reloadData() {
        updateViewState()
    }

    private func updateViewState() {
        hideAllStateViews()

        if historyModel.watchList.isEmpty {
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
                message: "开始观看直播后，最近打开的内容会显示在这里。",
                symbolName: "clock.badge.questionmark",
                tint: .orange
            )
        )

        let hostingController = UIHostingController(rootView: emptyView)
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
        print("\(title): \(error)")
    }
}

// MARK: - UICollectionViewDataSource

extension HistoryListViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return historyModel.watchList.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier, for: indexPath) as? LiveRoomCollectionViewCell else {
            return UICollectionViewCell()
        }

        guard indexPath.item < historyModel.watchList.count else {
            return cell
        }

        let room = historyModel.watchList[indexPath.item]
        cell.configure(with: room, navigationState: navigationState, namespace: namespace, liveCheckMode: .remote, onDelete: { [weak self] in
            // 删除历史记录回调
            self?.historyModel.removeHistory(room: room)
            self?.updateViewState()
        }, showsCoverBadge: true)
        cell.attachHostingController(to: self)

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension HistoryListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let watchList = historyModel.watchList
        guard indexPath.item < watchList.count else {
            collectionView.deselectItem(at: indexPath, animated: true)
            return
        }
        let room = watchList[indexPath.item]
        // mode = .remote:异步请求 API 查询直播状态
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let state = try await ApiManager.getCurrentRoomLiveState(
                    roomId: room.roomId,
                    userId: room.userId,
                    liveType: room.liveType
                )
                if state == .live {
                    self.navigationState.navigate(to: room)
                } else {
                    let alert = UIAlertController(title: "主播已下播", message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好的", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
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
        let watchList = historyModel.watchList
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
                    historyModel.removeHistory(room: room)
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

extension HistoryListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return calculateItemSize(for: collectionView.bounds.width)
    }
}
