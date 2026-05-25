//
//  FavoriteListViewController.swift
//  AngelLive
//
//  收藏列表 UICollectionView 实现 - 每个Section横向滚动
//

import UIKit
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

class FavoriteListViewController: UIViewController {

    // MARK: - Properties

    private var viewModel: AppFavoriteModel
    private var filteredSections: [FavoriteLiveSectionModel] = []
    private var searchText: String = ""
    /// 共享导航状态 - 用于解决 PiP 导航状态丢失问题
    private let navigationState: LiveRoomNavigationState
    /// 共享命名空间 - 用于 zoom 过渡动画
    private let namespace: Namespace.ID
    /// 由 SwiftUI wrapper 注入,用来在 contextMenu 失败时弹 swiftui-toasts 的 toast。
    var toastPresenter: ((ToastValue) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let layout = createCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(LiveRoomCollectionViewCell.self, forCellWithReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier)
        cv.register(FavoriteSectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: FavoriteSectionHeaderView.reuseIdentifier)
        cv.refreshControl = refreshControl
        cv.translatesAutoresizingMaskIntoConstraints = false
        // 见 RoomListViewController:同样的 SwiftUI Button 卡 tap 修复(iOS 专属,macOS 不需要)
        cv.delaysContentTouches = false
        cv.panGestureRecognizer.delaysTouchesBegan = false
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private var skeletonHostingController: UIHostingController<FavoriteSkeletonView>?
    private var errorHostingController: UIHostingController<AnyView>?
    private var emptyHostingController: UIHostingController<AnyView>?

    // MARK: - Initialization

    init(viewModel: AppFavoriteModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID) {
        self.viewModel = viewModel
        self.navigationState = navigationState
        self.namespace = namespace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateFilteredSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 确保导航栏大标题可以正常折叠
        navigationController?.navigationBar.prefersLargeTitles = true
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

    // MARK: - Compositional Layout

    private func createCompositionalLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self else { return nil }
            let section = sectionIndex < self.filteredSections.count ? self.filteredSections[sectionIndex] : nil
            let isLiveSection = section?.title == "正在直播"

            if isLiveSection {
                return self.createVerticalGridSection(environment: environment)
            } else {
                return self.createHorizontalSection(environment: environment)
            }
        }
    }

    // MARK: - 正在直播：纵向网格布局

    private func createVerticalGridSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let containerWidth = environment.container.contentSize.width
        let horizontalPadding: CGFloat = 20 // 与导航栏大标题对齐
        let itemSpacing: CGFloat = 15

        // iPad 3列，iPhone 2列
        let columns: CGFloat = isIPad ? 3 : 2
        let totalSpacing = horizontalPadding * 2 + itemSpacing * (columns - 1)
        let itemWidth = (containerWidth - totalSpacing) / columns
        let itemHeight = itemWidth / AppConstants.AspectRatio.card(width: itemWidth)

        // Item
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        // Group (横向排列多个item)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: Int(columns))
        group.interItemSpacing = .fixed(itemSpacing)

