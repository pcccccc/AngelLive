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
    private let toolbarOwner = UUID()
    private var toolbarSuppression: MacFullscreenToolbarSuppression?

    var suppressesFullscreenToolbar = false {
        didSet { updateFullscreenToolbar() }
    }

    func bind(to window: NSWindow?) {
        guard self.window !== window else { return }
        restoreFullscreenToolbar()
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
        updateFullscreenToolbar()
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
        restoreFullscreenToolbar()
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
            updateFullscreenToolbar()
            if exitRequested || pendingClose != nil { requestExitFullscreen() }
        case NSWindow.willExitFullScreenNotification: phase = .exiting
        case NSWindow.didExitFullScreenNotification:
            phase = .windowed
            restoreFullscreenToolbar()
            exitRequested = false
            advanceCloseIfPossible()
        case NSWindow.willCloseNotification: invalidate()
        default: break
        }
    }

    private func updateFullscreenToolbar() {
        guard suppressesFullscreenToolbar, phase == .fullscreen else {
            restoreFullscreenToolbar()
            return
        }
        guard let window else { return }
        let suppression = MacFullscreenToolbarSuppression.forWindow(window)
        suppression.acquire(for: toolbarOwner, in: window)
        toolbarSuppression = suppression
    }

    private func restoreFullscreenToolbar() {
        toolbarSuppression?.release(for: toolbarOwner)
        toolbarSuppression = nil
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

    isolated deinit {
        restoreFullscreenToolbar()
        removeObservers()
    }
}

/// Navigation and embedded playback can overlap during a handoff in the same window.
@MainActor
private final class MacFullscreenToolbarSuppression {
    private static let windows = NSMapTable<NSWindow, MacFullscreenToolbarSuppression>.weakToStrongObjects()
    private var owners: Set<UUID> = []
    private weak var hiddenToolbar: NSToolbar?
    private weak var ignoredToolbarWindow: NSWindow?

    static func forWindow(_ window: NSWindow) -> MacFullscreenToolbarSuppression {
        if let existing = windows.object(forKey: window) { return existing }
        let suppression = MacFullscreenToolbarSuppression()
        windows.setObject(suppression, forKey: window)
        return suppression
    }

    func acquire(for owner: UUID, in window: NSWindow) {
        owners.insert(owner)
        if let toolbar = window.toolbar, toolbar.isVisible {
            if let hiddenToolbar, hiddenToolbar !== toolbar { hiddenToolbar.isVisible = true }
            hiddenToolbar = toolbar
            toolbar.isVisible = false
        }
        // AppKit can keep its fullscreen toolbar in a separate child window after
        // hiding the toolbar. That child intercepts clicks on the player's top row.
        // Match the exact runtime class in this window's children and use the public
        // event flag. If AppKit supplies no match, leave every child's event routing alone.
        guard let child = window.childWindows?.first(where: {
            NSStringFromClass(type(of: $0)) == "NSToolbarFullScreenWindow"
        }), !child.ignoresMouseEvents else { return }
        ignoredToolbarWindow?.ignoresMouseEvents = false
        child.ignoresMouseEvents = true
        ignoredToolbarWindow = child
    }

    func release(for owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        ignoredToolbarWindow?.ignoresMouseEvents = false
        ignoredToolbarWindow = nil
        hiddenToolbar?.isVisible = true
        hiddenToolbar = nil
    }
}
