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

    private var hostingController: UIHostingController<AnyView>?

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
        let roomCard = LiveRoomCard(room: room, skipLiveCheck: true)
        let hosting = UIHostingController(rootView: AnyView(roomCard))
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

    /// 配置 cell（带外部导航状态和命名空间，用于解决 PiP 导航状态丢失问题）
    func configure(with room: LiveModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID, onDelete: (() -> Void)? = nil) {
        // 移除旧的 hosting controller
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // 创建新的 SwiftUI 视图，注入外部导航状态和命名空间
        var roomCard = LiveRoomCard(room: room, skipLiveCheck: true)
        roomCard.onDelete = onDelete
        let cardView = roomCard
            .environment(\.liveRoomNavigationState, navigationState)
            .environment(\.roomTransitionNamespace, namespace)
        let hosting = UIHostingController(rootView: AnyView(cardView))
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
