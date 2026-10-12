//
//  AnimatedTabBarVisibility.swift
//  AngelLive
//

import SwiftUI
import UIKit
import AngelLiveCore
import os

struct FullUITabBarSelectionContext {
    let tab: TabSelection
    let selection: Binding<TabSelection>

    var isActive: Bool { selection.wrappedValue == tab }
}

extension EnvironmentValues {
    @Entry var fullUITabBarSelectionContext: FullUITabBarSelectionContext? = nil
}

private struct FullUITabBarSelectionModifier: ViewModifier {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    let tab: TabSelection
    let selection: Binding<TabSelection>

    func body(content: Content) -> some View {
        if pluginAvailability.hasAvailablePlugins {
            content.environment(
                \.fullUITabBarSelectionContext,
                FullUITabBarSelectionContext(tab: tab, selection: selection)
            )
        } else {
            content
        }
    }
}

private struct FullUITabBarVisibilityModifier: ViewModifier {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), pluginAvailability.hasAvailablePlugins {
            // The navigation root owns FullUI visibility on iOS 18 and later.
            content
        } else {
            content.toolbar(.hidden, for: .tabBar)
        }
    }
}

private struct FullUITabBarVisibilityRootModifier: ViewModifier {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.fullUITabBarSelectionContext) private var selectionContext

    func body(content: Content) -> some View {
        content.background {
            if #available(iOS 18.0, *), pluginAvailability.hasAvailablePlugins {
                FullUITabBarVisibilityRootBridge(
                    selectionContext: selectionContext,
                    isActive: selectionContext?.isActive
                )
                .frame(width: 0, height: 0)
            }
        }
    }
}

