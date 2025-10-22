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

    // 子分类 CollectionView
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
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            // 主分类 SegmentedView
            mainCategorySegmentedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainCategorySegmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainCategorySegmentedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainCategorySegmentedView.heightAnchor.constraint(equalToConstant: 50),

            // 子分类 CollectionView
            collectionView.topAnchor.constraint(equalTo: mainCategorySegmentedView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

        // 默认选中第一个
        if !viewModel.categories.isEmpty {
            selectedMainIndex = 0
            collectionView.reloadData()
        }
    }

    private func getCurrentSubCategories() -> [LiveCategoryModel] {
        guard let viewModel = viewModel,
              viewModel.categories.indices.contains(selectedMainIndex) else {
            return []
        }
        return viewModel.categories[selectedMainIndex].subList ?? []
    }
}

// MARK: - JXSegmentedViewDelegate

extension CategoryManagementViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        selectedMainIndex = index
        collectionView.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension CategoryManagementViewController: UICollectionViewDataSource {
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

extension CategoryManagementViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 通过闭包回调通知选中的分类
        onCategorySelected?(selectedMainIndex, indexPath.item)

        // 返回上一页
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension CategoryManagementViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 4列布局
        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        let totalSpacing = (padding * 2) + (spacing * 3)
        let width = (collectionView.bounds.width - totalSpacing) / 4
        return CGSize(width: width, height: width * 1.2)
    }
}

// MARK: - SubCategoryCell

class SubCategoryCell: UICollectionViewCell {
    static let identifier = "SubCategoryCell"

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor(AppConstants.Colors.primaryText)
        label.numberOfLines = 2
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
        contentView.backgroundColor = UIColor(AppConstants.Colors.secondaryBackground)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.6),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func configure(with category: LiveCategoryModel) {
        titleLabel.text = category.title

        // 加载图标
        if let iconURL = URL(string: category.icon) {
            URLSession.shared.dataTask(with: iconURL) { [weak self] data, response, error in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.imageView.image = image
                    }
                }
            }.resume()
        }
    }
}
