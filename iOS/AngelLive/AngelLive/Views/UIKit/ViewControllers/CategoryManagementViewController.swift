//
//  CategoryManagementViewController.swift
//  AngelLive
//
//  Created by pangchong on 10/22/25.
//

import UIKit
import JXSegmentedView
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

class CategoryManagementViewController: UIViewController {

    // MARK: - Properties

    private weak var viewModel: PlatformDetailViewModel?
    var onCategorySelected: ((Int, Int) -> Void)?

    // 主分类 JXSegmentedView
    private lazy var mainCategoryDataSource = JXSegmentedTitleDataSource()

    private lazy var mainCategorySegmentedView: JXSegmentedView = {
        let view = JXSegmentedView()
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        view.dataSource = mainCategoryDataSource
        view.delegate = self

        // 配置线条指示器
        let indicator = JXSegmentedIndicatorLineView()
        indicator.indicatorWidth = 30
        indicator.indicatorColor = UIColor(AppConstants.Colors.accent)
        indicator.indicatorHeight = 4
        indicator.indicatorCornerRadius = 2
        indicator.verticalOffset = 2
        view.indicators = [indicator]

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // 子分类容器（支持左右滑动）
    private lazy var listContainerView: JXSegmentedListContainerView = {
        let container = JXSegmentedListContainerView(dataSource: self)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private var selectedMainIndex: Int = 0

    // MARK: - Initialization

    init(viewModel: PlatformDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        updateMainCategories()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)

        view.addSubview(mainCategorySegmentedView)
        view.addSubview(listContainerView)

        NSLayoutConstraint.activate([
            // 主分类 SegmentedView
            mainCategorySegmentedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainCategorySegmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainCategorySegmentedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainCategorySegmentedView.heightAnchor.constraint(equalToConstant: 50),

            // 子分类容器
            listContainerView.topAnchor.constraint(equalTo: mainCategorySegmentedView.bottomAnchor),
            listContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 关联 segmentedView 和容器，支持左右滑动切换
        mainCategorySegmentedView.listContainer = listContainerView
    }

    private func setupNavigationBar() {
        title = "全部分类"
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor(AppConstants.Colors.primaryText)
        ]
    }

    private func updateMainCategories() {
        guard let viewModel = viewModel else { return }

        let titles = viewModel.categories.map { $0.title }
        mainCategoryDataSource.titles = titles
        mainCategoryDataSource.isItemSpacingAverageEnabled = false

        // 颜色配置
        mainCategoryDataSource.titleNormalColor = UIColor(AppConstants.Colors.secondaryText)
        mainCategoryDataSource.titleSelectedColor = UIColor(AppConstants.Colors.accent)

        // 字体配置
        mainCategoryDataSource.titleNormalFont = .systemFont(ofSize: 15, weight: .regular)
        mainCategoryDataSource.titleSelectedFont = .systemFont(ofSize: 16, weight: .bold)

        // 开启缩放动画
        mainCategoryDataSource.isTitleZoomEnabled = true
        mainCategoryDataSource.titleSelectedZoomScale = 1.08

        // 设置每个 item 的宽度为自适应
        mainCategoryDataSource.itemWidth = JXSegmentedViewAutomaticDimension

        // 内容边距
        mainCategorySegmentedView.contentEdgeInsetLeft = 20
        mainCategorySegmentedView.contentEdgeInsetRight = 20

        mainCategorySegmentedView.reloadData()
        listContainerView.reloadData()

        // 默认选中第一个
        if !viewModel.categories.isEmpty {
            selectedMainIndex = 0
        }
    }

    private func getCurrentSubCategories() -> [LiveCategoryModel] {
        guard let viewModel = viewModel,
              viewModel.categories.indices.contains(selectedMainIndex) else {
            return []
        }
        return viewModel.categories[selectedMainIndex].subList
    }
}

// MARK: - JXSegmentedViewDelegate

extension CategoryManagementViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        selectedMainIndex = index
    }
}

// MARK: - JXSegmentedListContainerViewDataSource

extension CategoryManagementViewController: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int {
        guard let viewModel = viewModel else { return 0 }
        return viewModel.categories.count
    }

    func listContainerView(_ listContainerView: JXSegmentedListContainerView, initListAt index: Int) -> JXSegmentedListContainerViewListDelegate {
        let vc = CategoryGridViewController(
            viewModel: viewModel,
            mainCategoryIndex: index,
            onCategorySelected: onCategorySelected
        )
        return vc
    }
}
