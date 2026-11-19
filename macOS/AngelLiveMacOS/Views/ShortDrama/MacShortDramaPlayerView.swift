#if canImport(KSPlayer)
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import KSPlayerUI
import AppKit
import Kingfisher
import SharedAssets
internal import AVFoundation

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
    @State private var seekPreview = SeekPreviewModel()
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
    @State private var volumeExpanded = false
    @State private var isFullscreen = false
    @State private var isPinned = false
    @State private var showVideoInfo = false
    @State private var showAirPlay = false
    @State private var closeDeadline: ContinuousClock.Instant?
    @State private var preMuteVolume: Float = 1
    @State private var menuTrackingCount = 0
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var pointerOverControls = false
    @State private var bottomControlsFrame = CGRect.null
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macPlayerAcceptsCommands) private var acceptsCommands
    @Environment(\.scenePhase) private var scenePhase

    init(room: LiveModel, onClose: (@MainActor () -> Void)? = nil, onExitFullscreen: (@MainActor () -> Bool)? = nil) {
        self.room = room
        self.onClose = onClose
        self.onExitFullscreen = onExitFullscreen
        _model = State(initialValue: ShortDramaPlaybackModel(room: room))
    }

    private var title: String { room.roomTitle.isEmpty ? room.userName.orDash : room.roomTitle }
    private var episodeText: String { model.selectedEpisode?.title.orDash ?? "分集播放" }
    private var episodeSubtitle: LocalizedStringResource? {
        guard let episode = model.selectedEpisode else { return nil }
        let number = episode.number
        let separator = " · "
        var titleComponents = episode.quality.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: separator)[...]
        if titleComponents.first == "选集" {
            titleComponents = titleComponents.dropFirst()
        }
        if titleComponents.first == "第\(number)集" || titleComponents.first == "第 \(number) 集" {
            titleComponents = titleComponents.dropFirst()
        }
        let name = titleComponents.joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "第 \(number) 集" }
        return "第 \(number) 集 · \(name)"
    }

    private var isSeekable: Bool { controller.isSeekable(for: model.playback?.id) }
    private var isScrubbing: Bool { isSeeking && !seekCommitInFlight }
    private var inset: CGFloat { MacPlayerChrome.inset(fullscreen: isFullscreen) }
    private var chromeVisible: Bool { controlsVisible && !isScrubbing }
    private var playerLayer: KSPlayerLayer? { controller.coordinator?.playerLayer }
    private var airPlayPlayer: AVPlayer? {
        guard let quality = model.playback?.quality, RoomPlaybackResolver.isHLSQuality(quality),
              let source = playerLayer?.player as? KSAVPlayer, source.player.allowsExternalPlayback else {
            return nil
        }
        return source.player
    }
    private var isPaused: Bool { isReady && playerLayer?.state == .paused }

    private var controlsHeld: Bool {
        !isReady || model.isLoading || model.errorMessage != nil || model.hasFinished
            || isSeeking || volumeExpanded || showsEpisodes || showVideoInfo || showAirPlay
            || menuTrackingCount > 0 || voiceOverEnabled || isPaused
    }
    private var controlsVisible: Bool { controlsRevealed || controlsHeld }

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
                .allowsHitTesting(!showsEpisodes && !showVideoInfo && !isScrubbing)
                    .accessibilityHidden(true)
                if !isFullscreen {
                    WindowDragArea()
                        .frame(height: inset + MacPlayerChrome.controlSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(!showsEpisodes && !showVideoInfo && !isScrubbing)
                        .accessibilityHidden(true)
                }
                VStack {
                    topControls(width: geometry.size.width)
                        .opacity(chromeVisible ? 1 : 0)
                        .animation(chromeAnimation, value: chromeVisible)
                        .allowsHitTesting(chromeVisible)
                        .accessibilityHidden(!chromeVisible)
                    Spacer(minLength: 16)
                    bottomControls(availableWidth: geometry.size.width - 2 * inset)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MacPlayerChrome.hoverSpace)) } action: {
                            bottomControlsFrame = $0
                        }
                }
                .padding(inset)
                .allowsHitTesting(controlsVisible && !showsEpisodes && !showVideoInfo)
                .accessibilityHidden(showsEpisodes || showVideoInfo || !controlsVisible)
                statusContent
                    .padding(.horizontal, inset)
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(chromeAnimation, value: chromeVisible)
                    .allowsHitTesting(chromeVisible && !showsEpisodes && !showVideoInfo)
                    .accessibilityHidden(showsEpisodes || showVideoInfo || !chromeVisible)
                if isScrubbing {
                    MacPlayerScrubPreview(position: seekValue, duration: duration, state: seekPreview.state)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if showsEpisodes {
                    episodeOverlay(size: geometry.size)
                }
                if showVideoInfo, let coordinator = controller.coordinator {
                    VideoSettingsPanel(
                        coordinator: coordinator, qualityTitle: model.playback?.quality.title,
                        streamURL: model.playback?.url, isShowing: $showVideoInfo
                    )
                    .frame(width: min(380, geometry.size.width))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .coordinateSpace(name: MacPlayerChrome.hoverSpace)
            .onContinuousHover(coordinateSpace: .named(MacPlayerChrome.hoverSpace)) { phase in
                switch phase {
                case .active(let point):
                    pointerOverControls = MacPlayerChrome.isPointerOverControls(
                        point, inset: inset, bottomFrame: bottomControlsFrame
                    )
                    revealControls()
                case .ended:
                    guard pointerOverControls else { return }
                    pointerOverControls = false
                    revealControls()
                }
            }
        }
        .macPlayerContrast(while: controlsVisible) { playerLayer?.player }
        .background(PlayerWindowReferenceView(window: $playerWindow))
        .background(PlayerCursorAutoHide(hideDelay: 3, keepsCursorVisible: controlsHeld || pointerOverControls))
        .macPlayerWindowState(playerWindow) {
            isFullscreen = playerWindow?.styleMask.contains(.fullScreen) == true
            isPinned = playerWindow?.level == .floating
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(title)
        .toolbar(.hidden, for: .windowToolbar)
        .ignoresSafeArea()
        .task {
            isLeaving = false
            await model.load()
        }
        .task(id: closeDeadline) {
            guard let closeDeadline else { return }
            do { try await Task.sleep(until: closeDeadline, clock: .continuous) } catch { return }
            closePlayer()
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
            seekPreview.cancel()
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
        .onChange(of: seekValue) {
            if isScrubbing, let playback = model.playback {
                seekPreview.update(id: playback.id, url: playback.url, quality: playback.quality, targetTime: seekValue)
            }
        }
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
        .sheet(isPresented: $showAirPlay) {
            MacPlayerAirPlaySheet(player: airPlayPlayer)
                .onExitCommand { showAirPlay = false }
        }
        .focusable()
        .focusEffectDisabled()
        .focusedSceneValue(\.macPlayerCommands, acceptsCommands ? commandActions : nil)
        .onKeyPress(.return) {
            guard commandActions.canControlPlayback else { return .ignored }
            toggleFullscreen()
            return .handled
        }
        .macPlayerEscapeKey(isEnabled: acceptsCommands && menuTrackingCount == 0, action: handleEscape)
    }

    private var commandActions: MacPlayerCommandActions {
        let canControlPlayback = !showsEpisodes && !showVideoInfo && !showAirPlay && !isSeeking
        let seek: ((Double) -> Void)? = isSeekable ? { offset in seekBy(offset) } : nil
        return MacPlayerCommandActions(
            isPlaying: isPlaying, isMuted: volume == 0, isFullscreen: isFullscreen,
            togglePlayback: togglePlayback, toggleMute: toggleMute, toggleFullscreen: toggleFullscreen,
            changeVolume: { volume = min(1, max(0, volume + $0)); revealControls() },
            seek: seek, escape: handleEscape, canControlPlayback: canControlPlayback
        )
    }

    private var chromeAnimation: Animation {
        MacPlayerChrome.visibilityAnimation(reduceMotion: reduceMotion)
    }

    private func topControls(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: MacPlayerChrome.topControlSpacing) {
            MacPlayerCloseButton(action: closePlayer)
            MacPlayerTitle(
                title: title,
                subtitle: episodeSubtitle,
                maximumWidth: width * MacPlayerChrome.titleWidthFraction
            )
            Spacer(minLength: 0)
            MacPlayerGlassGroup {
                if let playerLayer { MacPlayerSubtitlesMenu(layer: playerLayer) }
                settingsMenu
                Button {
                    guard let playerWindow else { return }
                    isPinned.toggle()
                    playerWindow.level = isPinned ? .floating : .normal
                } label: { macPlayerIcon(isPinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(isPinned ? "取消置顶" : "置顶")
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .foregroundStyle(.white)
        .frame(height: MacPlayerChrome.controlSize)
    }

    private var settingsMenu: some View {
        Menu {
            Section("常用") {
                MacPlayerSleepTimerMenu(deadline: $closeDeadline)
            }
            if airPlayPlayer != nil {
                Section("投屏") {
                    Button { showAirPlay = true } label: { Label("投屏", systemImage: "airplay.video") }
                }
            }
            Section("更多") {
                Menu {
                    Toggle("自动连播", isOn: Binding(get: { model.autoplay }, set: { model.autoplay = $0 }))
                } label: {
                    Label("播放设置", systemImage: "slider.horizontal.3")
                }
                Button("视频信息") { showVideoInfo = true }.disabled(playerLayer == nil)
            }
        } label: { macPlayerIcon("gearshape") }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
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
            MacPlayerCenterPlayButton(title: model.hasFinished ? "重播本集" : "继续播放", action: togglePlayback)
        }
    }

    private func bottomControls(availableWidth: CGFloat) -> some View {
        let showsPercentage = availableWidth >= 400
        let sliderWidth: CGFloat = min(80, max(40, availableWidth - 200))
        let expandedWidth = sliderWidth + (showsPercentage ? 64 : 12)
        return VStack(spacing: 0) {
            if let note = model.selectionNote {
                Text(note).font(.caption).macPlayerMediaText()
                    .padding(.bottom, 8)
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(chromeAnimation, value: chromeVisible)
                    .accessibilityHidden(!chromeVisible)
            }
            if duration > 0 {
                MacPlayerProgressRow(
                    currentTime: seekCommitInFlight ? seekValue : currentTime, duration: duration,
                    position: Binding(get: { isSeeking ? seekValue : currentTime }, set: {
                        if isSeeking && !seekCommitInFlight { seekValue = $0 }
                    }),
                    isScrubbing: isScrubbing, canSeek: isSeekable && !seekCommitInFlight && !model.isLoading,
                    onEditingChanged: seekEditingChanged, onCancel: cancelScrubbing, seekBy: seekBy
                )
                    .padding(.bottom, MacPlayerProgressRow.buttonGap)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(chromeAnimation, value: controlsVisible)
            }
            MacShortDramaControlGroupsLayout(
                additionalPlaybackWidth: volumeExpanded ? 0 : expandedWidth
            ) {
                MacPlayerGlassGroup {
                    Button(action: togglePlayback) { macPlayerIcon(isPlaying ? "pause.fill" : "play.fill") }
                        .accessibilityLabel(model.hasFinished ? "重播本集" : isPlaying ? "暂停" : "播放")
                        .disabled(model.playback == nil && !model.hasFinished)
                    Button { adjacentEpisode(-1) } label: { macPlayerIcon("backward.end.fill") }
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                        .accessibilityLabel("上一集")
                        .disabled(!canMove(-1))
                    Button { adjacentEpisode(1) } label: { macPlayerIcon("forward.end.fill") }
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .accessibilityLabel("下一集")
                        .disabled(!canMove(1))
                    MacPlayerVolumeControl(
                        volume: $volume, isMuted: volume == 0, sliderWidth: sliderWidth, showsPercentage: showsPercentage,
                        toggleMute: toggleMute, onExpansionChanged: { volumeExpanded = $0 }
                    )
                }
                .fixedSize()
                MacPlayerGlassGroup {
                    Button(action: openEpisodes) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet").font(MacPlayerChrome.symbolFont)
                            Text("选集").font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: MacPlayerChrome.controlSize)
                        .contentShape(Rectangle())
                    }
                    .disabled(model.episodes.isEmpty)
                    MacPlayerRateMenu(rate: $playbackRate)
                    Button(action: toggleFullscreen) {
                        macPlayerIcon(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(isFullscreen ? "退出全屏" : "进入全屏")
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
            .opacity(chromeVisible ? 1 : 0)
            .animation(chromeAnimation, value: chromeVisible)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
        }
        .foregroundStyle(.white)
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

    private func revealControls() {
        controlsRevealed = true
        hideControlsTask?.cancel()
        guard !controlsHeld, !pointerOverControls, !isLeaving else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, !isLeaving, !controlsHeld else { return }
            controlsRevealed = false
        }
    }

    private func videoClicked() {
        guard !controlsHeld else { return }
        if controlsVisible {
            hideControlsTask?.cancel()
            controlsRevealed = false
        } else { revealControls() }
    }

    private func toggleFullscreen() {
        playerWindow?.toggleFullScreen(nil)
        revealControls()
    }

    private func handleEscape() {
        if showAirPlay { showAirPlay = false }
        else if showVideoInfo { showVideoInfo = false }
        else if showsEpisodes { closeEpisodes() }
        else if isScrubbing { cancelScrubbing() }
        else if onExitFullscreen?() == true { return }
        else if isFullscreen { toggleFullscreen() }
        else { closePlayer() }
    }

    private func toggleMute() {
        if volume > 0 {
            preMuteVolume = volume
            volume = 0
        } else {
            volume = preMuteVolume
        }
        revealControls()
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
            seekPreview.endScrubbing()
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

    private func seekBy(_ offset: Double) {
        let target = min(duration, max(0, currentTime + offset))
        guard target != currentTime else { return }
        revealControls()
        seekEditingChanged(true)
        guard isSeeking else { return }
        seekValue = target
        seekEditingChanged(false)
    }

    private func cancelScrubbing() {
        guard isScrubbing, let id = seekPlaybackID else { return }
        seekCommitInFlight = true
        seekPreview.endScrubbing()
        let shouldResume = resumeAfterSeek
        let sampledDuration = duration
        seekValue = currentTime
        seekTask = Task { @MainActor in
            controller.setDesiredPlayback(shouldResume, applyImmediately: false)
            seekTask = nil
            await model.completeScrubbing(
                playbackID: id, targetTime: nil, duration: sampledDuration,
                seekSucceeded: false, resumePlayback: shouldResume
            )
            guard !Task.isCancelled, !isLeaving, model.playback?.id == id else { return }
            seekPlaybackID = nil
            seekCommitInFlight = false
            isSeeking = false
            if shouldResume, !model.hasFinished { controller.play() }
            revealControls()
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
        seekPreview.cancel()
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

}

/// Keep the playback/volume group at the same bottom-left anchor during hover.
/// If both groups cannot fit, move only the episode picker above it instead of clipping controls.
private struct MacShortDramaControlGroupsLayout: Layout {
    // Reserve the expanded audio width when choosing rows so the episode target
    // stays put as the pointer moves between audio and episode controls.
    let additionalPlaybackWidth: CGFloat
    private let horizontalSpacing: CGFloat = 12
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
