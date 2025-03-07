//
//  IJKPlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2025/3/7.
//

import SwiftUI
import IJKMediaPlayerKit

struct IJKPlayerViewRepresentable: UIViewRepresentable {

    var url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let options = IJKFFOptions.byDefault()
        
        var isVideoToolBox = true
        if isVideoToolBox {
            options.setPlayerOptionIntValue(3840, forKey: "videotoolbox-max-frame-width")
            options.setPlayerOptionIntValue(1, forKey: "videotoolbox")
        } else {
            options.setPlayerOptionValue("fcc-i420", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-j420", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-yv12", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-nv12", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-bgra", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-bgr0", forKey: "overlay-format")
            options.setPlayerOptionValue("fcc-_es2", forKey: "overlay-format")
        }
        
        // Enable hardware acceleration
//        options.setPlayerOptionIntValue(1, forKey: "videotoolbox_hwaccel")
        print(url)
        let player = IJKFFMoviePlayerController(contentURL: url, with: options)
        player.view.frame = view.bounds
        player.scalingMode = .aspectFit
        view.addSubview(player.view)
        player.prepareToPlay()
        player.play()
        return view
    
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view if needed
    }
}

#Preview {
    IJKPlayerViewRepresentable(url: URL(string: "https://file-examples.com/storage/fe6a71582967c9a269c25cd/2017/04/file_example_MP4_1920_18MG.mp4")!)
}
