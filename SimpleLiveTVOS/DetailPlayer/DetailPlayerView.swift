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
                }
                .overlay {
                    PlayerControlView()
                        .environmentObject(roomInfoViewModel)
                }
        }
    }
}



