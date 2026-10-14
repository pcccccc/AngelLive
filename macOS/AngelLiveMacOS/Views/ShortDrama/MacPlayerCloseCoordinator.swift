import AppKit

/// A destination owns its close request and observes only its own AppKit window.
@MainActor
final class MacPlayerCloseCoordinator {
    private enum FullscreenPhase { case windowed, entering, fullscreen, exiting }
    private weak var window: NSWindow?
    private var phase = FullscreenPhase.windowed
    private var observers: [NSObjectProtocol] = []
    private var bindingGeneration = UUID()
    private var pendingClose: (@MainActor (NSWindow) -> Void)?
    private var exitRequested = false
    private var closeCompleted = false

    func bind(to window: NSWindow?) {
        guard self.window !== window else { return }
        if self.window != nil {
            cancelPendingClose()
            exitRequested = false
        }
        bindingGeneration = UUID()
        removeObservers()
        self.window = window
        guard let window else { return }
        phase = window.styleMask.contains(.fullScreen) ? .fullscreen : .windowed
        let center = NotificationCenter.default
        let generation = bindingGeneration
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                // Capture only Sendable name/generation; the observer is scoped to this exact window.
                MainActor.assumeIsolated {
                    guard let self, self.bindingGeneration == generation else { return }
                    self.receive(name: name)
                }
            })
        }
        advanceCloseIfPossible()
    }

    func requestClose(_ action: @escaping @MainActor (NSWindow) -> Void) {
        guard pendingClose == nil, !closeCompleted else { return }
        pendingClose = action
        advanceCloseIfPossible()
    }

    /// Esc exits fullscreen without closing playback. An in-flight transition consumes Esc once.
    @discardableResult
    func requestExitFullscreen() -> Bool {
        guard let window else { return false }
        switch phase {
        case .windowed: return false
        case .entering:
            exitRequested = true
        case .fullscreen:
            exitRequested = true
            phase = .exiting
            window.toggleFullScreen(nil)
        case .exiting: break
        }
        return true
    }

    /// Replacing the destination's room must not let an old transition close the new playback.
    func cancelPendingClose() {
        pendingClose = nil
        closeCompleted = false
    }

    func invalidate() {
        bindingGeneration = UUID()
        pendingClose = nil
        exitRequested = false
        closeCompleted = false
        removeObservers()
        window = nil
        phase = .windowed
    }

    private func receive(name: Notification.Name) {
        guard window != nil else { return }
        switch name {
        case NSWindow.willEnterFullScreenNotification: phase = .entering
        case NSWindow.didEnterFullScreenNotification:
            phase = .fullscreen
            if exitRequested || pendingClose != nil { requestExitFullscreen() }
        case NSWindow.willExitFullScreenNotification: phase = .exiting
        case NSWindow.didExitFullScreenNotification:
            phase = .windowed
            exitRequested = false
            advanceCloseIfPossible()
        case NSWindow.willCloseNotification: invalidate()
        default: break
        }
    }

    private func advanceCloseIfPossible() {
        guard let window, let action = pendingClose else { return }
        switch phase {
        case .windowed:
            pendingClose = nil
            closeCompleted = true
            action(window)
        case .entering, .fullscreen, .exiting:
            requestExitFullscreen()
        }
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    isolated deinit { removeObservers() }
}
