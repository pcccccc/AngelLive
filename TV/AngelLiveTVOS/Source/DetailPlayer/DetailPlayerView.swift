//
//  DetailPlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/12.
//

import SwiftUI
import SharedAssets
import AVKit
import AngelLiveDependencies
import Combine
import AngelLiveCore


struct DetailPlayerView: View {

    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    @State private var didCleanup = false
    @State private var authenticationRecovery: AuthenticationRecoveryRequest?
    @State private var accountRecoveryIsActive = false
    @State private var visibleRecoveryNotice: PlaybackRecoveryNotice?
    @State private var roomBannerID: String?
    @State private var lastBannerRoomID: String?
    @State private var roomBannerTask: Task<Void, Never>?
    @State private var showsBottomControls = false
    @State private var mountedControlsRoomID: String?
    @State private var sleepTimer: TVPlaybackSleepTimer?
    @State private var routedOnDemandRoom: LiveModel?
    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(AppState.self) var appViewModel
    @Environment(\.usesFullUI) private var usesFullUI
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    
    var body: some View {
        #if canImport(KSPlayer)
        if usesFullUI, let room = routedOnDemandRoom {
            Group {
                if TVVodRoute.matches(room: room, appViewModel: appViewModel) {
                    TVVodContainerView(room: room, settings: appViewModel.generalSettingsViewModel, onExit: endPlay)
                } else {
                    TVShortDramaPlayerView(room: room, onExit: endPlay)
                }
            }
            .id(room.id)
        } else {
            livePlayer
        }
        #else
        livePlayer
        #endif
    }

