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
            cell.configure(with: subCategories[indexPath.item])
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
        // 4列布局
        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        let totalSpacing = (padding * 2) + (spacing * 3)
        let width = (collectionView.bounds.width - totalSpacing) / 4
        return CGSize(width: width, height: width + 5)
    }
}
