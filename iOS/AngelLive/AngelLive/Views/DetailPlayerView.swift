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

    /// 全局播放器 coordinator，在整个 DetailPlayerView 生命周期中保持
    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()

    /// iPad 是否处于全屏模式
    @State private var isIPadFullscreen: Bool = false

    // MARK: - Device & Layout Detection

    /// 是否为 iPad
    private var isIPad: Bool {
        AppConstants.Device.isIPad
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isIPhoneLandscape = !isIPad && isLandscape
            let showInfoPanel = !(isIPhoneLandscape || isIPadFullscreen)

            // 计算播放器布局参数
            let playerWidth: CGFloat = {
                if showInfoPanel && isIPad && isLandscape {
                    return geometry.size.width - 400 // iPad 横屏减去右侧信息栏
                } else {
                    return geometry.size.width
                }
            }()

            let playerHeight: CGFloat = {
                if showInfoPanel && !isIPad {
                    return playerWidth / 16 * 9 // 竖屏保持 16:9 比例
                } else {
                    return geometry.size.height
                }
            }()

            ZStack(alignment: .topLeading) {
                // 模糊背景
                backgroundView

                // 播放器 - 始终在同一位置，只改变 frame，不会重建
                PlayerContentView(playerCoordinator: playerCoordinator)
                    .id("stable_player")
                    .environment(viewModel)
                    .frame(width: playerWidth, height: playerHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // 信息面板 - 根据布局动态显示/隐藏
                if showInfoPanel {
                    if isIPad && isLandscape {
                        // iPad 横屏：右侧面板
                        VStack(spacing: 0) {
                            StreamerInfoView()
                                .environment(viewModel)
                            Divider()
                                .background(Color.white.opacity(0.2))
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

                // 返回按钮
                if showInfoPanel {
                    backButton
                        .padding(.top, 8)
                        .padding(.leading, 8)
                        .zIndex(10)
                }
            }
        }
        .environment(\.isIPadFullscreen, $isIPadFullscreen)
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadPlayURL()
        }
        .onDisappear {
            viewModel.disconnectSocket()
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
        PlayerContentView(playerCoordinator: playerCoordinator)
            .id("stable_player") // 关键：所有布局使用相同的 id
            .environment(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }

    /// iPad 横屏布局（左右分栏）
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // 左侧：播放器
            PlayerContentView(playerCoordinator: playerCoordinator)
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
            PlayerContentView(playerCoordinator: playerCoordinator)
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

            // 更多功能按钮（右下角）
            MoreActionsButton(onClearChat: clearChat)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
    }

    private var chatListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.danmuMessages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 60) // 为更多按钮留出空间
            }
            .onChange(of: viewModel.danmuMessages.count) { oldValue, newValue in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - 返回按钮

    private var backButton: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .shadow(
                    color: .black.opacity(0.2),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .padding(.top, 8)
        .padding(.leading, 16)
    }

    // MARK: - Helper Methods

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if let lastMessage = viewModel.danmuMessages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func clearChat() {
        withAnimation {
            viewModel.danmuMessages.removeAll()
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
