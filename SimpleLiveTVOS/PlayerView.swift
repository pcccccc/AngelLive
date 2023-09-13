//
//  PlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/7/16.
//

import SwiftUI
import AVKit

struct PlayerView: View {
    
    @State private var willBeginFullScreenPresentation: Bool = false
    @State private var player = AVPlayer()
    @State private var url = ""
    var roomModel: BiliBiliCategoryListModel
    
    var body: some View {
        
        VStack {
            VideoPlayer(player: $player)
                .onAppear() {
                    Task {
                        let quality = try await Bilibili.getVideoQualites(roomModel:roomModel)
                        if quality.code == 0 {
                            if let qualityDescription = quality.data.quality_description {
                                var maxQn = 0
                                for item in qualityDescription {
                                    if item.qn > maxQn {
                                        maxQn = item.qn
                                    }
                                }
                                let playInfo = try await Bilibili.getPlayUrl(roomModel: roomModel, qn: maxQn)
                                for streamInfo in playInfo.data.playurl_info.playurl.stream {
                                    if streamInfo.protocol_name == "http_hls" {
                                        url = (streamInfo.format.last?.codec.last?.url_info.last?.host ?? "") + (streamInfo.format.last?.codec.last?.base_url ?? "") + (streamInfo.format.last?.codec.last?.url_info.last?.extra ?? "")
                                        let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: url)!))
                                        player = AVPlayer(playerItem: item)
                                        player.play()
                                        break
                                    }
                                }
                                print(url)
                                
                                
                                
                            }
                        }
                    }
                }
        }
        
    }
}

//struct PlayerView_Previews: PreviewProvider {
//    static var previews: some View {
//        PlayerView()
//    }
//}
