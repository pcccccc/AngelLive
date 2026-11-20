//
//  iOS17Compatibility.swift
//  AngelLive
//
//  iOS 17 兼容性修饰符
//

import SwiftUI
import UIKit

/// iOS 版本兼容的 zoom 过渡修饰符
struct ZoomTransitionModifier: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

/// iOS 版本兼容的 matchedTransitionSource 修饰符
struct MatchedTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// iOS 版本兼容的 presentationSizing 修饰符
struct WelcomePresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page.fitted(horizontal: true, vertical: false))
        } else {
            content
        }
    }
}

private struct InteractivePopGestureConfigurator: UIViewControllerRepresentable {
    let isEnabled: Bool
    let edgeOnly: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.updateConfiguration(isEnabled: isEnabled, edgeOnly: edgeOnly)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restoreInteractivePopConfiguration()
    }

    final class Controller: UIViewController {
        private var isGestureEnabled = false
        private var edgeOnly = false
        private var isVisible = false
        private weak var trackedGestureRecognizer: UIGestureRecognizer?
        private weak var originalDelegate: UIGestureRecognizerDelegate?
        private var originalIsEnabled = true
        private weak var contentPopGestureRecognizer: UIGestureRecognizer?
        private var originalContentPopEnabled = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            applyInteractivePopConfiguration()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isVisible = false
            restoreInteractivePopConfiguration()
        }

        func updateConfiguration(isEnabled: Bool, edgeOnly: Bool) {
            isGestureEnabled = isEnabled
            self.edgeOnly = edgeOnly
            if isVisible { applyInteractivePopConfiguration() }
        }

        private func applyInteractivePopConfiguration() {
            guard let navigationController, navigationController.viewControllers.count > 1,
                  let gestureRecognizer = navigationController.interactivePopGestureRecognizer else {
                return
            }

            guard isGestureEnabled || edgeOnly else {
                restoreInteractivePopConfiguration()
                return
            }

            if trackedGestureRecognizer !== gestureRecognizer {
                trackedGestureRecognizer = gestureRecognizer
                originalDelegate = gestureRecognizer.delegate
                originalIsEnabled = gestureRecognizer.isEnabled
            }

            gestureRecognizer.delegate = isGestureEnabled ? nil : originalDelegate
            gestureRecognizer.isEnabled = isGestureEnabled

            // Keep horizontal drags inside the player available to its own controls.
            if edgeOnly, #available(iOS 26.0, *),
               let contentPop = navigationController.interactiveContentPopGestureRecognizer {
                if contentPopGestureRecognizer !== contentPop {
                    contentPopGestureRecognizer = contentPop
                    originalContentPopEnabled = contentPop.isEnabled
                }
                contentPop.isEnabled = false
            }
        }

        func restoreInteractivePopConfiguration() {
            if let gestureRecognizer = trackedGestureRecognizer {
                gestureRecognizer.delegate = originalDelegate
                gestureRecognizer.isEnabled = originalIsEnabled
            }
            trackedGestureRecognizer = nil
            contentPopGestureRecognizer?.isEnabled = originalContentPopEnabled
            contentPopGestureRecognizer = nil
        }
    }
}

extension View {
    func interactivePopGestureEnabled(_ isEnabled: Bool, edgeOnly: Bool = false) -> some View {
        background(
            InteractivePopGestureConfigurator(isEnabled: isEnabled, edgeOnly: edgeOnly)
                .frame(width: 0, height: 0)
        )
    }
}
