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
    
    var roomInfoViewModel: RoomInfoStore
    @EnvironmentObject var favoriteModel: FavoriteModel
    
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    
    
    var body: some View {
        if roomInfoViewModel.currentPlayURL == nil {
            VStack {
                ProgressView()
            }
            .frame(width: 1920, height: 1080)
            .background(.ultraThickMaterial)
        }else {
            ZStack {
                KSVideoPlayer(coordinator: roomInfoViewModel.playerCoordinator, url:roomInfoViewModel.currentPlayURL ?? URL(string: "")!, options: roomInfoViewModel.option)
                    .background(Color.black)
                    .onAppear {
                        roomInfoViewModel.playerCoordinator.playerLayer?.play()
                        roomInfoViewModel.setPlayerDelegate()
                        if roomInfoViewModel.danmuSettingModel.showDanmu {
                            roomInfoViewModel.getDanmuInfo()
                        }
                    }
                    .onDisappear {
                        roomInfoViewModel.disConnectSocket()
                    }
                    .onSwipeGesture { direction in
                        switch direction {
                            default:
                                if roomInfoViewModel.showControlView == false {
                                    roomInfoViewModel.showControlView = true
                                }
                        }
                    }
                    .safeAreaPadding(.all)
                    .zIndex(1)
                PlayerControlView(roomInfoViewModel: roomInfoViewModel, danmuSettingModel: DanmuSettingModel())
                    .zIndex(3)
                    .frame(width: 1920, height: 1080)
                    .opacity(roomInfoViewModel.showControlView ? 1 : 0)
                    .safeAreaPadding(.all)
                VStack {
                    if roomInfoViewModel.danmuSettingModel.danmuAreaIndex >= 3 {
                        Spacer()
                    }
                    DanmuView(coordinator: roomInfoViewModel.danmuCoordinator, height: roomInfoViewModel.danmuSettingModel.getDanmuArea().0)
                        .frame(width: 1920, height: roomInfoViewModel.danmuSettingModel.getDanmuArea().0)
                        .opacity(roomInfoViewModel.danmuSettingModel.showDanmu ? 1 : 0)
                        .environmentObject(favoriteModel)
                    if roomInfoViewModel.danmuSettingModel.danmuAreaIndex < 3 {
                        Spacer()
                    }
                }
                .zIndex(2)
            }
            .onExitCommand(perform: {
                if roomInfoViewModel.showControlView == true {
                    roomInfoViewModel.showControlView = false
                }else {
                    roomInfoViewModel.playerCoordinator.playerLayer?.resetPlayer()
                    didExitView(false, "")
                }
            })
            .onPlayPauseCommand(perform: {
                if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying == true {
                    roomInfoViewModel.playerCoordinator.playerLayer?.pause()
                }else {
                    roomInfoViewModel.playerCoordinator.playerLayer?.play()
                }
            })
        }
    }
}



