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

struct RoomPlayerView: View {
    let room: LiveModel
    @State private var viewModel: RoomInfoViewModel
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var sleepActivity: NSObjectProtocol?
    @State private var playerWindow: NSWindow?
    @State private var volume: Float = 1.0
    @State private var isMuted = false
    @State private var didCleanup = false

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
                Text(viewModel.currentRoom.userName)
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
                    Task {
                        await viewModel.refreshPlayback()
                    }
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
                        // URL 变化时重新设置 delegate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                            applyAudioSettings()
                        }
                    }
                    .ignoresSafeArea()

                if coordinator.state == .buffering || coordinator.playerLayer?.player.playbackState == .seeking {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("正在加载...")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    @ViewBuilder
    func danmuOverlay(for containerSize: CGSize) -> some View {
        let settings = viewModel.danmuSettings
        if settings.showDanmu, viewModel.currentPlayURL != nil {
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

#Preview {
    RoomPlayerView(room: LiveModel(
        userName: "测试主播",
        roomTitle: "测试直播间",
        roomCover: "",
        userHeadImg: "",
        liveType: .bilibili,
        liveState: "live",
        userId: "",
        roomId: "12345",
        liveWatchedCount: "1.2万"
    ))
    .frame(width: 800, height: 600)
}
