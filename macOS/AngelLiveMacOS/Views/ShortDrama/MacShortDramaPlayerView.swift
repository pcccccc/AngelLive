#if canImport(KSPlayer)
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import AppKit
import Kingfisher
import SharedAssets

/// Desktop controls follow the existing player; episode resolution is shared with the other hosts.
struct MacShortDramaPlayerView: View {
    let room: LiveModel
    let onClose: (@MainActor () -> Void)?
    let onExitFullscreen: (@MainActor () -> Bool)?
    @State private var model: ShortDramaPlaybackModel
    @State private var controller = KSShortDramaPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(role: .primary, supportedGlobalCapabilities: [.audioFocus])
    @State private var playerWindow: NSWindow?
    @State private var isPlaying = false
    @State private var isReady = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var seekValue = 0.0
    @State private var isSeeking = false
    @State private var seekCommitInFlight = false
    @State private var resumeAfterSeek = false
    @State private var seekPlaybackID: UUID?
    @State private var seekTask: Task<Void, Never>?
    @State private var feedbackToast: ToastMessage?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var playbackRate: Float = 1
    @State private var volume: Float = 1
    @State private var showsEpisodes = false
    @State private var resumeAfterPanel = false
    @State private var operation: Task<Void, Never>?
    @State private var panelHoldTask: Task<Void, Never>?
    @State private var isLeaving = false
    @State private var sleepActivity: NSObjectProtocol?
    @State private var controlsRevealed = true
    @State private var controlsHovered = false
    @State private var volumeHovered = false
    @State private var isAdjustingVolume = false
    @State private var preMuteVolume: Float = 1
    @State private var menuTrackingCount = 0
    @State private var hideControlsTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HistoryModel.self) private var historyModel

    init(room: LiveModel, onClose: (@MainActor () -> Void)? = nil, onExitFullscreen: (@MainActor () -> Bool)? = nil) {
        self.room = room
        self.onClose = onClose
        self.onExitFullscreen = onExitFullscreen
        _model = State(initialValue: ShortDramaPlaybackModel(room: room))
    }

    private var title: String { room.roomTitle.isEmpty ? room.userName.orDash : room.roomTitle }
    private var episodeText: String { model.selectedEpisode.map { "第 \($0.number) 集" } ?? "分集播放" }
    private var isSeekable: Bool { controller.isSeekable(for: model.playback?.id) }

    private var controlsHeld: Bool {
        !isPlaying || !isReady || model.isLoading || model.errorMessage != nil
            || model.hasFinished || isSeeking || isAdjustingVolume || showsEpisodes
            || controlsHovered || menuTrackingCount > 0 || voiceOverEnabled
    }
    private var controlsVisible: Bool { controlsRevealed || controlsHeld }
    private var volumeIsExpanded: Bool { volumeHovered || isAdjustingVolume || voiceOverEnabled }

    private func volumeSliderWidth(availableWidth: CGFloat) -> CGFloat {
        // Four 30pt slots + three 16pt gaps + capsule 16pt + expansion gap 12pt
        // + window insets 32pt leave the remaining width for the native slider.
        availableWidth >= 352 ? 80 : max(40, min(80, availableWidth - 228))
    }

    private func volumeExpansionWidth(availableWidth: CGFloat) -> CGFloat {
        12 + volumeSliderWidth(availableWidth: availableWidth) + (availableWidth >= 352 ? 44 : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let playback = model.playback {
                    MacShortDramaPlayerSurface(
                        playback: playback, playbackRate: playbackRate, volume: volume,
                        desiredPlayback: controller.wantsPlayback,
                        model: model, controller: controller, playbackSession: playbackSession,
                        onReady: playbackReady,
                        onPlayingChanged: { id, playing in
                            guard model.playback?.id == id, !isLeaving else { return }
                            isPlaying = playing
                        }
                    )
                    .id(playback.id)
                }
                // This layer owns only uncovered video clicks and pointer activity.
                // Controls and the existing top window-drag strip receive their own events.
                MacShortDramaInteractionArea(onActivity: revealControls, onClick: videoClicked)
                    .allowsHitTesting(!showsEpisodes)
                    .accessibilityHidden(true)
                WindowDragArea()
                    .frame(height: 60)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(!showsEpisodes)
                VStack {
                    topControls
                        .padding(.horizontal, 16)
                        .onHover { controlsHoverChanged($0) }
                    Spacer(minLength: 16)
                    bottomControls(availableWidth: geometry.size.width)
                        .onHover { controlsHoverChanged($0) }
                }
                .padding(.top, 16)
                .opacity(controlsVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controlsVisible)
                .allowsHitTesting(controlsVisible && !showsEpisodes)
                .accessibilityHidden(showsEpisodes || !controlsVisible)
                // Match the live player's ZStack: status is centered in the video viewport,
                // independent of the title, progress row, and adaptive bottom control height.
                statusContent
                    .padding(.horizontal, 16)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controlsVisible)
                    .allowsHitTesting(controlsVisible && !showsEpisodes)
                    .accessibilityHidden(showsEpisodes || !controlsVisible)
                if showsEpisodes {
                    episodeOverlay(size: geometry.size)
                }
            }
        }
        .background(PlayerWindowReferenceView(window: $playerWindow))
        .environment(\.colorScheme, .dark)
        .navigationTitle(title)
        .toolbar(.hidden, for: .windowToolbar)
        .ignoresSafeArea()
        .task {
            isLeaving = false
            historyModel.addHistory(room: room)
            await model.load()
        }
        .task(id: model.playback?.id) {
            let id = model.playback?.id
            while !Task.isCancelled, !isLeaving, model.playback?.id == id {
                controller.restoreIfPossible(model: model, onReady: playbackReady)
                if let sample = controller.timeSample(for: id) {
                    currentTime = sample.current.isFinite ? max(0, sample.current) : 0
                    duration = sample.duration.isFinite ? max(0, sample.duration) : 0
                    if !isSeeking {
                        seekValue = currentTime
                        if let id {
                            model.playbackReady(id: id, duration: sample.duration)
                            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
                        }
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
        .onChange(of: model.playback?.id) { _, _ in
            seekTask?.cancel()
            seekTask = nil
            seekPlaybackID = nil
            seekCommitInFlight = false
            isReady = false
            isPlaying = false
            currentTime = 0
            duration = 0
            seekValue = 0
            isSeeking = false
            // Preparation must not overwrite a pause restored when an episode panel closes.
            if showsEpisodes || isLeaving { controller.setDesiredPlayback(false) }
        }
        .onChange(of: isPlaying) { _, playing in
            updateSleepActivity(playing)
            revealControls()
        }
        .onChange(of: controlsHeld) { _, _ in revealControls() }
        .onChange(of: controller.wantsPlayback) { _, wantsPlayback in
            if !wantsPlayback { persistCurrentProgress() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistCurrentProgress() }
        }
        .onChange(of: model.progressWarning) { _, message in
            if let message { showFeedback(message) }
        }
        .overlay(alignment: .top) {
            if let toast = feedbackToast {
                ToastView(toast: toast).padding(.top, 48)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: feedbackToast)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            guard playerWindow?.isKeyWindow == true else { return }
            menuTrackingCount += 1
            revealControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            menuTrackingCount = max(0, menuTrackingCount - 1)
            revealControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === playerWindow else { return }
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persistCurrentProgress()
        }
        .onDisappear { cleanup() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard !showsEpisodes else { return .ignored }
            playerWindow?.toggleFullScreen(nil)
            return .handled
        }
        .onExitCommand {
            if showsEpisodes {
                closeEpisodes()
            } else if onExitFullscreen?() == true {
                // The destination serializes full-screen transitions before any close request.
            } else if onExitFullscreen == nil, let window = playerWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else {
                closePlayer()
            }
        }
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            Button(action: closePlayer) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .adaptiveGlassEffect(in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Keep the existing 36pt circle/alignment while the button itself remains 44pt.
            .padding(-4)
            .accessibilityLabel("关闭播放器")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(episodeText).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .adaptiveGlassEffect()
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                Button { playerWindow?.toggleFullScreen(nil) } label: { controlIcon("arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain)
                    .padding(-7)
                    .accessibilityLabel("切换全屏")
                settingsMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .adaptiveGlassEffect()
        }
        .foregroundStyle(.white)
        .frame(height: 44)
    }

    private var settingsMenu: some View {
        Menu {
            Picker("播放速度", selection: $playbackRate) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                    Text(rateLabel(rate)).tag(rate)
                }
            }
            Toggle("自动连播", isOn: Binding(get: { model.autoplay }, set: { model.autoplay = $0 }))
        } label: { controlIcon("gearshape") }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .padding(-7)
        .accessibilityLabel("播放设置")
        .help("播放设置")
    }

    @ViewBuilder private var statusContent: some View {
        if let error = model.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 32))
                Text(error).font(.body).multilineTextAlignment(.center)
                Button("重试") { retry() }.controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 480)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        } else if model.isLoading || (model.playback != nil && !isReady && !model.hasFinished) {
            VStack(spacing: 12) {
                ProgressView().fullUIArcLoadingStyle(size: 34, lineWidth: 1.5).tint(.white)
                Text("正在加载\(episodeText)…").font(.body)
            }
            .foregroundStyle(.white)
        } else if model.episodes.isEmpty {
            ContentUnavailableView("暂无可播放剧集", systemImage: "film", description: Text("可返回选择其他剧目。"))
        } else if !isPlaying {
            Button(action: togglePlayback) {
                Image(systemName: "play.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .adaptiveGlassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.hasFinished ? "重播本集" : "继续播放")
        }
    }

    private func bottomControls(availableWidth: CGFloat) -> some View {
        VStack(spacing: 12) {
            if let note = model.selectionNote { Text(note).font(.caption).foregroundStyle(.white.opacity(0.72)) }
            HStack(spacing: 12) {
                Text(timeLabel(isSeeking ? seekValue : currentTime))
                MacShortDramaSlider(
                    value: $seekValue, maximum: max(1, duration),
                    isEnabled: isSeekable && !seekCommitInFlight && !model.isLoading,
                    label: "播放进度", valueDescription: timeLabel(seekValue),
                    onEditingChanged: seekEditingChanged
                )
                .frame(height: 20)
                Text(timeLabel(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            MacShortDramaControlGroupsLayout(
                additionalPlaybackWidth: volumeIsExpanded ? 0 : volumeExpansionWidth(availableWidth: availableWidth)
            ) {
                HStack(spacing: 16) {
                    Button(action: togglePlayback) { controlIcon(isPlaying ? "pause.fill" : "play.fill") }
                        .padding(-7)
                        .keyboardShortcut(.space, modifiers: [])
                        .accessibilityLabel(model.hasFinished ? "重播本集" : isPlaying ? "暂停" : "播放")
                        .disabled(model.playback == nil && !model.hasFinished)
                    Button { adjacentEpisode(-1) } label: { controlIcon("backward.end.fill") }
                        .padding(-7)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                        .accessibilityLabel("上一集")
                        .disabled(!canMove(-1))
                    Button { adjacentEpisode(1) } label: { controlIcon("forward.end.fill") }
                        .padding(-7)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .accessibilityLabel("下一集")
                        .disabled(!canMove(1))
                    volumeControls(availableWidth: availableWidth)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .adaptiveGlassEffect()
                .fixedSize(horizontal: true, vertical: true)
                episodeButton
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .adaptiveGlassEffect()
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        // Shade the full window edge, including the controls' outer inset.
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    private func volumeControls(availableWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                if volume > 0 {
                    preMuteVolume = volume
                    volume = 0
                } else {
                    volume = preMuteVolume
                }
                revealControls()
            } label: {
                controlIcon(volume == 0 ? "speaker.slash.fill" : volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
            }
            .buttonStyle(.plain)
            .padding(-7)
            .accessibilityLabel(volume == 0 ? "取消静音" : "静音")
            if volumeIsExpanded {
                HStack(spacing: 8) {
                    MacShortDramaSlider(
                        value: Binding(get: { Double(volume) }, set: { volume = Float($0) }),
                        maximum: 1, isEnabled: true, label: "音量",
                        valueDescription: "\(Int(volume * 100))%",
                        onEditingChanged: { isAdjustingVolume = $0; revealControls() }
                    )
                    .frame(width: volumeSliderWidth(availableWidth: availableWidth), height: 20)
                    if availableWidth >= 352 {
                        Text("\(Int(volume * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { volumeHovered = hovering }
            revealControls()
        }
    }

    private var episodeButton: some View {
        Button(action: openEpisodes) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 18, weight: .semibold))
                Text("选集").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-7)
        .disabled(model.episodes.isEmpty)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            // Button padding removes only the 7pt hit-area allowance from layout; visible
            // glyphs remain centered in the existing 30pt control slots and capsule sizes.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func episodeOverlay(size: CGSize) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { closeEpisodes() }
                .accessibilityHidden(true)
            MacShortDramaEpisodesPanel(room: room, model: model, onSelect: selectEpisode, onClose: closeEpisodes)
                .frame(width: min(380, size.width))
                .padding(.vertical, 16)
                .padding(.trailing, min(16, max(0, size.width - 380)))
        }
    }

    private func controlsHoverChanged(_ hovering: Bool) {
        controlsHovered = hovering
        revealControls()
    }

    private func revealControls() {
        controlsRevealed = true
        hideControlsTask?.cancel()
        guard !controlsHeld, !isLeaving else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            guard !Task.isCancelled, !isLeaving, !controlsHeld else { return }
            controlsRevealed = false
        }
    }

    private func videoClicked() {
        let wasVisible = controlsVisible
        revealControls()
        if wasVisible, isReady, !model.isLoading, model.errorMessage == nil {
            togglePlayback()
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        operation?.cancel()
        operation = Task { @MainActor in
            guard !isLeaving else { return }
            await action()
        }
    }

    private func togglePlayback() {
        guard !showsEpisodes, !isSeeking else { return }
        revealControls()
        if model.hasFinished, let id = model.selectedEpisodeID {
            controller.setDesiredPlayback(true)
            run { await model.selectEpisode(id: id) }
        } else {
            controller.setDesiredPlayback(!controller.wantsPlayback)
        }
    }

    private func retry() {
        controller.setDesiredPlayback(true)
        run {
            if let id = model.selectedEpisodeID { await model.selectEpisode(id: id) }
            else { await model.load() }
        }
    }

    private func openEpisodes() {
        guard !showsEpisodes, !isSeeking else { return }
        resumeAfterPanel = controller.wantsPlayback
        controller.setDesiredPlayback(false)
        showsEpisodes = true
        updatePanelHold(true)
    }

    private func closeEpisodes() {
        guard showsEpisodes else { return }
        showsEpisodes = false
        let willAdvance = model.selectedEpisodeID.flatMap {
            ShortDramaCompletionPolicy.nextEpisode(in: model.episodes, after: $0, autoplay: model.autoplay)
        } != nil
        controller.setDesiredPlayback(
            resumeAfterPanel && (!model.hasFinished || willAdvance),
            applyImmediately: !model.hasFinished
        )
        updatePanelHold(false)
    }

    private func selectEpisode(_ id: String) {
        persistCurrentProgress()
        let changesPlayback = id != model.selectedEpisodeID || model.hasFinished || model.playback == nil
        showsEpisodes = false
        controller.setDesiredPlayback(changesPlayback || resumeAfterPanel)
        run {
            // Select first so a deferred EOF cannot advance past the explicitly chosen episode.
            await model.selectEpisode(id: id)
            guard !Task.isCancelled, !isLeaving, !showsEpisodes else { return }
            updatePanelHold(false)
        }
    }

    private func updatePanelHold(_ presented: Bool) {
        // Modal updates have their own ordered task; opening a panel never cancels episode preparation.
        let previous = panelHoldTask
        panelHoldTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled, !isLeaving else { return }
            await model.setEpisodesPresented(presented)
        }
    }

    private func canMove(_ offset: Int) -> Bool {
        guard let index = model.episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }) else { return false }
        return model.episodes.indices.contains(index + offset)
    }

    private func adjacentEpisode(_ offset: Int) {
        guard !showsEpisodes, !isSeeking else { return }
        revealControls()
        guard let index = model.episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }), canMove(offset) else { return }
        controller.setDesiredPlayback(true)
        persistCurrentProgress()
        let id = model.episodes[index + offset].id
        run { await model.selectEpisode(id: id) }
    }

    private func seekEditingChanged(_ editing: Bool) {
        if editing {
            guard !isSeeking, let id = model.playback?.id, isSeekable,
                  model.beginScrubbing(playbackID: id) else { return }
            seekPlaybackID = id
            resumeAfterSeek = controller.wantsPlayback && !model.hasFinished
            isSeeking = true
            controller.pause()
        } else {
            guard isSeeking, !seekCommitInFlight, let id = seekPlaybackID else { return }
            let target = min(max(0, seekValue), duration)
            let sampledDuration = duration
            let shouldResume = resumeAfterSeek
            seekCommitInFlight = true
            seekTask = Task { @MainActor in
                let succeeded = await controller.seek(to: target, playbackID: id)
                guard !Task.isCancelled, !isLeaving, model.playback?.id == id else { return }
                let canResume = shouldResume && !controller.playbackHasFailed(for: id)
                controller.setDesiredPlayback(canResume && !showsEpisodes, applyImmediately: false)
                // Core may select the next episode here. Its playback-ID change must not
                // cancel this task and, through it, the next episode's preparation request.
                seekTask = nil
                await model.completeScrubbing(
                    playbackID: id, targetTime: target, duration: sampledDuration,
                    seekSucceeded: succeeded, resumePlayback: canResume
                )
                guard !Task.isCancelled, !isLeaving, model.playback?.id == id else { return }
                if model.hasFinished { controller.pause() }
                seekTask = nil
                seekPlaybackID = nil
                seekCommitInFlight = false
                isSeeking = false
                if succeeded {
                    currentTime = target
                    seekValue = target
                } else {
                    seekValue = currentTime
                    showFeedback("未能调整播放进度，请重试")
                }
                if canResume, !showsEpisodes, !model.hasFinished { controller.play() }
                revealControls()
            }
        }
    }

    private func playbackReady(_ id: UUID) {
        guard model.playback?.id == id, !isLeaving else { return }
        model.playbackReady(id: id, duration: controller.timeSample(for: id)?.duration ?? 0)
        isReady = true
    }

    private func persistCurrentProgress() {
        if !isSeeking, let id = model.playback?.id, let sample = controller.timeSample(for: id) {
            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
        }
        model.flushProgress()
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        let toast = ToastMessage(icon: "exclamationmark.triangle.fill", message: message, type: .info)
        feedbackToast = toast
        feedbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if feedbackToast == toast { feedbackToast = nil }
        }
    }

    private func closePlayer() {
        // Release only after the owning destination or window actually leaves the screen.
        if let onClose { onClose() } else { dismiss() }
    }

    private func cleanup() {
        guard !isLeaving else { return }
        persistCurrentProgress()
        isLeaving = true
        seekTask?.cancel()
        seekTask = nil
        feedbackTask?.cancel()
        feedbackTask = nil
        feedbackToast = nil
        hideControlsTask?.cancel()
        hideControlsTask = nil
        operation?.cancel()
        operation = nil
        panelHoldTask?.cancel()
        panelHoldTask = nil
        model.cancel()
        controller.stop()
        playbackSession.invalidate()
        updateSleepActivity(false)
    }

    private func updateSleepActivity(_ playing: Bool) {
        if playing && !isLeaving && sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "短剧播放")
        } else if !playing || isLeaving {
            if let activity = sleepActivity { ProcessInfo.processInfo.endActivity(activity) }
            sleepActivity = nil
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }

    private func rateLabel(_ rate: Float) -> String { "\(rate.formatted(.number.precision(.fractionLength(0...2))))×" }
}

