#if canImport(KSPlayer)
import AngelLiveCore
import Combine
import KSPlayer
import KSPlayerUI
import SwiftUI
import UIKit

@MainActor
final class VodPlayerPresentation: UIHostingController<VodPlayerViewport> {
    private let locksOrientation: Bool
    private weak var playerWindow: UIWindow?
    private var onFinish: ((Bool) -> Void)?
    private var closing = false

    init(window: UIWindow, model: VodPlaybackModel, episode: VodEpisode, sourceID: String?,
         onFinish: @escaping (Bool) -> Void) {
        let phone = window.traitCollection.userInterfaceIdiom == .phone
        locksOrientation = phone
        playerWindow = window
        self.onFinish = onFinish
        var viewport = VodPlayerViewport(window: window, phone: phone, model: model, episode: episode,
                                         sourceID: sourceID, onExit: {})
        super.init(rootView: viewport)
        viewport.onExit = { [weak self] in self?.close() }
        rootView = viewport
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        locksOrientation ? (closing ? .portrait : .landscape) : .all
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        locksOrientation ? .landscapeRight : super.preferredInterfaceOrientationForPresentation
    }

    override var prefersStatusBarHidden: Bool { true }

    func show(from presenter: UIViewController) {
        if let transition = presenter.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { [self, weak presenter] _ in
               guard let presenter, presenter.viewIfLoaded?.window != nil else { finish(failed: true); return }
               presentPlayer(from: presenter)
           }) { return }
        presentPlayer(from: presenter)
    }

    private func presentPlayer(from presenter: UIViewController) {
        if locksOrientation {
            KSOptions.supportedInterfaceOrientations = .landscape
            playerWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        presenter.present(self, animated: true) { [weak self] in
            guard let self, self.locksOrientation, !self.closing,
                  let scene = self.playerWindow?.windowScene, !scene.interfaceOrientation.isLandscape else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { [weak self] _ in
                self?.close(failed: true)
            }
        }
    }

    private func close(failed: Bool = false) {
        guard !closing else { return }
        closing = true
        if locksOrientation {
            KSOptions.supportedInterfaceOrientations = .portrait
            setNeedsUpdateOfSupportedInterfaceOrientations()
            playerWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        dismiss(animated: true) { [self] in finish(failed: failed) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !closing, isBeingDismissed || presentingViewController == nil { finish(failed: false) }
    }

    private func finish(failed: Bool) {
        guard let completion = onFinish else { return }
        onFinish = nil
        if locksOrientation {
            KSOptions.supportedInterfaceOrientations = .portrait
            playerWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            playerWindow?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        completion(failed)
    }
}

struct VodPlayerViewport: View {
    weak var window: UIWindow?
    let phone: Bool
    let model: VodPlaybackModel
    let episode: VodEpisode
    let sourceID: String?
    var onExit: () -> Void
    @State private var notifiedPhase: ScenePhase?

    private var currentPhase: ScenePhase {
        switch window?.windowScene?.activationState {
        case .foregroundActive, .foregroundInactive: .active
        case .background: .background
        default: UIApplication.shared.applicationState == .background ? .background : .active
        }
    }

    var body: some View {
        VodLandscapePlayerView(model: model, episode: episode, sourceID: sourceID,
                               requiresLandscape: phone, onExit: onExit)
            .fullUIWindowContext()
            .environment(\.scenePhase, notifiedPhase ?? currentPhase)
            .onAppear { notifiedPhase = currentPhase }
            .onReceive(Self.lifecycleNotifications) { notification in
                if let scene = notification.object as? UIScene {
                    guard scene === window?.windowScene else { return }
                    notifiedPhase = notification.name == UIScene.didEnterBackgroundNotification ? .background : .active
                } else {
                    notifiedPhase = notification.name == UIApplication.didEnterBackgroundNotification ? .background : currentPhase
                }
            }
    }

    private static let lifecycleNotifications = Publishers.MergeMany([
        UIScene.didActivateNotification, UIScene.willDeactivateNotification,
        UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
        UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification
    ].map { NotificationCenter.default.publisher(for: $0) })
}
#endif
