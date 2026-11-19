//
//  UnifiedPlayerControlOverlay.swift
//  AngelLive
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit
#if canImport(KSPlayer)
import KSPlayer
#endif

struct UnifiedPlayerControlOverlay: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.fullUIWindowContext) private var windowContext
    @Environment(\.fullUIPlayerIsFullscreen) private var isFullscreen
    @Environment(\.fullUILandscapePlayerLayout) private var landscapeLayout
    @Environment(\.fullUIPlayerShowsRoomBanner) private var showsRoomBanner
    @Environment(\.fullUIPlayerUsesInPlaceFullscreen) private var usesInPlaceFullscreen
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    let bridge: PlayerControlBridge
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool
    @Binding var isPopupPresented: Bool
    #if canImport(KSPlayer)
    let playerLayer: () -> KSPlayerLayer?
    @State private var timeline = KSRoomSeekTimeline()
    #endif

    @State private var autoHideTask: Task<Void, Never>?
    @State private var isSettingsPopupOpen = false
    @State private var videoScaleMode: VideoScaleMode = PlayerSettingModel().videoScaleMode
    @State private var showQualityPanel = false
    @State private var showDanmakuIssue = false
    @State private var playbackTimer = TimerManager()
    @State private var fullscreenMenu = FullUIPlaybackMenuState()

    // 将 bridge.isMaskShow 的值提取到本地 @State 以便 SwiftUI 能可靠追踪变化
    @State private var isMaskVisible: Bool = true

    // MARK: - Computed Properties

    private var controlInset: CGFloat {
        isFullscreen ? FullUIPlayerChrome.inset : FullUIPlayerDetailChrome.inset
    }

    /// 是否有弹窗/菜单展开
    private var isPopupOpen: Bool {
        showDanmakuSettings || showVideoSetting || isSettingsPopupOpen || fullscreenMenu.isPresented
            || showQualityPanel || showDanmakuIssue
    }

    private var isScrubbing: Bool {
        #if canImport(KSPlayer)
        timeline.target != nil
        #else
        false
        #endif
    }

    private var isCommittingSeek: Bool {
        #if canImport(KSPlayer)
        timeline.isCommitting
        #else
        false
        #endif
    }

    var body: some View {
        #if canImport(KSPlayer)
        overlayContent
            .fullUIPlayerContrast(
                while: isMaskVisible || bridge.isLocked.wrappedValue,
                source: FullUIPlayerContrastSource(roomID: viewModel.currentRoom.id, url: viewModel.currentPlayURL,
                                                   kernel: viewModel.selectedPlayerKernel)
            ) { currentTimelineLayer?.player }
            .task(id: isFullscreen && landscapeLayout != nil && viewModel.isOnDemand && isMaskVisible
                  ? viewModel.currentPlayURL : nil) {
                guard landscapeLayout != nil, viewModel.isOnDemand, isMaskVisible,
                      viewModel.currentPlayURL != nil else { return }
                while !Task.isCancelled {
                    timeline.sample(currentTimelineLayer)
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
            .onChange(of: viewModel.currentPlayURL) { timeline.reset() }
            .onChange(of: viewModel.currentRoom.id) { timeline.reset() }
            .onChange(of: landscapeLayout != nil) { timeline.cancelScrubbing() }
            .onDisappear { timeline.reset() }
        #else
        overlayContent
        #endif
    }

    private var overlayContent: some View {
        ZStack {
            Group {
                if let layout = landscapeLayout {
                    landscapeControls(layout)
                        .ignoresSafeArea(.container)
                } else {
                    Group {
                        if isFullscreen { fullscreenControls }
                        else { detailControls }
                    }
                    .modifier(ChromeVisibility(visible: isMaskVisible, reduceMotion: reduceMotion))
                }
            }
            .accessibilityHidden(fullscreenMenu.isPresented)
            // 触摸控制层时重置自动隐藏
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if isMaskVisible && !isPopupOpen {
                            startAutoHideTimer()
                        }
                    }
            )
            if isFullscreen, !bridge.isLocked.wrappedValue {
                FullUIPlayerDanmakuStatus(
                    status: viewModel.danmakuConnectionStatus,
                    controlsVisible: isMaskVisible,
                    controlBottomInset: landscapeLayout.map { $0.insets.bottom - $0.safeAreaBottom } ?? controlInset
                )
            }

            if fullscreenMenu.isPresented {
                if let layout = landscapeLayout {
                    playbackSettingsMenu(insets: layout.insets, showsRoomIdentity: !viewModel.isOnDemand)
                        .ignoresSafeArea(.container)
                } else {
                    playbackSettingsMenu(insets: EdgeInsets(top: controlInset, leading: controlInset,
                                                            bottom: 0, trailing: controlInset))
                }
            }
            // 清晰度选择面板（右侧滑入）
            if showQualityPanel {
                Color.black.opacity(0.001)
                    .onTapGesture { showQualityPanel = false }
                QualitySelectionPanel(isShowing: $showQualityPanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .alert("弹幕连接", isPresented: $showDanmakuIssue) {
            Button(viewModel.danmuSettings.showDanmu ? "关闭弹幕" : "开启弹幕") {
                viewModel.danmuSettings.showDanmu.toggle()
            }
            Button("关闭", role: .cancel) {}
        } message: {
            Text(viewModel.danmakuConnectionIssue ?? "弹幕连接状态已更新")
        }
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        // 双向同步 bridge.isMaskShow ↔ isMaskVisible
        .onChange(of: bridge.isMaskShow.wrappedValue) { _, newValue in
            if isMaskVisible != newValue {
                isMaskVisible = newValue
            }
        }
        .onChange(of: isMaskVisible) { _, newValue in
            if bridge.isMaskShow.wrappedValue != newValue {
                bridge.isMaskShow.wrappedValue = newValue
            }
            // 自动隐藏计时器管理
            if newValue && !isPopupOpen {
                startAutoHideTimer()
            } else if !newValue {
                cancelAutoHideTimer()
            }
        }
        .onChange(of: isFullscreen) { _, _ in
            isSettingsPopupOpen = false
            fullscreenMenu.isPresented = false
            if !isFullscreen {
                bridge.isLocked.wrappedValue = false
            }
        }
        .onChange(of: isPopupOpen) { _, isOpen in
            isPopupPresented = isOpen
            if isOpen {
                cancelAutoHideTimer()
            } else if isMaskVisible {
                startAutoHideTimer()
            }
        }
        .onChange(of: isScrubbing) { _, scrubbing in
            if scrubbing { cancelAutoHideTimer() }
            else if isMaskVisible { startAutoHideTimer() }
        }
        .onChange(of: bridge.isPlaying) { _, _ in
            if isMaskVisible { startAutoHideTimer() }
        }
        .onAppear {
            isMaskVisible = bridge.isMaskShow.wrappedValue
            isPopupPresented = isPopupOpen
            if isMaskVisible && !isPopupOpen {
                startAutoHideTimer()
            }
        }
        .onDisappear {
            cancelAutoHideTimer()
            isPopupPresented = false
        }
    }

    private func playbackSettingsMenu(insets: EdgeInsets, showsRoomIdentity: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { fullscreenMenu.isPresented = false }
                .accessibilityHidden(true)

            FullUIPlaybackMenu(state: fullscreenMenu, timer: playbackTimer, showsRoomIdentity: showsRoomIdentity)
                .padding(.trailing, insets.trailing)
                .padding(.top, insets.top + FullUIPlayerChrome.controlSize + 6)
                .padding(.bottom, max(8, insets.bottom))
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private func landscapeControls(_ layout: FullUILandscapePlayerLayout) -> some View {
        let locked = bridge.isLocked.wrappedValue
        let showsControls = isMaskVisible && !isScrubbing

        return GeometryReader { geometry in
            if !locked {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        if showsRoomBanner {
                            roomBanner(maximumWidth: roomBannerWidth(in: geometry.size.width, layout: layout))
                                .transition(.opacity)
                        } else {
                            chromeButton("chevron.backward", label: "返回", action: handleBackButton)
                                .fullUIPlayerGlass(in: Circle())
                                .fullUIPlayerShadow(in: Circle())
                                .modifier(ChromeVisibility(visible: showsControls, reduceMotion: reduceMotion))
                        }
                        Spacer(minLength: 0)
                        fullscreenTopActions
                            .modifier(ChromeVisibility(visible: showsControls, reduceMotion: reduceMotion))
                    }
                    .frame(height: FullUIPlayerChrome.controlSize)
                    Spacer(minLength: 0)
                    VStack(spacing: FullUILandscapePlayerLayout.progressGap) {
                        #if canImport(KSPlayer)
                        if viewModel.isOnDemand, timeline.duration > 0 {
                            progressControl
                                .modifier(ChromeVisibility(visible: isMaskVisible, reduceMotion: reduceMotion))
                        }
                        #endif
                        playbackBottomBar
                            .modifier(ChromeVisibility(visible: showsControls, reduceMotion: reduceMotion))
                    }
                }
                .padding(layout.insets)

                if showsCentralPlay && !isScrubbing {
                    centralPlayButton
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .modifier(ChromeVisibility(visible: showsControls, reduceMotion: reduceMotion))
                }
                #if canImport(KSPlayer)
                if let target = timeline.target {
                    let size = currentTimelineLayer?.player.naturalSize ?? .zero
                    FullUIPlayerSeekReadout(time: target, duration: timeline.duration, preview: timeline.preview.state,
                                            isHorizontalVideo: size.width >= size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                #endif
            }

            if locked || showsControls {
                FullUILandscapePlayerLock(isLocked: locked) {
                    bridge.isLocked.wrappedValue.toggle()
                    isMaskVisible = true
                    startAutoHideTimer()
                }
                .position(x: layout.lockInset + FullUIPlayerChrome.controlSize / 2, y: geometry.size.height / 2)
            }
        }
        .overlay(alignment: .top) {
            FullUILandscapePlayerStatus(isVisible: showsControls && !locked)
        }
    }

    private func roomBannerWidth(in viewportWidth: CGFloat, layout: FullUILandscapePlayerLayout) -> CGFloat {
        let preferredWidth = min(320, viewportWidth * 0.52)
        // Keep the existing concentric inset on displays with shallow corners.
        guard layout.insets.top < FullUILandscapePlayerStatus.bottomEdge else { return preferredWidth }
        let widthBeforeStatus = viewportWidth / 2 - FullUILandscapePlayerStatus.halfWidthWithClearance - layout.insets.leading
        return min(preferredWidth, max(0, widthBeforeStatus))
    }

    private func roomBanner(maximumWidth: CGFloat) -> some View {
        Button(action: handleBackButton) {
            FullUIPlayerRoomIdentity(room: viewModel.currentRoom)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: FullUIPlayerChrome.controlSize)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maximumWidth, alignment: .leading)
        .accessibilityHint("返回")
        .fullUIPlayerGlass(in: Capsule(), interactive: false)
        .fullUIPlayerShadow(in: Capsule())
        .environment(\.fullUIPlayerPrefersRegularGlass, true)
    }

    #if canImport(KSPlayer)
    private var currentTimelineLayer: KSPlayerLayer? {
        guard let layer = playerLayer(), layer.url == viewModel.currentPlayURL else { return nil }
        return layer
    }

    private var progressControl: some View {
        HStack(spacing: 8) {
            FullUIPlayerTimeLabel(time: timeline.elapsed)
                .opacity(isScrubbing ? 0 : 1)
                .accessibilityHidden(true)
            ShortDramaProgressSlider(
                value: Binding(get: { timeline.target ?? timeline.elapsed }, set: updateScrub),
                range: 0...timeline.duration,
                isEnabled: timeline.canSeek && !timeline.isCommitting,
                accessibilityLabel: "播放进度",
                accessibilityValue: "\(fullUIPlayerTime(timeline.target ?? timeline.elapsed)) / \(fullUIPlayerTime(timeline.duration))",
                onEditingChanged: { if $0 { timeline.beginScrubbing() } },
                onCommit: { timeline.seek(to: $0, on: currentTimelineLayer) },
                showsCompactTrack: false,
                onCancel: timeline.cancelScrubbing
            )
            FullUIPlayerTimeLabel(time: timeline.duration)
                .opacity(isScrubbing ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(height: ShortDramaProgressSlider.hitHeight)
    }

    private func updateScrub(_ value: Double) {
        let selection = RoomPlaybackResolver.selection(in: viewModel.currentRoomPlayArgs,
                                                       cdnIndex: viewModel.currentCdnIndex,
                                                       qualityIndex: viewModel.currentQualityIndex)
        timeline.updateScrub(to: value, url: viewModel.currentPlayURL, quality: selection?.quality)
    }
    #endif

    private var showsCentralPlay: Bool {
        !bridge.isPlaying && !bridge.isBuffering && !bridge.isInitialLoading
    }

    private var detailControls: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    chromeButton("chevron.backward", label: "返回", action: handleBackButton)
                        .fullUIPlayerGlass(in: Circle())
                        .fullUIPlayerShadow(in: Circle())
                    Spacer(minLength: 0)
                    FullUIPlayerGlassGroup {
                        if bridge.supportsPictureInPicture {
                            chromeButton("pip", label: "画中画", action: bridge.togglePictureInPicture)
                        }
                        settingsButton
                    }
                }
                Spacer(minLength: 0)
                playbackBottomBar
            }

            if showsCentralPlay {
                centralPlayButton
            }
        }
        .padding(controlInset)
    }

    private var fullscreenControls: some View {
        let locked = bridge.isLocked.wrappedValue
        let safeArea = windowContext?.window?.safeAreaInsets ?? .zero
        let videoCenterOffset = (safeArea.bottom - safeArea.top) / 2

        return ZStack(alignment: .leading) {
            chromeButton(locked ? "lock.fill" : "lock.open", label: locked ? "解锁" : "锁定") {
                bridge.isLocked.wrappedValue.toggle()
            }
            .fullUIPlayerGlass(in: Circle())
            .fullUIPlayerShadow(in: Circle())
            .offset(y: videoCenterOffset)

            if !locked {
                VStack(spacing: 0) {
                    fullscreenTopBar
                    Spacer(minLength: 0)
                    playbackBottomBar
                }

                if showsCentralPlay {
                    centralPlayButton
                        .frame(maxWidth: .infinity)
                        .offset(y: videoCenterOffset)
                }
            }
        }
        .padding(controlInset)
    }

    private var centralPlayButton: some View {
        Button(action: bridge.togglePlayPause) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fullUIPlayerGlass(in: Circle())
        .fullUIPlayerShadow(in: Circle())
        .accessibilityLabel("播放")
    }

    private var fullscreenTopBar: some View {
        HStack(spacing: 12) {
            chromeButton("chevron.backward", label: "返回", action: handleBackButton)
                .fullUIPlayerGlass(in: Circle())
                .fullUIPlayerShadow(in: Circle())

            FullUIPlayerName(
                viewModel.currentRoom.userName.isEmpty ? viewModel.currentRoom.roomTitle : viewModel.currentRoom.userName,
                font: .systemFont(ofSize: 13, weight: .semibold)
            )
            .foregroundStyle(.white)
            .fullUIPlayerMediaText()
            Spacer(minLength: 0)

            fullscreenTopActions
        }
    }

    private var fullscreenTopActions: some View {
        FullUIPlayerGlassGroup {
            if bridge.supportsPictureInPicture {
                chromeButton("pip", label: "画中画", action: bridge.togglePictureInPicture)
            }
            scaleModeMenu
            settingsButton
        }
    }

    private var playbackBottomBar: some View {
        HStack {
            FullUIPlayerGlassGroup {
                chromeButton(bridge.isPlaying ? "pause.fill" : "play.fill", label: bridge.isPlaying ? "暂停" : "播放") {
                    bridge.togglePlayPause()
                }
                .disabled(isCommittingSeek)
                chromeButton("arrow.counterclockwise", label: "刷新", action: bridge.refreshPlayback)
                    .disabled(viewModel.isLoading)
            }

            Spacer(minLength: 12)

            FullUIPlayerGlassGroup {
                danmakuButton
                qualityMenu
                chromeButton(fullscreenIconName, label: isFullscreen ? "退出全屏" : "全屏", action: toggleOrientationOrFullscreen)
            }
        }
    }

    private var danmakuButton: some View {
        Button {
            if viewModel.danmakuConnectionIssue != nil {
                showDanmakuIssue = true
            } else {
                viewModel.danmuSettings.showDanmu.toggle()
            }
        } label: {
            Image(systemName: viewModel.danmuSettings.showDanmu ? "captions.bubble.fill" : "captions.bubble")
                .font(FullUIPlayerChrome.symbolFont)
                .foregroundStyle(.white)
                .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("弹幕开关")
        .accessibilityValue(viewModel.danmakuConnectionIssue == nil ? "" : "连接异常")
        .overlay(alignment: .topTrailing) {
            if viewModel.danmakuConnectionIssue != nil {
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func chromeButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chromeSymbol(symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chromeSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(FullUIPlayerChrome.symbolFont)
            .foregroundStyle(.white)
            .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
            .contentShape(Rectangle())
    }

    private var settingsButton: some View {
        SettingsButton(
            showVideoSetting: $showVideoSetting,
            showDanmakuSettings: $showDanmakuSettings,
            onDismiss: { dismiss() },
            onPopupStateChanged: { isSettingsPopupOpen = $0 },
            fullscreenMenu: fullscreenMenu,
            playbackTimer: playbackTimer
        )
    }

    // MARK: - Quality Menu

    private var qualityMenu: some View {
        Button {
            showQualityPanel = true
        } label: {
            let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let width = ("清晰度清晰度" as NSString).size(withAttributes: [.font: font]).width
            FullUIPlayerName(viewModel.currentPlayQualityString, font: font, maximumWidth: width)
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, isFullscreen ? 12 : 10)
                .frame(minWidth: FullUIPlayerChrome.controlSize, minHeight: FullUIPlayerChrome.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("线路与清晰度")
        .accessibilityValue(viewModel.currentPlayQualityString)
    }

    // MARK: - Scale Mode Menu

    private var scaleModeMenu: some View {
        Menu {
            ForEach(VideoScaleMode.allCases, id: \.rawValue) { mode in
                Button {
                    videoScaleMode = mode
                    PlayerSettingModel().videoScaleMode = mode
                    bridge.applyScaleMode?(mode)
                } label: {
                    Label {
                        Text(mode.title)
                    } icon: {
                        Image(systemName: videoScaleMode == mode ? "checkmark" : mode.iconName)
                    }
                }
            }
        } label: {
            chromeSymbol("aspectratio")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("画面比例")
        .tint(.primary)
    }

    // MARK: - Helpers

    private var fullscreenIconName: String {
        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    /// 处理返回按钮点击
    /// - 显式全屏或紧凑高度时：先退出全屏；需要旋转时请求竖屏
    /// - 其他情况：dismiss 返回上一页
    private func handleBackButton() {
        if isIPadFullscreen.wrappedValue || verticalSizeClass == .compact {
            isIPadFullscreen.wrappedValue = false
            if usesInPlaceFullscreen { return }
            // 请求竖屏，旋转完成后恢复自由旋转。
            KSOptions.supportedInterfaceOrientations = .portrait

            guard let windowScene = windowContext?.windowScene else { return }

            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: .portrait
            )

            // 先通知 ViewController 刷新支持的方向
            if let rootVC = windowContext?.hostViewController {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
            DispatchQueue.main.async {
                windowScene.requestGeometryUpdate(geometryPreferences) { @Sendable error in
                    Logger.warning("退出全屏失败: \(error)", category: .ui)
                }
                // 旋转完成后恢复自由旋转，允许再次横屏自动全屏
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                    if let rootVC = windowContext?.hostViewController {
                        rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
        } else {
            // 竖屏：返回上一页
            dismiss()
            KSOptions.supportedInterfaceOrientations = .portrait
        }
    }

    private func toggleOrientationOrFullscreen() {
        let entersFullscreen = !isFullscreen
        isIPadFullscreen.wrappedValue = entersFullscreen
        if usesInPlaceFullscreen { return }

        let targetOrientation: UIInterfaceOrientationMask = entersFullscreen ? .landscapeRight : .portrait
        KSOptions.supportedInterfaceOrientations = targetOrientation

        guard let windowScene = windowContext?.windowScene else {
            return
        }

        // 先通知 ViewController 刷新支持的方向
        if let rootVC = windowContext?.hostViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
        DispatchQueue.main.async {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: targetOrientation
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { @Sendable error in
                Logger.warning("方向更新失败: \(error)", category: .ui)
            }
            // 旋转完成后恢复自由旋转
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = windowContext?.hostViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }

    // MARK: - Auto Hide Timer

    private func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isScrubbing else { return }
        if isFullscreen && (!bridge.isPlaying || voiceOverEnabled || bridge.isLocked.wrappedValue) { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && !isPopupOpen && !isScrubbing
                && (!isFullscreen || (bridge.isPlaying && !voiceOverEnabled && !bridge.isLocked.wrappedValue)) {
                isMaskVisible = false
            }
        }
    }

    private func cancelAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}

private struct ChromeVisibility: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(FullUIPlayerChrome.visibilityAnimation(visible, reduceMotion: reduceMotion), value: visible)
    }
}
