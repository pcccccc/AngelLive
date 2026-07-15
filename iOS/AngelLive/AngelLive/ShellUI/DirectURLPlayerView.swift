//
//  DirectURLPlayerView.swift
//  AngelLive
//
//  独立 URL 播放器：直接接收 URL 播放，不依赖 LiveParse 平台。
//  用于壳 UI 中的网络视频链接播放。
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 独立 URL 播放器视图，以 fullScreenCover 形式呈现
struct DirectURLPlayerView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // KS 播放器
    @StateObject private var playerCoordinator: KSVideoPlayer.Coordinator
    @StateObject private var playerModel: KSVideoPlayerModel
    @StateObject private var playbackSession: KSPlayerPlaybackSession

    // VLC 播放器
    @StateObject private var vlcPlaybackController = VLCPlaybackController()
    @State private var vlcState: VLCPlaybackBridgeState = .buffering
    @State private var hasVLCStartedPlayback = false

    // 控制层状态
    @State private var isMaskShow = true
    @State private var isLocked = false
    @State private var isPlaying = false
    @State private var playbackMachine = PlaybackStatusMachine()
    @State private var playbackStatus: PlaybackStatus = .loading

    private var useKSPlayer: Bool {
        let kernel = PlayerKernelSupport.resolvedKernel(for: PlayerSettingModel().playerKernel)
        return kernel == .ksplayer && PlayerKernelSupport.isKSPlayerAvailable
    }

    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    init(url: URL, title: String) {
        self.url = url
        self.title = title

        // 初始化 KSPlayer 选项
        let options = PlayerOptions()
        options.userAgent = "libmpv"
        options.registerRemoteControll = false
        options.canStartPictureInPictureAutomaticallyFromInline = PlayerSettingModel().enableAutoPiPOnBackground

        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = false
        KSOptions.canBackgroundPlay = PlayerSettingModel().enableBackgroundAudio

        // Direct URLs have no plugin hints, so URL inference is the final fallback.
        // Configure this options instance; KSOptions already copied static defaults in init.
        let urlString = url.absoluteString.lowercased()
        if urlString.contains(".m3u8") || urlString.contains("m3u8") {
            options.playerTypes = [KSAVPlayer.self, KSMEPlayer.self]
        } else {
            options.playerTypes = [KSMEPlayer.self]
        }

        let coordinator = KSVideoPlayer.Coordinator()
        let model = KSVideoPlayerModel(
            title: title,
            config: coordinator,
            options: options,
            url: url
        )
        _playerCoordinator = StateObject(wrappedValue: coordinator)
        _playerModel = StateObject(wrappedValue: model)
        _playbackSession = StateObject(wrappedValue: KSPlayerPlaybackSession(
            role: .primary,
            supportedGlobalCapabilities: [.audioFocus, .pictureInPicture, .remoteCommands]
        ))
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // 播放器层
            playerSurface

            // 缓冲指示器
            if shouldShowBuffering {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // 手势层（亮度/音量/双击全屏）
            #if canImport(KSPlayer)
            PlayerGestureView(
                onSingleTap: {
                    isMaskShow.toggle()
                },
                isLocked: $isLocked
            )
            #else
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isMaskShow.toggle()
                }
            #endif

            // 控制层
            DirectPlayerControlOverlay(
                bridge: controlBridge,
                onRefresh: {
                    refreshPlayback()
                }
            )
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            transition(.loadRequested)
            playbackSession.activate()
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
            // iPhone 支持横屏旋转
            if !AppConstants.Device.isIPad {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
            }
        }
        .onDisappear {
            playbackSession.invalidate()
            // iPhone 返回时强制竖屏
            if !AppConstants.Device.isIPad {
                KSOptions.supportedInterfaceOrientations = .portrait
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else { return }
                let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                // 先通知 ViewController 刷新支持的方向
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
                DispatchQueue.main.async {
                    windowScene.requestGeometryUpdate(prefs) { _ in }
                }
            }
        }
        .onChange(of: playerCoordinator.state) {
            guard useKSPlayer else { return }
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
            transition(.engineStateChanged(
                mapKSPlayerEngineState(playerCoordinator.state),
                isPlaying: playerCoordinator.playerLayer?.player.isPlaying == true
            ))
            isPlaying = playbackStatus.isPlaying
        }
        // 后台自动 PiP
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if useKSPlayer {
                if PlayerSettingModel().enableAutoPiPOnBackground,
                   playbackSession.owns(.pictureInPicture) {
                    #if canImport(KSPlayer)
                    if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer,
                       !playerLayer.isPictureInPictureActive {
                        playerLayer.pipStart()
                    }
                    #endif
                }
            } else {
                vlcPlaybackController.enterBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if useKSPlayer {
                #if canImport(KSPlayer)
                if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer,
                   playerLayer.isPictureInPictureActive {
                    playerLayer.pipStop(restoreUserInterface: true)
                }
                #endif
            } else {
                vlcPlaybackController.becomeActive()
            }
        }
    }

    // MARK: - Player Surface

    @ViewBuilder
    private var playerSurface: some View {
        if useKSPlayer {
            #if canImport(KSPlayer)
            KSCorePlayerView(
                config: playerCoordinator,
                url: url,
                options: playerModel.options,
                title: .constant(title),
                subtitleDataSource: nil
            )
            #else
            vlcPlayerSurface
            #endif
        } else {
            vlcPlayerSurface
        }
    }

    private var vlcPlayerSurface: some View {
        VLCVideoPlayerView(
            url: url,
            options: playerModel.options,
            controller: vlcPlaybackController
        ) { state in
            vlcState = state
            switch state {
            case .playing:
                isPlaying = true
                hasVLCStartedPlayback = true
            case .paused, .stopped, .error:
                isPlaying = false
            case .buffering:
                break
            }
        }
        .onAppear {
            vlcPlaybackController.activateSession()
        }
        .onDisappear {
            vlcPlaybackController.deactivateSession()
            vlcPlaybackController.stop()
            hasVLCStartedPlayback = false
            vlcState = .stopped
        }
    }

    private var shouldShowBuffering: Bool {
        if useKSPlayer {
            return playbackStatus.isLoading
        }
        return vlcState.isBuffering && !hasVLCStartedPlayback
    }

    // MARK: - Control Bridge

    private var controlBridge: PlayerControlBridge {
        if useKSPlayer {
            return PlayerControlBridge(
                isPlaying: canPauseKSPlayback,
                isBuffering: playbackStatus == .buffering,
                supportsPictureInPicture: playerCoordinator.playerLayer is KSComplexPlayerLayer,
                togglePlayPause: {
                    guard playbackSession.activate() else { return }
                    if canPauseKSPlayback {
                        playerCoordinator.playerLayer?.pause()
                    } else {
                        playerCoordinator.playerLayer?.play()
                    }
                },
                refreshPlayback: {
                    guard playbackSession.activate() else { return }
                    refreshPlayback()
                },
                togglePictureInPicture: {
                    guard playbackSession.activate() else { return }
                    #if canImport(KSPlayer)
                    if let playerLayer = playerCoordinator.playerLayer as? KSComplexPlayerLayer {
                        if playerLayer.isPictureInPictureActive {
                            playerLayer.pipStop(restoreUserInterface: true)
                        } else {
                            playerLayer.pipStart()
                        }
                    }
                    #endif
                },
                isMaskShow: $isMaskShow,
                isLocked: $isLocked
            )
        }

        return PlayerControlBridge(
            isPlaying: isPlaying,
            isBuffering: vlcState.isBuffering,
            supportsPictureInPicture: vlcPlaybackController.isPictureInPictureSupported,
            togglePlayPause: {
                vlcPlaybackController.togglePlayPause()
            },
            refreshPlayback: {
                refreshPlayback()
            },
            togglePictureInPicture: {
                vlcPlaybackController.togglePictureInPicture()
            },
            isMaskShow: $isMaskShow,
            isLocked: $isLocked
        )
    }

    // MARK: - Actions

    private var canPauseKSPlayback: Bool {
        playbackStatus == .playing || playbackStatus == .buffering
    }

    private func transition(_ event: PlaybackStatusEvent) {
        playbackMachine.send(event)
        playbackStatus = playbackMachine.status
    }

    private func refreshPlayback() {
        // 重新设置 URL 触发播放器重载
        if useKSPlayer {
            transition(.loadRequested)
            if let layer = playerCoordinator.playerLayer {
                layer.reset()
                layer.prepareToPlay()
            } else {
                playerModel.url = url
            }
        } else {
            // VLC: 停止后重新激活
            vlcPlaybackController.stop()
            hasVLCStartedPlayback = false
            vlcState = .buffering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                vlcPlaybackController.activateSession()
            }
        }
    }
}
