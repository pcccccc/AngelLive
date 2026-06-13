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
    /// KSPlayer 路径首帧标志:state 第一次进入 .buffering / .bufferFinished 后置 true,
    /// 直播流 state 在 KSPlayer 内可能长期停留在 .buffering(KSPlayer 视为 isPlaying),
    /// 之后不能再把 .buffering 当作"加载中"以免 overlay 常驻。
    @State private var hasKSStartedPlayback = false
    /// VLC 模式下的控制层显示/隐藏状态
    @State private var vlcMaskShow: Bool = true
    /// VLC 模式下的锁定状态
    @State private var vlcIsLocked: Bool = false
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
        // 关键背景:RoomInfoViewModel.setPlayerDelegate 把 playerLayer.delegate 抢成 self,
        // 因此 KSVideoPlayer.Coordinator.state 永远停在 .initialized,不能用它做起播判定。
        // RoomInfoViewModel.player(layer:state:) 已经把 layer.player.isPlaying 写到 viewModel.isPlaying,
        // 直接订阅它作为 sticky 起播信号。one-way sticky:置 true 后不再因暂停翻回。
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            guard useKSPlayer else { return }
            if isPlaying {
                hasKSStartedPlayback = true
            }
        }
        .onAppear {
            // KSPlayer 路径启动统一恢复协调器的 1Hz 采样;起播超时/stall/finish 全由它接管。
            guard useKSPlayer else { return }
            viewModel.recoveryCoordinator.start()
        }
        .onDisappear {
            // 停掉协调器采样(stop 幂等,未启动也安全)。
            viewModel.recoveryCoordinator.stop()
        }
        .onChange(of: playerCoordinator.state) {
            let state = playerCoordinator.state
            guard useKSPlayer else { return }
            Logger.debug("[PlayerFlow] KS state changed -> \(state)", category: .player)
            switch state {
            case .readyToPlay:
                viewModel.isPlaying = true
                // readyToPlay 是读取真实 naturalSize 的最可靠时机
                if !hasDetectedSize,
                   let naturalSize = playerCoordinator.playerLayer?.player.naturalSize,
                   naturalSize.width > 1.0, naturalSize.height > 1.0 {
                    let ratio = naturalSize.width / naturalSize.height
                    let isPortrait = ratio < 1.0
                    let isVerticalLive = isPortrait
                    print("📺 [readyToPlay] 视频尺寸: \(naturalSize.width) x \(naturalSize.height)")
                    print("📐 [readyToPlay] 视频比例: \(ratio)")
                    print("📱 [readyToPlay] 视频方向: \(isPortrait ? "竖屏" : "横屏")")
                    applyVideoFillMode(isVerticalLive: isVerticalLive)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        videoAspectRatio = ratio
                        isVideoPortrait = isPortrait
                        isVerticalLiveMode = isVerticalLive
                        hasDetectedSize = true
                    }
                }
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

                    if shouldShowLoading {
                        #if canImport(KSPlayer)
                        StreamLoadingOverlay(
                            dynamicInfo: playerCoordinator.playerLayer?.player.dynamicInfo
                        )
                        #else
                        StreamLoadingOverlay(dynamicInfo: nil)
                        #endif
                    }

                    // 竖屏直播模式使用专用控制层，普通模式使用统一控制层
                    #if canImport(KSPlayer)
                    if isVerticalLiveMode && useKSPlayer {
                        VerticalLiveControllerView(model: playerModel)
                    } else {
                        UnifiedPlayerControlOverlay(
                            bridge: controlBridge,
                            showVideoSetting: $showVideoSetting,
                            showDanmakuSettings: $showDanmakuSettings
                        )
                    }
                    #else
                    UnifiedPlayerControlOverlay(
                        bridge: controlBridge,
                        showVideoSetting: $showVideoSetting,
                        showDanmakuSettings: $showDanmakuSettings
                    )
                    #endif

                    #if canImport(KSPlayer)
                    if useKSPlayer && showVideoSetting {
                        VideoSettingHUDView(model: playerModel, isShowing: $showVideoSetting)
                            .padding(.trailing, 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .background(
                                Color.black.opacity(0.001)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showVideoSetting = false
                                    }
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    #endif
                }
                .animation(.easeInOut(duration: 0.3), value: showVideoSetting)
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
                        let screenSize = await MainActor.run { UIScreen.main.bounds.size }

                        print("🔍 开始检测视频尺寸... URL: \(playURL.absoluteString)")

                        while !Task.isCancelled && retryCount < maxRetries {
                            // 已被 readyToPlay 回调提前设置，直接退出
                            if hasDetectedSize { break }

                            if let naturalSize = playerCoordinator.playerLayer?.player.naturalSize,
                               naturalSize.width > 1.0, naturalSize.height > 1.0 {

                                // 排除屏幕/视图初始渲染尺寸：
                                // 如果 naturalSize 和屏幕尺寸（或其翻转）完全一致，说明还没拿到真实视频尺寸
                                let isScreenSize =
                                    (naturalSize.width == screenSize.width && naturalSize.height == screenSize.height) ||
                                    (naturalSize.width == screenSize.height && naturalSize.height == screenSize.width)

                                if isScreenSize {
                                    print("⚠️ 视频尺寸为屏幕尺寸: \(naturalSize.width) x \(naturalSize.height)，继续等待... (\(retryCount)/\(maxRetries))")
                                } else if !hasDetectedSize {
                                    let ratio = naturalSize.width / naturalSize.height
                                    let isPortrait = ratio < 1.0
                                    let isVerticalLive = isPortrait

                                    print("📺 视频尺寸: \(naturalSize.width) x \(naturalSize.height)")
                                    print("📐 视频比例: \(ratio)")
                                    print("📱 视频方向: \(isPortrait ? "竖屏" : "横屏")")

                                    await MainActor.run {
                                        applyVideoFillMode(isVerticalLive: isVerticalLive)

                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            videoAspectRatio = ratio
                                            isVideoPortrait = isPortrait
                                            isVerticalLiveMode = isVerticalLive
                                            hasDetectedSize = true
                                        }
                                    }

                                    break
                                } else {
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
                    // 加载中 — 复用直播流加载层(Arc + "connecting")。
                    StreamLoadingOverlay(dynamicInfo: nil)
                } else {
                    // 封面图作为背景
                    KFImage(URL(string: viewModel.currentRoom.roomCover))
                        .placeholder {
                            ZStack {
                                Rectangle()
                                    .fill(AppConstants.Colors.placeholderGradient())
                                Image("placeholder")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .opacity(0.7)
                            }
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
        // VLC 模式下的单击手势，切换控制层显示/隐藏
        .contentShape(Rectangle())
        .onTapGesture {
            vlcMaskShow.toggle()
        }
        .frame(maxWidth: .infinity, maxHeight: isVerticalLiveMode ? .infinity : nil)
        .clipped()
    }

    private var shouldShowBuffering: Bool {
        if useKSPlayer {
            // 已经渲染过帧后,只在用户主动 seek 时再现 — 直播流 KSPlayer.state 长期停留
            // 在 .buffering 是常态(KSPlayer 视为 isPlaying),不能再以此判定"缓冲中"。
            if hasKSStartedPlayback {
                return playerCoordinator.playerLayer?.player.playbackState == .seeking
            }
            return playerCoordinator.state == .buffering || playerCoordinator.playerLayer?.player.playbackState == .seeking
        }
        // VLC 直播流在播放后仍可能短暂回报 buffering，避免中间菊花常驻干扰观看。
        return vlcState.isBuffering && !hasVLCStartedPlayback
    }

    /// 直播流首次加载（URL 已就绪但尚未开始播放）：区别于用户主动暂停。
    /// 命中时上层会显示「正在加载…」+ 网速，避免中间播放按钮误导用户「页面卡住」。
    private var isInitialStreamLoading: Bool {
        if useKSPlayer {
            #if canImport(KSPlayer)
            // 已经渲染过帧后,初次加载层退场 — 直播流可能长期停在 .buffering / .readyToPlay,
            // 不靠粘性标志退场就会永远盖着。
            if hasKSStartedPlayback { return false }
            // 按 KSPlayer 定义,state.isPlaying 仅 .buffering / .bufferFinished 为真;
            // .readyToPlay 是「准备好可以播」而非「已在播」,此时还没渲染过帧。
            // 必须把这三个 pre-play 状态都视为加载中,否则 .readyToPlay 一帧会撤掉 overlay
            // 暴露黑屏,紧接着 .buffering 又把 overlay 盖回来 —— 视觉上闪一下黑。
            switch playerCoordinator.state {
            case .initialized, .preparing, .readyToPlay:
                return true
            default:
                return false
            }
            #else
            return false
            #endif
        }
        // VLC 还未首次进入播放状态时视为加载中
        return !hasVLCStartedPlayback && vlcState != .error && vlcState != .stopped
    }

    /// 当前是否应展示加载指示（buffering 或初次加载）。
    private var shouldShowLoading: Bool {
        shouldShowBuffering || isInitialStreamLoading
    }

    private var controlBridge: PlayerControlBridge {
        if useKSPlayer {
            return PlayerControlBridge(
                isPlaying: viewModel.isPlaying || playerCoordinator.state.isPlaying,
                isBuffering: playerCoordinator.state == .buffering || playerCoordinator.playerLayer?.player.playbackState == .seeking,
                isInitialLoading: isInitialStreamLoading,
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
                },
                applyScaleMode: { mode in
                    guard let player = playerCoordinator.playerLayer?.player else { return }
                    switch mode {
                    case .fit:
                        player.contentMode = .scaleAspectFit
                    case .stretch:
                        player.contentMode = .scaleToFill
                    case .fill:
                        player.contentMode = .scaleAspectFill
                    }
                },
                isMaskShow: Binding(
                    get: { playerModel.config.isMaskShow },
                    set: { playerModel.config.isMaskShow = $0 }
                ),
                isLocked: Binding(
                    get: { playerModel.isLocked },
                    set: { playerModel.isLocked = $0 }
                )
            )
        }

        return PlayerControlBridge(
            isPlaying: viewModel.isPlaying,
            isBuffering: vlcState.isBuffering,
            isInitialLoading: isInitialStreamLoading,
            supportsPictureInPicture: vlcPlaybackController.isPictureInPictureSupported,
            togglePlayPause: {
                vlcPlaybackController.togglePlayPause()
            },
            refreshPlayback: {
                viewModel.refreshPlayback()
            },
            togglePictureInPicture: {
                vlcPlaybackController.togglePictureInPicture()
            },
            isMaskShow: $vlcMaskShow,
            isLocked: $vlcIsLocked
        )
    }

    // 判断是否需要限制宽度（横屏设备 + 竖屏视频）
    private var shouldLimitWidth: Bool {
        isDeviceLandscape && isVideoPortrait
    }

    @MainActor
    private func applyVideoFillMode(isVerticalLive: Bool) {
        // 竖屏直播始终 fill（产品规则，无视用户设置）；
        // 横屏：用户设置过 → 用 PlayerSettingModel.videoScaleMode，否则沿用 fit 默认。
        let targetContentMode: UIView.ContentMode
        if isVerticalLive {
            targetContentMode = .scaleAspectFill
        } else {
            let setting = PlayerSettingModel()
            if setting.hasUserSetVideoScaleMode {
                switch setting.videoScaleMode {
                case .fit:
                    targetContentMode = .scaleAspectFit
                case .stretch:
                    targetContentMode = .scaleToFill
                case .fill:
                    targetContentMode = .scaleAspectFill
                }
            } else {
                targetContentMode = .scaleAspectFit
            }
        }

        // 同步 KSPlayer Coordinator 自带的 fill 标志，避免内部状态和实际 contentMode 不一致。
        playerCoordinator.isScaleAspectFill = (targetContentMode == .scaleAspectFill)

        guard let playerLayer = playerCoordinator.playerLayer else {
            return
        }

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

// MARK: - 直播加载指示

/// 直播流加载层:细圆弧 + 数字/单位分体网速,无背景片,贴在视频画面上。
/// 网速订阅 KSPlayer 自带的 `DynamicInfo.networkSpeed`(@Published)。
struct StreamLoadingOverlay: View {
    #if canImport(KSPlayer)
    let dynamicInfo: DynamicInfo?
    #else
    let dynamicInfo: AnyObject?
    #endif

    var body: some View {
        VStack(spacing: 22) {
            ArcSpinner(size: 42, lineWidth: 1.8)
            #if canImport(KSPlayer)
            if let info = dynamicInfo {
                StreamSpeedText(info: info)
            } else {
                StreamPlaceholder()
            }
            #else
            StreamPlaceholder()
            #endif
        }
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 3)
    }
}

#if canImport(KSPlayer)
private struct StreamSpeedText: View {
    @ObservedObject var info: DynamicInfo

    var body: some View {
        if info.networkSpeed > 0 {
            let (value, unit) = SpeedFormatter.split(bytesPerSecond: Int64(info.networkSpeed))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: value)
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            StreamPlaceholder()
        }
    }
}
#endif

private struct StreamPlaceholder: View {
    var body: some View {
        Text("connecting")
            .font(.system(size: 12, weight: .medium))
            .tracking(2.5)
            .foregroundStyle(.white.opacity(0.45))
            .textCase(.uppercase)
    }
}

/// 极简旋转圆弧。
private struct ArcSpinner: View {
    let size: CGFloat
    let lineWidth: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(
                Color.white.opacity(0.9),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

/// 网速格式化:返回 (数字, 单位) 拆分。
private enum SpeedFormatter {
    static func split(bytesPerSecond: Int64) -> (value: String, unit: String) {
        let bps = max(bytesPerSecond, 0)
        let kb = Double(bps) / 1024.0
        if kb < 1024 {
            return (String(format: "%.0f", kb), "KB/s")
        }
        return (String(format: "%.1f", kb / 1024.0), "MB/s")
    }
}
