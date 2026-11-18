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
    static let compactLandscapeControlInset: CGFloat = 16

    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.fullUIWindowContext) private var windowContext
    @Environment(\.fullUIPlayerIsFullscreen) private var isFullscreen
    @Environment(\.fullUIPlayerUsesExpandedLayout) private var usesExpandedLayout
    @Environment(\.fullUIPlayerUsesInPlaceFullscreen) private var usesInPlaceFullscreen
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    let bridge: PlayerControlBridge
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool
    @Binding var isPopupPresented: Bool
    #if canImport(KSPlayer)
    var contrastPlayer: () -> (any MediaPlayerProtocol)?
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

    /// 检测是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    /// 控制层基础内边距。iPhone 横屏使用更统一的角落留白，避免和圆角节奏打架。
    private var controlPadding: CGFloat {
        if isLandscape {
            return usesExpandedLayout ? 20 : Self.compactLandscapeControlInset
        }
        return 12
    }

    /// 顶部一排控制的目标高度，和返回按钮的 50pt 点击区对齐。
    private let topControlRowHeight: CGFloat = 50

    /// 顶部返回按钮与右上角控制层都使用 50pt 行高。
    private var topControlPadding: CGFloat {
        controlPadding
    }

    private var topShadowHeight: CGFloat {
        (topControlPadding + topControlRowHeight + 32) * 0.75
    }

    private var topShadowGradient: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong),
                    .black.opacity(AppConstants.PlayerUI.Opacity.overlayLight),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topShadowHeight)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 是否有弹窗/菜单展开
    private var isPopupOpen: Bool {
        showDanmakuSettings || showVideoSetting || isSettingsPopupOpen || fullscreenMenu.isPresented
            || showQualityPanel || showDanmakuIssue
    }

    var body: some View {
        #if canImport(KSPlayer)
        overlayContent.fullUIPlayerContrast(while: isFullscreen && isMaskVisible, player: contrastPlayer)
        #else
        overlayContent
        #endif
    }

    private var overlayContent: some View {
        ZStack {
            if !isFullscreen && !bridge.isLocked.wrappedValue {
                topShadowGradient
                    .opacity(isMaskVisible ? 1 : 0)

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(AppConstants.PlayerUI.Opacity.overlayLight),
                            .black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                .ignoresSafeArea()
                .opacity(isMaskVisible ? 1 : 0)
                .allowsHitTesting(false)
            }

            Group {
                if isFullscreen {
                    fullscreenControls
                } else {
                    detailControls
                }
            }
            .opacity(isMaskVisible ? 1 : 0)
            .allowsHitTesting(isMaskVisible)
            .accessibilityHidden(!isMaskVisible || fullscreenMenu.isPresented)
            .animation(
                isFullscreen ? FullUIPlayerChrome.visibilityAnimation(isMaskVisible, reduceMotion: reduceMotion) : nil,
                value: isMaskVisible
            )
            // 触摸控制层时重置自动隐藏
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if isMaskVisible && !isPopupOpen {
                            startAutoHideTimer()
                        }
                    }
            )
            FullUIPlayerDanmakuStatus(
                status: viewModel.danmakuConnectionStatus,
                controlsVisible: isMaskVisible,
                controlBottomInset: isFullscreen ? FullUIPlayerChrome.inset : controlPadding
            )

            if isFullscreen && fullscreenMenu.isPresented {
                fullscreenSettingsMenu
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
        }
        .onChange(of: isPopupOpen) { _, isOpen in
            isPopupPresented = isOpen
            if isOpen {
                cancelAutoHideTimer()
            } else if isMaskVisible {
                startAutoHideTimer()
            }
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

    private var fullscreenSettingsMenu: some View {
        let inset = FullUIPlayerChrome.inset
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { fullscreenMenu.isPresented = false }
                .accessibilityHidden(true)

            FullUIPlaybackMenu(state: fullscreenMenu, timer: playbackTimer)
                .padding(.trailing, inset)
                .padding(.top, inset + FullUIPlayerChrome.controlSize + 6)
                .padding(.bottom, 8)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var showsCentralPlay: Bool {
        !bridge.isPlaying && !bridge.isBuffering && !bridge.isInitialLoading
    }

    private var detailControls: some View {
        ZStack {
            lockButton
            if !bridge.isLocked.wrappedValue {
                backButtonLayer
                topRightLayer
                if showsCentralPlay {
                    Button(action: bridge.togglePlayPause) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                bottomLeftLayer
                bottomRightLayer
            }
        }
        .padding([.horizontal, .bottom], controlPadding)
    }

    private var fullscreenControls: some View {
        let inset = FullUIPlayerChrome.inset
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
                    fullscreenBottomBar
                }

                if showsCentralPlay {
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
                    .frame(maxWidth: .infinity)
                    .offset(y: videoCenterOffset)
                    .accessibilityLabel("播放")
                }
            }
        }
        .padding(inset)
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

            FullUIPlayerGlassGroup {
                if bridge.supportsPictureInPicture {
                    chromeButton("pip", label: "画中画", action: bridge.togglePictureInPicture)
                }
                scaleModeMenu
                settingsButton(fullscreen: true)
            }
        }
    }

    private var fullscreenBottomBar: some View {
        HStack {
            FullUIPlayerGlassGroup {
                chromeButton(bridge.isPlaying ? "pause.fill" : "play.fill", label: bridge.isPlaying ? "暂停" : "播放") {
                    bridge.togglePlayPause()
                }
                chromeButton("arrow.counterclockwise", label: "刷新", action: bridge.refreshPlayback)
                    .disabled(viewModel.isLoading)
            }

            Spacer(minLength: 12)

            FullUIPlayerGlassGroup {
                danmakuButton(size: FullUIPlayerChrome.controlSize)
                qualityMenu
                chromeButton(fullscreenIconName, label: "退出全屏", action: toggleOrientationOrFullscreen)
            }
        }
    }

    private func danmakuButton(size: CGFloat) -> some View {
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
                .frame(width: size, height: size)
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
                    .padding(size == 30 ? 3 : 8)
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
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: - Lock Button

    private var lockButton: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        bridge.isLocked.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: bridge.isLocked.wrappedValue ? "lock.fill" : "lock.open")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Back Button

    private var backButtonLayer: some View {
        VStack {
            HStack {
                Button {
                    handleBackButton()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .padding(-10)
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
        }
        .padding(.top, topControlPadding)
        .transition(.opacity)
    }

    // MARK: - Detail Top Right

    private var topRightLayer: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    if bridge.supportsPictureInPicture {
                        Button {
                            bridge.togglePictureInPicture()
                        } label: {
                            Image(systemName: "pip")
                                .frame(width: 30, height: 30)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsButton(fullscreen: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(height: topControlRowHeight)
            }
            Spacer()
        }
        .padding(.top, topControlPadding)
        .transition(.opacity)
    }

    private func settingsButton(fullscreen: Bool) -> some View {
        SettingsButton(
            showVideoSetting: $showVideoSetting,
            showDanmakuSettings: $showDanmakuSettings,
            onDismiss: { dismiss() },
            onPopupStateChanged: { isSettingsPopupOpen = $0 },
            fullscreenMenu: fullscreen ? fullscreenMenu : nil,
            playbackTimer: playbackTimer
        )
    }

    // MARK: - Bottom Left (Play/Pause + Refresh)

    private var bottomLeftLayer: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 16) {
                    Button {
                        bridge.togglePlayPause()
                    } label: {
                        Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        bridge.refreshPlayback()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
        }
    }

    // MARK: - Bottom Right (Danmu + Quality + Fullscreen)

    private var bottomRightLayer: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    danmakuButton(size: 30)

                    qualityMenu

                    Button {
                        toggleOrientationOrFullscreen()
                    } label: {
                        Image(systemName: fullscreenIconName)
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Quality Menu

    private var qualityMenu: some View {
        Button {
            showQualityPanel = true
        } label: {
            if isFullscreen {
                let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                let width = ("清晰度清晰度" as NSString).size(withAttributes: [.font: font]).width
                FullUIPlayerName(viewModel.currentPlayQualityString, font: font, maximumWidth: width)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                Text(viewModel.currentPlayQualityString)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
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
        if isFullscreen && (!bridge.isPlaying || voiceOverEnabled || bridge.isLocked.wrappedValue) { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && !isPopupOpen && (!isFullscreen || (bridge.isPlaying && !voiceOverEnabled && !bridge.isLocked.wrappedValue)) {
                isMaskVisible = false
            }
        }
    }

    private func cancelAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
