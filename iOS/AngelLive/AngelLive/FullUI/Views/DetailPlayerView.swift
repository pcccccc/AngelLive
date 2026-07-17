//
//  DetailPlayerView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct DetailPlayerView: View {
    @State var viewModel: RoomInfoViewModel
    let categoryRooms: [LiveModel]
    let canLoadMoreCategoryRooms: () -> Bool
    let onLoadMoreCategoryRooms: (() async -> [LiveModel])?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(HistoryModel.self) private var historyModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.scenePhase) private var scenePhase

    /// 全局播放器 coordinator，在整个 DetailPlayerView 生命周期中保持
    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    /// 稳定的播放器模型，避免随视图重建
    @StateObject private var playerModel = KSVideoPlayerModel(title: "", config: KSVideoPlayer.Coordinator(), options: KSOptions(), url: nil)
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary,
        supportedGlobalCapabilities: [.audioFocus, .nowPlaying, .pictureInPicture, .remoteCommands]
    )

    /// iPad 是否处于全屏模式
    @State private var isIPadFullscreen: Bool = false

    /// iPhone 播放器实际高度（由 PlayerContentView 报告）
    @State private var iPhonePlayerHeight: CGFloat = 0

    /// 是否为竖屏直播模式
    @State private var isVerticalLiveMode: Bool = false

    /// 当前是否 iPhone 横屏（用于禁用下滑手势）
    @State private var isIPhoneLandscape: Bool = false

    /// 进入后台前是否处于 iPhone 横屏全屏（用于回前台时保留用户主动触发的横屏）
    @State private var wasLandscapeBeforeBackground: Bool = false

    /// 用户离开底部时显示“查看最新评论”按钮
    @State private var showJumpToLatest: Bool = false
    /// 触发跳到底部的请求
    @State private var scrollToBottomRequest: Bool = false

    @State private var isRoomSwitcherPresented = false
    @State private var selectedRoomSourceIndex: Int
    @State private var switchingRoomID: String?
    @State private var failedRoomID: String?
    @State private var roomSwitchFailureMessage: String?
    @State private var roomSwitchTask: Task<Void, Never>?
    @State private var switcherCategoryRooms: [LiveModel]
    @State private var isLoadingMoreCategoryRooms = false

    init(
        viewModel: RoomInfoViewModel,
        categoryRooms: [LiveModel] = [],
        canLoadMoreCategoryRooms: @escaping () -> Bool = { false },
        onLoadMoreCategoryRooms: (() async -> [LiveModel])? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.categoryRooms = categoryRooms
        self.canLoadMoreCategoryRooms = canLoadMoreCategoryRooms
        self.onLoadMoreCategoryRooms = onLoadMoreCategoryRooms
        let hasCategoryRooms = categoryRooms.contains(viewModel.currentRoom)
            && categoryRooms.contains { $0 != viewModel.currentRoom }
        _selectedRoomSourceIndex = State(initialValue: hasCategoryRooms ? 2 : 0)
        _switcherCategoryRooms = State(initialValue: categoryRooms)
    }

    private var currentPlaybackError: Error? {
        viewModel.playError
    }

    private var playbackErrorTitle: String {
        if currentPlaybackError?.isAuthRequired == true {
            let platformName = LiveParseTools.getLivePlatformName(viewModel.currentRoom.liveType)
            return "播放失败-请登录\(platformName)账号"
        }
        return "播放失败"
    }

    private var playbackErrorMessage: String {
        if let error = currentPlaybackError {
            return error.liveParseMessage
        }
        return viewModel.playErrorMessage ?? "播放失败"
    }

    private var shouldShowPlatformLoginPrompt: Bool {
        currentPlaybackError?.isAuthRequired == true
    }

    private var shouldHideSystemBackButton: Bool {
        true
    }

    private var shouldEnableInteractivePopGesture: Bool {
        if #available(iOS 18.0, *) {
            return false
        }
        return !isIPhoneLandscape
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let iPhoneLandscapeMode = !AppConstants.Device.isIPad && isLandscape
            // 竖屏直播模式下隐藏信息面板，让播放器占满全屏
            let showInfoPanel = isVerticalLiveMode ? false : !(iPhoneLandscapeMode || isIPadFullscreen)

            // 获取安全区信息（在任何 edgesIgnoringSafeArea 之前）
            let safeInsets = EdgeInsets(
                top: geometry.safeAreaInsets.top,
                leading: geometry.safeAreaInsets.leading,
                bottom: geometry.safeAreaInsets.bottom,
                trailing: geometry.safeAreaInsets.trailing
            )

            // 计算播放器宽度
            let playerWidth: CGFloat = {
                // iPhone 横屏时补回安全区宽度，确保实际绘制能覆盖左右刘海区域
                let baseWidth = iPhoneLandscapeMode ? (geometry.size.width + safeInsets.leading + safeInsets.trailing) : geometry.size.width
                if isVerticalLiveMode {
                    return baseWidth // 竖屏直播占满宽度
                } else if showInfoPanel && AppConstants.Device.isIPad && isLandscape {
                    return baseWidth - 400 // iPad 横屏减去右侧信息栏
                } else {
                    return baseWidth
                }
            }()

            // 横屏时补回安全区高度，让内容也能覆盖上下刘海/指示器
            let safeAdjustedHeight = iPhoneLandscapeMode ? (geometry.size.height + safeInsets.top + safeInsets.bottom) : geometry.size.height

            // iPad: 使用计算的固定高度；iPhone: 使用报告的动态高度
            let playerHeight: CGFloat = {
                if isVerticalLiveMode {
                    return geometry.size.height // 竖屏直播占满高度
                } else if AppConstants.Device.isIPad {
                    // iPad 保持原逻辑
                    if showInfoPanel {
                        if isLandscape {
                            return geometry.size.height // iPad 横屏占满高度
                        } else {
                            return playerWidth / 16 * 9 // iPad 竖屏保持 16:9
                        }
                    } else {
                        return geometry.size.height // 全屏模式占满高度
                    }
                } else {
                    // iPhone: 使用 PlayerContentView 报告的高度，如果还没报告则用默认 16:9
                    return iPhonePlayerHeight > 0 ? iPhonePlayerHeight : (playerWidth / 16 * 9)
                }
            }()

            ZStack(alignment: .topLeading) {
                // 模糊背景
                backgroundView

                // 主播已下播视图
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
                        Button("返回") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
                }
                // 错误视图 - 当播放出错时显示
                else if viewModel.playError != nil || viewModel.playErrorMessage != nil {
                    ErrorView(
                        title: playbackErrorTitle,
                        message: playbackErrorMessage,
                        errorCode: nil,
                        detailMessage: currentPlaybackError?.liveParseDetail,
                        curlCommand: currentPlaybackError?.liveParseCurl,
                        showDismiss: true,
                        showRetry: true,
                        showLoginButton: shouldShowPlatformLoginPrompt,
                        showDetailButton: currentPlaybackError?.liveParseDetail?.isEmpty == false,
                        onDismiss: {
                            dismiss()
                        },
                        onRetry: {
                            Task {
                                await viewModel.loadPlayURL(force: true)
                            }
                        },
                        onLogin: shouldShowPlatformLoginPrompt ? {
                            dismiss()
                            NotificationCenter.default.post(name: .switchToSettings, object: nil)
                        } : nil
                    )
                    .zIndex(100)
                } else {
                    // 播放器 - 始终在同一位置，只改变 frame，不会重建
                    PlayerContentView(playerCoordinator: playerCoordinator, playerModel: playerModel)
                        .id("stable_player")
                        .environment(viewModel)
                        .environment(\.isVerticalLiveMode, isVerticalLiveMode)
                        .environment(\.safeAreaInsetsCustom, safeInsets)
                        .frame(
                            width: playerWidth,
                            height: AppConstants.Device.isIPad ? playerHeight : (iPhoneLandscapeMode ? safeAdjustedHeight : nil)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // iPhone 横屏时让播放器区域覆盖 Safe Area，避免控制层/统计被刘海遮挡
                        .edgesIgnoringSafeArea(iPhoneLandscapeMode ? .all : [])
                        // iPad: 阻止播放器区域的下拉手势触发退出，聊天面板仍可下拉退出
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { _ in }
                        )
                        .onPreferenceChange(PlayerHeightPreferenceKey.self) { height in
                            if !AppConstants.Device.isIPad {
                                iPhonePlayerHeight = height
                            }
                        }
                        .onPreferenceChange(VerticalLiveModePreferenceKey.self) { mode in
                            isVerticalLiveMode = mode
                        }

                    // 信息面板 - 根据布局动态显示/隐藏
                    if showInfoPanel {
                        if AppConstants.Device.isIPad && isLandscape {
                            // iPad 横屏：右侧面板
                            informationArea
                            .frame(width: 400)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: geometry.size.width - 400, y: 0)
                        } else {
                            // 竖屏：底部面板
                            informationArea
                            .frame(maxWidth: .infinity)
                            .frame(height: geometry.size.height - playerHeight)
                            .offset(x: 0, y: playerHeight)
                        }
                    }

                    // iOS 18+ interactivePopGesture 被禁用，这里用独立的 20pt 左边缘视图补回返回手势。
                    // 作为 ZStack 兄弟视图(而非 player 的 .overlay)，避免破坏 PreferenceKey 传递。
                    if #available(iOS 18.0, *), !iPhoneLandscapeMode {
                        EdgeSwipeDismissView(edgeWidth: 20) {
                            if AppConstants.Device.isIPad && isIPadFullscreen {
                                isIPadFullscreen = false
                            } else {
                                dismiss()
                            }
                        }
                        .frame(width: 20)
                        .frame(maxHeight: .infinity, alignment: .leading)
                        .ignoresSafeArea()
                    }
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                let isLandscape = newSize.width > newSize.height
                isIPhoneLandscape = !AppConstants.Device.isIPad && isLandscape
            }
            .onAppear {
                let isLandscape = geometry.size.width > geometry.size.height
                isIPhoneLandscape = !AppConstants.Device.isIPad && isLandscape
            }
        }
        .environment(\.isIPadFullscreen, $isIPadFullscreen)
        .navigationBarBackButtonHidden(shouldHideSystemBackButton)
        .interactivePopGestureEnabled(shouldEnableInteractivePopGesture)
        .interactiveDismissDisabled(isIPhoneLandscape)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Logger.debug("[PlayerFlow] Detail scenePhase -> \(newPhase), roomId=\(viewModel.currentRoom.roomId)", category: .player)
            switch newPhase {
            case .active:
                viewModel.resumeDanmuUpdatesIfNeeded()
                // iPhone：进后台前是横屏全屏（用户主动触发），回前台时保留横屏，
                // 否则会被设备姿态/系统重新查询 supportedInterfaceOrientations 扳回竖屏。
                if !AppConstants.Device.isIPad && wasLandscapeBeforeBackground {
                    wasLandscapeBeforeBackground = false
                    reassertLandscapeOrientation()
                }
            case .inactive, .background:
                viewModel.pauseDanmuUpdatesForBackground()
                // 只在「从活跃态离开」时记录:回前台路径是 background→inactive→active,
                // 若在 inactive 也记录会被回程的 inactive 用已翻回竖屏的值覆盖,导致保留失效。
                if oldPhase == .active && !AppConstants.Device.isIPad {
                    wasLandscapeBeforeBackground = isIPhoneLandscape
                }
            @unknown default:
                break
            }
        }
        .onChange(of: isVerticalLiveMode) { _, isVertical in
            // 竖屏直播模式下锁定竖屏，不允许自动横屏全屏
            if !AppConstants.Device.isIPad && isVertical {
                KSOptions.supportedInterfaceOrientations = .portrait
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            NowPlayingManager.updatePlaybackState(
                isPlaying: isPlaying,
                surfaceID: playbackSession.surfaceID
            )
        }
        .onChange(of: playerCoordinator.state) { _, _ in
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
        }
        .task {
            await viewModel.loadPlayURL()
        }
        .onAppear {
            playbackSession.activate()
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
            viewModel.playbackSurfaceID = playbackSession.surfaceID
            // 添加观看历史记录
            historyModel.addHistory(room: viewModel.currentRoom)
            // 设置 Now Playing 信息(占位;真正稳定的写入在 RoomInfoViewModel 的 readyToPlay 回调里补写)。
            // 远程控制命令(播放/暂停等)由 KSPlayer 的 registerRemoteControll 统一注册,此处不再重复注册。
            NowPlayingManager.update(
                room: viewModel.currentRoom,
                isPlaying: false,
                surfaceID: playbackSession.surfaceID
            )
            // iPhone 进入播放页时允许自由旋转，横屏时自动全屏
            if !AppConstants.Device.isIPad {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
        .onDisappear {
            roomSwitchTask?.cancel()
            Logger.debug("[PlayerFlow] Detail onDisappear, roomId=\(viewModel.currentRoom.roomId), kernel=\(viewModel.selectedPlayerKernel.rawValue)", category: .player)
            viewModel.disconnectSocket()
            // 清除 Now Playing 信息(远程控制命令由 KSPlayer 在 stop() 时自行注销)
            NowPlayingManager.clear(surfaceID: playbackSession.surfaceID)
            playbackSession.invalidate()
            viewModel.playbackSurfaceID = nil
            // iPhone 返回时强制竖屏
            if !AppConstants.Device.isIPad {
                // 设置支持的方向为竖屏
                KSOptions.supportedInterfaceOrientations = .portrait

                    guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else {
                    return
                }

                // 先通知 ViewController 刷新支持的方向
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
                DispatchQueue.main.async {
                    let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                        interfaceOrientations: .portrait
                    )
                    windowScene.requestGeometryUpdate(geometryPreferences) { error in
                        Logger.error("[PlayerFlow] 强制竖屏失败: \(error.localizedDescription)", category: .player)
                    }
                }
            }
        }
    }

    // MARK: - Orientation

    /// iPhone 回前台后保留横屏全屏:临时锁定横屏发起几何更新,完成后恢复自由旋转,
    /// 这样既保留用户主动横屏,又允许之后旋转/双击切回竖屏。
    private func reassertLandscapeOrientation() {
        guard !AppConstants.Device.isIPad else { return }
        KSOptions.supportedInterfaceOrientations = .landscape
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        // 先通知 ViewController 刷新支持的方向
        if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        // 延迟到下一个 run loop,确保 VC 已刷新支持的方向
        DispatchQueue.main.async {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: .landscape
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { error in
                Logger.warning("[PlayerFlow] 回前台保留横屏失败: \(error.localizedDescription)", category: .player)
            }
            // 旋转完成后恢复自由旋转,允许用户后续旋转/双击切回竖屏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        BlurredBackgroundView(imageURL: viewModel.currentRoom.userHeadImg)
            .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Layouts

    /// 全屏播放器布局（iPhone 横屏 或 iPad 全屏）
    private var fullscreenPlayerLayout: some View {
        PlayerContentView(playerCoordinator: playerCoordinator, playerModel: playerModel)
            .id("stable_player") // 关键：所有布局使用相同的 id
            .environment(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }

    /// iPad 横屏布局（左右分栏）
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // 左侧：播放器
            PlayerContentView(playerCoordinator: playerCoordinator, playerModel: playerModel)
                .id("stable_player") // 关键：所有布局使用相同的 id
                .environment(viewModel)
                .frame(maxWidth: .infinity)

            informationArea
                .frame(width: 400)
        }
    }

    /// 竖屏布局（上下排列）
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // 播放器容器
            PlayerContentView(playerCoordinator: playerCoordinator, playerModel: playerModel)
                .id("stable_player") // 关键：所有布局使用相同的 id
                .environment(viewModel)
                .frame(maxWidth: .infinity)

            informationArea
        }
    }

    // MARK: - 播放器下方信息区

    private var informationArea: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                StreamerInfoView()
                    .environment(viewModel)
                chatListView
            }

            if showJumpToLatest {
                jumpToLatestButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            RoomActionDock(
                isSwitcherPresented: isRoomSwitcherPresented,
                room: viewModel.currentRoom,
                onToggleSwitcher: toggleRoomSwitcher,
                onClearChat: clearChat
            )
            .environment(viewModel)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $isRoomSwitcherPresented) {
            RoomSwitcherPanel(
                currentRoom: viewModel.currentRoom,
                favorites: favoriteModel.roomList,
                history: historyModel.watchList,
                category: switcherCategoryRooms,
                selectedSourceIndex: $selectedRoomSourceIndex,
                switchingRoomID: switchingRoomID,
                failedRoomID: failedRoomID,
                failureMessage: roomSwitchFailureMessage,
                canLoadMoreCategory: canLoadMoreCategoryRooms,
                isLoadingMoreCategory: isLoadingMoreCategoryRooms,
                onLoadMoreCategory: loadMoreSwitcherCategoryRooms,
                onSelect: switchRoom
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: categoryRooms) { _, newValue in
            switcherCategoryRooms = newValue
        }
    }

    private var chatListView: some View {
        ChatTableView(
            messages: viewModel.danmuMessages,
            showJumpToLatest: $showJumpToLatest,
            scrollToBottomRequest: $scrollToBottomRequest
        )
    }

    private var jumpToLatestButton: some View {
        Button {
            scrollToBottomRequest = true
        } label: {
            HStack(spacing: 6) {
                Text("查看最新评论")
                Image(systemName: "arrow.down")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(AppConstants.PlayerUI.Opacity.overlayMedium))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Helper Methods

    private func clearChat() {
        withAnimation {
            viewModel.danmuMessages.removeAll()
            showJumpToLatest = false
        }
    }

    private func toggleRoomSwitcher() {
        isRoomSwitcherPresented.toggle()
    }

    private func switchRoom(_ room: LiveModel) {
        roomSwitchTask?.cancel()
        switchingRoomID = room.id
        failedRoomID = nil
        roomSwitchFailureMessage = nil
        let requestRoomID = room.id

        roomSwitchTask = Task { @MainActor in
            do {
                try await viewModel.switchRoom(to: room)
                try Task.checkCancellation()

                historyModel.addHistory(room: room)
                NowPlayingManager.update(
                    room: room,
                    isPlaying: false,
                    surfaceID: playbackSession.surfaceID
                )

                if switchingRoomID == requestRoomID {
                    switchingRoomID = nil
                }
            } catch is CancellationError {
                // A newer room selection owns the visible switching state.
            } catch {
                guard switchingRoomID == requestRoomID else { return }
                switchingRoomID = nil
                failedRoomID = requestRoomID
                roomSwitchFailureMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadMoreSwitcherCategoryRooms() async -> [LiveModel] {
        guard !isLoadingMoreCategoryRooms,
              let onLoadMoreCategoryRooms else {
            return switcherCategoryRooms
        }

        isLoadingMoreCategoryRooms = true
        defer { isLoadingMoreCategoryRooms = false }

        let rooms = await onLoadMoreCategoryRooms()
        switcherCategoryRooms = rooms
        return rooms
    }
}

// MARK: - iPad Fullscreen Support

/// iPad 全屏状态的 Environment Key
private struct IPadFullscreenEnvironmentKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var isIPadFullscreen: Binding<Bool> {
        get { self[IPadFullscreenEnvironmentKey.self] }
        set { self[IPadFullscreenEnvironmentKey.self] = newValue }
    }
}

// MARK: - Vertical Live Mode Environment Key

/// 竖屏直播模式的 Environment Key
struct VerticalLiveModeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isVerticalLiveMode: Bool {
        get { self[VerticalLiveModeEnvironmentKey.self] }
        set { self[VerticalLiveModeEnvironmentKey.self] = newValue }
    }
}
