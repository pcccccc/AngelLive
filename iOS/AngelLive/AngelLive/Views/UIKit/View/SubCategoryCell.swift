//
//  SubCategoryCell.swift
//  AngelLive
//
//  Created by pangchong on 10/22/25.
//

import UIKit
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI
import Kingfisher

/// 子分类网格单元格
class SubCategoryCell: UICollectionViewCell {
    static let identifier = "SubCategoryCell"

    // MARK: - UI Components

    // 背景模糊图片
    private let backImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    // 模糊效果视图
    private let blurEffectView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        return effectView
    }()

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
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

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        contentView.backgroundColor = UIColor(AppConstants.Colors.secondaryBackground)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        // 添加背景图片和模糊效果
        contentView.addSubview(backImageView)
        backImageView.addSubview(blurEffectView)

        // 添加前景图片和标题
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            // 背景图片铺满整个cell
            backImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // 模糊效果覆盖背景图片
            blurEffectView.topAnchor.constraint(equalTo: backImageView.topAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: backImageView.leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: backImageView.trailingAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: backImageView.bottomAnchor),

            // 前景图片
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.6),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),

            // 标题
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    // MARK: - Public Methods

    func configure(with category: LiveCategoryModel) {
        titleLabel.text = category.title

        // 加载图标
        if let iconURL = URL(string: category.icon) {
            // 前景图片
            self.imageView.kf.setImage(with: iconURL)
            // 背景模糊图片
            self.backImageView.kf.setImage(with: iconURL)
        } else if category.icon == "douyin" {
            self.imageView.image = UIImage(named: "")
            self.backImageView.image = UIImage(named: "")
        }
    }
}
