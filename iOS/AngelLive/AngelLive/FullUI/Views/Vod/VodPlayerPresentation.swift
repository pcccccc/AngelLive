#if canImport(KSPlayer)
import AngelLiveCore
import Combine
import KSPlayer
import KSPlayerUI
import SwiftUI
import UIKit

@MainActor
final class VodPlayerPresentation: UIHostingController<VodPlayerViewport> {
    private let phoneOrientation: HostContentOrientation?
    private weak var playerWindow: UIWindow?
    private var onFinish: ((Bool) -> Void)?
    private var closing = false

    init(window: UIWindow, model: VodPlaybackModel, episode: VodEpisode, sourceID: String?,
         orientation: HostContentOrientation,
         onFinish: @escaping (Bool) -> Void) {
        let phone = window.traitCollection.userInterfaceIdiom == .phone
        phoneOrientation = phone ? orientation : nil
        playerWindow = window
        self.onFinish = onFinish
        var viewport = VodPlayerViewport(window: window, requiresLandscape: phone && orientation == .landscape,
                                         model: model, episode: episode,
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

    private var phoneOrientationMask: UIInterfaceOrientationMask? {
        guard let phoneOrientation else { return nil }
        return phoneOrientation == .landscape ? .landscape : .portrait
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard let phoneOrientationMask else { return .all }
        return closing ? .portrait : phoneOrientationMask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        guard let phoneOrientation else { return super.preferredInterfaceOrientationForPresentation }
        return phoneOrientation == .landscape ? .landscapeRight : .portrait
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
        if let phoneOrientationMask {
            KSOptions.supportedInterfaceOrientations = phoneOrientationMask
            playerWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        presenter.present(self, animated: true) { [weak self] in
            guard let self, let mask = self.phoneOrientationMask, !self.closing,
                  let scene = self.playerWindow?.windowScene else { return }
            let current = scene.interfaceOrientation
            let matches = mask == .landscape ? current.isLandscape : current == .portrait
            guard !matches else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
                self?.close(failed: true)
            }
        }
    }

    private func close(failed: Bool = false) {
        guard !closing, onFinish != nil else { return }
        closing = true
        if phoneOrientation != nil {
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
        if phoneOrientation != nil {
            KSOptions.supportedInterfaceOrientations = .portrait
            playerWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            playerWindow?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        completion(failed)
    }
}

struct VodPlayerViewport: View {
    weak var window: UIWindow?
    let requiresLandscape: Bool
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
                               requiresLandscape: requiresLandscape, onExit: onExit)
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