    private var livePlayer: some View {
        playerContent
            .fullScreenCover(item: $authenticationRecovery, onDismiss: { accountRecoveryIsActive = false }) { request in
                AccountManagementView(recoveryPluginIDs: request.pluginIDs)
                    .frame(maxWidth: 1000)
                    .padding(80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
            .overlay(alignment: .top) {
                if let notice = visibleRecoveryNotice {
                    TVPlayerRecoveryNoticeBanner(notice: notice)
                        .padding(.top, 48)
                        .padding(.horizontal, 80)
                        .transition(accessibilityReduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    roomInfoViewModel.resumeDanmakuTranslationAfterBackground()
                case .background:
                    roomInfoViewModel.suspendDanmakuTranslationForBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onChange(of: roomInfoViewModel.recoveryNotice) { _, notice in
                showRecoveryNotice(notice)
            }
            .onChange(of: roomInfoViewModel.currentRoom.id) { _, roomID in
                if roomBannerID != roomID { cancelRoomBanner() }
            }
            .onChange(of: roomBannerCandidate, initial: true) { _, roomID in
                if let roomID, roomID != lastBannerRoomID {
                    showRoomBanner(for: roomID)
                } else if !usesFullUI || roomInfoViewModel.isOnDemand {
                    cancelRoomBanner()
                }
            }
            // 画质面板点击「登录后可用」档位：复用登录恢复页
            .onChange(of: roomInfoViewModel.pendingLoginRequest?.id) { _, _ in
                guard let request = roomInfoViewModel.pendingLoginRequest else { return }
                roomInfoViewModel.pendingLoginRequest = nil
                accountRecoveryIsActive = true
                authenticationRecovery = request
            }
            // 当前平台登录状态变化后重新取流，让被锁定的画质解锁
            .onReceive(
                NotificationCenter.default.publisher(for: .platformSessionMetadataDidChange)
                    .receive(on: RunLoop.main)
                    .compactMap { $0.object as? String }
            ) { pluginId in
                guard pluginId == SandboxPluginCatalog.platform(for: roomInfoViewModel.currentRoom.liveType)?.pluginId else { return }
                // 与错误页「重试」一致：先清掉错误态再重新取流
                if roomInfoViewModel.hasError {
                    roomInfoViewModel.hasError = false
                    roomInfoViewModel.currentError = nil
                }
                roomInfoViewModel.refreshPlayback()
            }
            .task(id: sleepTimer) {
                guard usesFullUI, let timer = sleepTimer else { return }
                do { try await ContinuousClock().sleep(until: timer.deadline) }
                catch { return }
                guard !Task.isCancelled, !didCleanup, sleepTimer == timer else { return }
                endPlay()
            }
            .onDisappear {
                cancelRoomBanner()
                sleepTimer = nil
                // Presenting account recovery keeps this room alive for a manual retry.
                guard !accountRecoveryIsActive else { return }
                cleanupPlayer()
            }
    }

    private var roomBannerCandidate: String? {
        guard usesFullUI, !roomInfoViewModel.isOnDemand,
              roomInfoViewModel.hasObservedPlaybackProgress else { return nil }
        return roomInfoViewModel.currentRoom.id
    }

    private func showRoomBanner(for roomID: String) {
        cancelRoomBanner()
        lastBannerRoomID = roomID
        roomBannerID = roomID
        roomBannerTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, roomBannerID == roomID else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
                roomBannerID = nil
            }
            roomBannerTask = nil
        }
    }

    private func cancelRoomBanner() {
        roomBannerTask?.cancel()
        roomBannerTask = nil
        roomBannerID = nil
    }

    @ViewBuilder
    private var playerContent: some View {
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
            .frame(width: usesFullUI ? nil : 1920, height: usesFullUI ? nil : 1080)
            .frame(maxWidth: usesFullUI ? .infinity : nil, maxHeight: usesFullUI ? .infinity : nil)
            .background(.black)
            .tvFullUIBackCommand(enabled: usesFullUI) { endPlay() }
        } else if roomInfoViewModel.hasError, let error = roomInfoViewModel.currentError {
            ErrorView(
                title: error.isAuthRequired ? "播放失败-请登录\(LiveParseTools.getLivePlatformName(roomInfoViewModel.currentRoom.liveType))账号" : "播放失败",
                message: error.liveParseMessage,
                detailMessage: error.liveParseDetail,
                curlCommand: error.liveParseCurl,
                showRetry: true,
                showLoginButton: error.showsLoginAction,
                onDismiss: {
                    endPlay()
                },
                onRetry: {
                    roomInfoViewModel.hasError = false
                    roomInfoViewModel.currentError = nil
                    if error.showsLoginAction || roomInfoViewModel.currentPlayURL == nil {
                        roomInfoViewModel.getPlayArgs(diagnosticAction: .retriedPlayback)
                    } else {
                        roomInfoViewModel.retryCurrentPlayer()
                    }
                },
                onLogin: {
                    let pluginIDs = SandboxPluginCatalog.platform(for: roomInfoViewModel.currentRoom.liveType).map { [$0.pluginId] } ?? []
                    accountRecoveryIsActive = true
                    authenticationRecovery = AuthenticationRecoveryRequest(pluginIDs: pluginIDs)
                }
            )
        } else if !usesFullUILiveLoading, roomInfoViewModel.currentPlayURL == nil {
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

                TVStreamLoadingOverlay(dynamicInfo: nil, stage: roomInfoViewModel.startupStage)
            }
            .frame(width: 1920, height: 1080)
            .background(.black)
        } else {
            playbackSurface(url: roomInfoViewModel.currentPlayURL)
        }
    }

    private func playbackSurface(url: URL?) -> some View {
        let exitWhileLoading: (() -> Void)? = url == nil ? { endPlay() } : nil
        let showsControls = url != nil || (usesFullUILiveLoading && mountedControlsRoomID == roomInfoViewModel.currentRoom.id)
        return ZStack {
            if let url {
                playerEngine(url: url)
            }
            if showsControls {
                playerControlLayers
            }
            if usesFullUILiveLoading, !roomInfoViewModel.hasObservedPlaybackProgress {
                TVPlayerLoadingScreen(
                    room: roomInfoViewModel.currentRoom,
                    stage: roomInfoViewModel.startupStage,
                    dynamicInfo: streamInfo(for: url)
                )
                .id(roomInfoViewModel.currentRoom.id)
                .allowsHitTesting(false)
                .zIndex(2.75)
            } else if url != nil, shouldShowStreamLoading {
                TVStreamLoadingOverlay(
                    dynamicInfo: playerCoordinator.playerLayer?.player.dynamicInfo,
                    stage: usesFullUILiveLoading ? .buffering : roomInfoViewModel.startupStage
                )
                .zIndex(4)
            }
        }
        .background { if usesFullUILiveLoading { Color.black.ignoresSafeArea() } }
        .onExitCommand(perform: usesFullUI ? nil : exitWhileLoading)
        .tvFullUIBackCommand(enabled: usesFullUI && !showsControls && !accountRecoveryIsActive) { endPlay() }
        .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.playerEndPlay)) { _ in
            endPlay()
        }
        .onPlayPauseCommand {
            if !usesFullUI { roomInfoViewModel.togglePlayPause() }
        }
        .frame(width: usesFullUI ? nil : 1920, height: usesFullUI ? nil : 1080)
    }

    private func playerEngine(url: URL) -> some View {
        KSVideoPlayer(coordinator: playerCoordinator, url: url, options: roomInfoViewModel.playerOption)
            .background(Color.black)
            .onAppear {
                if usesFullUILiveLoading { mountedControlsRoomID = roomInfoViewModel.currentRoom.id }
                playerCoordinator.playerLayer?.play()
                roomInfoViewModel.setPlayerDelegate(playerCoordinator: playerCoordinator)
                // 起播超时、卡顿和结束由恢复协调器的采样处理。
                roomInfoViewModel.recoveryCoordinator.start()
            }
            .onChange(of: url) { _, newURL in
                // 更换播放地址后，重新绑定 KSPlayer 可能重建的采样层。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard !didCleanup, roomInfoViewModel.currentPlayURL == newURL else { return }
                    roomInfoViewModel.setPlayerDelegate(playerCoordinator: playerCoordinator)
                }
            }
            .safeAreaPadding(.all)
            .zIndex(1)
    }

    @ViewBuilder
    private var playerControlLayers: some View {
        PlayerControlView(playerCoordinator: playerCoordinator,
                          showsRoomBanner: roomBannerID == roomInfoViewModel.currentRoom.id,
                          sleepTimer: sleepTimer,
                          accountRecoveryIsActive: accountRecoveryIsActive,
                          onSetSleepTimer: setSleepTimer,
                          onBottomControlVisibilityChange: { showsBottomControls = $0 },
                          onRouteOnDemandRoom: { routedOnDemandRoom = $0 })
            .zIndex(3)
            .frame(width: usesFullUI ? nil : 1920, height: usesFullUI ? nil : 1080)
            .safeAreaPadding(.all, usesFullUI ? 0 : nil)
            .ignoresSafeArea(usesFullUI ? .container : [])
            .environment(roomInfoViewModel)
            .environment(appViewModel)
        if roomInfoViewModel.supportsDanmu {
            VStack {
                if appViewModel.danmuSettingsViewModel.danmuAreaIndex >= 3 {
                    Spacer()
                }
                DanmuView(coordinator: roomInfoViewModel.danmuCoordinator,
                          height: appViewModel.danmuSettingsViewModel.getDanmuArea().0,
                          bottomControlBand: usesFullUI && showsBottomControls && !roomInfoViewModel.isOnDemand
                            ? TVFullUIPlayerControlMetrics.bottomControlBand : 0)
                    .frame(width: 1920, height: appViewModel.danmuSettingsViewModel.getDanmuArea().0)
                    .opacity(appViewModel.danmuSettingsViewModel.showDanmu ? 1 : 0)
                    .environment(appViewModel)
                if appViewModel.danmuSettingsViewModel.danmuAreaIndex < 3 {
                    Spacer()
                }
            }
            .zIndex(2)
        }

        #if canImport(KSPlayer)
        if appViewModel.pluginAvailability.hasAvailablePlugins, let url = roomInfoViewModel.currentPlayURL {
            Color.clear
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liveSubtitleOverlay(
                    coordinator: playerCoordinator,
                    playback: roomInfoViewModel.subtitlePlayback,
                    playbackIdentity: url.absoluteString,
                    bottomPadding: 64
                )
                .zIndex(2.5)
        }
        #endif
    }

    private func setSleepTimer(minutes: Int) {
        guard usesFullUI else { return }
        sleepTimer = minutes == 0 ? nil : TVPlaybackSleepTimer(
            minutes: minutes, deadline: .now + .seconds(minutes * 60)
        )
    }

    @MainActor func endPlay() {
        cleanupPlayer()
        didExitView(false, "")
    }

    @MainActor
    private func showRecoveryNotice(_ notice: PlaybackRecoveryNotice?) {
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

    @MainActor
    private func cleanupPlayer() {
        guard !didCleanup else { return }
        didCleanup = true
        sleepTimer = nil
        cancelRoomBanner()
        roomInfoViewModel.subtitlePlayback.stop()
        roomInfoViewModel.endPlaybackDiagnostics()
        SupportDiagnosticsService.shared.recordAction(
            .closedRoom,
            context: SupportDiagnosticActionContext.room(roomInfoViewModel.currentRoom)
        )
        roomInfoViewModel.recoveryCoordinator.stop()
        playerCoordinator.resetPlayer()
        roomInfoViewModel.disConnectSocket()
    }

    private var usesFullUILiveLoading: Bool {
        usesFullUI && !roomInfoViewModel.isOnDemand
    }

    private func streamInfo(for url: URL?) -> DynamicInfo? {
        guard let url, let layer = playerCoordinator.playerLayer, layer.url == url else { return nil }
        return layer.player.dynamicInfo
    }

    private var shouldShowStreamLoading: Bool {
        if roomInfoViewModel.hasObservedPlaybackProgress {
            guard let player = playerCoordinator.playerLayer?.player else { return false }
            return player.playbackState == .seeking
                || (usesFullUILiveLoading && playerCoordinator.state == .buffering && player.loadState != .playable)
        }
        return isInitialStreamLoading
    }

    /// 流首次加载（URL 已就绪但未开始播放）。
    /// 注意：.readyToPlay 是「准备好可以播」而非「已在播」，KSPlayer 此时尚未渲染帧。
    /// 不能用 isPlaying 二次过滤，否则 .readyToPlay 与 .buffering 之间会闪一帧黑。
    private var isInitialStreamLoading: Bool {
        switch playerCoordinator.state {
        case .paused, .playedToTheEnd, .error:
            return false
        default:
            return true
        }
    }
}

