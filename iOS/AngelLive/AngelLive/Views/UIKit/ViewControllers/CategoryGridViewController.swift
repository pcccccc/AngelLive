//
//  CategoryGridViewController.swift
//  AngelLive
//
//  Created by pangchong on 10/22/25.
//

import UIKit
import JXSegmentedView
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

/// 分类管理页面中的子分类网格视图控制器
class CategoryGridViewController: UIViewController, JXSegmentedListContainerViewListDelegate {

    // MARK: - Properties

    private weak var viewModel: PlatformDetailViewModel?
    private let mainCategoryIndex: Int
    private var onCategorySelected: ((Int, Int) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(SubCategoryCell.self, forCellWithReuseIdentifier: SubCategoryCell.identifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    // MARK: - Initialization

    init(viewModel: PlatformDetailViewModel?, mainCategoryIndex: Int, onCategorySelected: ((Int, Int) -> Void)?) {
        self.viewModel = viewModel
        self.mainCategoryIndex = mainCategoryIndex
        self.onCategorySelected = onCategorySelected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
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

    // MARK: - JXSegmentedListContainerViewListDelegate

    func listView() -> UIView {
        return view
    }

    // MARK: - Private Methods

    private func getCurrentSubCategories() -> [LiveCategoryModel] {
        guard let viewModel = viewModel,
              viewModel.categories.indices.contains(mainCategoryIndex) else {
            return []
        }
        return viewModel.categories[mainCategoryIndex].subList
    }

    /// 获取平台默认图标
    private func getPlatformIcon() -> String {
        guard let viewModel = viewModel else { return "" }
        switch viewModel.platform.liveType {
        case .bilibili:
            return "live_card_bili"
        case .douyu:
            return "live_card_douyu"
        case .huya:
            return "live_card_huya"
        case .douyin:
            return "live_card_douyin"
        case .yy:
            return "live_card_yy"
        case .cc:
            return "live_card_cc"
        case .ks:
            return "live_card_ks"
        case .youtube:
            return "live_card_youtube"
        }
    }
}

// MARK: - UICollectionViewDataSource

extension CategoryGridViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return getCurrentSubCategories().count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SubCategoryCell.identifier, for: indexPath) as! SubCategoryCell
        let subCategories = getCurrentSubCategories()
        if indexPath.item < subCategories.count {
            cell.configure(with: subCategories[indexPath.item], platformIcon: getPlatformIcon())
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension CategoryGridViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 通过闭包回调通知选中的分类
        onCategorySelected?(mainCategoryIndex, indexPath.item)

        // 返回上一页
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension CategoryGridViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let availableWidth = collectionView.bounds.width

        // 根据可用宽度动态计算列数
        let columns: CGFloat
        if isIPad {
            // iPad: 根据宽度自适应列数
            // 每个 cell 最小宽度约 100pt，最大宽度约 150pt
            if availableWidth > 1000 {
                columns = 8  // 超宽屏（横屏无 sidebar）
            } else if availableWidth > 700 {
                columns = 6  // 宽屏（横屏有 sidebar 或竖屏）
            } else if availableWidth > 500 {
                columns = 5  // 中等宽度
            } else {
                columns = 4  // 窄屏
            }
        } else {
            columns = 4  // iPhone 固定 4 列
        }

        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        let totalSpacing = (padding * 2) + (spacing * (columns - 1))
        let width = (availableWidth - totalSpacing) / columns
        return CGSize(width: width, height: width + 5)
    }
}
