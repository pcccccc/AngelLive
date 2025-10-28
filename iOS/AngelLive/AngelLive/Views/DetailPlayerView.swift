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
    @Environment(PlayerCoordinatorManager.self) private var playerManager

    /// iPad 是否处于全屏模式
    @State private var isIPadFullscreen: Bool = false

    // MARK: - Device & Layout Detection

    /// 是否为 iPad
    private var isIPad: Bool {
        AppConstants.Device.isIPad
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 模糊背景（使用主播头像）- 铺满整个屏幕
            backgroundView

            // 内容区域
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                let isIPhoneLandscape = !isIPad && isLandscape  // iPhone 横屏

                ZStack(alignment: .topLeading) {
                    // 根据设备和方向选择布局
                    if isIPhoneLandscape || isIPadFullscreen {
                        // iPhone 横屏 或 iPad 全屏：只显示播放器
                        fullscreenPlayerLayout
                    } else if AppConstants.Device.isIPad && isLandscape {
                        // iPad 横屏（非全屏）：左右分栏布局
                        iPadLandscapeLayout
                    } else {
                        // iPhone 竖屏 或 iPad 竖屏（非全屏）：上下布局
                        portraitLayout
                    }

                    // 返回按钮（始终显示在左上角）
                    // iPhone 横屏或 iPad 全屏时由播放器控制层显示，这里不显示
                    if !isIPhoneLandscape && !isIPadFullscreen {
                        backButton
                            .zIndex(3)
                    }
                }
            }
        }
        .environment(\.isIPadFullscreen, $isIPadFullscreen)
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadPlayURL()
        }
        .onDisappear {
            // 页面消失时断开弹幕连接
            viewModel.disconnectSocket()

            // 重置全局播放器状态
            playerManager.reset()
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        BlurredBackgroundView(imageURL: viewModel.currentRoom.userHeadImg)
            .edgesIgnoringSafeArea(.all)
    }

    // MARK: - 全屏播放器布局（iPhone 横屏 或 iPad 全屏）

    private var fullscreenPlayerLayout: some View {
        PlayerContainerView()
            .environment(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }

    // MARK: - iPad 横屏布局（左右分栏）

    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // 左侧：播放器
            PlayerContainerView()
                .environment(viewModel)
                .frame(maxWidth: .infinity)

            // 右侧：主播信息 + 聊天
            VStack(spacing: 0) {
                // 主播信息
                StreamerInfoView()
                    .environment(viewModel)

                Divider()
                    .background(Color.white.opacity(0.2))

                // 聊天区域
                chatAreaWithMoreButton
            }
            .frame(width: 400)
        }
    }

    // MARK: - 竖屏布局（上下排列）

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // 播放器容器
            PlayerContainerView()
                .frame(maxWidth: .infinity)
                .environment(viewModel)

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
