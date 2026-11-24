#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import AppKit
internal import AVFoundation
import KSPlayer
import SharedAssets
import SwiftUI

struct MacVodPlayerView: View {
    let model: VodPlaybackModel
    let episode: VodEpisode
    let sourceID: String?
    let onReturn: () -> Void
    let onClose: () -> Void
    let onExitFullscreen: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.macPlayerAcceptsCommands) private var acceptsCommands
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var hasKeyboardFocus: Bool

    @State private var controller = KSOnDemandPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(role: .primary, supportedGlobalCapabilities: [.audioFocus])
    @AppStorage(GeneralSettingModel.globalVodAutoplay, store: .shared) private var autoplayEnabled = true
    @State private var playbackStatus = KSOnDemandPlayerController.PlaybackStatus.preparing
    @State private var pictureMode = MacVodPictureMode.fit
    @State private var playbackRate: Float = 1
    @State private var volume: Float = 1
    @State private var preMuteVolume: Float = 1
    @State private var volumeHovered = false
    @State private var volumeEditing = false
    private var volumeExpanded: Bool { volumeHovered || volumeEditing || voiceOverEnabled }
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var seek: Scrub?
    @State private var seekCommitInFlight = false
    @State private var seekTask: Task<Void, Never>?
    @State private var seekPreview = SeekPreviewModel()
    @State private var operation: Task<Void, Never>?
    @State private var isLeaving = false
    @State private var notice: String?
    @State private var noticeRevision = 0
    @State private var drawer: MacVodPlayerDrawer.Kind?
    @State private var showVideoInfo = false
    @State private var showAirPlay = false
    @State private var closeDeadline: ContinuousClock.Instant?
    @State private var menuDepth = 0
    @State private var playerWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var originalWindowLevel: NSWindow.Level?
    @State private var controlsRevealed = true
    @State private var pointerOverControls = false
    @State private var bottomFrame = CGRect.null
    @State private var hideTask: Task<Void, Never>?
    @State private var sleepActivity: NSObjectProtocol?
    @State private var countdown = 8
    @State private var creditsHeight: CGFloat = 0

    private struct Scrub {
        let id: UUID
        let duration: Double
        let resume: Bool
        var target: Double
    }

    private enum PlaybackError: Error {
        case restorationFailed
    }

    private let inset = MacPlayerChrome.inset
    private let controlHeight: CGFloat = 34
    private var isSeries: Bool { model.detail?.kind == .series }
    private var isPlaying: Bool { playbackStatus.isPlaying && !model.hasFinished }
    private var isScrubbing: Bool { seek != nil && !seekCommitInFlight }
    private var canSeek: Bool { duration > 0 && controller.isSeekable(for: model.playback?.id) }
    private var hasPanel: Bool { drawer != nil || showVideoInfo || showAirPlay }
    private var overlayHold: Bool { hasPanel || menuDepth > 0 || scenePhase != .active }
    private var errorMessage: String? {
        model.errorMessage ?? (model.playback.map { controller.isRestoring(for: $0.id) } == true ? model.selectionNote : nil)
    }
    private var isLoading: Bool {
        guard errorMessage == nil else { return false }
        return model.playback == nil || playbackStatus.isPreparing
    }
    private var holdsControls: Bool {
        !isPlaying || isLoading || errorMessage != nil || model.hasFinished
            || seek != nil || volumeExpanded || overlayHold || voiceOverEnabled
    }
    private var controlsVisible: Bool { controlsRevealed || holdsControls }
    private var chromeVisible: Bool { controlsVisible && !isScrubbing }
    private var countdownOffer: VodCreditsOffer? {
        guard !overlayHold, seek == nil, !isLoading, autoplayEnabled else { return nil }
        return model.creditsOffer
    }
    private var airPlayPlayer: AVPlayer? {
        guard let quality = model.playback?.quality, RoomPlaybackResolver.isHLSQuality(quality),
              let source = controller.coordinator?.playerLayer?.player as? KSAVPlayer,
              source.player.allowsExternalPlayback else { return nil }
        return source.player
    }

    var body: some View {
        let content = viewport
            .background(MacFullUIWindowProbe(window: $playerWindow))
            .background(PlayerCursorAutoHide(hideDelay: 3, keepsCursorVisible: holdsControls
                                              || pointerOverControls || countdownOffer != nil))
            .macPlayerWindowState(playerWindow) {
                isFullscreen = playerWindow?.styleMask.contains(.fullScreen) == true
            }
            .onChange(of: playerWindow) { oldWindow, _ in
                if let originalWindowLevel { oldWindow?.level = originalWindowLevel }
                originalWindowLevel = nil
            }
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .windowToolbar)
            .ignoresSafeArea()
        return keyboard(lifecycle(content))
    }

    private var viewport: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let playback = model.playback {
                    MacVodPlayerSurface(playback: playback, model: model, controller: controller,
                                        playbackSession: playbackSession, rate: playbackRate, volume: volume,
                                        pictureMode: pictureMode, hidesSubtitles: seek != nil,
                                        subtitleBottomOffset: subtitleBottomOffset(in: geometry.size), onState: refreshPlaybackStatus)
                    .id(playback.id)
                }
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: togglePlayback)
                    .allowsHitTesting(!hasPanel && seek == nil)
                    .accessibilityHidden(true)
                if !isFullscreen {
                    WindowDragArea()
                        .frame(height: inset + controlHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(!hasPanel && seek == nil)
                        .accessibilityHidden(true)
                }
                chrome(size: geometry.size)
                    .allowsHitTesting(!hasPanel)
                    .accessibilityHidden(hasPanel)
                if !hasPanel, seek == nil, chromeVisible { status }
                if isScrubbing, let seek {
                    MacPlayerScrubPreview(position: seek.target, duration: seek.duration, state: seekPreview.state)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let countdownOffer { creditsCard(countdownOffer, size: geometry.size) }
                panels(size: geometry.size)
            }
            .coordinateSpace(name: MacPlayerChrome.hoverSpace)
            .onContinuousHover(coordinateSpace: .named(MacPlayerChrome.hoverSpace)) { phase in
                switch phase {
                case .active(let point):
                    pointerOverControls = (0..<(inset + controlHeight)).contains(point.y) || bottomFrame.contains(point)
                case .ended: pointerOverControls = false
                }
                revealControls()
            }
        }
    }

    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
            .task { await model.selectEpisode(id: episode.id, sourceID: sourceID) }
            .task(id: model.playback?.id) { await samplePlayback(id: model.playback?.id) }
            .task(id: overlayHold) {
                guard !Task.isCancelled, !isLeaving else { return }
                await model.setOverlayHoldPresented(overlayHold)
            }
            .task(id: countdownOffer) { await countDown() }
            .task(id: closeDeadline) {
                guard let closeDeadline else { return }
                do { try await Task.sleep(until: closeDeadline, clock: .continuous) } catch { return }
                cleanup()
                onClose()
            }
            .task(id: noticeRevision) {
                guard notice != nil else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                notice = nil
            }
            .onChange(of: model.playback?.id) {
                seekTask?.cancel()
                seekTask = nil
                seek = nil
                seekCommitInFlight = false
                seekPreview.cancel()
                refreshPlaybackStatus()
                currentTime = 0
                duration = 0
                countdown = 8
            }
            .onChange(of: model.progressWarning) { _, message in
                if let message { showNotice(message) }
            }
            .onChange(of: model.selectionNote) { _, message in
                if let message, !model.hasFinished { showNotice(message) }
            }
            .onChange(of: isPlaying, initial: true) { _, playing in
                updateSleepActivity(playing)
                revealControls()
            }
            .onChange(of: holdsControls) { revealControls() }
            .onChange(of: countdownOffer) { _, offer in
                if offer == nil, controlsRevealed { revealControls() }
            }
            .onChange(of: showVideoInfo) { _, presented in
                if !presented { restoreKeyboardFocus() }
            }
            .onChange(of: autoplayEnabled) { countdown = 8 }
            .onChange(of: controller.wantsPlayback) { _, playing in
                if !playing { persistProgress() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistProgress() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                guard playerWindow?.isKeyWindow == true else { return }
                menuDepth += 1
                revealControls()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                menuDepth = max(0, menuDepth - 1)
                revealControls()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                if notification.object as? NSWindow === playerWindow { cleanup() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                persistProgress()
            }
            .onDisappear(perform: cleanup)
            .sheet(isPresented: $showAirPlay, onDismiss: restoreKeyboardFocus) {
                MacPlayerAirPlaySheet(player: airPlayPlayer)
                    .onExitCommand { showAirPlay = false }
            }
    }

    private var controlsAnimation: Animation { MacPlayerChrome.visibilityAnimation(reduceMotion: reduceMotion) }

    private func keyboard<Content: View>(_ content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear(perform: restoreKeyboardFocus)
            .focusedSceneValue(\.macPlayerCommands, acceptsCommands ? commands : nil)
            .onKeyPress(.return) {
                guard acceptsCommands, commands.canControlPlayback else { return .ignored }
                toggleFullscreen()
                return .handled
            }
            .macPlayerEscapeKey(isEnabled: acceptsCommands && menuDepth == 0, action: handleEscape)
    }

    private var commands: MacPlayerCommandActions {
        let seekAction: ((Double) -> Void)? = canSeek ? { offset in seekBy(offset) } : nil
        return MacPlayerCommandActions(
            isPlaying: isPlaying, isMuted: volume == 0, isFullscreen: isFullscreen,
            togglePlayback: togglePlayback, toggleMute: toggleMute, toggleFullscreen: toggleFullscreen,
            changeVolume: { volume = min(1, max(0, volume + $0)); revealControls() },
            seek: seekAction, escape: handleEscape,
            canControlPlayback: !hasPanel && seek == nil && menuDepth == 0
        )
    }

    private func chrome(size: CGSize) -> some View {
        VStack {
            topControls(width: size.width)
                .opacity(chromeVisible && !hasPanel ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                .accessibilityHidden(!chromeVisible)
            Spacer(minLength: inset)
            bottomControls(width: size.width - 2 * inset)
                .onGeometryChange(for: CGRect.self) { [hoverSpace = MacPlayerChrome.hoverSpace] in
                    $0.frame(in: .named(hoverSpace))
                } action: {
                    bottomFrame = $0
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
        }
        .padding(inset)
        .animation(controlsAnimation, value: chromeVisible)
    }

    private func topControls(width: CGFloat) -> some View {
        let title = model.detail?.title ?? ""
        return HStack(spacing: 10) {
            Button(action: returnToDetail) { controlIcon("xmark") }
                .buttonStyle(.plain)
                .macPlayerGlass(in: Circle())
                .accessibilityLabel("返回作品详情")
                .help("返回作品详情")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title).font(.system(size: 13, weight: .semibold))
                if let subtitle = episodeSubtitle(workTitle: title) {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: controlHeight)
            .macPlayerGlass(in: Capsule(), interactive: false)
            .accessibilityElement(children: .combine)
            .frame(maxWidth: width * MacPlayerChrome.titleWidthFraction, alignment: .leading)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            MacPlayerGlassGroup {
                if !controller.subtitleTracks.isEmpty {
                    Button { openDrawer(.tracks) } label: { controlIcon("captions.bubble") }
                        .accessibilityLabel("字幕")
                }
                Button { openDrawer(.settings) } label: { controlIcon("gearshape") }
                    .accessibilityLabel("播放设置")
                Button(action: togglePin) { controlIcon(originalWindowLevel == nil ? "pin" : "pin.fill") }
                    .accessibilityLabel(originalWindowLevel == nil ? "置顶" : "取消置顶")
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .frame(height: controlHeight)
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: controlHeight, height: controlHeight)
            .contentShape(Rectangle())
    }

    private func episodeSubtitle(workTitle: String) -> LocalizedStringResource? {
        let current = model.selectedEpisode ?? episode
        if isSeries { return "\(current.macVodTitle)" }
        if !current.title.isEmpty, current.title != workTitle { return "\(current.title)" }
        return nil
    }

    private func bottomControls(width: CGFloat) -> some View {
        VStack(spacing: MacPlayerProgressRow.buttonGap) {
            // A separate row keeps the prompt above the timeline instead of covering the elapsed time.
            if chromeVisible, canSeek, model.activeIntroSkipTarget != nil, !hasPanel, menuDepth == 0, seek == nil {
                Button(action: skipIntro) {
                    Text("跳过片头")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                    .buttonStyle(.plain)
                    .macPlayerGlass(in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if duration > 0 { progressRow }
            controlGroups(width: width)
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                .accessibilityHidden(!chromeVisible)
        }
    }

    private var progressRow: some View {
        MacPlayerProgressRow(
            currentTime: seekCommitInFlight ? seek?.target ?? currentTime : currentTime,
            duration: duration, position: Binding(get: { seek?.target ?? currentTime }, set: updateSeek),
            isScrubbing: isScrubbing, canSeek: canSeek && !seekCommitInFlight,
            onEditingChanged: { editing in
                if editing { _ = beginSeek() }
                else if let seek { finishSeek(seek.target) }
            }, onCancel: { finishSeek(nil) }, seekBy: seekBy, cues: cueTimes
        )
    }

    private var cueTimes: [Double] {
        guard let playback = model.playback else { return [] }
        let intro = markerBoundary(playback.introMarker, useEnd: true)
        let credits = markerBoundary(playback.creditsMarker, useEnd: false)
        return [intro, credits].compactMap { $0 }
    }

    private func markerBoundary(_ marker: VodMarker?, useEnd: Bool) -> Double? {
        guard let marker, marker.start >= 0, marker.start < marker.end, marker.end <= duration else { return nil }
        return useEnd ? marker.end : marker.start
    }

    private func controlGroups(width: CGFloat) -> some View {
        let sliderWidth = min(80, max(40, width - 395))
        let showsPercentage = width >= 510
        let layout = width < (isSeries ? 412 : 282)
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            MacPlayerGlassGroup {
                Button(action: togglePlayback) {
                    controlIcon(model.hasFinished ? "arrow.counterclockwise" : isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(model.hasFinished ? "重播" : isPlaying ? "暂停" : "播放")
                .disabled(model.playback == nil || errorMessage != nil)
                if isSeries {
                    episodeButton(offset: -1, symbol: "backward.end.fill", label: "上一集", key: .leftArrow)
                    episodeButton(offset: 1, symbol: "forward.end.fill", label: "下一集", key: .rightArrow)
                }
                volumeControl(sliderWidth: sliderWidth, showsPercentage: showsPercentage)
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            MacPlayerGlassGroup {
                if isSeries {
                    Button { openDrawer(.episodes) } label: {
                        Label("选集", systemImage: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: controlHeight)
                            .contentShape(Rectangle())
                    }
                    .disabled(model.detail?.episodes.isEmpty != false)
                }
                rateMenu
                Button(action: toggleFullscreen) {
                    controlIcon(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isFullscreen ? "退出全屏" : "进入全屏")
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }

    private var rateMenu: some View {
        Menu {
            Picker("播放速度", selection: $playbackRate) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                    Text("\(rate.formatted())×").tag(rate)
                }
            }
        } label: {
            Text("\(playbackRate.formatted())×")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(minWidth: controlHeight, minHeight: controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .accessibilityLabel("播放速度")
        .accessibilityValue("\(playbackRate.formatted())×")
    }

    private func volumeControl(sliderWidth: CGFloat, showsPercentage: Bool) -> some View {
        HStack(spacing: 0) {
            Button(action: toggleMute) {
                controlIcon(volume == 0 ? "speaker.slash.fill" : volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
            }
            .accessibilityLabel(volume == 0 ? "取消静音" : "静音")
            .help(volume == 0 ? "取消静音" : "静音")
            if volumeExpanded {
                HStack(spacing: 8) {
                    Slider(value: $volume, in: 0...1) { volumeEditing = $0 }
                        .controlSize(.small)
                        .tint(.white)
                        .frame(width: sliderWidth)
                        .accessibilityLabel("音量")
                    if showsPercentage {
                        Text(volume.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.trailing, 10)
            }
        }
        .contentShape(Rectangle())
        .onHover { volumeHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: volumeExpanded)
    }

    private func episodeButton(offset: Int, symbol: String, label: LocalizedStringKey, key: KeyEquivalent) -> some View {
        Button {
            if let next = adjacentEpisode(offset) { select(next) }
        } label: { controlIcon(symbol) }
            .keyboardShortcut(key, modifiers: .command)
            .accessibilityLabel(label)
            .disabled(adjacentEpisode(offset) == nil || !commands.canControlPlayback)
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage {
            VStack(spacing: 12) {
                Text(verbatim: errorMessage).multilineTextAlignment(.center)
                Button("重试", action: retry).buttonStyle(.borderedProminent)
            }
            .padding(inset)
            .macPlayerGlass(in: .rect(cornerRadius: 16))
        } else if isLoading {
            ProgressView("正在准备播放").fullUIArcLoadingStyle()
                .allowsHitTesting(false)
        } else if !isPlaying {
            MacPlayerCenterPlayButton(title: model.hasFinished ? "重播" : "继续播放", action: togglePlayback)
        }
    }

    private func creditsCard(_ offer: VodCreditsOffer, size: CGSize) -> some View {
        let next = offer.nextEpisode
        let rect = videoRect(in: size)
        return MediaUpNextCard(episodeTitle: next.macVodTitle, countdown: countdown) {
            MacVodArtwork(path: next.stillURL)
        } actions: {
            Button(action: advanceFromCredits) { Label("立即播放", systemImage: "play.fill") }
                .buttonStyle(MediaUpNextButtonStyle(primary: true))
            Button("仍看片尾") { model.dismissCreditsOffer(playbackID: offer.playbackID) }
                .buttonStyle(MediaUpNextButtonStyle(primary: false))
        }
        .macPlayerGlass(in: .rect(cornerRadius: 16))
        .frame(maxWidth: min(430, max(0, rect.width - 2 * inset)), alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { creditsHeight = $0 }
        .padding(.trailing, size.width - rect.maxX + inset)
        .padding(.bottom, creditsBottomInset(in: size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func videoRect(in size: CGSize) -> CGRect {
        let viewport = CGRect(origin: .zero, size: size)
        guard pictureMode == .fit, let natural = controller.coordinator?.playerLayer?.player.naturalSize,
              natural.width > 0, natural.height > 0 else { return viewport }
        return AVMakeRect(aspectRatio: natural, insideRect: viewport)
    }

    private func subtitleBottomOffset(in size: CGSize) -> CGFloat {
        // The subtitle canvas fills the viewport, including its letterbox bars.
        if countdownOffer != nil { return creditsBottomInset(in: size) + creditsHeight + 14 }
        guard controlsVisible, !bottomFrame.isNull else { return 0 }
        return max(0, size.height - bottomFrame.minY + 14)
    }

    private func creditsBottomInset(in size: CGSize) -> CGFloat {
        let timeline = controlsVisible && !bottomFrame.isNull ? size.height - bottomFrame.minY + 12 : inset
        return max(size.height - videoRect(in: size).maxY + inset, timeline)
    }

    @ViewBuilder
    private func panels(size: CGSize) -> some View {
        if let drawer {
            MacVodPlayerDrawer(
                kind: drawer, model: model, controller: controller, autoplayEnabled: $autoplayEnabled,
                pictureMode: $pictureMode, closeDeadline: $closeDeadline, canAirPlay: airPlayPlayer != nil,
                onClose: closeDrawer, onEpisode: { select($0) },
                onSource: { source in if let selected = model.selectedEpisode { select(selected, sourceID: source) } },
                onTracks: { openDrawer(.tracks) },
                onAirPlay: { showAirPlay = true; self.drawer = nil },
                onVideoInfo: { showVideoInfo = true; self.drawer = nil }
            )
            .id(drawer)
            .frame(width: min(max(size.width * 0.36, 340), min(420, max(0, size.width - 2 * inset))))
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        if showVideoInfo, let coordinator = controller.coordinator {
            VideoSettingsPanel(coordinator: coordinator, qualityTitle: model.playback?.quality.title,
                               streamURL: model.playback?.url, isShowing: $showVideoInfo)
                .frame(width: min(380, size.width))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        if let notice {
            Text(verbatim: notice)
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .macPlayerGlass(in: Capsule(), interactive: false)
                .padding(.top, inset + controlHeight + 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private func samplePlayback(id: UUID?) async {
        guard let id else { return }
        while !Task.isCancelled && !isLeaving && model.playback?.id == id {
            controller.restoreIfPossible(model: model) { readyID in
                guard let sample = controller.timeSample(for: readyID) else { return }
                model.playbackReady(id: readyID, duration: sample.duration)
            }
            refreshPlaybackStatus()
            if seek == nil, !controller.isRestoring(for: id), let sample = controller.timeSample(for: id),
               sample.current.isFinite, sample.duration.isFinite, sample.duration > 0 {
                currentTime = max(0, sample.current)
                duration = sample.duration
                model.playbackReady(id: id, duration: duration)
                model.recordProgress(id: id, position: currentTime, duration: duration)
                if let marker = model.playback?.creditsMarker, currentTime < marker.start { countdown = 8 }
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    private func countDown() async {
        guard let offer = countdownOffer else { return }
        while countdown > 0 {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled, countdownOffer == offer else { return }
            countdown -= 1
        }
        guard !Task.isCancelled, countdownOffer == offer else { return }
        advanceFromCredits()
    }

    private func revealControls() {
        controlsRevealed = true
        hideTask?.cancel()
        guard !isLeaving, !holdsControls, !pointerOverControls, countdownOffer == nil else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !isLeaving, !holdsControls, !pointerOverControls, countdownOffer == nil else { return }
            controlsRevealed = false
        }
    }

    private func refreshPlaybackStatus() {
        playbackStatus = controller.playbackStatus(for: model.playback?.id)
    }

    private func togglePlayback() {
        guard model.playback != nil, seek == nil, !hasPanel, errorMessage == nil else { return }
        if model.hasFinished, let selected = model.selectedEpisode {
            select(selected, sourceID: model.playback?.sourceID)
        } else if controller.wantsPlayback {
            controller.pause()
            persistProgress()
        } else {
            controller.play()
        }
        refreshPlaybackStatus()
        revealControls()
    }

    private func adjacentEpisode(_ offset: Int) -> VodEpisode? {
        guard let episodes = model.detail?.episodes,
              let active = episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }),
              episodes.indices.contains(active + offset) else { return nil }
        return episodes[active + offset]
    }

    private func select(_ episode: VodEpisode, sourceID: String? = nil) {
        changePlayback { await model.selectEpisode(id: episode.id, sourceID: sourceID) }
    }

    private func advanceFromCredits() {
        guard countdownOffer != nil else { return }
        changePlayback { await model.advanceToNextEpisode() }
    }

    private func retry() {
        changePlayback {
            if let playback = model.playback, controller.isRestoring(for: playback.id) {
                // A failed restoration still owns the playback UUID. Clear it before resolving the same episode.
                await model.playbackFinished(id: playback.id, error: PlaybackError.restorationFailed)
            }
            guard !Task.isCancelled else { return }
            await model.retry()
        }
    }

    private func changePlayback(_ action: @escaping @MainActor () async -> Void) {
        guard !isLeaving, seek == nil else { return }
        persistProgress()
        operation?.cancel()
        operation = Task { await action() }
        closeDrawer()
        revealControls()
    }

    private func beginSeek() -> Bool {
        guard seek == nil, canSeek, let id = model.playback?.id, model.beginScrubbing(playbackID: id) else {
            return false
        }
        seek = Scrub(id: id, duration: duration, resume: controller.wantsPlayback && !model.hasFinished,
                     target: currentTime)
        controller.pause()
        return true
    }

    private func updateSeek(_ position: Double) {
        guard !seekCommitInFlight, let playback = model.playback, seek?.id == playback.id else { return }
        seek?.target = position
        seekPreview.update(id: playback.id, url: playback.url, quality: playback.quality, targetTime: position)
    }

    private func finishSeek(_ position: Double?) {
        guard let seek, !seekCommitInFlight else { return }
        let target = position.map { min(max($0, 0), seek.duration) }
        seekCommitInFlight = true
        seekPreview.endScrubbing()
        seekTask = Task {
            let succeeded: Bool
            if let target { succeeded = await controller.seek(to: target, playbackID: seek.id) }
            else { succeeded = false }
            guard !Task.isCancelled, !isLeaving, model.playback?.id == seek.id else { return }
            let resume = seek.resume && !controller.playbackHasFailed(for: seek.id)
            // Releasing the completion hold can start another episode and change the playback ID.
            seekTask = nil
            await model.completeScrubbing(playbackID: seek.id, targetTime: target, duration: seek.duration,
                                          seekSucceeded: succeeded, resumePlayback: resume)
            guard !Task.isCancelled, !isLeaving, model.playback?.id == seek.id else { return }
            self.seek = nil
            seekCommitInFlight = false
            if let target {
                if succeeded { currentTime = target }
                else { showNotice("暂时无法跳转") }
            }
            if resume, !model.hasFinished { controller.play() }
            revealControls()
        }
    }

    private func seekBy(_ offset: Double) {
        guard let sample = controller.timeSample(for: model.playback?.id), beginSeek() else { return }
        finishSeek(sample.current + offset)
    }

    private func skipIntro() {
        guard beginSeek(), let id = seek?.id else { return }
        finishSeek(model.skipIntro(playbackID: id))
    }

    private func openDrawer(_ kind: MacVodPlayerDrawer.Kind) {
        guard seek == nil else { return }
        drawer = kind
    }

    private func closeDrawer() {
        guard drawer != nil else { return }
        drawer = nil
        restoreKeyboardFocus()
    }

    private func restoreKeyboardFocus() { hasKeyboardFocus = acceptsCommands && !hasPanel }

    private func toggleMute() {
        if volume > 0 {
            preMuteVolume = volume
            volume = 0
        } else {
            volume = preMuteVolume
        }
        revealControls()
    }

    private func toggleFullscreen() {
        playerWindow?.toggleFullScreen(nil)
        revealControls()
    }

    private func togglePin() {
        guard let playerWindow else { return }
        if let originalWindowLevel {
            playerWindow.level = originalWindowLevel
            self.originalWindowLevel = nil
        } else {
            originalWindowLevel = playerWindow.level
            playerWindow.level = .floating
        }
    }

    private func handleEscape() {
        if showAirPlay { showAirPlay = false }
        else if showVideoInfo { showVideoInfo = false }
        else if drawer != nil { closeDrawer() }
        else if seek != nil { finishSeek(nil) }
        else if onExitFullscreen() { return }
        else { returnToDetail() }
    }

    private func showNotice(_ message: String) {
        notice = message
        noticeRevision += 1
    }

    private func persistProgress() {
        if seek == nil, let id = model.playback?.id, let sample = controller.timeSample(for: id) {
            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
        }
        model.flushProgress()
    }

    private func returnToDetail() {
        cleanup()
        onReturn()
    }

    private func cleanup() {
        guard !isLeaving else { return }
        isLeaving = true
        persistProgress()
        hideTask?.cancel()
        seekTask?.cancel()
        seekPreview.cancel()
        operation?.cancel()
        model.cancel()
        controller.stop()
        playbackSession.invalidate()
        updateSleepActivity(false)
        if let originalWindowLevel { playerWindow?.level = originalWindowLevel }
        originalWindowLevel = nil
    }

    private func updateSleepActivity(_ playing: Bool) {
        if playing, !isLeaving, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "点播播放")
        } else if !playing, let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }
}
#endif
