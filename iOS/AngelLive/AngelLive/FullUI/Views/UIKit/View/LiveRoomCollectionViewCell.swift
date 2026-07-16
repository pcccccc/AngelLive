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

    func configure(with room: LiveModel, liveCheckMode: LiveCheckMode = .local, showsCoverBadge: Bool = false) {
        let roomCard = LiveRoomCard(room: room, liveCheckMode: liveCheckMode, showsCoverBadge: showsCoverBadge)
        applyRootView(AnyView(roomCard), interactive: true)
    }

    /// 仅复用房间卡片外观，点击统一交给 UICollectionViewDelegate。
    func configureForSelection(
        with room: LiveModel,
        favoriteModel: AppFavoriteModel,
        liveCheckMode: LiveCheckMode = .local,
        showsCoverBadge: Bool = false
    ) {
        var roomCard = LiveRoomCard(room: room, liveCheckMode: liveCheckMode, showsCoverBadge: showsCoverBadge)
        roomCard.disableTapGesture = true
        applyRootView(AnyView(roomCard.environment(favoriteModel)), interactive: false)
    }

    /// 配置 cell（带外部导航状态和命名空间，用于解决 PiP 导航状态丢失问题）
    /// cell-based 场景:SwiftUI 只渲染视觉,tap 由 UICollectionView.didSelectItemAt 接管
    func configure(with room: LiveModel, navigationState: LiveRoomNavigationState, namespace: Namespace.ID, liveCheckMode: LiveCheckMode = .local, onDelete: (() -> Void)? = nil, showsCoverBadge: Bool = false) {
        var roomCard = LiveRoomCard(room: room, liveCheckMode: liveCheckMode, showsCoverBadge: showsCoverBadge)
        roomCard.onDelete = onDelete
        roomCard.disableTapGesture = true
        let cardView = roomCard
            .environment(\.liveRoomNavigationState, navigationState)
            .environment(\.roomTransitionNamespace, namespace)
        // interactive=false:hostingView 不收 touches,UICollectionView.didSelectItemAt 才能正常触发。
        // 副作用:SwiftUI 的 contextMenu 失效(后面如需恢复用 UIContextMenuInteraction)。
        applyRootView(AnyView(cardView), interactive: false)
    }

    /// 复用已有 UIHostingController，避免滚动时反复创建/销毁的开销
    private func applyRootView(_ rootView: AnyView, interactive: Bool) {
        if let hosting = hostingController {
            hosting.rootView = rootView
            hosting.view.isUserInteractionEnabled = interactive
        } else {
            let hosting = UIHostingController(rootView: rootView)
            hosting.view.backgroundColor = .clear
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            hosting.view.isUserInteractionEnabled = interactive
            contentView.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            hostingController = hosting
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 不销毁 hostingController，复用时直接更新 rootView
    }

    /// 把 cell 内部的 UIHostingController 作为子 VC 挂到指定 parent。
    /// 仅首次需要(parent 不变时是 no-op)。
    /// 这是 iOS 上 SwiftUI Button gesture state machine 正常工作的前提:
    /// 没有 parent VC 时,UIHostingController 拿不到完整的 responder chain,iOS 上 tap 会经常被吞,
    /// 但 macOS Catalyst 不依赖这条 chain 做 hit-test,所以表现不出问题。
    func attachHostingController(to parent: UIViewController) {
        guard let hosting = hostingController else { return }
        if hosting.parent === parent { return }
        if hosting.parent != nil {
            hosting.willMove(toParent: nil)
            hosting.removeFromParent()
        }
        parent.addChild(hosting)
        hosting.didMove(toParent: parent)
    }
}