/// Keep the playback/volume group at the same bottom-left anchor during hover.
/// If both groups cannot fit, move only the episode picker above it instead of clipping controls.
private struct MacShortDramaControlGroupsLayout: Layout {
    // Reserve the expanded audio width when choosing rows so the episode target
    // stays put as the pointer moves between audio and episode controls.
    let additionalPlaybackWidth: CGFloat
    private let horizontalSpacing: CGFloat = 32
    private let verticalSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let playback = subviews[0].sizeThatFits(.unspecified)
        let episodes = subviews[1].sizeThatFits(.unspecified)
        let rowWidth = playback.width + additionalPlaybackWidth + horizontalSpacing + episodes.width
        let width = proposal.width ?? rowWidth
        let height = rowWidth <= width
            ? max(playback.height, episodes.height)
            : playback.height + verticalSpacing + episodes.height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let playback = subviews[0].sizeThatFits(.unspecified)
        let episodes = subviews[1].sizeThatFits(.unspecified)
        let fitsRow = playback.width + additionalPlaybackWidth + horizontalSpacing + episodes.width <= bounds.width
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - playback.height),
            proposal: ProposedViewSize(playback)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - episodes.width,
                        y: fitsRow ? bounds.maxY - episodes.height : bounds.minY),
            proposal: ProposedViewSize(episodes)
        )
    }
}

