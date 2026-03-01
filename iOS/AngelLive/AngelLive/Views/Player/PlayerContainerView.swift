//
//  PlayerContainerView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

// MARK: - Preference Key for Player Height

struct PlayerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preference Key for Vertical Live Mode

struct VerticalLiveModePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

// MARK: - Vertical Live Mode Environment Key

struct VerticalLiveModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Safe Area Insets Environment Key

struct SafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = EdgeInsets()
}

extension EnvironmentValues {
    var safeAreaInsetsCustom: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

/// 播放器容器视图
struct PlayerContainerView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @ObservedObject var playerModel: KSVideoPlayerModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 检测是否为 iPad 横屏
    private var isIPadLandscape: Bool {
        AppConstants.Device.isIPad &&
        horizontalSizeClass == .regular &&
        verticalSizeClass == .compact
    }

    var body: some View {
        PlayerContentView(playerCoordinator: coordinator, playerModel: playerModel)
            .environment(viewModel)
    }
}

struct PlayerContentView: View {

    @Environment(RoomInfoViewModel.self) private var viewModel
    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator
    @ObservedObject var playerModel: KSVideoPlayerModel
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // 默认 16:9 横屏，减少跳动
    @State private var isVideoPortrait: Bool = false
    @State private var hasDetectedSize: Bool = false // 是否已检测到真实尺寸
    @State private var isVerticalLiveMode: Bool = false // 是否为竖屏直播模式
    @State private var vlcState: VLCPlaybackBridgeState = .buffering
    @State private var showVideoSetting = false
    @State private var showDanmakuSettings = false
    @State private var showVLCUnsupportedHint = false
    @StateObject private var vlcPlaybackController = VLCPlaybackController()
    @State private var hasVLCStartedPlayback = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 检测设备是否为横屏
    private var isDeviceLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    // 生成基于方向的唯一 key
    private var playerViewKey: String {
        "\(viewModel.currentPlayURL?.absoluteString ?? "")_\(isDeviceLandscape ? "landscape" : "portrait")"
    }

    private var useKSPlayer: Bool {
        viewModel.selectedPlayerKernel == .ksplayer && PlayerKernelSupport.isKSPlayerAvailable
    }

    var body: some View {
        GeometryReader { geometry in
            let playerHeight = calculatedHeight(for: geometry.size)

            playerContent
            .frame(
                width: geometry.size.width,
                height: isVerticalLiveMode ? nil : playerHeight
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: isVerticalLiveMode ? .infinity : nil,
                alignment: .center
            )
            .background(AppConstants.Device.isIPad ? Color.black : (isDeviceLandscape ? Color.black : Color.clear))
            .preference(key: PlayerHeightPreferenceKey.self, value: playerHeight)
            .preference(key: VerticalLiveModePreferenceKey.self, value: isVerticalLiveMode)
        }
        .edgesIgnoringSafeArea(isVerticalLiveMode ? .all : [])
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            Logger.debug(
                "[PlayerFlow] willResignActive, kernel=\(viewModel.selectedPlayerKernel.rawValue), useKS=\(useKSPlayer), url=\(compactURL(viewModel.currentPlayURL))",
                category: .player
            )
            if useKSPlayer {
                // 进入后台时自动开启画中画（每次读取最新设置值）
                if PlayerSettingModel().enableAutoPiPOnBackground {
                    if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer,
                       !playerLayer.isPictureInPictureActive {
                        playerLayer.pipStart()
                    }
                }
            } else {
                vlcPlaybackController.enterBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Logger.debug(
                "[PlayerFlow] didBecomeActive, kernel=\(viewModel.selectedPlayerKernel.rawValue), useKS=\(useKSPlayer), url=\(compactURL(viewModel.currentPlayURL))",
                category: .player
            )
            if useKSPlayer {
                // 返回前台时自动关闭画中画
                if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer,
                   playerLayer.isPictureInPictureActive {
                    playerLayer.pipStop(restoreUserInterface: true)
                }
            } else {
                vlcPlaybackController.becomeActive()
            }
        }
        .onChange(of: playerCoordinator.state) {
            let state = playerCoordinator.state
            guard useKSPlayer else { return }
            Logger.debug("[PlayerFlow] KS state changed -> \(state)", category: .player)
            switch state {
            case .readyToPlay:
                viewModel.isPlaying = true
            case .paused, .playedToTheEnd, .error:
                viewModel.isPlaying = false
            case .initialized, .buffering:
                break
            default:
                break
            }
        }
        .onChange(of: showVideoSetting) { _, isPresented in
            guard !useKSPlayer, isPresented else { return }
            Logger.debug("[PlayerFlow] VLC setting tapped, show unsupported hint", category: .player)
            showVideoSetting = false
            showVLCUnsupportedHint = true
        }
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsSheet(isPresented: $showDanmakuSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("提示", isPresented: $showVLCUnsupportedHint) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("VLC 内核暂不支持视频信息统计。")
        }
        .onDisappear {
            guard !useKSPlayer else { return }
            // 兜底关闭会话，真正停播在 VLC 视图 onDisappear 中处理，避免重复 stop。
            Logger.debug(
                "[PlayerFlow] PlayerContentView onDisappear, deactivate VLC session, url=\(compactURL(viewModel.currentPlayURL))",
                category: .player
            )
            vlcPlaybackController.deactivateSession()
            hasVLCStartedPlayback = false
            vlcState = .stopped
        }
    }

