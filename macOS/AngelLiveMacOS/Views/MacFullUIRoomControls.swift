import AppKit
internal import AVFoundation
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
#if canImport(KSPlayer)
import KSPlayer
#endif

struct MacFullUIRoomControls: View {
    @Bindable var viewModel: RoomInfoViewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @Binding var volume: Float
    @Binding var isMuted: Bool
    @Binding var showVideoInfo: Bool
    @Binding var roomSwitcherVisible: Bool
    let window: NSWindow?
    let onClose: (() -> Void)?
    let onExitFullscreen: (() -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.macPlayerAcceptsCommands) private var acceptsCommands
    @Environment(AppFavoriteModel.self) private var favorites
    @Environment(ToastManager.self) private var toastManager: ToastManager?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var panel: Panel?
    @State private var showStreamer = false
    @State private var showDanmakuIssue = false
    @State private var volumeExpanded = false
    @State private var menusTracking = 0
    @State private var isFullscreen = false
    @State private var isPinned = false
    @State private var isFavoriteLoading = false
    @State private var isFavoriteAnimating = false
    @State private var closeDeadline: ContinuousClock.Instant?
    @State private var playerSettings = PlayerSettingModel()
    @State private var subtitleActivationID = UUID()
    @State private var duration = 0.0
    @State private var currentTime = 0.0
    @State private var targetTime = 0.0
    @State private var isScrubbing = false
    @State private var resumeAfterScrub = false
    @State private var seekRequestID: UUID?
    @State private var playbackID = UUID()
    @State private var playbackRate: Float = 1
    #if canImport(KSPlayer)
    @State private var seekPreview = SeekPreviewModel()
    #endif

    enum Panel: String, Identifiable {
        case danmaku, subtitles, languages, airPlay
        var id: Self { self }
    }

