import SwiftUI
import UIKit
import Observation

/// Resolves window-dependent actions from the FullUI surface that owns them.
/// Keep the window weak and resolve its scene/screen at use time: folding can
/// move the same window to another display without recreating this context.
@MainActor
@Observable
final class FullUIWindowContext {
    private(set) weak var window: UIWindow?
    private(set) weak var hostViewController: UIViewController?

    var windowScene: UIWindowScene? { window?.windowScene }
    var screen: UIScreen? { windowScene?.screen }

    func attach(to view: UIView) {
        guard let window = view.window else { return }
        self.window = window
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                hostViewController = controller
                return
            }
            responder = current.next
        }
    }
}

private struct FullUIWindowContextKey: EnvironmentKey {
    static let defaultValue: FullUIWindowContext? = nil
}

private struct FullUIPlayerIsFullscreenKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FullUIPlayerUsesExpandedLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FullUIPlayerUsesInPlaceFullscreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fullUIWindowContext: FullUIWindowContext? {
        get { self[FullUIWindowContextKey.self] }
        set { self[FullUIWindowContextKey.self] = newValue }
    }

    var fullUIPlayerIsFullscreen: Bool {
        get { self[FullUIPlayerIsFullscreenKey.self] }
        set { self[FullUIPlayerIsFullscreenKey.self] = newValue }
    }

    var fullUIPlayerUsesExpandedLayout: Bool {
        get { self[FullUIPlayerUsesExpandedLayoutKey.self] }
        set { self[FullUIPlayerUsesExpandedLayoutKey.self] = newValue }
    }

    var fullUIPlayerUsesInPlaceFullscreen: Bool {
        get { self[FullUIPlayerUsesInPlaceFullscreenKey.self] }
        set { self[FullUIPlayerUsesInPlaceFullscreenKey.self] = newValue }
    }
}

extension View {
    /// Only FullUI entry points install this context; shared views keep their
    /// existing behavior when no FullUI context was provided.
    func fullUIWindowContext(isEnabled: Bool = true) -> some View {
        modifier(FullUIWindowContextModifier(isEnabled: isEnabled))
    }
}

private struct FullUIWindowContextModifier: ViewModifier {
    let isEnabled: Bool
    @State private var windowContext = FullUIWindowContext()

    func body(content: Content) -> some View {
        content
            .environment(\.fullUIWindowContext, isEnabled ? windowContext : nil)
            .background {
                FullUIWindowProbe(windowContext: windowContext)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

private struct FullUIWindowProbe: UIViewRepresentable {
    let windowContext: FullUIWindowContext

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.windowContext = windowContext
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.windowContext = windowContext
    }

    final class ProbeView: UIView {
        weak var windowContext: FullUIWindowContext?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Publish after SwiftUI's update. Keep the last attachment weakly
            // while disappearing so this page can restore its orientation policy.
            Task { @MainActor [weak self] in
                guard let self, self.window != nil else { return }
                self.windowContext?.attach(to: self)
            }
        }
    }
}