    // 计算视频高度
    private func calculatedHeight(for size: CGSize) -> CGFloat {
        let shouldFillHeight = isDeviceLandscape || AppConstants.Device.isIPad || isVerticalLiveMode
        let calculatedByRatio = size.width / videoAspectRatio

        return shouldFillHeight ? size.height : calculatedByRatio
    }

    // MARK: - Player Content

    private var playerContent: some View {
        Group {
            // 如果有播放地址，显示播放器
            if let playURL = viewModel.currentPlayURL {
                ZStack {
                    compatiblePlayerSurface(playURL: playURL)

                    if shouldShowBuffering {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    }

                    UnifiedPlayerControlOverlay(
                        bridge: controlBridge,
                        showVideoSetting: $showVideoSetting,
                        showDanmakuSettings: $showDanmakuSettings
                    )

                    #if canImport(KSPlayer)
                    if useKSPlayer && showVideoSetting {
                        VideoSettingHUDView(model: playerModel, isShowing: $showVideoSetting)
                            .padding(.trailing, 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    #endif
                }
                .task(id: "\(playURL.absoluteString)_\(viewModel.selectedPlayerKernel.rawValue)") {
                    Logger.debug(
                        "[PlayerFlow] player task start, kernel=\(viewModel.selectedPlayerKernel.rawValue), url=\(compactURL(playURL))",
                        category: .player
                    )
                    if useKSPlayer {
                        #if canImport(KSPlayer)
                        configureModelIfNeeded(playURL: playURL)

                        // iPad 直接使用默认 16:9，不做尺寸探测，避免频繁重建
                        if AppConstants.Device.isIPad {
                            await MainActor.run {
                                applyVideoFillMode(isVerticalLive: false)
                                videoAspectRatio = 16.0 / 9.0
                                isVideoPortrait = false
                                isVerticalLiveMode = false
                                hasDetectedSize = true
                            }
                            return
                        }

                        // 使用异步任务定期检查视频尺寸
                        var retryCount = 0
                        let maxRetries = 40 // 最多重试 40 次（10 秒）

                        print("🔍 开始检测视频尺寸... URL: \(playURL.absoluteString)")

                        while !Task.isCancelled && retryCount < maxRetries {
                            if let naturalSize = playerCoordinator.playerLayer?.player.naturalSize,
                               naturalSize.width > 0, naturalSize.height > 0 {

                                // 检查是否为有效尺寸（排除 1.0 x 1.0 等占位符）
                                let isValidSize = naturalSize.width > 1.0 && naturalSize.height > 1.0

                                if !isValidSize {
                                    print("⚠️ 检测到无效视频尺寸: \(naturalSize.width) x \(naturalSize.height)，继续等待... (\(retryCount)/\(maxRetries))")
                                } else if !hasDetectedSize {
                                    let ratio = naturalSize.width / naturalSize.height
                                    let isPortrait = ratio < 1.0
                                    let isVerticalLive = isPortrait && naturalSize.height >= 1280

                                    print("📺 视频尺寸: \(naturalSize.width) x \(naturalSize.height)")
                                    print("📐 视频比例: \(ratio)")
                                    print("📱 视频方向: \(isPortrait ? "竖屏" : "横屏")")
                                    print("🖥️ 设备方向: \(isDeviceLandscape ? "横屏" : "竖屏")")

                                    if isVerticalLive {
                                        print("🎬 检测到竖屏直播模式！高度: \(naturalSize.height)")
                                    }

                                    await MainActor.run {
                                        applyVideoFillMode(isVerticalLive: isVerticalLive)

                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            videoAspectRatio = ratio
                                            isVideoPortrait = isPortrait
                                            isVerticalLiveMode = isVerticalLive
                                            hasDetectedSize = true
                                        }
                                    }

                                    break // 获取到后退出循环
                                } else {
                                    // 已经检测过，直接退出
                                    break
                                }
                            }

                            retryCount += 1
                            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25秒
                        }

                        // 超时后仍未获取到有效尺寸，强制显示（使用默认 16:9 比例）
                        if retryCount >= maxRetries && !hasDetectedSize {
                            await MainActor.run {
                                applyVideoFillMode(isVerticalLive: false)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    hasDetectedSize = true
                                }
                            }
                        }
                        #endif
                    } else {
                        await MainActor.run {
                            Logger.debug("[PlayerFlow] task prepare VLC defaults", category: .player)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                videoAspectRatio = 16.0 / 9.0
                                isVideoPortrait = false
                                isVerticalLiveMode = false
                                hasDetectedSize = true
                                hasVLCStartedPlayback = false
                            }
                        }
                    }
                }
                .onChange(of: playURL) { _ in
                    Logger.debug("[PlayerFlow] playURL changed -> \(compactURL(playURL)), reset detect states", category: .player)
                    // 切换视频时重置为默认 16:9 比例并重新检测
                    videoAspectRatio = 16.0 / 9.0
                    isVideoPortrait = false
                    isVerticalLiveMode = false
                    hasDetectedSize = false
                    hasVLCStartedPlayback = false
                    if useKSPlayer {
                        applyVideoFillMode(isVerticalLive: false) // 重置为默认的 fit 模式
                    }
                    // task(id: playURL.absoluteString) 会自动触发重新检测
                }
            } else {
                if viewModel.isLoading {
                    // 加载中
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("正在解析直播地址...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // 封面图作为背景
                    KFImage(URL(string: viewModel.currentRoom.roomCover))
                        .placeholder {
                            Rectangle()
                                .fill(AppConstants.Colors.placeholderGradient())
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func compatiblePlayerSurface(playURL: URL) -> some View {
        if useKSPlayer {
            #if canImport(KSPlayer)
            KSVideoPlayerView(
                model: playerModel,
                subtitleDataSource: nil,
                liftCycleBlock: { coordinator, isDisappear in
                    if !isDisappear {
                        viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                    }
                },
                showsControlLayer: false
            )
            .frame(maxWidth: .infinity, maxHeight: isVerticalLiveMode ? .infinity : nil)
            .clipped()
            #else
            vlcPlayerView(playURL: playURL)
            #endif
        } else {
            vlcPlayerView(playURL: playURL)
        }
    }

    private func vlcPlayerView(playURL: URL) -> some View {
        VLCVideoPlayerView(url: playURL, options: viewModel.playerOption, controller: vlcPlaybackController) { state in
            Logger.debug(
                "[PlayerFlow] VLC bridge callback state=\(state), url=\(compactURL(playURL)), sessionActive=\(vlcPlaybackController.isSessionActive)",
                category: .player
            )
            vlcState = state
            switch state {
            case .playing:
                viewModel.isPlaying = true
                hasVLCStartedPlayback = true
            case .paused, .stopped, .error:
                viewModel.isPlaying = false
            case .buffering:
                break
            }
        }
        .onAppear {
            Logger.debug("[PlayerFlow] VLC surface onAppear, activate session, url=\(compactURL(playURL))", category: .player)
            vlcPlaybackController.activateSession()
        }
        .onDisappear {
            Logger.debug("[PlayerFlow] VLC surface onDisappear, stop + deactivate, url=\(compactURL(playURL))", category: .player)
            vlcPlaybackController.deactivateSession()
            vlcPlaybackController.stop()
            hasVLCStartedPlayback = false
            vlcState = .stopped
        }
        .frame(maxWidth: .infinity, maxHeight: isVerticalLiveMode ? .infinity : nil)
        .clipped()
    }

    private var shouldShowBuffering: Bool {
        if useKSPlayer {
            return playerCoordinator.state == .buffering || playerCoordinator.playerLayer?.player.playbackState == .seeking
        }
        // VLC 直播流在播放后仍可能短暂回报 buffering，避免中间菊花常驻干扰观看。
        return vlcState.isBuffering && !hasVLCStartedPlayback
    }

    private var controlBridge: PlayerControlBridge {
        if useKSPlayer {
            return PlayerControlBridge(
                isPlaying: viewModel.isPlaying || playerCoordinator.state.isPlaying,
                isBuffering: playerCoordinator.state == .buffering || playerCoordinator.playerLayer?.player.playbackState == .seeking,
                supportsPictureInPicture: playerCoordinator.playerLayer is KSComplexPlayerLayer,
                togglePlayPause: {
                    if viewModel.isPlaying || playerCoordinator.state.isPlaying {
                        playerCoordinator.playerLayer?.pause()
                    } else {
                        playerCoordinator.playerLayer?.play()
                    }
                },
                refreshPlayback: {
                    viewModel.refreshPlayback()
                },
                togglePictureInPicture: {
                    if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer {
                        if playerLayer.isPictureInPictureActive {
                            playerLayer.pipStop(restoreUserInterface: true)
                        } else {
                            playerLayer.pipStart()
                        }
                    }
                }
            )
        }

        return PlayerControlBridge(
            isPlaying: viewModel.isPlaying,
            isBuffering: vlcState.isBuffering,
            supportsPictureInPicture: vlcPlaybackController.isPictureInPictureSupported,
            togglePlayPause: {
                vlcPlaybackController.togglePlayPause()
            },
            refreshPlayback: {
                viewModel.refreshPlayback()
            },
            togglePictureInPicture: {
                vlcPlaybackController.togglePictureInPicture()
            }
        )
    }

    // 判断是否需要限制宽度（横屏设备 + 竖屏视频）
    private var shouldLimitWidth: Bool {
        isDeviceLandscape && isVideoPortrait
    }

    @MainActor
    private func applyVideoFillMode(isVerticalLive: Bool) {
        playerCoordinator.isScaleAspectFill = isVerticalLive

        guard let playerLayer = playerCoordinator.playerLayer else {
            return
        }

        let targetContentMode: UIView.ContentMode = isVerticalLive ? .scaleAspectFill : .scaleAspectFit

        if playerLayer.player.contentMode != targetContentMode {
            playerLayer.player.contentMode = targetContentMode
        }

        let playerView = playerLayer.player.view
        playerView.clipsToBounds = isVerticalLive
        playerView.layer.masksToBounds = isVerticalLive
        playerView.setNeedsLayout()
        playerView.layoutIfNeeded()
    }

    /// 确保播放器模型只创建一次并与全局 coordinator / options 对齐
    private func configureModelIfNeeded(playURL: URL) {
        // 让模型使用外部的 coordinator 和当前 options
        if playerModel.config !== playerCoordinator {
            playerModel.config = playerCoordinator
        }
        playerModel.options = viewModel.playerOption

        // 仅当 URL 变化时才更新，避免重复创建/重置
        if playerModel.url != playURL {
            playerModel.url = playURL
        }
    }

    private func compactURL(_ url: URL?) -> String {
        guard let url else { return "nil" }
        let host = url.host ?? "unknown-host"
        return "\(host)\(url.path)"
    }
}

// MARK: - Video Aspect Ratio Modifier

/// 视频比例修饰器
/// - 所有情况: 填满容器，无比例限制
private struct VideoAspectRatioModifier: ViewModifier {
    let aspectRatio: CGFloat?
    let isIPad: Bool
    let isLandscape: Bool

    func body(content: Content) -> some View {
        // 所有情况都填满容器，不设置 aspectRatio
        content
    }
}
