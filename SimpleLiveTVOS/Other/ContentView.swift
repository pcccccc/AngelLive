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


struct ContentView: View {
    
    @State private var selection = 1
    @StateObject var favoriteStore = FavoriteStore()
    
    var body: some View {
        NavigationView {
            TabView(selection:$selection) {
                FavoriteMainView()
                    .tabItem {
                        if favoriteStore.isLoading == true || favoriteStore.cloudKitReady == false {
                            Label(
                                title: {  },
                                icon: {
                                    Image(systemName: favoriteStore.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : favoriteStore.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                                          
                                }
                            )
                            .contentTransition(.symbolEffect(.replace))
                        }else {
                            Text("收藏")
                        }
                    }
                .tag(0)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .bilibili)
                    .tabItem {
                        Text("B站")
                    }
                .tag(1)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .huya)
                    .tabItem {
                        Text("虎牙")
                    }
                .tag(2)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .douyu)
                    .tabItem {
                        Text("斗鱼")
                    }
                .tag(3)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .douyin)
                    .tabItem {
                        Text("抖音")
                    }
                .tag(4)
                .environmentObject(favoriteStore)
                SearchRoomView()
                    .tabItem {
                        Text("搜索")
                    }
                .tag(5)
                .environmentObject(favoriteStore)
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                .tag(6)
                .environmentObject(favoriteStore)
            }
        }
        .onAppear {
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
