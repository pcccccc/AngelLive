#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import SwiftUI
import UIKit

struct VodLandscapePlayerView: View {
    let model: VodPlaybackModel
    var episode: VodEpisode? = nil
    let sourceID: String?

    let requiresLandscape: Bool
    let onExit: () -> Void
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.fullUIWindowContext) var windowContext
    @Environment(\.layoutDirection) var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

    @State var controller = KSOnDemandPlayerController()
    @State var settings = GeneralSettingModel()
    @State var seekPreview = SeekPreviewModel()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(role: .primary, supportedGlobalCapabilities: [.audioFocus])
    @FocusState private var keyboardFocused: Bool

    @State var clock = PlaybackClock()
    @State private var playbackStatus = KSOnDemandPlayerController.PlaybackStatus.preparing
    @State var controlsVisible = true
    @State var chromeRevision = 0
    @State var isLocked = false
    @State var drawer: VodPlayerDrawer.Kind?
    @State var rate: Float = 1
    @State var pictureMode = VodPictureMode.fit
    @State var boosted = false
    @State var seek: SeekInteraction?
    @State private var seekTask: Task<Void, Never>?
    @State private var selectionTask: Task<Void, Never>?
    @State var countdown = 8
    @State var creditsHeight: CGFloat = 0
    @State var adjustment: VodPlayerGestures.Adjustment?
    @State private var adjustmentRevision = 0
    @State var notice: String?
    @State private var noticeRevision = 0
    @State private var isLeaving = false
    @State private var resumeOnForegroundID: UUID?

    struct PlaybackClock {
        var current: Double = 0
        var duration: Double = 0
    }

    struct SeekInteraction {
        let id: UUID
        let origin: Double
        let duration: Double
        var resume: Bool
        let fromPicture: Bool
        var target: Double
        var cancelling = false
    }

    private struct HideTimerKey: Equatable {
        let eligible: Bool
        let revision: Int
    }

    var body: some View {
        keyboardAndPointerInput
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
    }

    private var viewport: some View {
        GeometryReader { geometry in
            let layout = FullUILandscapePlayerLayout(
                geometry: geometry, window: windowContext?.window, direction: layoutDirection
            )
            let canShowPlayer = !requiresLandscape || geometry.size.width > geometry.size.height
            ZStack {
                Color.black
                surface(bottomInset: layout.insets.bottom)
                    .padding(.trailing, drawer == nil ? 0 : drawerWidth(in: geometry) + geometry.safeAreaInsets.trailing + 12)
                    .opacity(canShowPlayer ? 1 : 0)
                if canShowPlayer {
                    gestureSurface
                    chrome(layout: layout)
                    if let drawer { drawerOverlay(drawer, geometry: geometry) }
                }
            }
            .ignoresSafeArea(.container)
            .defersSystemGestures(on: isLocked && layout.defersSystemGestures ? .all : [])
            .modifier(FullUIPlayerStatusBar(isLandscapeFullscreen: true))
        }
    }

    private var playbackLifecycle: some View {
        viewport
            .onChange(of: model.playback?.id) { _, _ in resetPlaybackReadout() }
            .onChange(of: model.selectionNote) { _, note in
                if let note { showNotice(note) }
            }
            .onChange(of: model.hasFinished) { _, finished in
                if finished && seek == nil { clock.current = clock.duration }
            }
            .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
            .task {
                if let episode {
                    await model.selectEpisode(id: episode.id, sourceID: sourceID)
                } else {
                    await model.loadAndPlayInitialEpisode()
                }
            }
            .task(id: scenePhase == .background ? nil : model.playback?.id) { await samplePlayback() }
            .task(id: overlayHold) {
                guard !Task.isCancelled, !isLeaving else { return }
                await model.setOverlayHoldPresented(overlayHold)
            }
            .onDisappear { stopPlayback() }
    }

    private var timedChrome: some View {
        playbackLifecycle
            .onChange(of: voiceOverEnabled) { _, enabled in
                if enabled { showControls() }
            }
            .onChange(of: playing) { _, active in
                if !active && seek == nil { showControls() }
            }
            .onChange(of: clock.current) { _, position in
                if let start = creditsStart, position < start { countdown = 8 }
            }
            .task(id: HideTimerKey(eligible: shouldAutoHide, revision: chromeRevision)) { await autoHide() }
            .task(id: countdownOffer) { await countDown() }
            .task(id: adjustmentRevision) {
                guard adjustment != nil else { return }
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { adjustment = nil }
            }
            .task(id: noticeRevision) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(1.8))
                if !Task.isCancelled { notice = nil }
            }
    }

    private var keyboardAndPointerInput: some View {
        timedChrome
            .focusable(usesKeyboard)
            .focused($keyboardFocused)
            .focusEffectDisabled()
            .onChange(of: usesKeyboard, initial: true) { _, active in keyboardFocused = active }
            .onHover { inside in
                if inside && usesKeyboard && !isLocked { showControls() }
            }
            .onContinuousHover { phase in
                if case .active = phase, usesKeyboard && !isLocked && drawer == nil { showControls() }
            }
            .onKeyPress(.space) { handlePlaybackKey { togglePlayback() } }
            .onKeyPress(.leftArrow) { handlePlaybackKey { seekBy(-10) } }
            .onKeyPress(.rightArrow) { handlePlaybackKey { seekBy(10) } }
            .onKeyPress(.escape, action: handleEscape)
    }

    private func handleEscape() -> KeyPress.Result {
        guard usesKeyboard, !isLocked else { return .ignored }
        if drawer != nil { closeDrawer() } else { exit() }
        return .handled
    }

    private func resetPlaybackReadout() {
        countdown = 8
        if model.playback == nil {
            clock = PlaybackClock()
        }
        refreshPlaybackStatus()
        showControls()
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .background {
            resumeOnForegroundID = (seek?.resume ?? controller.wantsPlayback) ? controller.playbackID : nil
            if seek != nil {
                seekTask?.cancel()
                seekTask = nil
                seek?.resume = false
                finishSeek(nil)
            }
            setBoost(false)
            saveCurrentProgress()
            controller.pause()
        } else if let id = resumeOnForegroundID {
            resumeOnForegroundID = nil
            if id == model.playback?.id, id == controller.playbackID, !model.hasFinished {
                controller.play()
            }
        }
    }

    @ViewBuilder
    private func surface(bottomInset: CGFloat) -> some View {
        if let playback = model.playback, scenePhase != .background || playback.id == controller.playbackID {
            VodPlayerSurface(
                playback: playback, model: model, controller: controller, playbackSession: playbackSession,
                rate: boosted ? 2 : rate, pictureMode: drawer == nil ? pictureMode : .fit, hidesSubtitles: seek != nil || model.hasFinished,
                subtitleBottomOffset: (showsChrome ? 2 * FullUIPlayerChrome.controlSize + bottomInset : 0)
                    + (countdownOffer == nil ? 0 : creditsHeight + 8 + (showsChrome ? 0 : bottomInset)),
                onState: refreshPlaybackStatus
            )
            .id(playback.id)
        }
    }

    private var gestureSurface: some View {
        VodPlayerGestures(
            isEnabled: !isLocked && drawer == nil && scenePhase != .background,
            allowsSeek: canSeek && seekTask == nil,
            allowsAdjustments: settings.enablePlayerGesture,
            allowsBoost: playing && seek == nil,
            onTap: {
                if controlsVisible && !voiceOverEnabled { controlsVisible = false } else { showControls() }
            },
            onDoubleTap: togglePlayback,
            onSeek: pictureSeek,
            onSeekEnd: { cancelled in finishSeek(cancelled ? nil : seek?.target) },
            onBoost: setBoost,
            onAdjustment: {
                adjustment = $0
                adjustmentRevision += 1
            }
        )
    }

    var playing: Bool { playbackStatus.isPlaying && !model.hasFinished }
    var canSeek: Bool { controller.isSeekable(for: model.playback?.id) && clock.duration > 0 }
    var showsChrome: Bool { controlsVisible && !isLocked && seek == nil && drawer == nil }
    var isLoading: Bool {
        guard model.errorMessage == nil else { return false }
        return model.playback == nil || model.isLoadingPlayback || playbackStatus.isPreparing
    }
    var isSeries: Bool { model.detail?.kind == .series }
    var currentTime: Double { seek?.target ?? clock.current }
    var creditsStart: Double? { markerBoundary(model.playback?.creditsMarker, useEnd: false) }
    var introEnd: Double? { markerBoundary(model.playback?.introMarker, useEnd: true) }
    var countdownOffer: VodCreditsOffer? {
        guard !overlayHold, seek == nil, !isLoading else { return nil }
        return model.creditsOffer
    }

    private var usesKeyboard: Bool { windowContext?.window?.traitCollection.userInterfaceIdiom == .pad }
    private var overlayHold: Bool { drawer != nil || isLocked || scenePhase == .background }
    private var shouldAutoHide: Bool {
        showsChrome && playing && !isLoading && !boosted && countdownOffer == nil && !voiceOverEnabled
    }

    private func markerBoundary(_ marker: VodMarker?, useEnd: Bool) -> Double? {
        guard let marker, marker.start >= 0, marker.start < marker.end, marker.end <= clock.duration else {
            return nil
        }
        return useEnd ? marker.end : marker.start
    }

    func showControls() {
        controlsVisible = true
        chromeRevision += 1
    }

    private func autoHide() async {
        guard shouldAutoHide else { return }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, shouldAutoHide else { return }
        controlsVisible = false
    }

    private func countDown() async {
        guard let offer = countdownOffer else { return }
        while countdown > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, countdownOffer == offer else { return }
            countdown -= 1
        }
        guard countdownOffer == offer else { return }
        advanceFromCredits()
    }

    private func samplePlayback() async {
        guard scenePhase != .background, let id = model.playback?.id else { return }
        while !Task.isCancelled && model.playback?.id == id && !isLeaving {
            controller.restoreIfPossible(model: model) { readyID in
                guard let sample = controller.timeSample(for: readyID) else { return }
                model.playbackReady(id: readyID, duration: sample.duration)
            }
            refreshPlaybackStatus()
            if seek == nil, !model.hasFinished, !controller.isRestoring(for: id),
               let sample = controller.timeSample(for: id), sample.duration.isFinite, sample.duration > 0 {
                model.playbackReady(id: id, duration: sample.duration)
                clock = .init(current: sample.current, duration: sample.duration)
                model.recordProgress(id: id, position: sample.current, duration: sample.duration)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func handlePlaybackKey(_ action: () -> Void) -> KeyPress.Result {
        guard usesKeyboard, !isLocked, drawer == nil else { return .ignored }
        action()
        return .handled
    }

    private func refreshPlaybackStatus() {
        playbackStatus = controller.playbackStatus(for: model.playback?.id)
    }

    func togglePlayback() {
        guard model.playback != nil, seek == nil else { return }
        if model.hasFinished, let id = model.selectedEpisodeID {
            selectEpisode(id, sourceID: model.playback?.sourceID)
        } else if controller.wantsPlayback {
            controller.pause()
            saveCurrentProgress()
        } else {
            controller.play()
        }
        refreshPlaybackStatus()
        showControls()
    }

    private func setBoost(_ active: Bool) {
        guard boosted != active else { return }
        boosted = active
        controller.setRate(active ? 2 : rate)
        if !active { showControls() }
    }

    func changeEpisode(_ offset: Int) {
        guard let episodes = model.detail?.episodes,
              let index = episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }) else { return }
        let target = index + offset
        guard episodes.indices.contains(target) else {
            showNotice(offset < 0 ? "已经是第一集" : "已经是最后一集")
            return
        }
        selectEpisode(episodes[target].id)
    }

    func selectEpisode(_ id: String, sourceID: String? = nil) {
        changePlayback { await model.selectEpisode(id: id, sourceID: sourceID) }
    }

    func advanceFromCredits() {
        changePlayback { await model.advanceToNextEpisode() }
    }

    func retry() {
        changePlayback { await model.retry() }
    }

    private func changePlayback(_ action: @escaping @MainActor () async -> Void) {
        guard !isLeaving else { return }
        saveCurrentProgress()
        selectionTask?.cancel()
        seekTask?.cancel()
        seekTask = nil
        seek = nil
        seekPreview.cancel()
        setBoost(false)
        selectionTask = Task {
            guard !Task.isCancelled else { return }
            await action()
        }
        closeDrawer()
        showControls()
    }

    func openDrawer(_ kind: VodPlayerDrawer.Kind) {
        guard seek == nil, !isLocked else { return }
        setBoost(false)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)) { drawer = kind }
    }

    func closeDrawer() {
        guard drawer != nil else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)) { drawer = nil }
        if usesKeyboard { keyboardFocused = true }
        showControls()
    }

    private func beginSeek(fromPicture: Bool) -> Bool {
        guard canSeek, seek == nil, seekTask == nil, let id = model.playback?.id,
              model.beginScrubbing(playbackID: id) else { return false }
        let origin = controller.timeSample(for: id)?.current ?? clock.current
        seek = SeekInteraction(id: id, origin: origin, duration: clock.duration,
                               resume: controller.wantsPlayback && !model.hasFinished,
                               fromPicture: fromPicture, target: origin)
        controller.pause()
        return true
    }

    func trackSeek(_ position: Double) {
        if seek == nil { _ = beginSeek(fromPicture: false) }
        updateSeek(position, cancelling: false)
    }

    private func pictureSeek(_ translation: CGSize) {
        if seek == nil { _ = beginSeek(fromPicture: true) }
        guard let seek, seek.fromPicture else { return }
        updateSeek(seek.origin + Double(translation.width) / 6, cancelling: translation.height < -48)
    }

    private func updateSeek(_ target: Double, cancelling: Bool) {
        guard var value = seek, seekTask == nil, let playback = model.playback, playback.id == value.id else { return }
        value.target = min(max(target, 0), value.duration)
        value.cancelling = cancelling
        seek = value
        seekPreview.update(id: value.id, url: playback.url, quality: playback.quality, targetTime: value.target)
    }

    func finishSeek(_ position: Double?) {
        if seek == nil, position != nil { _ = beginSeek(fromPicture: false) }
        guard let value = seek, seekTask == nil else { return }
        seekPreview.endScrubbing()
        seekTask = Task {
            var succeeded = false
            let target = position.map { min(max($0, 0), value.duration) }
            if let target { succeeded = await controller.seek(to: target, playbackID: value.id) }
            guard !Task.isCancelled, !isLeaving, model.playback?.id == value.id else { return }
            await model.completeScrubbing(playbackID: value.id, targetTime: target, duration: value.duration,
                                          seekSucceeded: succeeded, resumePlayback: value.resume)
            guard !Task.isCancelled, !isLeaving else { return }
            seekTask = nil
            seek = nil
            guard model.playback?.id == value.id else { return }
            clock.current = succeeded ? target ?? value.origin : value.origin
            if target != nil && !succeeded { showNotice("暂时无法跳转") }
            if value.resume && !model.hasFinished { controller.play() }
            showControls()
        }
    }

    private func seekBy(_ offset: Double) {
        guard let id = model.playback?.id, let sample = controller.timeSample(for: id) else { return }
        finishSeek(sample.current + offset)
    }

    func skipIntro() {
        guard canSeek, let id = model.playback?.id, let target = model.skipIntro(playbackID: id) else { return }
        finishSeek(target)
    }

    func showNotice(_ message: String) {
        notice = message
        noticeRevision += 1
    }

    func exit() {
        stopPlayback()
        onExit()
    }

    private func stopPlayback() {
        guard !isLeaving else { return }
        isLeaving = true
        selectionTask?.cancel()
        seekTask?.cancel()
        seekPreview.cancel()
        saveCurrentProgress()
        model.cancel()
        controller.stop()
    }

    private func saveCurrentProgress() {
        if seek == nil, let id = model.playback?.id, let sample = controller.timeSample(for: id) {
            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
        }
        model.flushProgress()
    }
}

