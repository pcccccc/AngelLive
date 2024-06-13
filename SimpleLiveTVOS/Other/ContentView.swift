//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher
import GameController
import LiveParse
import Network
import UDPBroadcast
import Foundation
import Darwin

struct ContentView: View {
    
    @Environment(DanmuSettingModel.self) var danmuSettingModel
    @Environment(FavoriteModel.self) var favoriteModel
    @State private var selection = 0
    
    @State var broadcastConnection: UDPBroadcastConnection?
    
    var body: some View {
        NavigationView {
            TabView(selection:$selection) {
                
                FavoriteMainView()
                    .tabItem {
                        if favoriteModel.isLoading == true || favoriteModel.cloudKitReady == false {
                            Label(
                                title: {  },
                                icon: {
                                    Image(systemName: favoriteModel.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : favoriteModel.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                }
                            )
                            .contentTransition(.symbolEffect(.replace))
                        }else {
                            Text("收藏")
                        }
                    }
                .tag(0)
                .environment(favoriteModel)
                .environment(danmuSettingModel)
                PlatformView()
                    .tabItem {
                        Text("全部")
                    }
                    .environment(favoriteModel)
                    .environment(danmuSettingModel)
//                ListMainView(liveType: .bilibili)
//                    .tabItem {
//                        Text("B站")
//                    }
//                .tag(1)
//                .environment(favoriteModel)
//                .environment(danmuSettingModel)
//                ListMainView(liveType: .huya)
//                    .tabItem {
//                        Text("虎牙")
//                    }
//                .tag(2)
//                .environment(favoriteModel)
//                .environment(danmuSettingModel)
//                ListMainView(liveType: .douyu)
//                    .tabItem {
//                        Text("斗鱼")
//                    }
//                .tag(3)
//                .environment(favoriteModel)
//                .environment(danmuSettingModel)
//                ListMainView(liveType: .douyin)
//                    .tabItem {
//                        Text("抖音")
//                    }
//                .tag(4)
//                .environment(favoriteModel)
//                .environment(danmuSettingModel)
                SearchRoomView()
                    .tabItem {
                        Text("搜索")
                    }
                .tag(5)
                .environment(favoriteModel)
                .environment(danmuSettingModel)
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                .tag(6)
                .environment(favoriteModel)
                .environment(danmuSettingModel)
            }
        }
        .onAppear {
            do {
                
            }
            Task {
                try await Douyin.getRequestHeaders()
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


