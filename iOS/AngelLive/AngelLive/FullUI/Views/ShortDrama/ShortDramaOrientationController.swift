#if canImport(KSPlayer)
import SwiftUI
import UIKit
import Observation
import KSPlayer

/// Owns only this page's orientation lease; it never selects another window scene.
@MainActor
@Observable
final class ShortDramaOrientationController {
    private weak var scene: UIWindowScene?
    private weak var host: UIViewController?
    private var hasSavedPolicy = false
    private var savedPolicy: UIInterfaceOrientationMask?
    private var savedOrientation = UIInterfaceOrientation.unknown
    private var allowsLandscape = false
    private var manualOrientation: UIInterfaceOrientationMask?
    private var active = true
    private var requestID = UUID()
    var errorMessage: String?

    var permitsOrientationRequests: Bool {
        guard let host else { return false }
        return host.traitCollection.userInterfaceIdiom != .pad
    }

    func attach(view: UIView) {
        guard active, let window = view.window else { return }
        scene = window.windowScene
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                host = controller
                break
            }
            responder = current.next
        }
        guard !hasSavedPolicy else { return }
        hasSavedPolicy = true
        savedPolicy = KSOptions.supportedInterfaceOrientations
        savedOrientation = scene?.interfaceOrientation ?? .unknown
        applyPolicy()
    }

    func setLandscapeAllowed(_ allowed: Bool) {
        guard active else { return }
        allowsLandscape = allowed
        if !allowed, manualOrientation == .landscape { manualOrientation = .portrait }
        if hasSavedPolicy { applyPolicy() }
        if !allowed, scene?.interfaceOrientation.isLandscape == true,
           permitsOrientationRequests {
            request(.portrait)
        }
    }

    func enterLandscape() {
        guard allowsLandscape, permitsOrientationRequests else { return }
        manualOrientation = .landscape
        request(.landscape)
    }

    func exitLandscape() {
        guard permitsOrientationRequests else { return }
        manualOrientation = .portrait
        request(.portrait)
    }

    func restore() {
        guard active else { return }
        active = false
        requestID = UUID()
        guard hasSavedPolicy else { return }
        KSOptions.supportedInterfaceOrientations = savedPolicy
        host?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if permitsOrientationRequests,
           let mask = Self.mask(for: savedOrientation) {
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    private func applyPolicy() {
        guard permitsOrientationRequests else { return }
        KSOptions.supportedInterfaceOrientations = allowsLandscape
            ? (manualOrientation ?? .allButUpsideDown) : .portrait
        host?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func request(_ mask: UIInterfaceOrientationMask) {
        guard active, let scene else { return }
        errorMessage = nil
        let token = UUID()
        requestID = token
        KSOptions.supportedInterfaceOrientations = mask
        host?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active, self.requestID == token else { return }
                self.manualOrientation = nil
                self.applyPolicy()
                self.errorMessage = "暂时无法切换屏幕方向"
            }
        }
    }

    func geometryDidChange() {
        // Manual fullscreen owns its orientation until the explicit exit. Unlocking it
        // here lets a still-portrait device immediately undo the fullscreen request.
        if active, hasSavedPolicy { applyPolicy() }
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: nil
        }
    }
}

struct ShortDramaWindowProbe: UIViewRepresentable {
    let controller: ShortDramaOrientationController

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.controller = controller
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.controller = controller
    }

    final class Probe: UIView {
        weak var controller: ShortDramaOrientationController?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Attaching can change observed state, so do it after the SwiftUI update.
            Task { @MainActor [weak self] in
                guard let self, self.window != nil else { return }
                self.controller?.attach(view: self)
            }
        }
    }
}
#endif