/// NSSlider matches the live player's compact white slider and keeps native keyboard/AX behavior.
/// Editing brackets both mouse tracking and single-step keyboard/accessibility actions.
private struct MacShortDramaSlider: NSViewRepresentable {
    @Binding var value: Double
    let maximum: Double
    let isEnabled: Bool
    let label: String
    let valueDescription: String
    let onEditingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> MacShortDramaNativeSlider {
        let slider = MacShortDramaNativeSlider(value: value, minValue: 0, maxValue: maximum,
                                              target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.sliderType = .linear
        slider.controlSize = .small
        slider.isContinuous = true
        slider.trackFillColor = .white.withAlphaComponent(0.8)
        return slider
    }

    func updateNSView(_ slider: MacShortDramaNativeSlider, context: Context) {
        context.coordinator.parent = self
        slider.maxValue = maximum
        if !slider.isTrackingEdit { slider.doubleValue = value }
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(label)
        slider.spokenValue = valueDescription
        slider.onEditingChanged = onEditingChanged
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MacShortDramaSlider
        init(_ parent: MacShortDramaSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: MacShortDramaNativeSlider) {
            let discreteEdit = !sender.isTrackingEdit
            if discreteEdit { parent.onEditingChanged(true) }
            parent.value = sender.doubleValue
            if discreteEdit { parent.onEditingChanged(false) }
        }
    }
}

private final class MacShortDramaNativeSlider: NSSlider {
    var isTrackingEdit = false
    var spokenValue = ""
    var onEditingChanged: ((Bool) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func accessibilityValueDescription() -> String? { spokenValue }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTrackingEdit = true
        onEditingChanged?(true)
        super.mouseDown(with: event)
        isTrackingEdit = false
        onEditingChanged?(false)
    }
}

private struct MacShortDramaInteractionArea: NSViewRepresentable {
    let onActivity: () -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> MacShortDramaInteractionNSView {
        MacShortDramaInteractionNSView()
    }

