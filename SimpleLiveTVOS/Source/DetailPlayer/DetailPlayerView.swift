//
//  DetailPlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/12.
//

import SwiftUI
import KSPlayer
import AVKit


struct DetailPlayerView: View {
    
    @ObservedObject private var playerCoordinator: KSVideoPlayer.Coordinator = KSVideoPlayer.Coordinator()
    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(AppState.self) var appViewModel
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    
    var body: some View {
        if roomInfoViewModel.currentPlayURL == nil {
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
        didExitView(false, "")
    }
}



