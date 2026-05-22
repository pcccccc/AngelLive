//
//  DetailPlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/12.
//

import SwiftUI
import AVKit
import AngelLiveDependencies
import AngelLiveCore


struct DetailPlayerView: View {

    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    @State private var didCleanup = false
    /// 标记 KSPlayer 是否曾进入实际渲染态(.buffering / .bufferFinished)。
    /// 直播流 state 在 KSPlayer 内可能长期停留在 .buffering(被视作 isPlaying),
    /// 不能再把 .buffering 当作"加载中"来盖 overlay,否则永不消失。
    @State private var hasStartedStreamPlayback = false
    /// 首次起播 watchdog:URL 已设但 8s 内未起播自动 refreshPlayback,每条 URL 最多重试 1 次,
    /// 兜底 KSPlayer prepareToPlay 卡住(createPlayerItem hang / HLS 握手阻塞 等)。
    @State private var watchdogLastURL: URL?
    @State private var watchdogRetried = false
    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(AppState.self) var appViewModel
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    
    var body: some View {
        if roomInfoViewModel.displayState == .streamerOffline {
            // 主播已下播页面
            VStack(spacing: 30) {
                Image(systemName: "tv.slash")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                Text("主播已下播")
                    .font(.title)
                    .foregroundColor(.white)
                Text(roomInfoViewModel.currentRoom.userName.orDash)
                    .font(.headline)
                    .foregroundColor(.gray)
                Button("返回") {
                    endPlay()
                }
                .padding(.top, 20)
            }
            .frame(width: 1920, height: 1080)
            .background(.black)
        } else if roomInfoViewModel.hasError, let error = roomInfoViewModel.currentError {
            ErrorView(
                title: error.isAuthRequired ? "播放失败-请登录\(LiveParseTools.getLivePlatformName(roomInfoViewModel.currentRoom.liveType))账号" : "播放失败",
                message: error.liveParseMessage,
                detailMessage: error.liveParseDetail,
                curlCommand: error.liveParseCurl,
                showRetry: true,
                showLoginButton: error.isAuthRequired,
                onDismiss: {
                    endPlay()
                },
                onRetry: {
                    roomInfoViewModel.hasError = false
                    roomInfoViewModel.currentError = nil
                    playerCoordinator.playerLayer?.play()
                }
            )
        } else if roomInfoViewModel.currentPlayURL == nil {
            ZStack {
                KFImage(URL(string: roomInfoViewModel.currentRoom.roomCover))
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
                    .frame(width: 1920, height: 1080)
                    .clipped()
                    .blur(radius: 24)
                    .overlay {
                        Color.black.opacity(0.5)
                    }

                TVStreamLoadingOverlay(dynamicInfo: nil)
            }
            .frame(width: 1920, height: 1080)
            .background(.black)
        }else {
            ZStack {
                KSVideoPlayer(coordinator: playerCoordinator, url: roomInfoViewModel.currentPlayURL ?? URL(string: "")!, options: roomInfoViewModel.playerOption)
                    .background(Color.black)
                    .onAppear {
                        playerCoordinator.playerLayer?.play()
                        roomInfoViewModel.setPlayerDelegate(playerCoordinator: playerCoordinator)
                    }
                    .safeAreaPadding(.all)
                    .zIndex(1)

                // 加载/缓冲指示器 - URL 已就绪但尚未开始播放，或播放中缓冲时显示
                if shouldShowStreamLoading {
                    TVStreamLoadingOverlay(
                        dynamicInfo: playerCoordinator.playerLayer?.player.dynamicInfo
                    )
                    .zIndex(4)
                }

                PlayerControlView(playerCoordinator: playerCoordinator)
                    .zIndex(3)
                    .frame(width: 1920, height: 1080)
//                    .opacity(roomInfoViewModel.showControlView ? 1 : 0)
                    .safeAreaPadding(.all)
                    .environment(roomInfoViewModel)
                    .environment(appViewModel)
                if roomInfoViewModel.supportsDanmu {
                    VStack {
                        if appViewModel.danmuSettingsViewModel.danmuAreaIndex >= 3 {
                            Spacer()
                        }
                        DanmuView(coordinator: roomInfoViewModel.danmuCoordinator, height: appViewModel.danmuSettingsViewModel.getDanmuArea().0)
                            .frame(width: 1920, height: appViewModel.danmuSettingsViewModel.getDanmuArea().0)
                            .opacity(appViewModel.danmuSettingsViewModel.showDanmu ? 1 : 0)
                            .environment(appViewModel)
                        if appViewModel.danmuSettingsViewModel.danmuAreaIndex < 3 {
                            Spacer()
                        }
                    }
                    .zIndex(2)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.playerEndPlay)) { _ in
                endPlay()
            }
            .onDisappear {
                cleanupPlayer()
            }
            .onPlayPauseCommand {
                roomInfoViewModel.togglePlayPause()
            }
            // 关键背景:RoomInfoViewModel.setPlayerDelegate 把 playerLayer.delegate 抢成 self,
            // 因此 KSVideoPlayer.Coordinator.state 永远停在 .initialized,不能用它做起播判定。
            // RoomInfoViewModel.player(layer:state:) 已经把 layer.player.isPlaying 写到 isPlaying,
            // 直接订阅它作为 sticky 起播信号。one-way sticky:置 true 后不再因暂停翻回。
            .onChange(of: roomInfoViewModel.isPlaying) { _, isPlaying in
                if isPlaying {
                    hasStartedStreamPlayback = true
                }
            }
            .task(id: roomInfoViewModel.currentPlayURL) {
                await runStartupWatchdog()
            }
            .frame(width: 1920, height: 1080)
        }
    }
    
