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
import AppKit
import Kingfisher

struct RoomPlayerView: View {
    let room: LiveModel
    @Environment(HistoryModel.self) private var historyModel
    @State private var viewModel: RoomInfoViewModel
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var sleepActivity: NSObjectProtocol?
    @State private var playerWindow: NSWindow?
    @State private var volume: Float = 1.0
    @State private var isMuted = false
    @State private var didCleanup = false
    /// 首帧渲染粘性标志:state 第一次进入 .buffering / .bufferFinished 后置 true,
    /// 直播流 state 可能长期停留在 .buffering(KSPlayer 视为 isPlaying),
    /// 之后不能再把 .buffering 当作"加载中"以免 overlay 常驻。
    @State private var hasKSStartedPlayback = false

    init(room: LiveModel) {
        self.room = room
        self._viewModel = State(initialValue: RoomInfoViewModel(room: room))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                playerSurface(for: viewModel)

                danmuOverlay(for: geometry.size)

                // 控制层
                PlayerControlView(room: room, viewModel: viewModel, coordinator: coordinator, volume: $volume, isMuted: $isMuted)
            }
        }
        .navigationTitle(viewModel.currentRoom.roomTitle)
        .toolbar(.hidden, for: .windowToolbar)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .background(PlayerWindowReferenceView(window: $playerWindow))
        .onAppear {
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
        .onDisappear {
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
                  keyWindow == playerWindow,
                  let playerLayer = coordinator.playerLayer as? KSComplexPlayerLayer
            else { return }
            playerLayer.registerRemoteControllEvent()
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                preventSleep()
            } else {
                allowSleep()
            }
            disableWindowBackgroundDrag()
        }
        .onChange(of: coordinator.state) { _, _ in
            disableWindowBackgroundDrag()
        }
        // VM observes Coordinator callbacks without replacing its layer delegate.
        // Keep a sticky first-play signal so later buffering does not look like startup.
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                hasKSStartedPlayback = true
            }
        }
        .onAppear {
            // 启动统一恢复协调器的 1Hz 采样;起播超时/stall/finish 全由它接管。
            viewModel.recoveryCoordinator.start()
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
                    Text(errorMsg)
                        .font(.subheadline)
                        .foregroundColor(.gray)
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
                        dynamicInfo: coordinator.playerLayer?.player.dynamicInfo
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

                MacStreamLoadingOverlay(dynamicInfo: nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 是否应展示加载层（缓冲或初次加载）。
    func shouldShowStreamLoading(viewModel: RoomInfoViewModel) -> Bool {
        // 已进入实际渲染态后,只在用户主动 seek 时再现 —— 直播流 KSPlayer.state 长期停留
        // 在 .buffering 是常态,不能以此判定"加载中",否则 overlay 永不消失。
        if hasKSStartedPlayback {
            return coordinator.playerLayer?.player.playbackState == .seeking
        }
        return isInitialStreamLoading(viewModel: viewModel)
    }

    /// 流首次加载（URL 已就绪但未开始播放）。
    /// 注意：.readyToPlay 是「准备好可以播」而非「已在播」，KSPlayer 此时尚未渲染帧。
    /// 不能用 viewModel.isPlaying 二次过滤，否则 .readyToPlay 与 .buffering 之间会闪一帧黑。
    func isInitialStreamLoading(viewModel: RoomInfoViewModel) -> Bool {
        if hasKSStartedPlayback { return false }
        switch coordinator.state {
        case .initialized, .preparing, .readyToPlay:
            return true
        default:
            return false
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

    var body: some View {
        VStack(spacing: 18) {
            ArcSpinner(size: 34, lineWidth: 1.5)
            if let info = dynamicInfo {
                MacStreamSpeedText(info: info)
            } else {
                MacStreamPlaceholder()
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
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
        } else {
            MacStreamPlaceholder()
        }
    }
}

private struct MacStreamPlaceholder: View {
    var body: some View {
        Text("connecting")
            .font(.system(size: 11, weight: .medium))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.45))
            .textCase(.uppercase)
    }
}

private struct PlayerWindowReferenceView: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReferenceView {
        WindowReferenceView(window: $window)
    }

    func updateNSView(_ nsView: WindowReferenceView, context: Context) {}
}

private final class WindowReferenceView: NSView {
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
