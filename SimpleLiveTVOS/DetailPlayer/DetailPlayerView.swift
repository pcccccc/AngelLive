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
    
    @EnvironmentObject var liveListViewModel: LiveListStore
    @State var url = ""
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    var option = KSOptions()
    private var player: AVPlayer {
           // 替换成您的视频 URL
           AVPlayer(url: URL(string: url)!)
    }
    
    var body: some View {
//        KSVideoPlayer(coordinator: playerCoordinator, url:liveListViewModel.currentPlayURL ?? URL(string: "")!, options: option)
//            .background(Color.black)
//            .onAppear {
//                
//            }
//            .onExitCommand(perform: {
//                self.didExitView(false, "")
//            }
//        )
        KSVideoPlayerView(url: URL(string: url)!, options: KSOptions())
            .background(Color.black)
            .onAppear {
                
            }
//        VideoPlayer(player: player)
//            .onAppear {
//                player.play()
//            }
    }
}


#Preview {
    DetailPlayerView()
}

