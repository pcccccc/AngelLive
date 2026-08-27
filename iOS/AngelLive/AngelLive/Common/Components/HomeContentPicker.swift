//
//  HomeContentPicker.swift
//  AngelLive
//
//  iPhone 首页 Tab 的长按菜单。iPad 使用独立的首页与收藏栏目。
//

import AngelLiveCore
import SwiftUI
import UIKit

/// 找到真实首页 Tab item view 并挂系统 `UIContextMenuInteraction`。
/// SwiftUI 的 `TabContent.contextMenu` 在部分底部 TabBar 形态不会把交互安装到
/// 实际 Tab，所以 iOS 17+ 都统一走 UIKit 桥接路径。
struct HomeTabContextMenuInstaller: UIViewRepresentable {
    let options: [HomePlatformOption]
    let recommendationsAvailable: Bool
    let selectedPreference: HomePagePreference
    let selectedPluginId: String
    let onSelectRecommendations: () -> Void
    let onSelectFavorites: () -> Void
    let onSelectPlatform: (HomePlatformOption) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = InstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onHierarchyChange = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            DispatchQueue.main.async {
                coordinator.installIfNeeded(from: view)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.configuration = Configuration(
            options: options,
            recommendationsAvailable: recommendationsAvailable,
            selectedPreference: selectedPreference,
            selectedPluginId: selectedPluginId,
            onSelectRecommendations: onSelectRecommendations,
            onSelectFavorites: onSelectFavorites,
            onSelectPlatform: onSelectPlatform
        )

        coordinator.scheduleInstallation(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        (uiView as? InstallerView)?.onHierarchyChange = nil
        coordinator.deactivate()
    }
}

extension HomeTabContextMenuInstaller {
    final class InstallerView: UIView {
        var onHierarchyChange: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHierarchyChange?()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onHierarchyChange?()
        }
    }

    struct Configuration {
        let options: [HomePlatformOption]
        let recommendationsAvailable: Bool
        let selectedPreference: HomePagePreference
        let selectedPluginId: String
        let onSelectRecommendations: () -> Void
        let onSelectFavorites: () -> Void
        let onSelectPlatform: (HomePlatformOption) -> Void
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        private static let menuConfigurationIdentifier = NSString(string: "home-tab-menu")

        var configuration: Configuration?

        private var isActive = true
        private weak var installedItemView: UIView?
        private var interaction: UIContextMenuInteraction?
        private var pendingInstallations: [DispatchWorkItem] = []

