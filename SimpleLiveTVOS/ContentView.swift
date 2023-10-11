//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher


struct ContentView: View {
    
    @State private var selection = 1
    
    var body: some View {
        NavigationView {
            TabView(selection:$selection) {
                FavoriteMainView()
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
                .tag(0)
                ListMainView(liveType: .bilibili)
                .tabItem {
                    Label("bilibi", image: "bilibili")
                }
                .tag(1)
                ListMainView(liveType: .huya)
                .tabItem {
                    Label("虎牙", image: "huya")
                }
                .tag(2)
                ListMainView(liveType: .douyu)
                .tabItem {
                    Label("斗鱼", image: "douyu")
                }
                .tag(3)
                ListMainView(liveType: .douyin)
                .tabItem {
                    Label("抖音", image: "douyin")
                }
                .tag(4)
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
