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
        if isIPadLandscape {
            // iPad 横屏：填充整个可用高度
            PlayerContentView()
                .environment(viewModel)
        } else {
            // iPhone 或 iPad 竖屏：使用 16:9 比例
            GeometryReader { proxy in
                PlayerContentView()
                    .environment(viewModel)
                    .frame(height: proxy.size.width * 9 / 16)
            }
            .aspectRatio(16/9, contentMode: .fit)
        }
    }
}

struct PlayerContentView: View {
    
    @Environment(RoomInfoViewModel.self) private var viewModel
    @ObservedObject private var playerCoordinator: KSVideoPlayer.Coordinator = KSVideoPlayer.Coordinator()
    
    var body: some View {
        ZStack(alignment: .center) {
            // 背景
            Color.black

            // 如果有播放地址，显示播放器
            if let playURL = viewModel.currentPlayURL {
                KSVideoPlayer(
                    coordinator: _playerCoordinator,
                    url: playURL,
                    options: viewModel.playerOption
                )
                .background(Color.black)
                .onAppear {
                    playerCoordinator.playerLayer?.play()
                    viewModel.setPlayerDelegate(playerCoordinator: playerCoordinator)
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
                    //                // 封面图作为背景
                    KFImage(URL(string: viewModel.currentRoom.roomCover))
                        .placeholder {
                            Rectangle()
                                .fill(AppConstants.Colors.placeholderGradient())
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }
}
