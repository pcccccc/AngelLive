//
//  PlayView2.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/7/16.
//

import SwiftUI
import AVKit

struct PlayView2: View {
    
    @State var player = AVPlayer(url: URL(string: "http://video.chinanews.com/flv/2019/04/23/400/111773_web.mp4")!)
    @State var isplaying = false
    @State var showcontrols = false
    @State var value : Float = 0
    
    var body: some View {
        
        VStack{
            
            ZStack{
                
                VideoPlayer(player: $player)

            }
            .frame(height: UIScreen.main.bounds.height / 3.5)
//            .onTapGesture {
//
//                self.showcontrols = true
//            }
            
            GeometryReader{_ in
                
                VStack{
                    
                    Text("Custom Video Player").foregroundColor(.white)
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            
            self.player.play()
            self.isplaying = true
        }
    }
}


struct Controls : View {
    
    @Binding var player : AVPlayer
    @Binding var isplaying : Bool
    @Binding var pannel : Bool
    @Binding var value : Float
    
    var body : some View{
        
        VStack{
            
            Spacer()
            
            HStack{
                
                Button(action: {
                    
                    self.player.seek(to: CMTime(seconds: self.getSeconds() - 10, preferredTimescale: 1))
                    
                }) {
                    
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(20)
                }
                
                Spacer()
                
                Button(action: {
                    
                    if self.isplaying{
                        
                        self.player.pause()
                        self.isplaying = false
                    }
                    else{
                        
                        self.player.play()
                        self.isplaying = true
                    }
                    
                }) {
                    
                    Image(systemName: self.isplaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(20)
                }
                
                Spacer()
                
                Button(action: {
                    
                    self.player.seek(to: CMTime(seconds: self.getSeconds() + 10, preferredTimescale: 1))
                    
                }) {
                    
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(20)
                }
            }
            
            Spacer()
            
            
        }.padding()
        .background(Color.black.opacity(0.4))
//        .onTapGesture {
//
//            self.pannel = false
//        }
        .onAppear {
            
            self.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { (_) in
                
                self.value = self.getSliderValue()
                
                if self.value == 1.0{
                    
                    self.isplaying = false
                }
            }
        }
        
        
    }
    
    func getSliderValue()->Float{
        
        return Float(self.player.currentTime().seconds / (self.player.currentItem?.duration.seconds)!)
    }
    
    func getSeconds()->Double{
        
        return Double(Double(self.value) * (self.player.currentItem?.duration.seconds)!)
    }
}


struct VideoPlayer : UIViewControllerRepresentable {
    
    @Binding var player : AVPlayer
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<VideoPlayer>) -> AVPlayerViewController {
        
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resize
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: UIViewControllerRepresentableContext<VideoPlayer>) {
        
        uiViewController.player = player
    }
}

