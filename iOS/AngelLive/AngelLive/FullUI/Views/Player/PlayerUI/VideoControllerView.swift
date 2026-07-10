#if canImport(KSPlayer)

//
//  VideoControllerView.swift
//  AngelLive
//
//  Forked and modified from KSPlayer by kintan
//  Created by pangchong on 10/26/25.
//

import Foundation
import SwiftUI
import KSPlayer
internal import AVFoundation
import AngelLiveCore
import AngelLiveDependencies

struct VideoControllerView: View {
    @ObservedObject
    private var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.isVerticalLiveMode) private var isVerticalLiveMode
    @Environment(\.safeAreaInsetsCustom) private var safeAreaInsets
    @State private var showDanmakuSettings = false
    @State private var autoHideTask: Task<Void, Never>? // 自动隐藏控制层的任务
    @State private var isSettingsPopupOpen = false // SettingsButton 内部弹窗状态
    @State private var showQualityPanel = false
    @State private var videoScaleMode: VideoScaleMode = PlayerSettingModel().videoScaleMode
    @State private var statusBarVM = StatusBarViewModel()

    /// 是否有弹窗/菜单展开（展开时暂停自动隐藏）
    private var isPopupOpen: Bool {
        showDanmakuSettings || model.showVideoSetting || isSettingsPopupOpen || showQualityPanel
    }

    private var playerWidth: CGFloat {
        model.config.playerLayer?.player.view.frame.width ?? 0
    }

    /// 检测是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    /// iPhone 横屏时需要忽略安全区（刘海/指示器区域也覆盖控制层）
    private var shouldIgnoreSafeArea: Bool {
        isLandscape && !AppConstants.Device.isIPad
    }

    /// 控制层基础内边距。iPhone 横屏使用更统一的角落留白，避免和圆角节奏打架。
    private var controlPadding: CGFloat {
        if isLandscape {
            return AppConstants.Device.isIPad ? 20 : 16
        }
        return 12
    }

    /// 锁屏按钮单独按左侧安全区收进去，其余四角控制统一先试 25pt。
    private var iPhoneLandscapeLockInset: CGFloat {
        shouldIgnoreSafeArea ? safeAreaInsets.leading + 5 : 0
    }

    private var iPhoneLandscapeCornerInset: CGFloat {
        shouldIgnoreSafeArea ? 25 : 0
    }

    /// 顶部一排控制的目标高度，和返回按钮的 50pt 点击区对齐。
    private let topControlRowHeight: CGFloat = 50

    /// 顶部状态信息仅在全屏时显示，并放在屏幕宽度中心。
    private var showsCenteredStatusBar: Bool {
        isLandscape || isIPadFullscreen.wrappedValue
    }

    /// iPadOS 26 窗口控制按钮的参考几何：x=20, y=20, width=38, height=20。
    private var windowControlsFrame: CGRect? {
        guard AppConstants.Device.isIPad else { return nil }
        guard #available(iOS 26.0, *) else { return nil }
        return CGRect(x: 20, y: 20, width: 38, height: 20)
    }

    /// 仅在 iPad 窗口化运行时，为左上返回按钮预留红绿灯空间。
    private var shouldOffsetBackButtonForWindowControls: Bool {
        guard windowControlsFrame != nil else { return false }
        guard #available(iOS 26.0, *) else { return false }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return false
        }

        let sceneBounds = windowScene.effectiveGeometry.coordinateSpace.bounds
        let screenBounds = windowScene.screen.coordinateSpace.bounds
        let tolerance: CGFloat = 2

        return abs(sceneBounds.width - screenBounds.width) > tolerance ||
            abs(sceneBounds.height - screenBounds.height) > tolerance
    }

    private var windowControlsLeadingInset: CGFloat {
        guard shouldOffsetBackButtonForWindowControls, let frame = windowControlsFrame else { return 0 }
        return frame.maxX + 12
    }

    /// 顶部返回按钮与右上角控制层都使用 50pt 行高，统一下移 2pt 后继续保持 centerY 对齐。
    private var topControlPadding: CGFloat {
        guard windowControlsFrame != nil else { return controlPadding }
        return 7
    }

    private var centeredStatusBarTopPadding: CGFloat {
        5
    }

    /// 顶部阴影覆盖时间、电池和控制按钮，提升花屏背景下的可读性。
    private var topShadowHeight: CGFloat {
        (max(topControlPadding + topControlRowHeight, centeredStatusBarTopPadding + 20) + 32) * 0.75
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

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    // MARK: - Helper Methods

    /// 启动/重置自动隐藏计时器
    private func startAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && !isPopupOpen {
                model.config.isMaskShow = false
            }
        }
    }

    /// 取消自动隐藏计时器
    private func cancelAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    /// 应用视频缩放模式
    private func applyVideoScaleMode(_ mode: VideoScaleMode) {
        // 保存设置
        let playerSetting = PlayerSettingModel()
        playerSetting.videoScaleMode = mode

        guard let playerLayer = model.config.playerLayer else { return }
        let player = playerLayer.player

        switch mode {
        case .fit:
            // 适应：保持比例，可能有黑边
            player.contentMode = .scaleAspectFit
        case .stretch:
            // 拉伸：填满屏幕，不保持比例
            player.contentMode = .scaleToFill
        case .fill:
            // 铺满：保持比例，裁剪填满
            player.contentMode = .scaleAspectFill
        }
    }

    /// 状态栏内容（时间 + 电池），模仿系统状态栏样式，无背景
    @ViewBuilder
    private var statusBarContent: some View {
        HStack(spacing: 4) {
            Text(statusBarVM.formattedTime)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: statusBarVM.batteryIconName)
                .font(.system(size: 11))
                .foregroundStyle(statusBarVM.batteryColor)
        }
    }

    /// 处理返回按钮点击
    /// - iPad 全屏时：退出全屏
    /// - iPhone 横屏时：退出全屏（切换到竖屏）
    /// - 其他情况：返回上一页
    private func handleBackButton() {
        if AppConstants.Device.isIPad && isIPadFullscreen.wrappedValue {
            // iPad 全屏，退出全屏（不改变方向）
            isIPadFullscreen.wrappedValue = false
            return
        } else if !AppConstants.Device.isIPad && UIApplication.isLandscape {
            // iPhone 横屏，切换回竖屏
            KSOptions.supportedInterfaceOrientations = .portrait

            // 使用 iOS 16+ API
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else {
                    return
                }

                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: .portrait
                )

                // 先通知 ViewController 刷新支持的方向
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
                DispatchQueue.main.async {
                    windowScene.requestGeometryUpdate(geometryPreferences) { error in
                        Logger.warning("退出全屏失败: \(error)", category: .ui)
                    }
                    // 旋转完成后恢复自由旋转
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                        if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                        }
                    }
                }
            } else {
                // iOS 16 以下降级方案
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        } else {
            // 竖屏，返回上一页
            dismiss()
            KSOptions.supportedInterfaceOrientations = .portrait
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        // 根据模式选择不同的控制层
        if isVerticalLiveMode {
            VerticalLiveControllerView(model: model)
        } else {
            ZStack {
                // 顶/底部渐变背景（锁定时隐藏）
                if !model.isLocked {
                    topShadowGradient
                        .opacity(model.config.isMaskShow ? 1 : 0)

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
                    .opacity(model.config.isMaskShow ? 1 : 0)
                }

                // 控制按钮层（带 padding）
                ZStack {
                    // 左侧中间：锁定按钮（始终显示）
                    VStack {
                        Spacer()
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.isLocked.toggle()
                                }
                            } label: {
                                Image(systemName: model.isLocked ? "lock.fill" : "lock.open")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .adaptiveCircleGlassEffect()
                            }
                            .ksBorderlessButton()
                            .padding(.leading, iPhoneLandscapeLockInset)
                            Spacer()
                        }
                        Spacer()
                    }
                    .transition(.opacity)

                    // 左上角：返回按钮（始终显示，锁定时隐藏）
                    if !model.isLocked {
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
                                .padding(.leading, windowControlsLeadingInset + iPhoneLandscapeCornerInset)
                                .ksBorderlessButton()
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(.top, topControlPadding)
                        .transition(.opacity)
                    }

                    if !model.isLocked {
                        if showsCenteredStatusBar {
                            VStack {
                                statusBarContent
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, centeredStatusBarTopPadding)
                                Spacer()
                            }
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }

                        // 右上角：投屏、画面平铺、画中画、设置按钮（锁定时隐藏）
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                HStack(spacing: 16) {
                                    // AirPlay 和画面缩放仅在横屏/全屏时显示
                                    // AirPlay 仅在 HLS 流时可用（FLV 投屏只有音频）
                                    if isLandscape || isIPadFullscreen.wrappedValue {
                                        if viewModel.isHLSStream && model.config.playerLayer?.player.allowsExternalPlayback == true {
                                            AirPlayView()
                                                .frame(width: 30, height: 30)
                                        }
                                        KSVideoPlayerViewBuilder.scaleModeMenuButton(
                                            config: model.config,
                                            currentMode: $videoScaleMode,
                                            onModeChange: { mode in
                                                applyVideoScaleMode(mode)
                                            }
                                        )
                                    }
                                    KSVideoPlayerViewBuilder.pipButton(config: model.config)
                                    SettingsButton(
                                        showVideoSetting: $model.showVideoSetting,
                                        showDanmakuSettings: $showDanmakuSettings,
                                        onDismiss: { dismiss() },
                                        onPopupStateChanged: { isOpen in
                                            isSettingsPopupOpen = isOpen
                                            if isOpen {
                                                cancelAutoHideTimer()
                                            } else if model.config.isMaskShow {
                                                startAutoHideTimer()
                                            }
                                        }
                                    )
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .adaptiveGlassEffect()
                                .frame(height: topControlRowHeight)
                                .padding(.trailing, iPhoneLandscapeCornerInset)
                            }
                            Spacer()
                        }
                        .padding(.top, topControlPadding)
                        .transition(.opacity)
                    }

                    // 中间：播放/暂停按钮（播放时隐藏，锁定时隐藏）
                    if !viewModel.isPlaying && !model.isLocked {
                        KSVideoPlayerViewBuilder.playButton(config: model.config, isPlaying: viewModel.isPlaying)
                    }

                    // 左下角：播放/暂停、刷新按钮（锁定时隐藏）
                    if !model.isLocked {
                        VStack {
                            Spacer()
                            HStack {
                                HStack(spacing: 16) {
                                    KSVideoPlayerViewBuilder.playButton(config: model.config, isToolbar: true, isPlaying: viewModel.isPlaying)
                                    KSVideoPlayerViewBuilder.refreshButton(isLoading: viewModel.isLoading) {
                                        viewModel.refreshPlayback()
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .adaptiveGlassEffect()
                                .padding(.leading, iPhoneLandscapeCornerInset)
                                Spacer()
                            }
                        }
                    }

                    // 右下角：弹幕开关、清晰度设置、竖屏按钮（可选）、全屏按钮（锁定时隐藏）
                    if !model.isLocked {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 16) {
                                    if viewModel.supportsDanmu {
                                        // 弹幕开关按钮
                                        KSVideoPlayerViewBuilder.danmakuButton(showDanmu: $viewModel.danmuSettings.showDanmu)
                                    }

                                    // 清晰度设置菜单
                                    KSVideoPlayerViewBuilder.qualityMenuButton(viewModel: viewModel, showQualitySheet: $showQualityPanel)

                                    // 竖屏按钮（仅在视频为竖屏时显示）
                                    if let naturalSize = model.config.playerLayer?.player.naturalSize,
                                       !naturalSize.isHorizonal {
                                        KSVideoPlayerViewBuilder.portraitButton
                                    }

                                    // 全屏按钮
                                    KSVideoPlayerViewBuilder.landscapeButton(isIPadFullscreen: isIPadFullscreen)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .adaptiveGlassEffect()
                                .padding(.trailing, iPhoneLandscapeCornerInset)
                            }
                        }
                    }
                }
                .padding(.leading, controlPadding)
                .padding(.trailing, controlPadding)
                .padding(.bottom, controlPadding)
                .opacity(model.config.isMaskShow ? 1 : 0)
                .ignoresSafeArea(shouldIgnoreSafeArea ? .all : [])
                // 捕获控制层上的任何触摸，重置自动隐藏计时器
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            if model.config.isMaskShow && !isPopupOpen {
                                startAutoHideTimer()
                            }
                        }
                )

                // HUD 设置面板（右侧滑入，无 padding）
                if model.showVideoSetting {
                    VideoSettingHUDView(model: model, isShowing: $model.showVideoSetting)
                        .padding(.top, 0)
                        .padding(.bottom, 0)
                        .padding(.trailing, 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .background(
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.showVideoSetting = false
                                }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .ignoresSafeArea(shouldIgnoreSafeArea ? .all : [])
                }

                // 清晰度选择面板（右侧滑入）
                if showQualityPanel {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { showQualityPanel = false }
                    QualitySelectionPanel(isShowing: $showQualityPanel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .ignoresSafeArea(shouldIgnoreSafeArea ? .all : [])
                }
            }
            .ksIsFocused($model.focusableView, equals: .controller)
            .font(.body)
            .buttonStyle(.borderless)
            .animation(.easeInOut(duration: 0.3), value: model.showVideoSetting)
            .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
            .sheet(isPresented: $showDanmakuSettings) {
                DanmakuSettingsSheet(isPresented: $showDanmakuSettings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            // 控制层显示时启动自动隐藏计时器
            .onChange(of: model.config.isMaskShow) { _, isMaskShow in
                if isMaskShow && !isPopupOpen {
                    startAutoHideTimer()
                } else if !isMaskShow {
                    cancelAutoHideTimer()
                }
            }
            // 弹窗关闭后重新启动计时器
            .onChange(of: showDanmakuSettings) { _, isShowing in
                if !isShowing && model.config.isMaskShow && !isPopupOpen {
                    startAutoHideTimer()
                } else if isShowing {
                    cancelAutoHideTimer()
                }
            }
            .onChange(of: model.showVideoSetting) { _, isShowing in
                if !isShowing && model.config.isMaskShow && !isPopupOpen {
                    startAutoHideTimer()
                } else if isShowing {
                    cancelAutoHideTimer()
                }
            }
            .onAppear {
                // 视图首次出现时，如果控制层显示则启动自动隐藏计时器
                if model.config.isMaskShow && !isPopupOpen {
                    startAutoHideTimer()
                }
            }
            .onDisappear {
                cancelAutoHideTimer()
            }
        }
    }
}

struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
    fileprivate var timeFont: Font
    var body: some View {
        // 直播应用，只显示"直播中"
        Text("Live Streaming")
            .font(timeFont)
    }
}

// HUD 样式的设置视图
struct VideoSettingHUDView: View {
    @ObservedObject
    var model: KSVideoPlayerModel
    @Binding var isShowing: Bool
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var panelWidth: CGFloat {
        if AppConstants.Device.isIPad {
            return 420
        }
        return horizontalSizeClass == .compact ? 320 : 360
    }

    private var normalizedQualityTitle: String? {
        let trimmed = viewModel.currentPlayQualityString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "清晰度" else { return nil }
        return trimmed
    }

    private var currentStreamURL: URL? {
        viewModel.currentPlayURL ?? model.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        streamInfoSection

                        if let playerLayer = model.config.playerLayer {
                            videoInfoSection(playerLayer: playerLayer)
                            performanceInfoSection(playerLayer: playerLayer)
                        } else {
                            loadingState
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .adaptiveRoundedRectGlassEffect(cornerRadius: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("视频信息统计")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("实时查看当前流、解码方式和播放性能。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 12)

            Button {
                isShowing = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .adaptiveCircleGlassEffect()
            }
            .buttonStyle(.plain)
        }
    }

    private var currentPlayerType: MediaPlayerProtocol.Type {
        if let player = model.config.playerLayer?.player {
            return type(of: player)
        }
        return KSOptions.firstPlayerType
    }

    private var streamInfoSection: some View {
        sectionCard(title: "当前流", systemImage: "dot.radiowaves.left.and.right") {
            InfoRow(title: "播放方案", value: Self.playerDisplayName(for: currentPlayerType))

            if let normalizedQualityTitle {
                InfoRow(title: "当前清晰度", value: normalizedQualityTitle)
            }

            if let currentStreamURL {
                InfoRow(title: "流协议", value: Self.streamProtocol(for: currentStreamURL))
                InfoRow(title: "流地址", value: Self.formatStreamURL(currentStreamURL))
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("正在读取播放器统计信息...")
                .foregroundStyle(.white.opacity(0.72))
                .font(.system(size: 15, weight: .medium))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveRoundedRectGlassEffect(cornerRadius: 22)
    }

    @ViewBuilder
    private func videoInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let videoTrack = playerLayer.player.tracks(mediaType: .video).first { $0.isEnabled }
        let videoType = (videoTrack?.dynamicRange ?? .sdr).description
        let decodeType = playerLayer.options.videoDecodeType.rawValue
        let naturalSize = playerLayer.player.naturalSize
        let sizeText: String? = naturalSize.width > 0 && naturalSize.height > 0
            ? "\(Int(naturalSize.width)) x \(Int(naturalSize.height))"
            : nil

        sectionCard(title: "视频信息", systemImage: "film") {
            InfoRow(title: "视频类型", value: videoType)
            InfoRow(title: "解码方式", value: decodeType)
            if let sizeText {
                InfoRow(title: "视频尺寸", value: sizeText)
            }
        }
    }

    @ViewBuilder
    private func performanceInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let dynamicInfo = playerLayer.player.dynamicInfo
        let fpsText = String(format: "%.1f fps", dynamicInfo.displayFPS)
        let droppedFrames = dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount
        let syncText = String(format: "%.3f s", dynamicInfo.audioVideoSyncDiff)
        let networkSpeed = Self.formatBytes(Int64(dynamicInfo.networkSpeed)) + "/s"
        let videoBitrate = Self.formatBytes(Int64(dynamicInfo.videoBitrate)) + "ps"
        let audioBitrate = Self.formatBytes(Int64(dynamicInfo.audioBitrate)) + "ps"

        sectionCard(title: "性能信息", systemImage: "speedometer") {
            InfoRow(title: "显示帧率", value: fpsText)
            InfoRow(title: "丢帧数", value: "\(droppedFrames)")
            InfoRow(title: "音视频同步", value: syncText)
            InfoRow(title: "网络速度", value: networkSpeed)
            InfoRow(title: "视频码率", value: videoBitrate)
            InfoRow(title: "音频码率", value: audioBitrate)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveRoundedRectGlassEffect(cornerRadius: 22)
    }

    private static func playerDisplayName(for playerType: MediaPlayerProtocol.Type) -> String {
        let name = String(describing: playerType)
        if name.contains("KSAVPlayer") {
            return "AVPlayer"
        }
        if name.contains("KSMEPlayer") {
            return "MEPlayer"
        }
        return name
            .replacingOccurrences(of: "AngelLiveDependencies.", with: "")
            .replacingOccurrences(of: "KSPlayer.", with: "")
    }

    private static func streamProtocol(for url: URL) -> String {
        let lowercasedPath = url.path.lowercased()
        if lowercasedPath.contains(".m3u8") {
            return "HLS"
        }
        if lowercasedPath.contains(".flv") {
            return "FLV"
        }
        return url.scheme?.uppercased() ?? "未知"
    }

    private static func formatStreamURL(_ url: URL) -> String {
        let host = url.host() ?? url.host ?? url.absoluteString
        let lastPathComponent = url.lastPathComponent
        guard !lastPathComponent.isEmpty else { return host }

        if lastPathComponent.count <= 36 {
            return "\(host)/\(lastPathComponent)"
        }

        let prefix = lastPathComponent.prefix(16)
        let suffix = lastPathComponent.suffix(12)
        return "\(host)/\(prefix)...\(suffix)"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.white.opacity(0.72))
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent("Display FPS", value: dynamicInfo.displayFPS, format: .number)
        LabeledContent("Audio Video sync", value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent("Dropped Frames", value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent("Bytes Read", value: formatBytes(dynamicInfo.bytesRead) + "B")
        LabeledContent("Audio bitrate", value: formatBytes(Int64(dynamicInfo.audioBitrate)) + "bps")
        LabeledContent("Video bitrate", value: formatBytes(Int64(dynamicInfo.videoBitrate)) + "bps")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }
}

public struct HUDLogView: View {
    @ObservedObject
    public var dynamicInfo: DynamicInfo
    public var body: some View {
        Text(dynamicInfo.hudLogText)
            .foregroundColor(Color.orange)
            .multilineTextAlignment(.leading)
            .padding()
    }
}

private extension DynamicInfo {
    var hudLogText: String {
        var log = ""
        log += "Display FPS: \(displayFPS)\n"
        log += "Dropped Frames: \(droppedVideoFrameCount)\n"
        log += "Audio Video sync: \(audioVideoSyncDiff)\n"
        log += "Network Speed: \(formatBytes(Int64(networkSpeed)))B/s\n"
        #if DEBUG
        log += "Average Audio Video sync: \(averageAudioVideoSyncDiff)\n"
        #endif
        return log
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }
}

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(.black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func adaptiveCircleGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(.black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func adaptiveRoundedRectGlassEffect(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.interactive().tint(.black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

#endif
