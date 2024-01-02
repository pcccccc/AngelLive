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
    
    var body: some View {
        NavigationView {
            TabView(selection:$selection) {
                FavoriteMainView()
                    .tabItem {
                        Text("收藏")
                    }
                    .tag(0)
                ListMainView(liveType: .bilibili)
                    .tabItem {
                        Text("B站")
                    }
                    .tag(1)
                ListMainView(liveType: .huya)
                    .tabItem {
                        Text("虎牙")
                    }
                    .tag(2)
                ListMainView(liveType: .douyu)
                    .tabItem {
                        Text("斗鱼")
                    }
                    .tag(3)
                ListMainView(liveType: .douyin)
                    .tabItem {
                        Text("抖音")
                    }
                    .tag(4)
                SearchRoomView()
                    .tabItem {
                        Text("搜索")
                    }
                    .tag(5)
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                    .tag(6)
                
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
