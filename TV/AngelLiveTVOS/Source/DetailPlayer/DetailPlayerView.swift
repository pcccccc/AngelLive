//
//  DetailPlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/12.
//

import SwiftUI
import AVKit
import AngelLiveDependencies


struct DetailPlayerView: View {
    
    @ObservedObject private var playerCoordinator: KSVideoPlayer.Coordinator = KSVideoPlayer.Coordinator()
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
                Text(roomInfoViewModel.currentRoom.userName)
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
                title: error.isBilibiliAuthRequired ? "播放失败-请登录B站账号并检查官方页面" : "播放失败",
                message: error.liveParseMessage,
                detailMessage: error.liveParseDetail,
                curlCommand: error.liveParseCurl,
                showRetry: true,
                showLoginButton: error.isBilibiliAuthRequired,
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
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("正在解析直播地址")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(width: 1920, height: 1080)
            .background(.black)
        }else {
            ZStack {
                KSVideoPlayer(coordinator: _playerCoordinator, url:roomInfoViewModel.currentPlayURL ?? URL(string: "")!, options: roomInfoViewModel.playerOption)
                    .background(Color.black)
                    .onAppear {
                        playerCoordinator.playerLayer?.play()
                        roomInfoViewModel.setPlayerDelegate(playerCoordinator: playerCoordinator)
                    }
                    .safeAreaPadding(.all)
                    .zIndex(1)

                // 缓冲加载指示器 - 视频播放中但在缓冲时显示
                if playerCoordinator.state == .buffering || playerCoordinator.playerLayer?.player.playbackState == .seeking {
                    ProgressView()
                        .scaleEffect(2.0)
                        .tint(.white)
                        .zIndex(4)
                }

                PlayerControlView(playerCoordinator: playerCoordinator)
                    .zIndex(3)
                    .frame(width: 1920, height: 1080)
//                    .opacity(roomInfoViewModel.showControlView ? 1 : 0)
                    .safeAreaPadding(.all)
                    .environment(roomInfoViewModel)
                    .environment(appViewModel)
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
            .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.playerEndPlay)) { _ in
                endPlay()
            }
//            .onExitCommand(perform: {
//                if roomInfoViewModel.showControlView == true {
//                    return
//                }
//                if roomInfoViewModel.showControlView == false {
//                    endPlay()
//                }
//            })
            
        }
    }
    
    @MainActor func endPlay() {
//        playerCoordinator.playerLayer?.observer.isObserving = false
        playerCoordinator.resetPlayer()
        roomInfoViewModel.disConnectSocket()
        didExitView(false, "")
    }
}


