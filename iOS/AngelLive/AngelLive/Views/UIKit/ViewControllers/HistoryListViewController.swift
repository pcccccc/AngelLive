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
    private var lastKnownCollectionWidth: CGFloat = 0

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(LiveRoomCollectionViewCell.self, forCellWithReuseIdentifier: LiveRoomCollectionViewCell.reuseIdentifier)
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private var emptyHostingController: UIHostingController<AnyView>?

    // MARK: - Initialization

    init(historyModel: HistoryModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID) {
        self.historyModel = historyModel
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
            VStack(spacing: AppConstants.Spacing.lg) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.5))

                Text("暂无观看记录")
                    .font(.title3)
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text("开始观看直播后会显示在这里")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        cell.configure(with: room, navigationState: navigationState, namespace: namespace) { [weak self] in
            // 删除历史记录回调
            self?.historyModel.removeHistory(room: room)
            self?.updateViewState()
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension HistoryListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 导航由 LiveRoomCard 内部通过外部导航状态处理
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension HistoryListViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return calculateItemSize(for: collectionView.bounds.width)
    }
}
