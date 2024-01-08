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
    
    @EnvironmentObject var roomInfoViewModel: RoomInfoStore
    
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    var option = KSOptions()
    
    var body: some View {
        if roomInfoViewModel.currentPlayURL == nil {
            ProgressView()
        }else {
            KSVideoPlayer(coordinator: roomInfoViewModel.playerCoordinator, url:roomInfoViewModel.currentPlayURL ?? URL(string: "")!, options: option)
                .background(Color.black)
                .onAppear {
                    roomInfoViewModel.playerCoordinator.playerLayer?.play()
                    roomInfoViewModel.getDanmuInfo()
                }
                .overlay {
                    ZStack {
                        PlayerControlView()
                            .environmentObject(roomInfoViewModel)
                            .zIndex(2)
                        VStack {
                            if roomInfoViewModel.danmuSettingModel.danmuAreaIndex >= 3 {
                                Spacer()
                            }
                            DanmuView(coordinator: roomInfoViewModel.danmuCoordinator, height: roomInfoViewModel.danmuSettingModel.getDanmuArea().0)
                                .zIndex(1)
                                .frame(width: 1920, height: roomInfoViewModel.danmuSettingModel.getDanmuArea().0)
                                .opacity(roomInfoViewModel.danmuSettingModel.showDanmu ? 1 : 0)
                                .background(Color.red)
                            if roomInfoViewModel.danmuSettingModel.danmuAreaIndex < 3 {
                                Spacer()
                            }
                        }
                    }
            }
                .onDisappear {
                    roomInfoViewModel.disConnectSocket()
                }
        }
    }
}



