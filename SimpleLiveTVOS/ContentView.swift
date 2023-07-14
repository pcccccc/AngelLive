//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher

struct ContentView: View {
    @State var size: CGFloat = 130
    
    
    var body: some View {
        
        TabView {
            HStack {
                LeftMenu(size: $size)
                    .cornerRadius(20)
                VStack(alignment: .leading, content: {
                    
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
                   
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
          
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                            .padding(.bottom, 5)
                                    }
                                }
                                .contextMenu(menuItems: {
                                    Button {
                                        
                                    } label: {
                                        Text("收藏")
                                    }
                                    Button {
                                        
                                    } label: {
                                        Text("取消")
                                    }
                                })
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
                })
            }
            .tabItem {
                Label("收藏", systemImage: "heart.fill")
            }
            ZStack {
                
            }
            .tabItem {
                Label("bilibi", image: "bilibili")
            }
            ZStack {
                
            }
            .tabItem {
                Label("虎牙", image: "huya")
            }
            ZStack {
                
            }
            .tabItem {
                Label("斗鱼", image: "douyu")
            }
            ZStack {
                
            }
            .tabItem {
                Label("企鹅", image: "egame")
            }
            ZStack {
                
            }
            .tabItem {
                Label("抖音", image: "douyin")
            }
        }
        
    }
    
        
    
    func goToPlaylist() {
        
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