        func scheduleInstallation(from hostingView: UIView) {
            pendingInstallations.forEach { $0.cancel() }
            pendingInstallations.removeAll()

            // TabView 在不同系统上创建 UITabBarButton 的时机不同。覆盖下一帧和
            // 首次布局后的短窗口；后续尺寸/层级变化由 InstallerView 再触发。
            for delay in [0.0, 0.12, 0.4, 1.0] {
                let workItem = DispatchWorkItem { [weak self, weak hostingView] in
                    guard let self, let hostingView else { return }
                    self.installIfNeeded(from: hostingView)
                }
                pendingInstallations.append(workItem)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }

        func installIfNeeded(from hostingView: UIView) {
            guard isActive,
                  let tabBarController = Self.findTabBarController(from: hostingView),
                  let firstItem = tabBarController.tabBar.items?.first,
                  let itemView = firstItem.value(forKey: "view") as? UIView,
                  Self.isActuallyVisible(itemView)
            else { return }

            guard installedItemView !== itemView else { return }
            removeInteraction()

            let interaction = UIContextMenuInteraction(delegate: self)
            itemView.addInteraction(interaction)
            installedItemView = itemView
            self.interaction = interaction
        }

        func deactivate() {
            isActive = false
            pendingInstallations.forEach { $0.cancel() }
            pendingInstallations.removeAll()
            removeInteraction()
            configuration = nil
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard configuration != nil else { return nil }
            return UIContextMenuConfiguration(
                identifier: Self.menuConfigurationIdentifier,
                previewProvider: nil
            ) { [weak self] _ in
                self?.makeMenu()
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configuration: UIContextMenuConfiguration,
            highlightPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            invisibleTargetedPreview(for: interaction)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configuration: UIContextMenuConfiguration,
            dismissalPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            invisibleTargetedPreview(for: interaction)
        }

        private func makeMenu() -> UIMenu? {
            guard let configuration else { return nil }

            var destinationActions: [UIMenuElement] = []
            if configuration.recommendationsAvailable {
                destinationActions.append(UIAction(
                    title: HomePagePreference.recommendations.displayName,
                    image: UIImage(systemName: "sparkles"),
                    state: configuration.selectedPreference == .recommendations
                        && configuration.selectedPluginId.isEmpty ? .on : .off
                ) { [weak self] _ in
                    self?.configuration?.onSelectRecommendations()
                })
            }

            destinationActions.append(UIAction(
                title: HomePagePreference.favorites.displayName,
                image: UIImage(systemName: "heart.fill"),
                state: configuration.selectedPreference == .favorites ? .on : .off
            ) { [weak self] _ in
                self?.configuration?.onSelectFavorites()
            })

            var sections: [UIMenuElement] = [
                UIMenu(title: "", options: .displayInline, children: destinationActions)
            ]

            if !configuration.options.isEmpty {
                let platformActions = configuration.options.map { option in
                    UIAction(
                        title: option.displayName,
                        image: Self.platformImage(for: option),
                        state: configuration.selectedPreference == .recommendations
                            && configuration.selectedPluginId == option.pluginId ? .on : .off
                    ) { [weak self] _ in
                        self?.configuration?.onSelectPlatform(option)
                    }
                }
                sections.append(UIMenu(title: "", options: .displayInline, children: platformActions))
            }

            return UIMenu(title: "", children: sections)
        }

        /// Liquid Glass 的选中 Tab 已经自带抬升反馈。系统再快照整个 item view
        /// 会把图标和标题复制一份，形成重影。保留一个近乎不可见的合法预览区域，
        /// 既维持系统菜单的定位与转场，也不重复绘制 Tab 内容。
        private func invisibleTargetedPreview(
            for interaction: UIContextMenuInteraction
        ) -> UITargetedPreview? {
            guard let sourceView = interaction.view,
                  sourceView.window != nil,
                  !sourceView.bounds.isEmpty else { return nil }

            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            let center = CGPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY)
            parameters.visiblePath = UIBezierPath(rect: CGRect(
                x: center.x,
                y: center.y,
                width: 0.01,
                height: 0.01
            ))
            parameters.shadowPath = UIBezierPath()
            return UITargetedPreview(view: sourceView, parameters: parameters)
        }

        private func removeInteraction() {
            if let interaction {
                installedItemView?.removeInteraction(interaction)
            }
            interaction = nil
            installedItemView = nil
        }

        private static func platformImage(for option: HomePlatformOption) -> UIImage? {
            PlatformIconProvider.tabImage(for: option.liveType)
                ?? UIImage(systemName: "play.tv")
        }

        private static func findTabBarController(from hostingView: UIView) -> UITabBarController? {
            var responder: UIResponder? = hostingView
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                if let viewController = current as? UIViewController,
                   let tabBarController = viewController.tabBarController {
                    return tabBarController
                }
                responder = current.next
            }

            guard let window = hostingView.window,
                  let rootViewController = window.rootViewController else { return nil }
            return findVisibleTabBarController(in: rootViewController)
        }

        private static func findVisibleTabBarController(
            in viewController: UIViewController
        ) -> UITabBarController? {
            if let presented = viewController.presentedViewController,
               let result = findVisibleTabBarController(in: presented) {
                return result
            }
            if let tabBarController = viewController as? UITabBarController,
               isActuallyVisible(tabBarController.tabBar) {
                return tabBarController
            }
            for child in viewController.children.reversed() {
                if let result = findVisibleTabBarController(in: child) {
                    return result
                }
            }
            return nil
        }

        private static func isActuallyVisible(_ view: UIView) -> Bool {
            guard let window = view.window,
                  !view.isHidden,
                  view.alpha > 0.01,
                  view.bounds.width > 1,
                  view.bounds.height > 1 else { return false }

            var ancestor = view.superview
            while let current = ancestor {
                guard !current.isHidden, current.alpha > 0.01 else { return false }
                ancestor = current.superview
            }

            let frameInWindow = view.convert(view.bounds, to: window)
            return frameInWindow.intersects(window.bounds)
        }
    }
}
