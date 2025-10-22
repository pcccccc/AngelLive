//
//  SubCategoryViewController.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import UIKit
import SwiftUI
import JXSegmentedView
import AngelLiveCore
import AngelLiveDependencies

class SubCategoryViewController: UIViewController {

    // MARK: - Properties

    private weak var viewModel: PlatformDetailViewModel?
    private let mainCategoryIndex: Int

    // 子分类 JXSegmentedView
    private lazy var subCategoryDataSource = JXSegmentedTitleDataSource()

    private lazy var subCategorySegmentedView: JXSegmentedView = {
        let view = JXSegmentedView()
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        view.dataSource = subCategoryDataSource
        view.delegate = self

        // 配置线条指示器
        let indicator = JXSegmentedIndicatorLineView()
        indicator.indicatorWidth = 20
        indicator.indicatorColor = UIColor(AppConstants.Colors.accent)
        indicator.indicatorHeight = 4
        indicator.indicatorCornerRadius = 2
        indicator.verticalOffset = 2 // 指示器向上偏移，更贴近文字
        view.indicators = [indicator]

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // 房间列表容器
    private lazy var listContainerView: JXSegmentedListContainerView = {
        let container = JXSegmentedListContainerView(dataSource: self)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    // 管理按钮
    private lazy var manageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("管理", for: .normal)
        button.setTitleColor(UIColor(AppConstants.Colors.accent), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(manageButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    init(viewModel: PlatformDetailViewModel, mainCategoryIndex: Int) {
        self.viewModel = viewModel
        self.mainCategoryIndex = mainCategoryIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateSubCategories()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)

        view.addSubview(subCategorySegmentedView)
        view.addSubview(manageButton)
        view.addSubview(listContainerView)

        NSLayoutConstraint.activate([
            // 子分类 SegmentedView
            subCategorySegmentedView.topAnchor.constraint(equalTo: view.topAnchor),
            subCategorySegmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subCategorySegmentedView.trailingAnchor.constraint(equalTo: manageButton.leadingAnchor, constant: -8),
            subCategorySegmentedView.heightAnchor.constraint(equalToConstant: 50),

            // 管理按钮
            manageButton.centerYAnchor.constraint(equalTo: subCategorySegmentedView.centerYAnchor),
            manageButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            manageButton.widthAnchor.constraint(equalToConstant: 50),

            // 房间列表容器
            listContainerView.topAnchor.constraint(equalTo: subCategorySegmentedView.bottomAnchor),
            listContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 关联子分类 segmentedView 和容器
        subCategorySegmentedView.listContainer = listContainerView
    }

    func updateSubCategories() {
        guard let viewModel = viewModel else { return }

        // 确保主分类索引正确
        let subCategories: [LiveCategoryModel]
        if viewModel.categories.indices.contains(mainCategoryIndex) {
            subCategories = viewModel.categories[mainCategoryIndex].subList
        } else {
            subCategories = []
        }

        let titles = subCategories.map { $0.title }
        subCategoryDataSource.titles = titles
        subCategoryDataSource.isItemSpacingAverageEnabled = false

        // 颜色配置
        subCategoryDataSource.titleNormalColor = UIColor(AppConstants.Colors.secondaryText)
        subCategoryDataSource.titleSelectedColor = UIColor(AppConstants.Colors.accent)

        // 字体配置 - 选中时更大更粗
        subCategoryDataSource.titleNormalFont = .systemFont(ofSize: 15, weight: .regular)
        subCategoryDataSource.titleSelectedFont = .systemFont(ofSize: 16, weight: .bold)

        // 开启缩放动画
        subCategoryDataSource.isTitleZoomEnabled = true
        subCategoryDataSource.titleSelectedZoomScale = 1.08

        // 设置每个 item 的宽度为自适应（根据文字宽度）
        subCategoryDataSource.itemWidth = JXSegmentedViewAutomaticDimension

        // 内容边距
        subCategorySegmentedView.contentEdgeInsetLeft = 20
        subCategorySegmentedView.contentEdgeInsetRight = 20

        subCategorySegmentedView.reloadData()
        listContainerView.reloadData()

        // 默认选中第一个
        if !subCategories.isEmpty {
            viewModel.selectedSubCategoryIndex = 0
        }
    }

    func selectSubCategory(at index: Int) {
        guard let viewModel = viewModel else { return }
        let subCategories = getCurrentSubCategories()
        guard index < subCategories.count else { return }

        viewModel.selectedSubCategoryIndex = index
        subCategorySegmentedView.selectItemAt(index: index)

        // 检查缓存，如果没有数据则加载
        let key = "\(mainCategoryIndex)-\(index)"
        if viewModel.roomListCache[key]?.isEmpty ?? true {
            Task { @MainActor in
                // 临时保存并恢复索引
                let oldMainIndex = viewModel.selectedMainCategoryIndex
                let oldSubIndex = viewModel.selectedSubCategoryIndex

                viewModel.selectedMainCategoryIndex = mainCategoryIndex
                viewModel.selectedSubCategoryIndex = index

                await viewModel.loadRoomList()

                viewModel.selectedMainCategoryIndex = oldMainIndex
                viewModel.selectedSubCategoryIndex = oldSubIndex

                // 通知当前显示的 ViewController 更新数据
                if let currentVC = listContainerView.validListDict[index] as? RoomListViewController {
                    currentVC.updateRooms()
                }
            }
        }
    }

    private func getCurrentSubCategories() -> [LiveCategoryModel] {
        guard let viewModel = viewModel,
              viewModel.categories.indices.contains(mainCategoryIndex) else {
            return []
        }
        return viewModel.categories[mainCategoryIndex].subList ?? []
    }

    // MARK: - Actions

    @objc private func manageButtonTapped() {
        guard let viewModel = viewModel else { return }
        let managementVC = CategoryManagementViewController(viewModel: viewModel)
        navigationController?.pushViewController(managementVC, animated: true)
    }
}

// MARK: - JXSegmentedViewDelegate

extension SubCategoryViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        guard let viewModel = viewModel else { return }

        viewModel.selectedSubCategoryIndex = index

        // 检查缓存，如果没有数据则加载
        let key = "\(mainCategoryIndex)-\(index)"
        if viewModel.roomListCache[key]?.isEmpty ?? true {
            Task { @MainActor in
                // 临时保存并恢复索引
                let oldMainIndex = viewModel.selectedMainCategoryIndex
                let oldSubIndex = viewModel.selectedSubCategoryIndex

                viewModel.selectedMainCategoryIndex = mainCategoryIndex
                viewModel.selectedSubCategoryIndex = index

                await viewModel.loadRoomList()

                viewModel.selectedMainCategoryIndex = oldMainIndex
                viewModel.selectedSubCategoryIndex = oldSubIndex

                // 通知当前显示的 ViewController 更新数据
                if let currentVC = listContainerView.validListDict[index] as? RoomListViewController {
                    currentVC.updateRooms()
                }
            }
        }
    }
}

// MARK: - JXSegmentedListContainerViewDataSource

extension SubCategoryViewController: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int {
        return getCurrentSubCategories().count
    }

    func listContainerView(_ listContainerView: JXSegmentedListContainerView, initListAt index: Int) -> JXSegmentedListContainerViewListDelegate {
        let vc = RoomListViewController(
            viewModel: viewModel!,
            mainCategoryIndex: mainCategoryIndex,
            subCategoryIndex: index
        )
        return vc
    }
}

// MARK: - JXSegmentedListContainerViewListDelegate

extension SubCategoryViewController: JXSegmentedListContainerViewListDelegate {
    func listView() -> UIView {
        return view
    }
}