        // Section
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = itemSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: horizontalPadding, bottom: 24, trailing: horizontalPadding)

        // Header
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(44)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return section
    }

    // MARK: - 其他分组：横向滚动布局

    private func createHorizontalSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // 计算卡片尺寸
        let containerWidth = environment.container.contentSize.width
        let horizontalPadding: CGFloat = 20 // 与导航栏大标题对齐
        let itemSpacing: CGFloat = 15

        // iPad显示3个卡片，iPhone显示2个卡片（可以看到下一个的一部分）
        let visibleItems: CGFloat = isIPad ? 3.2 : 2.2
        let totalSpacing = horizontalPadding * 2 + itemSpacing * (ceil(visibleItems) - 1)
        let itemWidth = (containerWidth - totalSpacing) / visibleItems
        let itemHeight = itemWidth / AppConstants.AspectRatio.card(width: itemWidth)

        // Item
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        // Group (横向)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        // Section
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = itemSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: horizontalPadding, bottom: 24, trailing: horizontalPadding)

        // Header
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(44)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return section
    }

    // MARK: - Data

    func updateSearchText(_ text: String) {
        // 只在搜索文本真正变化时才更新
        guard searchText != text else { return }
        searchText = text
        updateFilteredSections()
    }

    private func updateFilteredSections() {
        if searchText.isEmpty {
            filteredSections = viewModel.groupedRoomList
        } else {
            let keyword = searchText.lowercased()
            filteredSections = viewModel.groupedRoomList.compactMap { section in
                let rooms = section.roomList.filter { room in
                    room.userName.lowercased().contains(keyword) ||
                    room.roomTitle.lowercased().contains(keyword)
                }
                guard !rooms.isEmpty else { return nil }
                var newSection = FavoriteLiveSectionModel()
                newSection.roomList = rooms
                newSection.title = section.title
                newSection.type = section.type
                return newSection
            }
        }
        updateViewState()
    }

    func reloadData() {
        updateFilteredSections()
    }

    /// 仅更新状态视图（skeleton/error/empty），不触发 collectionView.reloadData()
    /// 用于 syncStatus、isLoading 等状态变化但数据未变时
    func updateStateViewsOnly() {
        hideAllStateViews()

        if viewModel.isLoading && filteredSections.isEmpty {
            // 仅在没有旧数据时显示骨架屏
            showSkeletonView()
        } else if viewModel.cloudReturnError || !viewModel.cloudKitReady {
            showErrorView(message: viewModel.cloudKitStateString)
        } else if filteredSections.isEmpty {
            if searchText.isEmpty {
                showEmptyView()
            } else {
                showSearchEmptyView()
            }
        }
        // 有数据时什么都不做 - 保持当前 collection 不变
    }

    private func updateViewState() {
        hideAllStateViews()

        if viewModel.isLoading {
            showSkeletonView()
        } else if viewModel.cloudReturnError || !viewModel.cloudKitReady {
            showErrorView(message: viewModel.cloudKitStateString)
        } else if filteredSections.isEmpty {
            if searchText.isEmpty {
                showEmptyView()
            } else {
                showSearchEmptyView()
            }
        } else {
            collectionView.reloadData()
        }
    }

    // MARK: - State Views

    private func hideAllStateViews() {
        skeletonHostingController?.view.removeFromSuperview()
        skeletonHostingController?.removeFromParent()
        skeletonHostingController = nil

        errorHostingController?.view.removeFromSuperview()
        errorHostingController?.removeFromParent()
        errorHostingController = nil

        emptyHostingController?.view.removeFromSuperview()
        emptyHostingController?.removeFromParent()
        emptyHostingController = nil
    }

    private func showSkeletonView() {
        let skeletonView = FavoriteSkeletonView()
        let hostingController = UIHostingController(rootView: skeletonView)
        hostingController.view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        skeletonHostingController = hostingController
    }

    private func showErrorView(message: String) {
        let errorView = AnyView(
            ErrorView(
                title: "获取收藏失败",
                message: message,
                showRetry: true,
                onRetry: { [weak self] in
                    self?.handleRefresh()
                }
            )
        )
        showStateView(errorView, storeIn: &errorHostingController)
    }

    private func showEmptyView() {
        let emptyView = AnyView(
            ErrorView.empty(
                title: "暂无收藏",
                message: "在其他页面添加喜欢的直播间后，会显示在这里。",
                symbolName: "star.square.on.square",
                tint: .pink
            )
        )
        showStateView(emptyView, storeIn: &emptyHostingController)
    }

    private func showSearchEmptyView() {
        let emptyView = AnyView(
            ErrorView.empty(
                title: "未找到相关主播",
                message: "换个关键词试试，或者直接搜索房间号和分享链接。",
                symbolName: "person.crop.circle.badge.questionmark",
                tint: .blue
            )
        )
        showStateView(emptyView, storeIn: &emptyHostingController)
    }

    private func showStateView(_ view: AnyView, storeIn controller: inout UIHostingController<AnyView>?) {
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        self.view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        controller = hostingController
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        Task { @MainActor in
            await viewModel.pullToRefresh()
            updateFilteredSections()
            refreshControl.endRefreshing()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension FavoriteListViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        // 使用局部快照避免数据竞争导致的崩溃
        let sections = filteredSections
        return sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // 使用局部快照避免数据竞争导致的崩溃
        let sections = filteredSections
        guard section >= 0, section < sections.count else {
            return 0
        }
        return sections[section].roomList.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier, for: indexPath) as? LiveRoomCollectionViewCell else {
            return UICollectionViewCell()
        }

        // 使用局部快照避免数据竞争导致的崩溃
        let sections = filteredSections
        guard indexPath.section < sections.count else {
            return cell
        }
        let rooms = sections[indexPath.section].roomList
        guard indexPath.item < rooms.count else {
            return cell
        }
        let room = rooms[indexPath.item]
        cell.configure(with: room, navigationState: navigationState, namespace: namespace, showsCoverBadge: true)
        cell.attachHostingController(to: self)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: FavoriteSectionHeaderView.reuseIdentifier, for: indexPath) as? FavoriteSectionHeaderView else {
            return UICollectionReusableView()
        }

        // 使用局部快照避免数据竞争导致的崩溃
        let sections = filteredSections
        guard indexPath.section < sections.count else {
            return header
        }
        let section = sections[indexPath.section]
        header.configure(title: section.title, count: section.roomList.count)

        return header
    }
}