    @MainActor func endPlay() {
        cleanupPlayer()
        didExitView(false, "")
    }

    @MainActor
    private func cleanupPlayer() {
        guard !didCleanup else { return }
        didCleanup = true
        playerCoordinator.resetPlayer()
        roomInfoViewModel.disConnectSocket()
    }

    /// 起播超时兜底:8s 内 isPlaying 没翻 true 就自动 refreshPlayback 一次。
    /// .task(id:) 在 currentPlayURL 变化时自动 cancel 旧 task 重起。
    @MainActor
    private func runStartupWatchdog() async {
        guard let url = roomInfoViewModel.currentPlayURL else { return }

        if watchdogLastURL != url {
            watchdogLastURL = url
            watchdogRetried = false
        }

        guard !watchdogRetried else { return }
        if roomInfoViewModel.isPlaying { return }

        do {
            try await Task.sleep(nanoseconds: 8_000_000_000)
        } catch {
            return
        }

        guard !Task.isCancelled,
              roomInfoViewModel.currentPlayURL == url,
              !roomInfoViewModel.isPlaying else { return }

        watchdogRetried = true
        print("[PlayerFlow] watchdog: tvOS 起播 8s 超时,自动 refreshPlayback (url=\(url.absoluteString))")
        roomInfoViewModel.refreshPlayback()
    }

    /// 是否应展示加载层（缓冲或初次加载）。
    private var shouldShowStreamLoading: Bool {
        // 起播一次之后,只在用户主动 seek 时再现 overlay。直播流不会 seek,通常等于永不再现。
        if hasStartedStreamPlayback {
            return playerCoordinator.playerLayer?.player.playbackState == .seeking
        }
        return isInitialStreamLoading
    }

    /// 流首次加载（URL 已就绪但未开始播放）。
    /// 注意：.readyToPlay 是「准备好可以播」而非「已在播」，KSPlayer 此时尚未渲染帧。
    /// 不能用 isPlaying 二次过滤，否则 .readyToPlay 与 .buffering 之间会闪一帧黑。
    private var isInitialStreamLoading: Bool {
        switch playerCoordinator.state {
        case .initialized, .preparing, .readyToPlay:
            return true
        default:
            return false
        }
    }
}

// MARK: - 直播加载指示

/// tvOS 直播流加载层:细圆弧 + 数字/单位分体网速,无背景片,贴在视频画面上。
/// 网速订阅 KSPlayer 自带的 `DynamicInfo.networkSpeed`(@Published)。
struct TVStreamLoadingOverlay: View {
    let dynamicInfo: DynamicInfo?

    var body: some View {
        VStack(spacing: 32) {
            ArcSpinner(size: 64, lineWidth: 2.5)
            if let info = dynamicInfo {
                TVStreamSpeedText(info: info)
            } else {
                TVStreamPlaceholder()
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 4)
    }
}

private struct TVStreamSpeedText: View {
    @ObservedObject var info: DynamicInfo

    var body: some View {
        if info.networkSpeed > 0 {
            let (value, unit) = SpeedFormatter.split(bytesPerSecond: Int64(info.networkSpeed))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 18, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            TVStreamPlaceholder()
        }
    }
}

private struct TVStreamPlaceholder: View {
    var body: some View {
        Text("connecting")
            .font(.system(size: 18, weight: .medium))
            .tracking(4)
            .foregroundStyle(.white.opacity(0.45))
            .textCase(.uppercase)
    }
}

// MARK: - 共享组件

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
