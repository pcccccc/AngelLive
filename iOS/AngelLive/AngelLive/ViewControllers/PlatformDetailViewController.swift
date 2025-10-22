//
//  PlatformDetailViewController.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import UIKit
import SwiftUI
import JXSegmentedView
import AngelLiveCore
import AngelLiveDependencies

class PlatformDetailViewController: UIViewController {

    // MARK: - Properties

    private var viewModel: PlatformDetailViewModel

    // 主分类 JXSegmentedView
    private lazy var mainCategoryDataSource = JXSegmentedTitleDataSource()

    private lazy var mainCategorySegmentedView: JXSegmentedView = {
        let view = JXSegmentedView()
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        view.dataSource = mainCategoryDataSource
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

    // 主分类容器（用于嵌套子分类）
    private lazy var mainListContainerView: JXSegmentedListContainerView = {
        let container = JXSegmentedListContainerView(dataSource: self)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

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
        loadCategories()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        title = viewModel.platform.title

        view.addSubview(mainCategorySegmentedView)
        view.addSubview(mainListContainerView)

        NSLayoutConstraint.activate([
            // 主分类 SegmentedView
            mainCategorySegmentedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainCategorySegmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainCategorySegmentedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainCategorySegmentedView.heightAnchor.constraint(equalToConstant: 56),

            // 主分类容器
            mainListContainerView.topAnchor.constraint(equalTo: mainCategorySegmentedView.bottomAnchor),
            mainListContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainListContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainListContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 关联主分类 segmentedView 和容器
        mainCategorySegmentedView.listContainer = mainListContainerView
    }

    private func setupMainCategories() {
        let titles = viewModel.categories.map { $0.title }
        mainCategoryDataSource.titles = titles
        mainCategoryDataSource.isItemSpacingAverageEnabled = false
        // 颜色配置
        mainCategoryDataSource.titleNormalColor = UIColor(AppConstants.Colors.primaryText)
        mainCategoryDataSource.titleSelectedColor = UIColor(AppConstants.Colors.primaryText)
        
        // 字体配置 - 选中时更大更粗
        mainCategoryDataSource.titleNormalFont = .systemFont(ofSize: 21, weight: .bold)
        mainCategoryDataSource.titleSelectedFont = .systemFont(ofSize: 22, weight: .heavy)

        // 开启缩放动画
        mainCategoryDataSource.isTitleZoomEnabled = true
        mainCategoryDataSource.titleSelectedZoomScale = 1.1

        // 设置每个 item 的宽度为自适应（根据文字宽度）
        mainCategoryDataSource.itemWidth = JXSegmentedViewAutomaticDimension
        mainCategoryDataSource.itemSpacing = 16 // item 之间的间距

        // 内容边距
        mainCategorySegmentedView.contentEdgeInsetLeft = 20
        mainCategorySegmentedView.contentEdgeInsetRight = 20

        mainCategorySegmentedView.reloadData()
        mainListContainerView.reloadData()

        // 默认选中第一个
        if !viewModel.categories.isEmpty {
            viewModel.selectedMainCategoryIndex = 0
        }
    }

    // MARK: - Data Loading

    private func loadCategories() {
        Task { @MainActor in
            await viewModel.loadCategories()

            if !viewModel.categories.isEmpty {
                setupMainCategories()
            }
        }
    }

    // MARK: - Public Methods

    func selectCategory(mainIndex: Int, subIndex: Int) {
        // 切换到指定的主分类
        guard viewModel.categories.indices.contains(mainIndex) else { return }

        viewModel.selectedMainCategoryIndex = mainIndex
        mainCategorySegmentedView.selectItemAt(index: mainIndex)

        // 延迟切换子分类，确保主分类动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if let subCategoryVC = self.mainListContainerView.validListDict[mainIndex] as? SubCategoryViewController {
                subCategoryVC.selectSubCategory(at: subIndex)
            }
        }
    }
}

// MARK: - JXSegmentedViewDelegate

extension PlatformDetailViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        // 只处理主分类切换
        if segmentedView == mainCategorySegmentedView {
            guard index != viewModel.selectedMainCategoryIndex else { return }

            Task { @MainActor in
                await viewModel.selectMainCategory(index: index)

                // 通知对应的子页面更新
                if let childVC = mainListContainerView.validListDict[index] as? SubCategoryViewController {
                    childVC.updateSubCategories()
                }
            }
        }
    }
}

// MARK: - JXSegmentedListContainerViewDataSource

extension PlatformDetailViewController: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int {
        return viewModel.categories.count
    }

    func listContainerView(_ listContainerView: JXSegmentedListContainerView, initListAt index: Int) -> JXSegmentedListContainerViewListDelegate {
        let vc = SubCategoryViewController(
            viewModel: viewModel,
            mainCategoryIndex: index
        )
        return vc
    }
}