    func updateNSView(_ view: MacShortDramaInteractionNSView, context: Context) {
        view.onActivity = onActivity
        view.onClick = onClick
    }
}

private final class MacShortDramaInteractionNSView: NSView {
    var onActivity: (() -> Void)?
    var onClick: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var pointerDragged = false
    private weak var trackingWindow: NSWindow?
    private var previousAcceptsMouseMovedEvents: Bool?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let trackingWindow, let previousAcceptsMouseMovedEvents {
            trackingWindow.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        }
        trackingWindow = window
        previousAcceptsMouseMovedEvents = window?.acceptsMouseMovedEvents
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onActivity?() }
    override func mouseMoved(with event: NSEvent) { onActivity?() }
    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        pointerDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownLocation, !pointerDragged else { return }
        let point = event.locationInWindow
        guard hypot(point.x - origin.x, point.y - origin.y) >= 3 else { return }
        pointerDragged = true
        onActivity?()
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil; pointerDragged = false }
        guard mouseDownLocation != nil, !pointerDragged else { return }
        onClick?()
    }
}

private struct MacShortDramaEpisodesPanel: View {
    let room: LiveModel
    let model: ShortDramaPlaybackModel
    let onSelect: (String) -> Void
    let onClose: () -> Void
    @State private var browseGroupID: String?