    private var room: LiveModel { viewModel.currentRoom }
    private var isFavorite: Bool { favorites.roomList.contains(room) }
    private var inset: CGFloat { MacPlayerChrome.inset(fullscreen: isFullscreen) }
    private var isOnDemand: Bool {
        #if canImport(KSPlayer)
        viewModel.isOnDemand
        #else
        false
        #endif
    }
    private var canSeek: Bool {
        #if canImport(KSPlayer)
        isOnDemand && duration > 0 && coordinator.playerLayer?.player.seekable == true
        #else
        false
        #endif
    }
    private var chromeVisible: Bool { controlsVisible && !isScrubbing }
    private var holdsControls: Bool {
        panel != nil || showStreamer || showDanmakuIssue || roomSwitcherVisible || showVideoInfo
            || volumeExpanded || menusTracking > 0 || voiceOverEnabled || isScrubbing || seekRequestID != nil
            || (viewModel.displayState == .playing && coordinator.state == .paused)
    }
    private var airPlayPlayer: AVPlayer? {
        #if canImport(KSPlayer)
        guard viewModel.isHLSStream, let source = coordinator.playerLayer?.player as? KSAVPlayer,
              source.player.allowsExternalPlayback else { return nil }
        return source.player
        #else
        return nil
        #endif
    }
    private var qualityTitle: String {
        let title = viewModel.currentPlayQualityString.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "清晰度") : title
    }

    var body: some View {
        #if canImport(KSPlayer)
        playerControls.macPlayerContrast(while: controlsVisible) { coordinator.playerLayer?.player }
        #else
        playerControls
        #endif
    }

    private var playerControls: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded { toggleFullscreen() }
                        .exclusively(before: TapGesture().onEnded { toggleControls() }))
                    .allowsHitTesting(viewModel.displayState != .error && !roomSwitcherVisible && !showVideoInfo && !isScrubbing)
                    .accessibilityHidden(true)
                if !isFullscreen {
                    WindowDragArea()
                        .frame(height: inset + MacPlayerChrome.controlSize)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityHidden(true)
                }
                VStack {
                    topRow(width: geometry.size.width)
                        .opacity(chromeVisible ? 1 : 0)
                        .animation(chromeAnimation, value: chromeVisible)
                        .allowsHitTesting(chromeVisible)
                        .accessibilityHidden(!chromeVisible)
                    Spacer(minLength: 0)
                    if isOnDemand {
                        onDemandBottom(width: geometry.size.width)
                    } else {
                        bottomRow(width: geometry.size.width)
                            .opacity(chromeVisible ? 1 : 0)
                            .animation(chromeAnimation, value: chromeVisible)
                    }
                }
                .padding(inset)
                .allowsHitTesting(controlsVisible && !roomSwitcherVisible && !showVideoInfo)
                .accessibilityHidden(!controlsVisible || roomSwitcherVisible || showVideoInfo)

                if !viewModel.isPlaying, viewModel.displayState == .playing, coordinator.state == .paused {
                    MacPlayerCenterPlayButton(title: "继续播放", action: togglePlayback)
                        .opacity(chromeVisible ? 1 : 0)
                        .animation(chromeAnimation, value: chromeVisible)
                        .allowsHitTesting(chromeVisible && !roomSwitcherVisible && !showVideoInfo)
                        .accessibilityHidden(!chromeVisible || roomSwitcherVisible || showVideoInfo)
                }

                if !isOnDemand {
                    MacPlayerDanmakuStatus(
                        status: viewModel.danmakuConnectionStatus,
                        controlsVisible: controlsVisible,
                        controlBottomInset: inset
                    )
                }
                #if canImport(KSPlayer)
                if isScrubbing {
                    MacPlayerScrubPreview(position: targetTime, duration: duration, state: seekPreview.state)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
                if showVideoInfo {
                    VideoSettingsPanel(
                        coordinator: coordinator, qualityTitle: qualityTitle,
                        streamURL: viewModel.currentPlayURL, isShowing: $showVideoInfo
                    )
                    .frame(width: min(380, geometry.size.width))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active: revealControls()
                case .ended:
                    hideTask?.cancel()
                    if !holdsControls { controlsVisible = false }
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background(PlayerCursorAutoHide(hideDelay: 3, keepsCursorVisible: holdsControls))
        .macPlayerWindowState(window) {
            isFullscreen = window?.styleMask.contains(.fullScreen) == true
            isPinned = window?.level == .floating
        }
        .focusedSceneValue(\.macPlayerCommands, acceptsCommands ? commandActions : nil)
        .macPlayerEscapeKey(isEnabled: acceptsCommands && menusTracking == 0, action: handleEscape)
        .onAppear { revealControls() }
        .onDisappear { hideTask?.cancel(); resetTimeline() }
        .onChange(of: holdsControls) { revealControls() }
        .onChange(of: room) { showStreamer = false; showDanmakuIssue = false }
        .onChange(of: viewModel.currentPlayURL) { resetTimeline() }
        .onChange(of: viewModel.danmakuConnectionIssue) {
            if viewModel.danmakuConnectionIssue == nil { showDanmakuIssue = false }
        }
        .onChange(of: viewModel.subtitlePlayback.activationID) {
            if panel == .languages { panel = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            if window?.isKeyWindow == true { menusTracking += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            menusTracking = max(0, menusTracking - 1)
        }
        .sheet(item: $panel) { selection in
            panelContent(selection).onExitCommand { panel = nil }
        }
        .task(id: closeDeadline) {
            guard let closeDeadline else { return }
            do { try await Task.sleep(until: closeDeadline, clock: .continuous) } catch { return }
            closePlayer()
        }
        .task(id: isOnDemand && controlsVisible) {
            guard isOnDemand, controlsVisible else { return }
            await sampleTimeline()
        }
    }

    private var commandActions: MacPlayerCommandActions {
        let canControlPlayback = !roomSwitcherVisible && !showVideoInfo && !showStreamer && !showDanmakuIssue
            && panel == nil && !isScrubbing && seekRequestID == nil
        let seek: ((Double) -> Void)? = canSeek ? { offset in seekBy(offset) } : nil
        return MacPlayerCommandActions(
            isPlaying: viewModel.isPlaying, isMuted: isMuted, isFullscreen: isFullscreen,
            togglePlayback: togglePlayback, toggleMute: toggleMute, toggleFullscreen: toggleFullscreen,
            changeVolume: { setVolume((isMuted ? 0 : volume) + $0) },
            seek: seek, escape: handleEscape, canControlPlayback: canControlPlayback
        )
    }

    private var chromeAnimation: Animation {
        MacPlayerChrome.visibilityAnimation(reduceMotion: reduceMotion)
    }

    private func topRow(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: MacPlayerChrome.topControlSpacing) {
            MacPlayerCloseButton(action: closePlayer)
            if isOnDemand {
                MacPlayerTitle(
                    title: room.roomTitle.isEmpty ? room.userName.orDash : room.roomTitle,
                    maximumWidth: width * MacPlayerChrome.titleWidthFraction
                )
            } else {
                Button { showStreamer = true } label: {
                    MacPlayerName(
                        room.userName.orDash, font: .systemFont(ofSize: 13, weight: .semibold),
                        maximumWidth: width * 0.46
                    )
                    .macPlayerTitleCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .help("查看主播信息")
                .popover(isPresented: $showStreamer, arrowEdge: .bottom) {
                    StreamerInfoPopover(room: room).environment(\.colorScheme, .light)
                }
            }
            Spacer(minLength: 0)
            MacPlayerGlassGroup {
                if isOnDemand {
                    #if canImport(KSPlayer)
                    if let layer = coordinator.playerLayer { MacPlayerSubtitlesMenu(layer: layer) }
                    #endif
                    settingsMenu
                } else {
                    Button { roomSwitcherVisible = true } label: { macPlayerIcon("rectangle.stack") }
                        .accessibilityLabel("快速换台")
                        .help("快速换台")
                }
                Button {
                    guard let window else { return }
                    isPinned.toggle()
                    window.level = isPinned ? .floating : .normal
                } label: { macPlayerIcon(isPinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(isPinned ? "取消置顶" : "置顶")
                    .help(isPinned ? "取消置顶" : "置顶")
                if !isOnDemand {
                    favoriteButton
                    settingsMenu
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func bottomRow(width: CGFloat) -> some View {
        let usableWidth = width - 2 * inset
        let qualityWidth: CGFloat = viewModel.currentRoomPlayArgs?.isEmpty == false ? 114 : 0
        let rightWidth = (viewModel.supportsDanmu ? 88.0 : 44.0) + qualityWidth
        let sliderRoom = usableWidth - rightWidth - 3 * MacPlayerChrome.controlSize - 24
        let includesPercentage = sliderRoom >= 80 + 64
        return HStack(spacing: 12) {
            MacPlayerGlassGroup {
                Button(action: togglePlayback) { macPlayerIcon(viewModel.isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(viewModel.isPlaying ? "暂停" : "播放")
                Button { viewModel.refreshPlayback() } label: { macPlayerIcon("arrow.counterclockwise") }
                    .accessibilityLabel("刷新")
                    .disabled(viewModel.isLoading)
                volumeControl(width: includesPercentage ? 80 : min(80, max(40, sliderRoom)), showsPercentage: includesPercentage)
            }
            .fixedSize()
            Spacer(minLength: 0)
            MacPlayerGlassGroup {
                if viewModel.supportsDanmu { danmakuButton }
                if let lines = viewModel.currentRoomPlayArgs, !lines.isEmpty { qualityMenu(lines) }
                fullscreenButton
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func onDemandBottom(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            if duration > 0 {
                MacPlayerProgressRow(
                    currentTime: seekRequestID != nil ? targetTime : currentTime, duration: duration,
                    position: Binding(get: { isScrubbing || seekRequestID != nil ? targetTime : currentTime }, set: updateScrub),
                    isScrubbing: isScrubbing, canSeek: canSeek && seekRequestID == nil,
                    onEditingChanged: seekEditingChanged, onCancel: cancelScrubbing, seekBy: seekBy
                )
                .padding(.bottom, MacPlayerProgressRow.buttonGap)
                .opacity(controlsVisible ? 1 : 0)
                .animation(chromeAnimation, value: controlsVisible)
            }
            HStack(spacing: 12) {
                MacPlayerGlassGroup {
                    Button(action: togglePlayback) { macPlayerIcon(viewModel.isPlaying ? "pause.fill" : "play.fill") }
                        .accessibilityLabel(viewModel.isPlaying ? "暂停" : "播放")
                    volumeControl(width: 80, showsPercentage: width >= 380)
                }
                .fixedSize()
                Spacer(minLength: 0)
                MacPlayerGlassGroup {
                    MacPlayerRateMenu(rate: $playbackRate)
                    fullscreenButton
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
            .opacity(chromeVisible ? 1 : 0)
            .animation(chromeAnimation, value: chromeVisible)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
        }
        .onChange(of: playbackRate) { coordinator.playerLayer?.player.playbackRate = playbackRate }
        .onChange(of: coordinator.state) {
            if coordinator.state == .readyToPlay { coordinator.playerLayer?.player.playbackRate = playbackRate }
        }
    }

    private func volumeControl(width: CGFloat, showsPercentage: Bool) -> some View {
        MacPlayerVolumeControl(
            volume: Binding(get: { isMuted ? 0 : volume }, set: setVolume),
            isMuted: isMuted, sliderWidth: width, showsPercentage: showsPercentage,
            toggleMute: toggleMute, onExpansionChanged: { volumeExpanded = $0 }
        )
    }

    private var fullscreenButton: some View {
        Button(action: toggleFullscreen) {
            macPlayerIcon(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityLabel(isFullscreen ? "退出全屏" : "进入全屏")
    }

    private var favoriteButton: some View {
        Button { Task { await toggleFavorite() } } label: {
            macPlayerIcon(isFavorite ? "heart.fill" : "heart", color: isFavorite ? .red : .white)
                .opacity(isFavoriteLoading ? 0.4 : 1)
        }
        .disabled(isFavoriteLoading)
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
        .help(isFavorite ? "取消收藏" : "收藏")
        .changeEffect(.spray(origin: .center) {
            Image(systemName: isFavorite ? "heart.fill" : "heart.slash.fill").foregroundStyle(.red)
        }, value: isFavoriteAnimating, isEnabled: !reduceMotion)
    }

    private var danmakuButton: some View {
        Button {
            if viewModel.danmakuConnectionIssue != nil { showDanmakuIssue = true }
            else { viewModel.toggleDanmuDisplay() }
        } label: {
            macPlayerIcon(viewModel.danmuSettings.showDanmu ? "captions.bubble.fill" : "captions.bubble")
                .overlay(alignment: .topTrailing) {
                    if viewModel.danmakuConnectionIssue != nil {
                        Circle().fill(.orange).frame(width: 5, height: 5).padding(9)
                    }
                }
        }
        .accessibilityLabel(viewModel.danmakuConnectionIssue == nil
            ? (viewModel.danmuSettings.showDanmu ? "隐藏弹幕" : "显示弹幕") : "弹幕连接状态")
        .popover(isPresented: $showDanmakuIssue) {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.danmakuConnectionIssue ?? "").font(.callout)
                Button(viewModel.danmuSettings.showDanmu ? "隐藏弹幕" : "显示弹幕") {
                    showDanmakuIssue = false
                    viewModel.toggleDanmuDisplay()
                }
            }
            .padding(16)
            .frame(width: 240)
        }
    }

    private func qualityMenu(_ lines: [LiveQualityModel]) -> some View {
        Menu {
            lineOptions(lines)
        } label: {
            MacPlayerName(qualityTitle, font: .systemFont(ofSize: 15, weight: .semibold), maximumWidth: 90)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("清晰度，\(qualityTitle)"))
    }

    @ViewBuilder
    private func lineOptions(_ lines: [LiveQualityModel]) -> some View {
        if lines.count == 1, let line = lines.first {
            qualityOptions(line, index: 0, lines: lines)
        } else {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let title = PlaybackDisplay.lineTitle(for: line, index: index)
                Menu(index == viewModel.currentCdnIndex ? "\(title)（当前）" : title) {
                    qualityOptions(line, index: index, lines: lines)
                }
            }
        }
    }

    private func qualityOptions(_ line: LiveQualityModel, index: Int, lines: [LiveQualityModel]) -> some View {
        ForEach(Array(line.qualitys.enumerated()), id: \.offset) { offset, quality in
            let title = PlaybackDisplay.qualityTitle(quality, in: lines)
            Button {
                viewModel.changePlayUrl(cdnIndex: index, urlIndex: offset, selectionOrigin: .user)
            } label: {
                if RoomPlaybackResolver.isLocked(quality) {
                    Label("\(title)（登录后可用）", systemImage: "lock.fill")
                } else if index == viewModel.currentCdnIndex, offset == viewModel.currentQualityIndex {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
        }
    }

    private var settingsMenu: some View {
        @Bindable var settings = playerSettings
        return Menu {
            Section("常用") {
                if !isOnDemand, viewModel.supportsDanmu {
                    Button { panel = .danmaku } label: { Label("弹幕", systemImage: "captions.bubble") }
                }
                if !isOnDemand {
                    Menu {
                        LiveSubtitleQuickControls(playback: viewModel.subtitlePlayback) {
                            subtitleActivationID = viewModel.subtitlePlayback.activationID
                            panel = .languages
                        }
                        Button("翻译与字幕设置…") { panel = .subtitles }
                    } label: {
                        Label("字幕与翻译", systemImage: "captions.bubble")
                    }
                }
                MacPlayerSleepTimerMenu(deadline: $closeDeadline)
            }
            if airPlayPlayer != nil {
                Section("投屏") {
                    Menu {
                        Button("AirPlay 投屏…") { panel = .airPlay }
                    } label: {
                        Label("投屏", systemImage: "airplay.video")
                    }
                }
            }
            Section("更多") {
                Menu {
                    if isOnDemand, let lines = viewModel.currentRoomPlayArgs, !lines.isEmpty {
                        Menu("清晰度") { lineOptions(lines) }
                    }
                    Picker("默认画质", selection: $settings.defaultPlaybackQuality) {
                        ForEach(DefaultPlaybackQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("播放设置", systemImage: "slider.horizontal.3")
                }
                Button { showVideoInfo = true } label: { Label("视频信息", systemImage: "info.circle") }
            }
        } label: { macPlayerIcon("gearshape") }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .accessibilityLabel("播放器设置")
            .help("播放器设置")
    }

    @ViewBuilder
    private func panelContent(_ panel: Panel) -> some View {
        switch panel {
        case .danmaku:
            DanmakuSettingsPanel(viewModel: viewModel)
        case .subtitles:
            NavigationStack {
                TranslationSettingView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { self.panel = nil }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 480)
        case .languages:
            LiveSubtitleLanguageSelectionSheet(playback: viewModel.subtitlePlayback, activationID: subtitleActivationID)
        case .airPlay:
            MacPlayerAirPlaySheet(player: airPlayPlayer)
        }
    }

    private func toggleControls() {
        guard !holdsControls else { return }
        if controlsVisible {
            hideTask?.cancel()
            controlsVisible = false
        } else {
            revealControls()
        }
    }

    private func sampleTimeline() async {
        #if canImport(KSPlayer)
        while !Task.isCancelled {
            if !isScrubbing, seekRequestID == nil, let player = coordinator.playerLayer?.player {
                let total = player.duration
                let position = player.currentPlaybackTime
                duration = total.isFinite ? max(0, total) : 0
                currentTime = position.isFinite ? min(duration, max(0, position)) : 0
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
        #endif
    }

    private func resetTimeline() {
        playbackID = UUID()
        seekRequestID = nil
        isScrubbing = false
        duration = 0
        currentTime = 0
        targetTime = 0
        #if canImport(KSPlayer)
        seekPreview.cancel()
        #endif
    }

    private func updateScrub(_ value: Double) {
        guard isScrubbing else { return }
        targetTime = value
        #if canImport(KSPlayer)
        if let url = viewModel.currentPlayURL,
           let selection = RoomPlaybackResolver.selection(
               in: viewModel.currentRoomPlayArgs,
               cdnIndex: viewModel.currentCdnIndex,
               qualityIndex: viewModel.currentQualityIndex
           ) {
            seekPreview.update(id: playbackID, url: url, quality: selection.quality, targetTime: value)
        }
        #endif
    }

    private func seekEditingChanged(_ editing: Bool) {
        #if canImport(KSPlayer)
        guard let layer = coordinator.playerLayer else { return }
        if editing {
            guard canSeek, seekRequestID == nil, !isScrubbing else { return }
            isScrubbing = true
            targetTime = currentTime
            resumeAfterScrub = layer.player.isPlaying
            if resumeAfterScrub { layer.pause() }
        } else {
            guard isScrubbing else { return }
            isScrubbing = false
            seekPreview.endScrubbing()
            commitSeek(targetTime, layer: layer, resume: resumeAfterScrub)
        }
        #endif
    }

    private func seekBy(_ offset: Double) {
        #if canImport(KSPlayer)
        guard canSeek, seekRequestID == nil, !isScrubbing, let layer = coordinator.playerLayer else { return }
        let target = min(duration, max(0, currentTime + offset))
        guard target != currentTime else { return }
        commitSeek(target, layer: layer, resume: layer.player.isPlaying)
        #endif
    }

    private func cancelScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        #if canImport(KSPlayer)
        seekPreview.endScrubbing()
        #endif
        if resumeAfterScrub { coordinator.playerLayer?.play() }
        revealControls()
    }

    #if canImport(KSPlayer)
    private func commitSeek(_ target: Double, layer: KSPlayerLayer, resume: Bool) {
        let requestID = UUID()
        targetTime = target
        revealControls()
        seekRequestID = requestID
        layer.player.seek(time: target) { [weak layer] didSeek in
            guard seekRequestID == requestID else { return }
            seekRequestID = nil
            guard let layer, coordinator.playerLayer === layer else { return }
            if didSeek { currentTime = target }
            else {
                toastManager?.show(icon: "exclamationmark.triangle", message: "未能调整播放进度，请重试", type: .info)
            }
            if resume { layer.play() }
            revealControls()
        }
    }
    #endif

    private func revealControls() {
        controlsVisible = true
        hideTask?.cancel()
        guard !holdsControls else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            controlsVisible = false
        }
    }

    private func togglePlayback() {
        guard !isScrubbing, seekRequestID == nil else { return }
        if viewModel.isPlaying { coordinator.playerLayer?.pause() }
        else { coordinator.playerLayer?.play() }
        revealControls()
    }

    private func toggleFullscreen() {
        window?.toggleFullScreen(nil)
        revealControls()
    }

    private func handleEscape() {
        if panel != nil { panel = nil }
        else if showStreamer { showStreamer = false }
        else if showDanmakuIssue { showDanmakuIssue = false }
        else if roomSwitcherVisible { roomSwitcherVisible = false }
        else if showVideoInfo { showVideoInfo = false }
        else if isScrubbing { cancelScrubbing() }
        else if onExitFullscreen?() == true { return }
        else if isFullscreen { toggleFullscreen() }
        else { closePlayer() }
    }

    private func setVolume(_ value: Float) {
        volume = min(1, max(0, value))
        if volume > 0 { isMuted = false }
        applyVolume()
    }

    private func toggleMute() {
        isMuted.toggle()
        if !isMuted && volume == 0 { volume = 1 }
        applyVolume()
    }

    private func applyVolume() {
        coordinator.playerLayer?.player.isMuted = isMuted
        coordinator.playerLayer?.player.playbackVolume = volume
        revealControls()
    }

    private func closePlayer() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func toggleFavorite() async {
        guard !isFavoriteLoading else { return }
        let target = room
        let wasFavorite = isFavorite
        isFavoriteLoading = true
        defer { isFavoriteLoading = false }
        do {
            if wasFavorite { try await favorites.removeFavoriteRoom(room: target) }
            else { try await favorites.addFavorite(room: target) }
            if target == room { isFavoriteAnimating.toggle() }
            toastManager?.show(
                icon: wasFavorite ? "heart.slash.fill" : "heart.fill",
                message: wasFavorite ? "已取消收藏" : "收藏成功", type: wasFavorite ? .info : .success
            )
        } catch {
            toastManager?.show(
                icon: "xmark.circle.fill",
                message: "收藏操作失败：\(FavoriteService.formatErrorCode(error: error))", type: .error
            )
        }
    }
}