// MARK: - 直播加载指示

private struct TVPlayerLoadingScreen: View {
    let room: LiveModel
    let stage: PlaybackStartupStage
    let dynamicInfo: DynamicInfo?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if !room.roomCover.isEmpty, let url = URL(string: room.roomCover) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .scaleEffect(1.04)
                        .blur(radius: 18)
                        .accessibilityHidden(true)
                    Color.black.opacity(0.50)
                }

                VStack(spacing: 16) {
                    avatar
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    Text(room.userName.orDash)
                        .font(.system(size: 48, weight: .semibold))
                        .lineLimit(1)
                    TranslatedRoomTitle(room.roomTitle.orDash)
                        .font(.system(size: 31))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                    ArcSpinner(size: 64, lineWidth: 2.5)
                        .tint(.white)
                        .padding(.top, 16)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stage.title)
                            .font(.system(size: 29, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .layoutPriority(1)
                        if let dynamicInfo {
                            TVStreamSpeedText(info: dynamicInfo, isInline: true)
                        }
                    }
                    .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, TVFullUIPlayerControlMetrics.screenInset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("player.loading")
            }
            .clipped()
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var avatar: some View {
        if !room.userHeadImg.isEmpty, let url = URL(string: room.userHeadImg) {
            KFImage(url)
                .placeholder { avatarPlaceholder }
                .resizable()
                .scaledToFill()
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 52, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.15))
    }
}

