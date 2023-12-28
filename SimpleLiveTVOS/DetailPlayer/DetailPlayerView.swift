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
    
    @EnvironmentObject var liveViewModel: LiveStore
    @State var url = ""
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    var option = KSOptions()
    private var player: AVPlayer {
           // 替换成您的视频 URL
           AVPlayer(url: URL(string: url)!)
    }
    
    var body: some View {
        KSVideoPlayer(coordinator: liveViewModel.playerCoordinator, url:liveViewModel.currentPlayURL ?? URL(string: "")!, options: option)
            .background(Color.black)
            .onAppear {
                
            }
            .overlay {
                PlayerControlView()
                    .environmentObject(liveViewModel)
            }
    }
}



