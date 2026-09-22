//
//  AnimatedTabBarVisibility.swift
//  AngelLive
//

import SwiftUI
import UIKit
import AngelLiveCore

/// Hides the tab bar for FullUI destinations using UIKit's tab bar API.
///
/// FullUI destinations are pushed by a `NavigationStack` whose UIKit host owns
/// the tab bar. The bridge controller itself is the navigation intent marker
/// while iOS 18+ drives the system tab bar directly.
/// SwiftUI attaches this bridge after navigation starts; the child controller's
/// lifecycle `animated` argument does not reflect the parent transition.
private struct FullUITabBarVisibilityModifier: ViewModifier {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), pluginAvailability.hasAvailablePlugins {
            content.background(
                FullUITabBarVisibilityBridge()
                    .frame(width: 0, height: 0)
            )
        } else {
            content.toolbar(.hidden, for: .tabBar)
        }
    }
}

private struct FullUITabBarVisibilityBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        struct NavigationContext {
            let navigationController: UINavigationController
            let host: UIViewController
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            guard #available(iOS 18.0, *),
                  let context = configureNavigationDestination() else {
                return
            }

            setTabBarHidden(
                true,
                in: context.navigationController,
                animated: !UIAccessibility.isReduceMotionEnabled
            )
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)

            guard #available(iOS 18.0, *),
                  let context = navigationContext() else {
                return
            }

            let coordinator = context.host.transitionCoordinator
                ?? context.navigationController.transitionCoordinator
            let shouldHide = shouldKeepTabBarHidden(
                in: context.navigationController,
                coordinator: coordinator
            )
            setTabBarHidden(
                shouldHide,
                in: context.navigationController,
                animated: !UIAccessibility.isReduceMotionEnabled
            )

            coordinator?.animate(alongsideTransition: nil) { [weak self] transitionContext in
                guard transitionContext.isCancelled,
                      let self,
                      let currentContext = self.navigationContext(),
                      currentContext.navigationController === context.navigationController else {
                    return
                }

                self.setTabBarHidden(
                    true,
                    in: currentContext.navigationController,
                    animated: !UIAccessibility.isReduceMotionEnabled
                )
            }
        }

        @discardableResult
        func configureNavigationDestination() -> NavigationContext? {
            guard let context = navigationContext() else {
                return nil
            }

            let isRoot = context.host === context.navigationController.viewControllers.first
            guard !isRoot else {
                return nil
            }

            return context
        }

        private func navigationContext() -> NavigationContext? {
            var current = parent
            while let controller = current, let parent = controller.parent {
                if let navigationController = parent as? UINavigationController {
                    return NavigationContext(
                        navigationController: navigationController,
                        host: controller
                    )
                }

                current = parent
            }

            return nil
        }

        private func shouldKeepTabBarHidden(
            in navigationController: UINavigationController,
            coordinator: UIViewControllerTransitionCoordinator?
        ) -> Bool {
            let stack = navigationController.viewControllers

            if let target = coordinator?.viewController(forKey: .to),
               let targetIndex = stack.firstIndex(where: { $0 === target }) {
                return containsNavigationMarker(in: stack, through: targetIndex)
            }

            return containsNavigationMarker(in: stack)
        }

        private func containsNavigationMarker(
            in stack: [UIViewController],
            through targetIndex: Int? = nil
        ) -> Bool {
            for index in stack.indices {
                guard index > 0 else { continue }
                if let targetIndex, index > targetIndex {
                    break
                }
                if containsNavigationMarker(in: stack[index]) {
                    return true
                }
            }
            return false
        }

        private func containsNavigationMarker(in controller: UIViewController) -> Bool {
            controller.children.contains { child in
                child is Controller || containsNavigationMarker(in: child)
            }
        }

        @available(iOS 18.0, *)
        private func setTabBarHidden(
            _ hidden: Bool,
            in navigationController: UINavigationController,
            animated: Bool
        ) {
            guard let tabBarController = navigationController.tabBarController else {
                return
            }

            let valueBefore = tabBarController.isTabBarHidden
            guard valueBefore != hidden else {
                return
            }

            let animationsWereEnabled = UIView.areAnimationsEnabled
            if animated && !animationsWereEnabled {
                // SwiftUI's child appearance callback can disable UIKit animations;
                // enable this tab bar transition only for the synchronous call.
                UIView.setAnimationsEnabled(true)
                defer {
                    UIView.setAnimationsEnabled(animationsWereEnabled)
                }

                tabBarController.setTabBarHidden(hidden, animated: animated)
                return
            }

            tabBarController.setTabBarHidden(hidden, animated: animated)
        }
    }
}

extension View {
    func fullUITabBarHidden() -> some View {
        modifier(FullUITabBarVisibilityModifier())
    }
}
