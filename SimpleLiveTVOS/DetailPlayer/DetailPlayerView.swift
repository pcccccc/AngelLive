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
    
    @EnvironmentObject var liveListViewModel: LiveListViewModel
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
//        KSVideoPlayerView(url: URL(string: "https://d1--cn-gotcha204-2.bilivideo.com/live-bvc/739431/live_8739477_3713195_minihevc/index.m3u8?expires=1702984547&len=0&oi=1026837085&pt=h5&qn=0&trid=1007319318cda1c6445caf27e9d421159031&sigparams=cdn,expires,len,oi,pt,qn,trid&cdn=cn-gotcha204&sign=581a3ffd79d6494032a15a73ca82fd86&sk=5f3c668d092618412836c79cbb6dac4f&p2p_type=4294967295&sl=9&free_type=0&mid=0&pp=rtmp&source=onetier&trace=20&site=5b5e7756e553a05fbc86a23d8af4fcb3&order=1")!, options: KSOptions())
//            .background(Color.black)
//            .onAppear {
//                
//            }
        VideoPlayer(player: player)
            .onAppear {
                player.play()
            }
    }
}


#Preview {
    DetailPlayerView()
}