/// A single owner attached to the root content of each FullUI NavigationStack.
@available(iOS 18.0, *)
private struct FullUITabBarVisibilityRootBridge: UIViewControllerRepresentable {
    let selectionContext: FullUITabBarSelectionContext?
    // Reading the binding in the modifier makes selection changes update this bridge.
    let isActive: Bool?

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.updateSelection(selectionContext, isActive: isActive)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.dismantle()
    }

    @MainActor
    final class Controller: UIViewController {
        private static let logger = Logger(subsystem: "AngelLive", category: "FullUITabBarVisibility")

        private weak var rootHost: UIViewController?
        private weak var ownedNavigationController: UINavigationController?
        private var selectionContext: FullUITabBarSelectionContext?
        private var lastIsActive: Bool?
        private var transitionIdentifier: ObjectIdentifier?
        private weak var coordinatedTransition: (any UIViewControllerTransitionCoordinator)?
        private var generation = 0
        private var hasPendingTransition = false
        private var isDismantled = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            guard parent != nil else { return }
            reconcileAppearance()
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            reconcileAppearance()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            reconcileAppearance()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            reconcileAppearance()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPendingTransition, let navigation = navigationContext() else { return }
            writeTabBarHidden(navigation.topViewController !== rootHost, in: navigation, phase: "settled")
        }

        func updateSelection(_ context: FullUITabBarSelectionContext?, isActive: Bool?) {
            selectionContext = context
            let changed = lastIsActive != isActive
            lastIsActive = isActive
            if changed, isActive == false {
                invalidateTransition()
            } else if changed, isActive == true {
                // The root can be offscreen while its preserved stack is selected.
                reconcileAppearance()
            }
        }

        func dismantle() {
            isDismantled = true
            invalidateTransition()
            rootHost = nil
            ownedNavigationController = nil
            selectionContext = nil
        }

        private func invalidateTransition() {
            generation += 1
            transitionIdentifier = nil
            coordinatedTransition = nil
            hasPendingTransition = false
        }

        private func navigationContext() -> UINavigationController? {
            guard !isDismantled else { return nil }

            if let navigation = ownedNavigationController, let rootHost {
                guard rootHost === navigation.viewControllers.first,
                      !hasOuterNavigationController(navigation) else { return nil }
                return navigation
            }

            var current = parent
            while let controller = current, let ancestor = controller.parent {
                if let navigation = ancestor as? UINavigationController {
                    guard controller === navigation.viewControllers.first,
                          !hasOuterNavigationController(navigation) else { return nil }
                    rootHost = controller
                    ownedNavigationController = navigation
                    return navigation
                }
                current = ancestor
            }
            return nil
        }

        private func hasOuterNavigationController(_ navigation: UINavigationController) -> Bool {
            var ancestor = navigation.parent
            while let controller = ancestor {
                if controller is UINavigationController { return true }
                ancestor = controller.parent
            }
            return false
        }

        private func isActive(in navigation: UINavigationController) -> Bool {
            if let selectionContext {
                // Updates for different tabs are not atomic; never trust a cached Bool here.
                return selectionContext.isActive
            }
            guard let selected = navigation.tabBarController?.selectedViewController else { return false }
            var ancestor: UIViewController? = navigation
            while let controller = ancestor {
                if controller === selected { return true }
                ancestor = controller.parent
            }
            return false
        }

        private func reconcileAppearance() {
            guard let navigation = navigationContext(), let root = rootHost,
                  isActive(in: navigation),
                  let tabBarView = navigation.tabBarController?.view else { return }

            guard let coordinator = navigation.transitionCoordinator ?? root.transitionCoordinator else {
                guard !hasPendingTransition else { return }
                writeTabBarHidden(navigation.topViewController !== root, in: navigation, phase: "current")
                return
            }

            let identifier = ObjectIdentifier(coordinator)
            // The weak reference also avoids confusing a reused object address
            // with an earlier coordinator that has already been released.
            guard coordinatedTransition == nil || transitionIdentifier != identifier else { return }
            invalidateTransition()
            transitionIdentifier = identifier
            coordinatedTransition = coordinator
            hasPendingTransition = true
            let token = generation
            let fromIsRoot = coordinator.viewController(forKey: .from) === root
            let target = coordinator.viewController(forKey: .to)
            let isNavigationTransition = navigation.viewControllers.contains { $0 === target }
            let toIsRoot = target === root
            let hidden = isNavigationTransition ? !toIsRoot : navigation.topViewController !== root
            let usesPresentationAnimation = isNavigationTransition && fromIsRoot != toIsRoot
                && !UIAccessibility.isReduceMotionEnabled

            if usesPresentationAnimation {
                // Keep the system bar present while the coordinator drives a
                // standard UIView property, including interactive cancellation.
                writeTabBarHidden(false, in: navigation, phase: "prepare")
                writePresentationAlpha(fromIsRoot ? 1 : 0, token: token, root: root, in: navigation, animated: false)
            }

            let registered = coordinator.animateAlongsideTransition(in: tabBarView, animation: { [weak self, weak navigation, weak root] _ in
                guard let self, let navigation, let root,
                      self.isCurrentTransition(token, root: root, in: navigation) else { return }
                if usesPresentationAnimation {
                    self.writePresentationAlpha(toIsRoot ? 1 : 0, token: token, root: root, in: navigation, animated: true)
                } else {
                    self.writeTabBarHidden(hidden, in: navigation, phase: "transition")
                }
            }, completion: { [weak self, weak navigation, weak root] context in
                guard let self, let navigation, let root,
                      self.isCurrentTransition(token, root: root, in: navigation) else { return }
                self.hasPendingTransition = false
                let completedHidden = isNavigationTransition
                    ? !(context.isCancelled ? fromIsRoot : toIsRoot)
                    : navigation.topViewController !== root
                self.writeTabBarHidden(completedHidden, in: navigation, phase: "completion", cancelled: context.isCancelled, commitBeforeRestoringPresentation: true)
            })

            if !registered, isCurrentTransition(token, root: root, in: navigation) {
                hasPendingTransition = false
                writeTabBarHidden(navigation.topViewController !== root, in: navigation, phase: "uncoordinated")
            }
        }

        private func isCurrentTransition(_ token: Int, root: UIViewController, in navigation: UINavigationController) -> Bool {
            !isDismantled && generation == token
                && rootHost === root && ownedNavigationController === navigation
                && navigation.viewControllers.first === root && isActive(in: navigation)
        }

        private func ownedTabBar(in navigation: UINavigationController) -> UITabBarController? {
            guard !isDismantled, navigation === ownedNavigationController,
                  let rootHost, rootHost === navigation.viewControllers.first,
                  !hasOuterNavigationController(navigation), isActive(in: navigation),
                  let tabBar = navigation.tabBarController else { return nil }
            return tabBar
        }

        private func writePresentationAlpha(
            _ alpha: CGFloat,
            token: Int,
            root: UIViewController,
            in navigation: UINavigationController,
            animated: Bool
        ) {
            guard isCurrentTransition(token, root: root, in: navigation),
                  let tabBar = ownedTabBar(in: navigation) else { return }

            let animationsWereEnabled = UIView.areAnimationsEnabled
            if animated && !animationsWereEnabled {
                // SwiftUI can disable animations during child appearance;
                // enable only this assignment so the coordinator captures it.
                UIView.setAnimationsEnabled(true)
            }
            defer {
                if animated && !animationsWereEnabled {
                    UIView.setAnimationsEnabled(animationsWereEnabled)
                }
            }
            if animated {
                tabBar.tabBar.alpha = alpha
            } else {
                UIView.performWithoutAnimation { tabBar.tabBar.alpha = alpha }
            }
        }

        /// Commit system visibility and restore neutral presentation even when
        /// its hidden flag already matches, including activation of another tab.
        private func writeTabBarHidden(
            _ hidden: Bool,
            in navigation: UINavigationController,
            phase: String,
            cancelled: Bool = false,
            commitBeforeRestoringPresentation: Bool = false
        ) {
            guard let tabBar = ownedTabBar(in: navigation) else { return }

            Self.logger.debug("phase=\(phase, privacy: .public) depth=\(navigation.viewControllers.count) hidden=\(hidden) cancelled=\(cancelled)")
            if !commitBeforeRestoringPresentation {
                UIView.performWithoutAnimation { tabBar.tabBar.alpha = 1 }
            }
            if tabBar.isTabBarHidden != hidden {
                tabBar.setTabBarHidden(hidden, animated: false)
            }
            if commitBeforeRestoringPresentation {
                UIView.performWithoutAnimation { tabBar.tabBar.alpha = 1 }
            }
        }
    }
}

extension View {
    func fullUITabBarVisibilityRoot() -> some View {
        modifier(FullUITabBarVisibilityRootModifier())
    }

    func fullUITabBarSelection(tab: TabSelection, selection: Binding<TabSelection>) -> some View {
        modifier(FullUITabBarSelectionModifier(tab: tab, selection: selection))
    }

    func fullUITabBarHidden() -> some View {
        modifier(FullUITabBarVisibilityModifier())
    }
}