// MARK: - UICollectionViewDelegate

extension FavoriteListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer { collectionView.deselectItem(at: indexPath, animated: true) }
        let sections = filteredSections
        guard indexPath.section < sections.count else { return }
        let rooms = sections[indexPath.section].roomList
        guard indexPath.item < rooms.count else { return }
        let room = rooms[indexPath.item]
        // mode = .local:用本地 liveState 判断
        // liveState 为 nil 或非 close 视为在播
        let isLive: Bool = {
            guard let raw = room.liveState, let state = LiveState(rawValue: raw) else { return true }
            return state != .close
        }()
        if isLive {
            navigationState.navigate(to: room)
        } else {
            let alert = UIAlertController(title: "主播已下播", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好的", style: .default))
            present(alert, animated: true)
        }
    }

    /// 长按弹"取消收藏"菜单(替代 SwiftUI 自带 contextMenu;cell-based 路径下 hostingView
    /// 关掉了 isUserInteractionEnabled,SwiftUI 长按收不到事件,改由 UICollectionView 接管)。
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let sections = filteredSections
        guard indexPath.section < sections.count else { return nil }
        let rooms = sections[indexPath.section].roomList
        guard indexPath.item < rooms.count else { return nil }
        let room = rooms[indexPath.item]
        let viewModel = self.viewModel

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let unfavorite = UIAction(
                title: "取消收藏",
                image: UIImage(systemName: "heart.slash.fill"),
                attributes: .destructive
            ) { [weak self] _ in
                let toastPresenter = self?.toastPresenter
                Task { @MainActor in
                    do {
                        try await viewModel.removeFavoriteRoom(room: room)
                        toastPresenter?(ToastValue(
                            icon: Image(systemName: "heart.slash.fill"),
                            message: "已取消收藏"
                        ))
                    } catch {
                        let detail = FavoriteService.formatErrorCode(error: error)
                        toastPresenter?(ToastValue(
                            icon: Image(systemName: "xmark.circle.fill"),
                            message: "取消收藏失败:\(detail)"
                        ))
                        print("取消收藏失败: \(error)")
                    }
                }
            }
            return UIMenu(title: "", children: [unfavorite])
        }
    }
}

// MARK: - Section Header View

class FavoriteSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "FavoriteSectionHeaderView"

    private let indicatorView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let countContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGray5
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(indicatorView)
        addSubview(titleLabel)
        addSubview(countContainerView)
        countContainerView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 4),
            indicatorView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: indicatorView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countContainerView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countContainerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            countContainerView.heightAnchor.constraint(equalToConstant: 20),
            countContainerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            countLabel.leadingAnchor.constraint(equalTo: countContainerView.leadingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: countContainerView.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: countContainerView.centerYAnchor)
        ])
    }

    func configure(title: String, count: Int) {
        titleLabel.text = title
        countLabel.text = "\(count)"

        // 颜色指示器：正在直播为绿色，其他为灰色
        let isLive = title == "正在直播"
        indicatorView.backgroundColor = isLive ? .systemGreen : .systemGray
    }
}

// MARK: - Skeleton View

struct FavoriteSkeletonView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(0..<2, id: \.self) { _ in
                        skeletonSection(geometry: geometry)
                    }
                }
                .padding(.top, 16)
            }
            .shimmering()
        }
    }

    @ViewBuilder
    private func skeletonSection(geometry: GeometryProxy) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let horizontalPadding: CGFloat = 20
        let itemSpacing: CGFloat = 15
        let visibleItems: CGFloat = isIPad ? 3.2 : 2.2
        let totalSpacing = horizontalPadding * 2 + itemSpacing * (ceil(visibleItems) - 1)
        let itemWidth = (geometry.size.width - totalSpacing) / visibleItems

        VStack(alignment: .leading, spacing: 15) {
            // Header skeleton
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4, height: 18)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 20)

                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 20)
            }
            .padding(.horizontal, horizontalPadding)

            // Cards skeleton (横向)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: itemSpacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        LiveRoomCardSkeleton(width: itemWidth)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}
