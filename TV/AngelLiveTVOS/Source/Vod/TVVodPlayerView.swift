#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import SwiftUI
import UIKit

struct TVVodPlayerView: View {
    let model: VodPlaybackModel
    let episode: VodEpisode
    let sourceID: String?
    let settings: GeneralSettingModel
    let backInput: TVVodBackInput
    let onExit: (String?) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var focus: Control?
    @State private var controller = KSOnDemandPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary, supportedGlobalCapabilities: [.audioFocus]
    )
    @State private var playbackStatus = KSOnDemandPlayerController.PlaybackStatus.preparing
    @State private var rate: Float = 1
    @State private var pictureMode: TVVodPictureMode = .fit
    @State private var clock = PlaybackClock()
    @State private var preview = SeekPreviewModel()
    @State private var seek: Seek?
    @State private var seekTask: Task<Void, Never>?
    @State private var selectionTask: Task<Void, Never>?
    @State private var showsControls = true
    @State private var controlsRevision = 0
    @State private var pendingFocus: Control?
    @State private var lastBottomControl: Control = .playPause
    @State private var panel: TVVodSelectionPanel.Kind?
    @State private var panelPage: TVVodSelectionPanel.Page = .main
    @State private var panelSourceControl: Control = .settings
    @State private var countdown = 8
    @State private var creditsHeight: CGFloat = 0
    @State private var resumeAfterSuspension: Bool?
    @State private var didExit = false
    @State private var notice: String?
    @State private var noticeRevision = 0

    private enum Control: Hashable {
        case reveal, previous, backward, playPause, forward, next, episodes, tracks, rate, settings
        case timeline, intro, playNext, dismissNext, retry, exit

        var isBottomControl: Bool {
            switch self {
            case .previous, .backward, .playPause, .forward, .next, .episodes, .tracks, .rate, .settings: true
            default: false
            }
        }
    }

    private struct PlaybackClock {
        var position = 0.0
        var duration = 0.0
    }

    private struct Seek {
        let playbackID: UUID
        let origin: Double
        let duration: Double
        let resumes: Bool
        var target: Double
        var previews: Bool
    }

    private struct HideTimer: Equatable {
        let canHide: Bool
        let revision: Int
    }

    private enum PlaybackError: Error {
        case restorationFailed
    }

    private var isSeries: Bool { model.detail?.kind == .series }
    private var error: String? {
        if let message = model.errorMessage { return message }
        guard let playback = model.playback, controller.isRestoring(for: playback.id) else { return nil }
        return model.selectionNote
    }
    private var isPreparing: Bool {
        guard error == nil else { return false }
        return model.playback == nil || playbackStatus.isPreparing
    }
    private var isPlaying: Bool {
        playbackStatus.isPlaying && !model.hasFinished
    }
    private var canSeek: Bool {
        clock.duration > 0 && seek == nil && controller.isSeekable(for: model.playback?.id)
    }
    private var scrubTarget: Double? { seek?.previews == true ? seek?.target : nil }
    private var overlayHold: Bool { panel != nil || seek != nil || scenePhase != .active }
    private var countdownOffer: VodCreditsOffer? {
        guard settings.vodAutoplayEnabled, !overlayHold, !isPreparing else { return nil }
        return model.creditsOffer
    }
    private var canAutoHide: Bool {
        showsControls && !overlayHold && isPlaying && !isPreparing && countdownOffer == nil && !voiceOverEnabled
    }
    private var visibilityAnimation: Animation {
        TVFullUIPlayerControlMetrics.visibilityAnimation(reduceMotion: reduceMotion)
    }

    var body: some View {
        playerLifecycle
            .modifier(TVVodBackModifier(input: backInput, onBack: handleBack))
            .onPlayPauseCommand {
                if panel == nil { togglePlayback() }
            }
    }

    private var playerLifecycle: some View {
        playbackLayout
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
            .onAppear { playbackSession.register() }
            .task { await model.selectEpisode(id: episode.id, sourceID: sourceID) }
            .task(id: model.playback?.id) { await samplePlayback() }
            .task(id: overlayHold) {
                guard !Task.isCancelled, !didExit else { return }
                await model.setOverlayHoldPresented(overlayHold)
            }
            .task(id: HideTimer(canHide: canAutoHide, revision: controlsRevision)) { await autoHide() }
            .task(id: countdownOffer) { await countDown() }
            .task(id: pendingFocus) {
                guard let target = pendingFocus else { return }
                await Task.yield()
                guard !Task.isCancelled, pendingFocus == target, panel == nil else { return }
                focus = target
                pendingFocus = nil
            }
            .task(id: noticeRevision) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                notice = nil
            }
            .onChange(of: model.playback?.id) { playbackChanged() }
            .onChange(of: error) { _, message in
                if message != nil {
                    closePanel()
                    showControls(focusing: .retry)
                }
            }
            .onChange(of: model.hasFinished) { _, finished in
                if finished, showsControls, panel == nil, seek == nil {
                    controlActivity()
                } else if finished, countdownOffer == nil, panel == nil, seek == nil {
                    showControls(focusing: .playPause)
                }
            }
            .onChange(of: model.selectionNote) { _, note in
                if let note { showNotice(note) }
            }
            .onChange(of: countdownOffer) { oldOffer, offer in
                if let offer, offer != oldOffer, !showsControls, panel == nil {
                    pendingFocus = .playNext
                } else if offer == nil, focus == .playNext || focus == .dismissNext {
                    pendingFocus = showsControls ? .playPause : .reveal
                }
            }
            .onChange(of: focus) { previous, current in
                if let current, current.isBottomControl { lastBottomControl = current }
                if previous == .timeline, let current, current != .timeline, scrubTarget != nil {
                    finishSeek(nil)
                }
                controlActivity()
            }
            .onChange(of: voiceOverEnabled) { _, enabled in
                if enabled, panel == nil, !showsControls { showControls(focusing: .playPause) }
            }
            .onChange(of: scenePhase) { _, phase in sceneChanged(phase) }
            .onDisappear(perform: cleanup)
    }

    private var playbackLayout: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let playback = model.playback {
                    TVVodPlayerSurface(playback: playback, model: model, controller: controller,
                                       playbackSession: playbackSession, rate: rate, pictureMode: pictureMode,
                                       hidesSubtitles: seek != nil, subtitleBottomOffset: subtitleBottomOffset,
                                       shouldPlay: scenePhase == .active,
                                       onState: refreshPlaybackStatus)
                    .id(playback.id)
                    .clipped()
                }
                if let error {
                    errorView(error)
                } else if panel == nil {
                    if showsControls {
                        controls(width: geometry.size.width)
                            .transition(.opacity)
                    } else {
                        wakeButton
                    }
                    if let target = scrubTarget {
                        TVPlayerSeekReadout(time: target, duration: clock.duration, preview: preview)
                    }
                    if let offer = countdownOffer { creditsCard(offer) }
                }
                if isPreparing {
                    ProgressView()
                        .fullUIArcLoadingStyle(size: 64, lineWidth: 2.5)
                        .tint(.white)
                        .accessibilityLabel("正在准备播放")
                        .allowsHitTesting(false)
                }
                if let notice, panel == nil {
                    Text(verbatim: notice)
                        .font(.system(size: 23, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .tvPlayerGlass(in: Capsule(), interactive: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, TVFullUIPlayerControlMetrics.screenInset)
                        .allowsHitTesting(false)
                }
                if let panel { panelLayout(panel, size: geometry.size) }
            }
        }
    }

    private var wakeButton: some View {
        Button { showControls(focusing: .playPause) } label: {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(TVFullUIHiddenControlButtonStyle())
        .focused($focus, equals: .reveal)
        .accessibilityLabel("显示播放控制")
        .onMoveCommand { _ in showControls(focusing: .playPause) }
    }

    private func controls(width: CGFloat) -> some View {
        let inset = TVFullUIPlayerControlMetrics.screenInset
        let titleWidth = max(0, width - 2 * inset) * 0.46
        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                playerTitle(width: titleWidth)
                Spacer(minLength: 0)
                transport
            }
            .padding(.vertical, inset)
            .opacity(scrubTarget == nil ? 1 : 0)
            .disabled(scrubTarget != nil)
            .accessibilityHidden(scrubTarget != nil)
            if clock.duration > 0 {
                timeline
                    .padding(.bottom, timelineInset)
            }
            if canSeek, model.activeIntroSkipTarget != nil {
                VStack {
                    Spacer()
                    introButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, timelineInset + TVPlayerTimeline.height + TVPlayerTimeline.buttonGap)
                }
            }
        }
        .padding(.horizontal, inset)
        .defaultFocus($focus, .playPause)
    }

    private func playerTitle(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TVPlayerName(name: model.detail?.title ?? "", font: .systemFont(ofSize: 38, weight: .bold),
                         maximumWidth: width)
                .tvPlayerMediaText()
            if let selected = model.selectedEpisode,
               isSeries || (!selected.title.isEmpty && selected.title != model.detail?.title) {
                TVPlayerName(name: isSeries ? selected.tvVodTitle : selected.title,
                             font: .systemFont(ofSize: 24, weight: .medium),
                             maximumWidth: width)
                    .foregroundStyle(.white.opacity(0.85))
                    .tvPlayerMediaText()
            }
        }
        .allowsHitTesting(false)
    }

    private var transport: some View {
        HStack(spacing: TVFullUIPlayerControlMetrics.spacing) {
            TVFullUIPlayerControlGroup {
                if isSeries {
                    iconButton("上一集", symbol: "backward.end.fill", control: .previous) { moveEpisode(-1) }
                        .disabled(adjacentEpisode(-1) == nil || seek != nil)
                }
                iconButton("后退15秒", symbol: "gobackward.15", control: .backward) { seekBy(-15) }
                    .disabled(!canSeek)
                iconButton(playPauseLabel, symbol: isPlaying ? "pause.fill" : "play.fill",
                           control: .playPause, action: togglePlayback)
                    .disabled(model.playback == nil)
                iconButton("前进15秒", symbol: "goforward.15", control: .forward) { seekBy(15) }
                    .disabled(!canSeek)
                if isSeries {
                    iconButton("下一集", symbol: "forward.end.fill", control: .next) { moveEpisode(1) }
                        .disabled(adjacentEpisode(1) == nil || seek != nil)
                }
            }
            Spacer(minLength: 0)
            if isSeries {
                TVFullUIPlayerControlGroup {
                    controlButton("选集", control: .episodes, shape: .capsule) {
                        openPanel(.episodes, from: .episodes)
                    } label: {
                        Label("选集", systemImage: "list.bullet").font(.system(size: 24, weight: .semibold))
                    }
                }
            }
            TVFullUIPlayerControlGroup {
                iconButton("字幕与音轨", symbol: "captions.bubble", control: .tracks) { openPanel(.tracks, from: .tracks) }
                controlButton("倍速 \(tvVodRateLabel(rate))", control: .rate, shape: .capsule) {
                    openPanel(.rate, from: .rate)
                } label: {
                    Text(tvVodRateLabel(rate)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                }
                iconButton("播放设置", symbol: "gearshape", control: .settings) { openPanel(.settings, from: .settings) }
            }
            .disabled(model.playback == nil)
        }
        .onMoveCommand { direction in
            controlActivity()
            if direction == .up, canSeek { focus = .timeline }
        }
    }

    private var playPauseLabel: String {
        if model.hasFinished { return isSeries ? "重播本集" : "重播" }
        return isPlaying ? "暂停" : "继续播放"
    }

    private var subtitleBottomOffset: CGFloat {
        guard panel == nil, error == nil else { return 0 }
        let controls = showsControls ? timelineInset + TVPlayerTimeline.height + TVPlayerTimeline.buttonGap : 0
        if countdownOffer != nil {
            return max(controls, TVFullUIPlayerControlMetrics.screenInset) + creditsHeight + 12
        }
        return controls
    }

    private var timelineInset: CGFloat {
        TVFullUIPlayerControlMetrics.bottomControlBand + TVPlayerTimeline.buttonGap
    }

    private var timeline: some View {
        Button {
            if let target = scrubTarget { finishSeek(target) }
        } label: {
            TVPlayerTimeline(elapsed: clock.position, duration: clock.duration, target: scrubTarget,
                             isFocused: focus == .timeline, cues: cueTimes)
        }
        .buttonStyle(TVFullUIHiddenControlButtonStyle())
        .focused($focus, equals: .timeline)
        .focusSection()
        .disabled(!canSeek && seek == nil)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(tvPlayerTimeLabel(scrubTarget ?? clock.position))，总时长 \(tvPlayerTimeLabel(clock.duration))")
        .accessibilityHint(scrubTarget == nil ? "左右调整进度" : "按选择键确认，按菜单键取消")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seekBy(15)
            case .decrement: seekBy(-15)
            @unknown default: break
            }
        }
        .onMoveCommand { direction in
            controlActivity()
            switch direction {
            case .left: adjustPreview(-15)
            case .right: adjustPreview(15)
            case .down:
                if let target = scrubTarget { finishSeek(target, returningToControls: true) }
                else { focus = lastBottomControl }
            case .up:
                if canSeek, model.activeIntroSkipTarget != nil { focus = .intro }
                else if countdownOffer != nil { focus = .playNext }
            @unknown default: break
            }
        }
    }

    private var cueTimes: [Double] {
        guard let playback = model.playback else { return [] }
        return [markerTime(playback.introMarker, at: \.end),
                markerTime(playback.creditsMarker, at: \.start)].compactMap { $0 }
    }

    private func markerTime(_ marker: VodMarker?, at boundary: KeyPath<VodMarker, Double>) -> Double? {
        guard let marker, marker.start >= 0, marker.end > marker.start, marker.end <= clock.duration else {
            return nil
        }
        return marker[keyPath: boundary]
    }

    private var introButton: some View {
        TVFullUIPlayerControlGroup {
            controlButton("跳过片头", control: .intro, shape: .capsule) {
                guard canSeek, let id = model.playback?.id, let target = model.skipIntro(playbackID: id) else { return }
                focus = .timeline
                seekTo(target)
            } label: {
                Text("跳过片头").font(.system(size: 24, weight: .semibold))
            }
        }
        .onMoveCommand { direction in
            if direction == .down { focus = .timeline }
        }
    }

    private func creditsCard(_ offer: VodCreditsOffer) -> some View {
        let next = offer.nextEpisode
        return MediaUpNextCard(episodeTitle: next.tvVodTitle, countdown: countdown) {
            TVVodArtwork(path: next.stillURL)
        } actions: {
            Button(action: advance) { Label("立即播放", systemImage: "play.fill") }
                .buttonStyle(MediaUpNextButtonStyle(primary: true))
                .focused($focus, equals: .playNext)
            Button("仍看片尾") {
                model.dismissCreditsOffer(playbackID: offer.playbackID)
                focus = showsControls ? .playPause : .reveal
            }
            .buttonStyle(MediaUpNextButtonStyle(primary: false))
            .focused($focus, equals: .dismissNext)
        }
        .tvPlayerGlass(in: RoundedRectangle(cornerRadius: 28))
        .frame(maxWidth: 720, alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { creditsHeight = $0 }
        .focusSection()
        .onMoveCommand { direction in
            if direction == .down, showsControls { focus = canSeek ? .timeline : .playPause }
        }
        .padding(.trailing, TVFullUIPlayerControlMetrics.screenInset)
        .padding(.bottom, showsControls ? timelineInset + TVPlayerTimeline.height + TVPlayerTimeline.buttonGap
                 : TVFullUIPlayerControlMetrics.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func iconButton(_ title: String, symbol: String, control: Control,
                            action: @escaping () -> Void) -> some View {
        controlButton(title, control: control, shape: .circle, action: action) {
            Image(systemName: symbol).font(.system(size: 30, weight: .bold))
                .frame(width: 40, height: 40)
        }
    }

    private func controlButton<Label: View>(_ title: String, control: Control, shape: TVPlayerControlShape,
                                            action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action, label: label)
            .modifier(TVFullUIPlayerControlButtonModifier(enabled: true, isFocused: focus == control, shape: shape))
            .focused($focus, equals: control)
            .accessibilityLabel(title)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Text("播放失败").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(verbatim: message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 26) {
                Button("重试", action: retry)
                    .focused($focus, equals: .retry)
                Button("返回", action: exit).focused($focus, equals: .exit)
            }
            .buttonStyle(TVVodPillStyle())
        }
        .defaultFocus($focus, .retry)
        .padding(TVFullUIPlayerControlMetrics.screenInset)
    }

    private func panelLayout(_ kind: TVVodSelectionPanel.Kind, size: CGSize) -> some View {
        HStack {
            Spacer()
            TVVodSelectionPanel(kind: kind, model: model, controller: controller, settings: settings,
                                page: $panelPage, rate: $rate, pictureMode: $pictureMode,
                                onSelect: { selectEpisode($0) },
                                onSource: { source in
                                    if let id = model.selectedEpisodeID { selectEpisode(id, sourceID: source) }
                                }, onClose: closePanel)
                .frame(width: min(size.width * 0.4, 640), height: max(0, size.height - 80))
                .padding(.vertical, 40)
                .padding(.trailing, 48)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
        .zIndex(2)
    }

    private func openPanel(_ kind: TVVodSelectionPanel.Kind, from source: Control) {
        guard panel == nil, seek == nil, error == nil else { return }
        panelSourceControl = source
        panelPage = .main
        pendingFocus = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { panel = kind }
        focus = nil
    }

    private func closePanel() {
        guard panel != nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { panel = nil }
        showControls(focusing: panelSourceControl)
    }

    private func handleBack() {
        if panel != nil {
            if panelPage == .main { closePanel() }
            else { panelPage = .main }
        } else if scrubTarget != nil {
            finishSeek(nil)
        } else if seekTask != nil {
            return
        } else if error != nil || !showsControls {
            exit()
        } else {
            hideControls()
        }
    }

    private func controlActivity() { controlsRevision += 1 }

    private func showControls(focusing target: Control? = nil) {
        withAnimation(visibilityAnimation) { showsControls = true }
        if let target { pendingFocus = target }
        controlActivity()
    }

    private func hideControls() {
        withAnimation(visibilityAnimation) { showsControls = false }
        pendingFocus = countdownOffer == nil ? .reveal : .playNext
    }

    private func autoHide() async {
        guard canAutoHide else { return }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, canAutoHide else { return }
        hideControls()
    }

    private func countDown() async {
        guard let offer = countdownOffer else { return }
        while countdown > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, countdownOffer == offer else { return }
            countdown -= 1
        }
        guard !Task.isCancelled, countdownOffer == offer else { return }
        advance()
    }

    private func samplePlayback() async {
        guard let id = model.playback?.id else { return }
        while !Task.isCancelled, !didExit, model.playback?.id == id {
            controller.restoreIfPossible(model: model) { readyID in
                guard let sample = controller.timeSample(for: readyID) else { return }
                model.playbackReady(id: readyID, duration: sample.duration)
            }
            refreshPlaybackStatus()
            if seek == nil, scenePhase == .active, !model.hasFinished, !controller.isRestoring(for: id),
               let sample = controller.timeSample(for: id), sample.duration.isFinite, sample.duration > 0 {
                model.playbackReady(id: id, duration: sample.duration)
                clock = .init(position: sample.current, duration: sample.duration)
                model.recordProgress(id: id, position: sample.current, duration: sample.duration)
                if let start = model.playback?.creditsMarker?.start, sample.current < start { countdown = 8 }
                if focus == .intro, model.activeIntroSkipTarget == nil { focus = canSeek ? .timeline : .playPause }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func playbackChanged() {
        clock = PlaybackClock()
        countdown = 8
        seekTask?.cancel()
        seekTask = nil
        seek = nil
        preview.cancel()
        refreshPlaybackStatus()
        if panel == nil, error == nil { showControls(focusing: .playPause) }
    }

    private func refreshPlaybackStatus() {
        playbackStatus = controller.playbackStatus(for: model.playback?.id)
    }

    private func togglePlayback() {
        guard model.playback != nil, seek == nil else { return }
        if model.hasFinished, let id = model.selectedEpisodeID {
            selectEpisode(id, sourceID: model.playback?.sourceID)
        } else if controller.wantsPlayback {
            controller.pause()
            saveProgress()
        } else {
            controller.play()
        }
        refreshPlaybackStatus()
        showControls(focusing: showsControls ? nil : .playPause)
    }

    private func adjacentEpisode(_ offset: Int) -> VodEpisode? {
        guard let episodes = model.detail?.episodes,
              let current = episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }),
              episodes.indices.contains(current + offset) else { return nil }
        return episodes[current + offset]
    }

    private func moveEpisode(_ offset: Int) {
        if let adjacent = adjacentEpisode(offset) { selectEpisode(adjacent.id) }
    }

    private func selectEpisode(_ id: String, sourceID: String? = nil) {
        if model.isLoadingPlayback, model.selectedEpisodeID == id, sourceID == nil {
            closePanel()
            return
        }
        if model.playback?.episodeID == id, sourceID == nil, !model.hasFinished,
           model.playback?.refreshOnSelect == false, model.progressSnapshot?.episodes[id]?.completed != true {
            closePanel()
            return
        }
        changePlayback { await model.selectEpisode(id: id, sourceID: sourceID) }
    }

    private func advance() { changePlayback { await model.advanceToNextEpisode() } }

    private func retry() {
        changePlayback {
            if let playback = model.playback, controller.isRestoring(for: playback.id) {
                await model.playbackFinished(id: playback.id, error: PlaybackError.restorationFailed)
            }
            guard !Task.isCancelled, !didExit else { return }
            await model.retry()
        }
    }

    private func changePlayback(_ action: @escaping @MainActor () async -> Void) {
        guard !didExit, seek == nil else { return }
        saveProgress()
        selectionTask?.cancel()
        closePanel()
        showControls(focusing: .playPause)
        selectionTask = Task {
            guard !Task.isCancelled, !didExit else { return }
            await action()
        }
    }

    private func beginSeek(previews: Bool) -> Bool {
        guard canSeek, let id = model.playback?.id, model.beginScrubbing(playbackID: id) else { return false }
        let origin = controller.timeSample(for: id)?.current ?? clock.position
        seek = Seek(playbackID: id, origin: origin, duration: clock.duration,
                    resumes: controller.wantsPlayback && !model.hasFinished,
                    target: origin, previews: previews)
        controller.pause()
        return true
    }

    private func adjustPreview(_ delta: Double) {
        if seek == nil, !beginSeek(previews: true) { return }
        guard var seek, seek.previews, let playback = model.playback, playback.id == seek.playbackID else { return }
        seek.target = min(max(seek.target + delta, 0), seek.duration)
        self.seek = seek
        preview.update(id: playback.id, url: playback.url, quality: playback.quality, targetTime: seek.target)
    }

    private func seekBy(_ delta: Double) {
        guard beginSeek(previews: false), let seek else { return }
        finishSeek(seek.origin + delta)
    }

    private func seekTo(_ target: Double) {
        guard beginSeek(previews: false) else { return }
        finishSeek(target)
    }

    private func finishSeek(_ position: Double?, returningToControls: Bool = false) {
        guard var seek, seekTask == nil else { return }
        seek.previews = false
        self.seek = seek
        preview.endScrubbing()
        let target = position.map { min(max($0, 0), seek.duration) }
        let id = seek.playbackID
        seekTask = Task {
            var succeeded = false
            if let target { succeeded = await controller.seek(to: target, playbackID: id) }
            guard !Task.isCancelled, !didExit, model.playback?.id == id else { return }
            let resumes = seek.resumes && !controller.playbackHasFailed(for: id)
            // Settlement may consume a deferred EOF and start a new episode.
            seekTask = nil
            await model.completeScrubbing(playbackID: id, targetTime: target, duration: seek.duration,
                                          seekSucceeded: succeeded, resumePlayback: resumes)
            guard !Task.isCancelled, !didExit, model.playback?.id == id else { return }
            self.seek = nil
            clock.position = succeeded ? target ?? seek.origin : seek.origin
            if let start = model.playback?.creditsMarker?.start, clock.position < start { countdown = 8 }
            if target != nil && !succeeded { showNotice("暂时无法跳转") }
            if resumes, scenePhase == .active, !model.hasFinished { controller.play() }
            if returningToControls { focus = lastBottomControl }
            controlActivity()
        }
    }

    private func sceneChanged(_ phase: ScenePhase) {
        if phase != .active {
            if resumeAfterSuspension == nil {
                resumeAfterSuspension = seek?.resumes ?? controller.wantsPlayback
            }
            saveProgress()
            controller.pause()
            if scrubTarget != nil { finishSeek(nil) }
        } else if let resumes = resumeAfterSuspension {
            resumeAfterSuspension = nil
            if resumes, seek == nil, !model.hasFinished { controller.play() }
            controlActivity()
        }
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeRevision += 1
    }

    private func saveProgress() {
        if seek == nil, let id = model.playback?.id, let sample = controller.timeSample(for: id) {
            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
        }
        model.flushProgress()
    }

    private func cleanup() {
        guard !didExit else { return }
        didExit = true
        selectionTask?.cancel()
        seekTask?.cancel()
        preview.cancel()
        saveProgress()
        model.cancel()
        controller.stop()
        playbackSession.invalidate()
    }

    private func exit() {
        guard !didExit else { return }
        let id = model.selectedEpisodeID
        cleanup()
        onExit(id)
    }
}
#endif