/// tvOS 直播流加载层:细圆弧 + 数字/单位分体网速,无背景片,贴在视频画面上。
/// 网速订阅 KSPlayer 自带的 `DynamicInfo.networkSpeed`(@Published)。
struct TVStreamLoadingOverlay: View {
    let dynamicInfo: DynamicInfo?
    let stage: PlaybackStartupStage

    var body: some View {
        VStack(spacing: 24) {
            ArcSpinner(size: 64, lineWidth: 2.5)
                .tint(.white)
            VStack(spacing: 10) {
                Text(stage.title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let info = dynamicInfo {
                    TVStreamSpeedText(info: info)
                }
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage.title)
    }
}

private struct TVStreamSpeedText: View {
    @ObservedObject var info: DynamicInfo
    var isInline = false

    var body: some View {
        if info.networkSpeed > 0 {
            let (value, unit) = SpeedFormatter.split(bytesPerSecond: Int64(info.networkSpeed))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: isInline ? 34 : 44, weight: isInline ? .light : .ultraLight, design: .rounded))
                    .foregroundStyle(.white.opacity(isInline ? 0.72 : 1))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: isInline ? 19 : 18, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(isInline ? 0.72 : 0.55))
            }
        }
    }
}

private struct TVPlayerRecoveryNoticeBanner: View {
    let notice: PlaybackRecoveryNotice

    var body: some View {
        Text(notice.title)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 800)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel(notice.title)
    }
}

// MARK: - 共享组件

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