    private struct GridPosition: Equatable {
        let groupID: String?
        let episodeIDs: [String]
        let width: CGFloat
    }

    init(room: LiveModel, model: ShortDramaPlaybackModel,
         onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.room = room
        self.model = model
        self.onSelect = onSelect
        self.onClose = onClose
        let groups = ShortDramaEpisodeGroup.make(from: model.episodes)
        _browseGroupID = State(initialValue: groups.first { $0.contains(episodeID: model.selectedEpisodeID) }?.id
            ?? groups.first?.id)
    }

    private var groups: [ShortDramaEpisodeGroup] { ShortDramaEpisodeGroup.make(from: model.episodes) }
    private var selectedGroup: ShortDramaEpisodeGroup? {
        groups.first { $0.id == browseGroupID }
            ?? groups.first { $0.contains(episodeID: model.selectedEpisodeID) }
            ?? groups.first
    }
    private var visibleEpisodes: [ShortDramaEpisode] { selectedGroup?.episodes ?? [] }
    private var scrollEpisodeID: String? {
        selectedGroup?.contains(episodeID: model.selectedEpisodeID) == true
            ? model.selectedEpisodeID : visibleEpisodes.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                PanelCloseButton(closesOnEscape: true, action: onClose).accessibilityLabel("关闭选集")
                VStack(alignment: .leading, spacing: 6) {
                    Text("选集").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    Text("可播 \(model.episodes.count) 集").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 12)
            }
            if groups.count > 1 {
                HStack(spacing: 8) {
                    Text("剧集区间").accessibilityHidden(true)
                    MacShortDramaGroupPicker(groups: groups, selection: Binding(
                        get: { selectedGroup?.id ?? "" },
                        set: { browseGroupID = $0 }
                    ))
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack(alignment: .top, spacing: 12) {
                                KFImage(URL(string: room.roomCover)).resizable().scaledToFill()
                                    .frame(width: 60, height: 84).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(room.roomTitle.isEmpty ? room.userName.orDash : room.roomTitle)
                                        .font(.headline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                                    if let name = model.selectedEpisode?.cdn.displayName, !name.isEmpty {
                                        Text(name).font(.caption).foregroundStyle(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                                ForEach(visibleEpisodes) { episode in
                                    let selected = episode.id == model.selectedEpisodeID
                                    Button { onSelect(episode.id) } label: {
                                        ZStack(alignment: .topTrailing) {
                                            Text("\(episode.number)")
                                                .font(.body.weight(selected ? .semibold : .regular))
                                                .frame(maxWidth: .infinity, minHeight: 48)
                                            if selected {
                                                Image(systemName: "play.fill").font(.system(size: 10)).padding(5)
                                            }
                                        }
                                        .foregroundStyle(.white)
                                        .background(.white.opacity(selected ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? .white : .white.opacity(0.08), lineWidth: selected ? 1.5 : 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .id(episode.id)
                                    .accessibilityLabel("第 \(episode.number) 集\(selected ? "，当前集" : "")")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .task(id: GridPosition(groupID: selectedGroup?.id,
                                           episodeIDs: visibleEpisodes.map(\.id), width: geometry.size.width)) {
                        // Browsing ranges and resizing reveal current or first within this range.
                        // Playback sampling and manual scrolling never change this key.
                        guard let id = scrollEpisodeID else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 24)
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .onChange(of: model.episodes.map(\.id)) { _, _ in
            guard !groups.contains(where: { $0.id == browseGroupID }) else { return }
            browseGroupID = groups.first { $0.contains(episodeID: model.selectedEpisodeID) }?.id
                ?? groups.first?.id
        }
    }
}

/// Keep the native popup's intrinsic bezel while making its surrounding row a 44pt target.
private struct MacShortDramaGroupPicker: NSViewRepresentable {
    let groups: [ShortDramaEpisodeGroup]
    @Binding var selection: String

    func makeNSView(context: Context) -> MacShortDramaGroupPickerView {
        MacShortDramaGroupPickerView()
    }

    func updateNSView(_ view: MacShortDramaGroupPickerView, context: Context) {
        view.onSelect = { selection = $0 }
        view.update(groups: groups, selectedID: selection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MacShortDramaGroupPickerView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

private final class MacShortDramaGroupPickerView: NSView {
    private let popup = MacShortDramaGroupPopUpButton(frame: .zero, pullsDown: false)
    var onSelect: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        popup.font = .systemFont(ofSize: 15, weight: .medium)
        popup.controlSize = .regular
        popup.autoenablesItems = false
        popup.setAccessibilityLabel("剧集区间")
        popup.target = self
        popup.action = #selector(selectionChanged)
        addSubview(popup)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: popup.intrinsicContentSize.width, height: 44)
    }

    override func layout() {
        super.layout()
        let height = popup.intrinsicContentSize.height
        popup.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    }

    func update(groups: [ShortDramaEpisodeGroup], selectedID: String) {
        let items = popup.itemArray
        if items.count != groups.count || zip(items, groups).contains(where: {
            $0.0.representedObject as? String != $0.1.id || $0.0.title != $0.1.title
        }) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.font = popup.font
            for group in groups {
                let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                item.representedObject = group.id
                menu.addItem(item)
            }
            popup.menu = menu
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        if popup.selectedItem?.representedObject as? String != selectedID {
            popup.select(popup.itemArray.first { $0.representedObject as? String == selectedID })
        }
    }

    // The child handles its normal bezel. Only clicks in this view's own padding
    // arrive here; NSView's hit testing confines the extension to the 44pt bounds.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(popup)
        popup.performClick(nil)
    }

    @objc private func selectionChanged() {
        guard let id = popup.selectedItem?.representedObject as? String else { return }
        onSelect?(id)
    }
}

private final class MacShortDramaGroupPopUpButton: NSPopUpButton {
    override func accessibilityFrame() -> NSRect {
        guard let superview, let window else { return super.accessibilityFrame() }
        return window.convertToScreen(superview.convert(superview.bounds, to: nil))
    }
}
#endif
