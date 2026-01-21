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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(HistoryModel.self) private var historyModel
    @Environment(\.scenePhase) private var scenePhase

    /// 全局播放器 coordinator，在整个 DetailPlayerView 生命周期中保持
    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    /// 稳定的播放器模型，避免随视图重建
    @StateObject private var playerModel = KSVideoPlayerModel(title: "", config: KSVideoPlayer.Coordinator(), options: KSOptions(), url: nil)

    /// iPad 是否处于全屏模式
    @State private var isIPadFullscreen: Bool = false

    /// iPhone 播放器实际高度（由 PlayerContentView 报告）
    @State private var iPhonePlayerHeight: CGFloat = 0

    /// 是否为竖屏直播模式
    @State private var isVerticalLiveMode: Bool = false

    /// 当前是否 iPhone 横屏（用于禁用下滑手势）
    @State private var isIPhoneLandscape: Bool = false

    /// 用户离开底部时显示“查看最新评论”按钮
    @State private var showJumpToLatest: Bool = false
    /// 触发跳到底部的请求
    @State private var scrollToBottomRequest: Bool = false

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
                    ErrorView.playback(
                        message: viewModel.playErrorMessage ?? "播放失败",
                        errorCode: nil,
                        detailMessage: viewModel.playError?.liveParseDetail,
                        curlCommand: viewModel.playError?.liveParseCurl,
                        onDismiss: {
                            dismiss()
                        },
                        onRetry: {
                            Task {
                                await viewModel.loadPlayURL()
                            }
                        }
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
                            VStack(spacing: 0) {
                                StreamerInfoView()
                                    .environment(viewModel)
                                chatAreaWithMoreButton
                            }
                            .frame(width: 400)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: geometry.size.width - 400, y: 0)
                        } else {
                            // 竖屏：底部面板
                            VStack(spacing: 0) {
                                StreamerInfoView()
                                    .environment(viewModel)
                                chatAreaWithMoreButton
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: geometry.size.height - playerHeight)
                            .offset(x: 0, y: playerHeight)
                        }
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
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isIPhoneLandscape)
        .onChange(of: scenePhase) { _, newPhase in
            print("📱 scenePhase changed to: \(newPhase)")
            switch newPhase {
            case .active:
                viewModel.resumeDanmuUpdatesIfNeeded()
            case .inactive, .background:
                viewModel.pauseDanmuUpdatesForBackground()
            @unknown default:
                break
            }
        }
        .task {
            await viewModel.loadPlayURL()
        }
        .onAppear {
            // 添加观看历史记录
            historyModel.addHistory(room: viewModel.currentRoom)
        }
        .onDisappear {
            viewModel.disconnectSocket()
            // iPhone 返回时强制竖屏
            if !AppConstants.Device.isIPad {
                // 设置支持的方向为竖屏
                KSOptions.supportedInterfaceOrientations = .portrait

                    guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else {
                    return
                }

                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: .portrait
                )

                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    print("❌ 强制竖屏失败: \(error)")
                }

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

            // 右侧：主播信息 + 聊天
            VStack(spacing: 0) {
                StreamerInfoView()
                    .environment(viewModel)

                Divider()
                    .background(Color.white.opacity(0.2))

                chatAreaWithMoreButton
            }
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

            // 主播信息
            StreamerInfoView()
                .environment(viewModel)

            // 聊天区域
            chatAreaWithMoreButton
        }
    }

    // MARK: - 聊天区域（带更多按钮）

    private var chatAreaWithMoreButton: some View {
        ZStack(alignment: .bottomTrailing) {
            // 聊天消息列表
            chatListView

            if showJumpToLatest {
                jumpToLatestButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 更多功能按钮（右下角）
            MoreActionsButton(
                room: viewModel.currentRoom,
                onClearChat: clearChat
            )
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }

    private var chatListView: some View {
        Group {
            if scenePhase == .active {
                ChatTableView(
                    messages: viewModel.danmuMessages,
                    showJumpToLatest: $showJumpToLatest,
                    scrollToBottomRequest: $scrollToBottomRequest
                )
            } else {
                EmptyView()
            }
        }
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