struct VodDirectPlayerView: View {
    private let orientation: HostContentOrientation
    @State private var model: VodPlaybackModel
    @State private var orientationRequestID: UUID?
    @State private var geometryUpdateFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fullUIWindowContext) private var windowContext

    init(room: LiveModel) {
        orientation = VodRouting.preferredOrientation(for: room)
        _model = State(initialValue: VodRouting.model(for: room))
    }

    private var isPhone: Bool {
        if let window = windowContext?.window {
            return window.traitCollection.userInterfaceIdiom == .phone
        }
        return !AppConstants.Device.isIPad
    }

    var body: some View {
        VodLandscapePlayerView(
            model: model, sourceID: nil,
            requiresLandscape: isPhone && orientation == .landscape && !geometryUpdateFailed,
            onExit: {
                restorePortrait()
                dismiss()
            }
        )
        .navigationBarBackButtonHidden()
        .interactivePopGestureEnabled(false, edgeOnly: true)
        .interactiveDismissDisabled()
        .onChange(of: windowContext?.hostViewController, initial: true) { _, _ in requestOrientation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { requestOrientation() }
        }
        .onDisappear { restorePortrait() }
    }

    private func requestOrientation() {
        guard isPhone, let window = windowContext?.window, window.windowScene != nil,
              windowContext?.hostViewController != nil else { return }
        let id = UUID()
        orientationRequestID = id
        // The window probe can attach during either the zoom cover or a push.
        // Wait for that transition to finish so UIKit queries the visible controller.
        if let transition = orientationControllers(in: window).lazy.compactMap(\.transitionCoordinator).first,
           transition.animate(alongsideTransition: nil, completion: { context in
               guard !context.isCancelled else { return }
               applyOrientation(id, in: window)
           }) { return }
        applyOrientation(id, in: window)
    }

    private func applyOrientation(_ id: UUID, in window: UIWindow) {
        guard orientationRequestID == id, windowContext?.window === window,
              let scene = window.windowScene else { return }
        let mask: UIInterfaceOrientationMask = orientation == .landscape ? .landscape : .portrait
        geometryUpdateFailed = false
        updatePolicy(mask, in: window)
        let current = scene.effectiveGeometry.interfaceOrientation
        guard !(orientation == .landscape ? current.isLandscape : current == .portrait) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { @Sendable error in
            let code = (error as NSError).code
            Task { @MainActor in
                guard orientationRequestID == id else { return }
                // Keep the declared mask available for device rotation even if
                // the scene rejects this explicit geometry request.
                geometryUpdateFailed = true
                Logger.warning("[VOD] 场景方向请求被拒绝（\(code)）", category: .player)
            }
        }
    }

    private func restorePortrait() {
        guard orientationRequestID != nil else { return }
        orientationRequestID = nil
        updatePolicy(.portrait, in: windowContext?.window)
        windowContext?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }

    private func updatePolicy(_ mask: UIInterfaceOrientationMask, in window: UIWindow?) {
        KSOptions.supportedInterfaceOrientations = mask
        if let window {
            for controller in orientationControllers(in: window) {
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    private func orientationControllers(in window: UIWindow) -> [UIViewController] {
        var controllers: [UIViewController] = []
        var current = windowContext?.hostViewController
        while let controller = current {
            controllers.append(controller)
            current = controller.parent
        }
        current = window.rootViewController
        while let controller = current {
            if !controllers.contains(where: { $0 === controller }) { controllers.append(controller) }
            current = controller.presentedViewController
        }
        return controllers
    }
}
#endif
