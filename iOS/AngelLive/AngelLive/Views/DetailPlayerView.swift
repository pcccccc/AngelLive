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
    @State private var isPlayerFullScreen = false

    // MARK: - Device & Layout Detection

    /// 是否为 iPad
    private var isIPad: Bool {
        AppConstants.Device.isIPad
    }

    /// 是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    /// 是否使用分栏布局（iPad 横屏）
    private var useSplitLayout: Bool {
        isIPad && isLandscape
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 模糊背景（使用主播头像）- 铺满整个屏幕
            BlurredBackgroundView(imageURL: viewModel.currentRoom.userHeadImg)
                .edgesIgnoringSafeArea(.all)

            // 内容区域
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // 根据设备和方向选择布局
                    if useSplitLayout {
                        // iPad 横屏：左右分栏布局
                        iPadLandscapeLayout
                    } else {
                        // iPhone 或 iPad 竖屏：上下布局
                        portraitLayout
                    }

                    // 屏幕弹幕层（飞过效果）
                    if viewModel.showDanmu {
                        DanmuView(coordinator: viewModel.danmuCoordinator)
                            .allowsHitTesting(false) // 不拦截触摸事件
                            .zIndex(2)
                    }

                    // 返回按钮（非全屏显示）
                    if !isPlayerFullScreen {
                        backButton
                            .zIndex(3)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadPlayURL()
        }
        .onDisappear {
            // 页面消失时断开弹幕连接
            viewModel.disconnectSocket()
        }
    }

    // MARK: - iPad 横屏布局（左右分栏）

    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // 左侧：播放器
            PlayerContainerView(isFullScreen: $isPlayerFullScreen)
                .environment(viewModel)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: isPlayerFullScreen ? .infinity : nil)

            // 右侧：主播信息 + 聊天
            if !isPlayerFullScreen {
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
    }

    // MARK: - 竖屏布局（上下排列）

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // 播放器容器
            PlayerContainerView(isFullScreen: $isPlayerFullScreen)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: isPlayerFullScreen ? .infinity : nil)
                .environment(viewModel)

            if !isPlayerFullScreen {
                // 主播信息
                StreamerInfoView()
                    .environment(viewModel)
                // 聊天区域
                chatAreaWithMoreButton
            }
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
