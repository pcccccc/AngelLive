//
//  RoomPlayerView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import Combine
import AppKit
import Kingfisher

struct RoomPlayerView: View {
    let room: LiveModel
    @Environment(HistoryModel.self) private var historyModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: RoomInfoViewModel
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary,
        supportedGlobalCapabilities: [.audioFocus, .nowPlaying, .remoteCommands]
    )
    @State private var sleepActivity: NSObjectProtocol?
    @State private var playerWindow: NSWindow?
    @State private var volume: Float = 1.0
    @State private var isMuted = false
    @State private var didCleanup = false
    @State private var translationService = RoomTitleTranslationService.shared
    /// 首帧渲染粘性标志:state 第一次进入 .buffering / .bufferFinished 后置 true,
    /// 直播流 state 可能长期停留在 .buffering(KSPlayer 视为 isPlaying),
    /// 之后不能再把 .buffering 当作"加载中"以免 overlay 常驻。
    @State private var visibleRecoveryNotice: PlaybackRecoveryNotice?
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?
    @State private var lockedQualityToast: ToastMessage?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(room: LiveModel) {
        self.room = room
        self._viewModel = State(initialValue: RoomInfoViewModel(room: room))
    }

    private var titleTranslationEnabled: Bool {
        SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType) != nil
    }

    private var canShowLiveSubtitleSurface: Bool {
        switch viewModel.displayState {
        case .loading, .playing:
            return true
        case .error, .streamerOffline:
            return false
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                playerSurface(for: viewModel)

                danmuOverlay(for: geometry.size)

                #if canImport(KSPlayer)
                if canShowLiveSubtitleSurface, let url = viewModel.currentPlayURL {
                    Color.clear
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .liveSubtitleOverlay(
                            coordinator: coordinator,
                            playbackIdentity: url.absoluteString,
                            bottomPadding: 64
                        )
                }
                #endif

                // 控制层
                PlayerControlView(room: room, viewModel: viewModel, coordinator: coordinator, volume: $volume, isMuted: $isMuted)

                if let notice = visibleRecoveryNotice {
                    VStack {
                        MacPlayerRecoveryNoticeBanner(notice: notice)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                            .transition(accessibilityReduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .navigationTitle(
            titleTranslationEnabled
                ? translationService.displayTitle(for: viewModel.currentRoom.roomTitle)
                : viewModel.currentRoom.roomTitle
        )
        .toolbar(.hidden, for: .windowToolbar)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .background(PlayerWindowReferenceView(window: $playerWindow))
        .onAppear {
            playbackSession.register()
            playbackSession.attach(playerLayer: coordinator.playerLayer)
            if playerWindow?.isKeyWindow == true {
                playbackSession.activate()
            }
            disableWindowBackgroundDrag()
            historyModel.addHistory(room: viewModel.currentRoom)
        }
        .onKeyPress(.space) {
            if viewModel.isPlaying {
                coordinator.playerLayer?.pause()
            } else {
                coordinator.playerLayer?.play()
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
            return .handled
        }
        .onTapGesture(count: 2) {
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
        }
        .onKeyPress(.escape) {
            if let window = NSApplication.shared.keyWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            adjustVolume(by: 0.05)
            return .handled
        }
        .onKeyPress(.downArrow) {
            adjustVolume(by: -0.05)
            return .handled
        }
        .task {
            await viewModel.loadPlayURL()
        }
        .roomTitleTranslationTask(
            viewModel.currentRoom.roomTitle,
            enabled: titleTranslationEnabled
        )
        .onDisappear {
            SupportDiagnosticsService.shared.recordAction(
                .closedRoom,
                context: SupportDiagnosticActionContext.room(viewModel.currentRoom)
            )
            playbackSession.invalidate()
            cleanupPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            // 其他播放窗口关闭时，重新应用当前窗口的音频设置，避免状态被意外重置。
            guard closedWindow != playerWindow else { return }
            DispatchQueue.main.async {
                applyAudioSettings()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let keyWindow = notification.object as? NSWindow,
                  keyWindow == playerWindow
            else { return }
            playbackSession.attach(playerLayer: coordinator.playerLayer)
            playbackSession.activate()
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                preventSleep()
            } else {
                allowSleep()
            }
            disableWindowBackgroundDrag()
        }
        .onChange(of: viewModel.recoveryNotice) { _, notice in
            showRecoveryNotice(notice)
        }
        .onChange(of: coordinator.state) { _, _ in
            playbackSession.attach(playerLayer: coordinator.playerLayer)
            disableWindowBackgroundDrag()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.resumeDanmakuTranslationAfterBackground()
            case .background:
                viewModel.suspendDanmakuTranslationForBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        // VM observes Coordinator callbacks without replacing its layer delegate.
        // Keep a sticky first-play signal so later buffering does not look like startup.
        .onAppear {
            // 启动统一恢复协调器的 1Hz 采样;起播超时/stall/finish 全由它接管。
            viewModel.recoveryCoordinator.start()
        }
        .sheet(item: $authenticationRecoveryRequest) { request in
            NavigationStack {
                MacAccountManagementView(recoveryPluginIDs: request.pluginIDs)
                    .frame(minWidth: 620, minHeight: 420)
            }
        }
        // 画质菜单点击「登录后可用」档位：复用登录恢复 sheet
        .onChange(of: viewModel.pendingLoginRequest?.id) { _, _ in
            guard let request = viewModel.pendingLoginRequest else { return }
            viewModel.pendingLoginRequest = nil
            authenticationRecoveryRequest = request
        }
        // 会员档位等只提示不切换；播放器窗口没有全局 toast 浮层，这里就地展示
        .onChange(of: viewModel.lockedQualityNotice) { _, notice in
            guard let notice else { return }
            viewModel.lockedQualityNotice = nil
            showLockedQualityToast(notice)
        }
        .overlay(alignment: .top) {
            if let toast = lockedQualityToast {
                ToastView(toast: toast)
                    .padding(.top, 48)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: lockedQualityToast)
        // 当前平台登录状态变化后重新取流，让被锁定的画质解锁
        .onReceive(
            NotificationCenter.default.publisher(for: .platformSessionMetadataDidChange)
                .compactMap { $0.object as? String }
                .receive(on: RunLoop.main)
        ) { pluginId in
            guard pluginId == SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)?.pluginId else { return }
            viewModel.refreshPlayback()
        }
    }

    private func showLockedQualityToast(_ message: String) {
        let toast = ToastMessage(icon: "lock.fill", message: message, type: .info)
        lockedQualityToast = toast
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if lockedQualityToast == toast {
                lockedQualityToast = nil
            }
        }
    }

    private func preventSleep() {
        guard sleepActivity == nil else { return }
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "Video playback in progress"
        )
    }

    private func allowSleep() {
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    private func cleanupPlayer() {
        guard !didCleanup else { return }
        didCleanup = true
        viewModel.endPlaybackDiagnostics()
        viewModel.recoveryCoordinator.stop()
        coordinator.resetPlayer()
        viewModel.disconnectSocket()
        allowSleep()
    }

    private func disableWindowBackgroundDrag() {
        DispatchQueue.main.async {
            playerWindow?.isMovableByWindowBackground = false
        }
    }

    private func adjustVolume(by delta: Float) {
        let newValue = min(1.0, max(0.0, volume + delta))
        guard newValue != volume else { return }
        volume = newValue
    }

    private func applyAudioSettings() {
        guard let player = coordinator.playerLayer?.player else { return }
        player.isMuted = isMuted
        player.playbackVolume = volume
        if viewModel.isPlaying {
            coordinator.playerLayer?.play()
        }
    }
}

private extension RoomPlayerView {
    @ViewBuilder
    func playerSurface(for viewModel: RoomInfoViewModel) -> some View {
        if viewModel.displayState == .streamerOffline {
            VStack(spacing: 20) {
                Image(systemName: "tv.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("主播已下播")
                    .font(.title2)
                    .foregroundColor(.white)
                Text(viewModel.currentRoom.userName.orDash)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else if viewModel.displayState == .error {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                Text("播放失败")
                    .font(.title2)
                    .foregroundColor(.white)
                if let errorMsg = viewModel.playErrorMessage {
                    Text(viewModel.playError.map { $0.showsLoginAction ? $0.liveParseMessage : errorMsg } ?? errorMsg)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                if viewModel.playError?.showsLoginAction == true {
                    Button {
                        let platform = SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)
                        authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                            pluginIDs: platform.map { [$0.pluginId] } ?? []
                        )
                    } label: {
                        let platformName = SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)?.displayName
                        Text(platformName.map { "登录 \($0)" } ?? "选择登录平台")
                    }
                    .buttonStyle(.bordered)
                }
                Button("重试") {
                    viewModel.displayState = .loading
                    viewModel.refreshPlayback()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else if let url = viewModel.currentPlayURL {
            ZStack {
                KSVideoPlayer(coordinator: coordinator, url: url, options: viewModel.playerOption)
                    .onAppear {
                        viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                        applyAudioSettings()
                    }
                    .onChange(of: viewModel.currentPlayURL) { _, _ in
                        // URL 变化时重新绑定业务回调和采样 layer。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                            applyAudioSettings()
                        }
                    }
                    .ignoresSafeArea()

                if shouldShowStreamLoading(viewModel: viewModel) {
                    MacStreamLoadingOverlay(
                        dynamicInfo: coordinator.playerLayer?.player.dynamicInfo,
                        stage: viewModel.startupStage
                    )
                }
            }
        } else {
            ZStack {
                Color.black
                KFImage(URL(string: viewModel.currentRoom.roomCover))
                    .placeholder {
                        ZStack {
                            Color.black
                            Image("placeholder")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(0.5)
                        }
                    }
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .overlay(Color.black.opacity(0.5))
                    .clipped()

                MacStreamLoadingOverlay(dynamicInfo: nil, stage: viewModel.startupStage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @MainActor
    func showRecoveryNotice(_ notice: PlaybackRecoveryNotice?) {
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
            visibleRecoveryNotice = notice
        }
        guard let notice else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard visibleRecoveryNotice?.id == notice.id else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                visibleRecoveryNotice = nil
            }
        }
    }

    /// 是否应展示加载层（缓冲或初次加载）。
    func shouldShowStreamLoading(viewModel: RoomInfoViewModel) -> Bool {
        // 已进入实际渲染态后,只在用户主动 seek 时再现 —— 直播流 KSPlayer.state 长期停留
        // 在 .buffering 是常态,不能以此判定"加载中",否则 overlay 永不消失。
        if viewModel.hasObservedPlaybackProgress {
            return coordinator.playerLayer?.player.playbackState == .seeking
        }
        return isInitialStreamLoading(viewModel: viewModel)
    }

    /// 流首次加载（URL 已就绪但未开始播放）。
    /// 注意：.readyToPlay 是「准备好可以播」而非「已在播」，KSPlayer 此时尚未渲染帧。
    /// 不能用 viewModel.isPlaying 二次过滤，否则 .readyToPlay 与 .buffering 之间会闪一帧黑。
    func isInitialStreamLoading(viewModel: RoomInfoViewModel) -> Bool {
        if viewModel.hasObservedPlaybackProgress { return false }
        switch coordinator.state {
        case .paused, .playedToTheEnd, .error:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    func danmuOverlay(for containerSize: CGSize) -> some View {
        let settings = viewModel.danmuSettings
        if viewModel.supportsDanmu, settings.showDanmu, viewModel.currentPlayURL != nil {
            let config = danmuConfig(for: containerSize.height, index: settings.danmuAreaIndex)
            VStack(spacing: 0) {
                if config.position == .bottom {
                    Spacer()
                }

                DanmuView(
                    coordinator: viewModel.danmuCoordinator,
                    size: CGSize(width: containerSize.width, height: config.height),
                    fontSize: CGFloat(settings.danmuFontSize),
                    speed: CGFloat(settings.danmuSpeed),
                    paddingTop: CGFloat(settings.danmuTopMargin),
                    paddingBottom: CGFloat(settings.danmuBottomMargin)
                )
                .frame(width: containerSize.width, height: config.height)
                .opacity(settings.showDanmu ? 1 : 0)

                if config.position == .top {
                    Spacer()
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuAreaIndex)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuFontSize)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuSpeed)
        } else {
            EmptyView()
        }
    }

    func danmuConfig(for containerHeight: CGFloat, index: Int) -> (height: CGFloat, position: DanmuPosition) {
        let ratios: [CGFloat] = [0.25, 0.5, 1.0, 0.5, 0.25]
        let clampedIndex = max(0, min(index, ratios.count - 1))
        let heightRatio = ratios[clampedIndex]
        let height = max(containerHeight * heightRatio, 1)

        if clampedIndex == 2 {
            return (height, .full)
        } else if clampedIndex >= 3 {
            return (height, .bottom)
        } else {
            return (height, .top)
        }
    }

    enum DanmuPosition {
        case top
        case bottom
        case full
    }
}

// MARK: - 直播加载指示

/// macOS 直播流加载层:细圆弧 + 数字/单位分体网速,无背景片,贴在视频画面上。
/// 网速订阅 KSPlayer 自带的 `DynamicInfo.networkSpeed`(@Published)。
struct MacStreamLoadingOverlay: View {
    let dynamicInfo: DynamicInfo?
    let stage: PlaybackStartupStage

    var body: some View {
        VStack(spacing: 14) {
            ArcSpinner(size: 34, lineWidth: 1.5)
            VStack(spacing: 6) {
                Text(stage.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let info = dynamicInfo {
                    MacStreamSpeedText(info: info)
                }
            }
        }
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage.title)
    }
}

private struct MacStreamSpeedText: View {
    @ObservedObject var info: DynamicInfo

    var body: some View {
        if info.networkSpeed > 0 {
            let (value, unit) = SpeedFormatter.split(bytesPerSecond: Int64(info.networkSpeed))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: value)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

private struct MacPlayerRecoveryNoticeBanner: View {
    let notice: PlaybackRecoveryNotice

    var body: some View {
        Text(notice.title)
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(notice.title)
    }
}

struct PlayerWindowReferenceView: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReferenceView {
        WindowReferenceView(window: $window)
    }

    func updateNSView(_ nsView: WindowReferenceView, context: Context) {}
}

final class WindowReferenceView: NSView {
    @Binding var windowBinding: NSWindow?

    init(window: Binding<NSWindow?>) {
        _windowBinding = window
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowBinding = self.window
    }
}

// MARK: - 共享组件

/// 极简旋转圆弧。线宽 / 直径可配,默认白色 90%。
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

/// 网速格式化:返回 (数字, 单位) 拆分,以便分别排版。
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

#Preview {
    RoomPlayerView(room: LiveModel(
        userName: "测试主播",
        roomTitle: "测试直播间",
        roomCover: "",
        userHeadImg: "",
        liveType: .placeholder,
        liveState: "live",
        userId: "",
        roomId: "12345",
        liveWatchedCount: "1.2万"
    ))
    .frame(width: 800, height: 600)
}
