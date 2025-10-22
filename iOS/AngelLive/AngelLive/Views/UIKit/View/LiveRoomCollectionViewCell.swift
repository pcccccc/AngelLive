//
//  LiveRoomCollectionViewCell.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import UIKit
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

class LiveRoomCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "LiveRoomCollectionViewCell"

    private var hostingController: UIHostingController<LiveRoomCard>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }

    func configure(with room: LiveModel) {
        // 移除旧的 hosting controller
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // 创建新的 SwiftUI 视图
        let roomCard = LiveRoomCard(room: room)
        let hosting = UIHostingController(rootView: roomCard)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        hostingController = hosting
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }
}
