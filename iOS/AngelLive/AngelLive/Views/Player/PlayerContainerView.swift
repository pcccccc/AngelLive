//
//  PlayerContainerView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 播放器容器视图
struct PlayerContainerView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    

    // 检测是否为 iPad 横屏
    private var isIPadLandscape: Bool {
        AppConstants.Device.isIPad &&
        horizontalSizeClass == .regular &&
        verticalSizeClass == .compact
    }

    var body: some View {
        PlayerContentView()
            .environment(viewModel)
            
    }
}

struct PlayerContentView: View {

    @Environment(RoomInfoViewModel.self) private var viewModel
    @StateObject private var playerCoordinator: KSVideoPlayer.Coordinator = KSVideoPlayer.Coordinator()
    @State private var videoAspectRatio: CGFloat? = nil
    @State private var isVideoPortrait: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 检测设备是否为横屏
    private var isDeviceLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            // 如果有播放地址，显示播放器
            if let playURL = viewModel.currentPlayURL {
                KSVideoPlayerView(
                    coordinator: playerCoordinator,
                    url: playURL,
                    options: viewModel.playerOption
                ) { coordinator, isDisappear in
                    if !isDisappear {
                        viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                    }
                }
                .task {
                    // 使用异步任务定期检查视频尺寸
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

                        if let naturalSize = playerCoordinator.playerLayer?.player.naturalSize,
                           naturalSize.width > 0, naturalSize.height > 0 {
                            let ratio = naturalSize.width / naturalSize.height
                            let isPortrait = ratio < 1.0

                            if videoAspectRatio != ratio {
                                print("📺 视频尺寸: \(naturalSize.width) x \(naturalSize.height)")
                                print("📐 视频比例: \(ratio)")
                                print("📱 视频方向: \(isPortrait ? "竖屏" : "横屏")")
                                print("🖥️ 设备方向: \(isDeviceLandscape ? "横屏" : "竖屏")")

                                videoAspectRatio = ratio
                                isVideoPortrait = isPortrait

                                // 打印应用的策略
                                if isDeviceLandscape && isPortrait {
                                    print("✅ 应用策略: 横屏设备+竖屏视频 → 限制宽度，居中显示")
                                } else {
                                    print("✅ 应用策略: 标准 aspect fit 显示")
                                }

                                break // 获取到后退出循环
                            }
                        }
                    }
                }
                .onChange(of: playURL) { _ in
                    // 切换视频时重置比例
                    print("🔄 切换视频，重置比例")
                    videoAspectRatio = nil
                    isVideoPortrait = false
                }
            } else {
                if viewModel.isLoading {
                    // 加载中
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("正在解析直播地址...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // 封面图作为背景
                    KFImage(URL(string: viewModel.currentRoom.roomCover))
                        .placeholder {
                            Rectangle()
                                .fill(AppConstants.Colors.placeholderGradient())
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .frame(
            maxWidth: shouldLimitWidth ? nil : .infinity,
            maxHeight: .infinity
        )
        .aspectRatio(videoAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity) // 外层容器仍然填满，用于居中
        .background(Color.black)
    }

    // 判断是否需要限制宽度（横屏设备 + 竖屏视频）
    private var shouldLimitWidth: Bool {
        isDeviceLandscape && isVideoPortrait
    }
}
