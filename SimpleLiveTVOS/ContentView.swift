//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher


struct ContentView: View {
    
    var body: some View {
        NavigationView {
            TabView {
                ZStack {
                    
                }
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
                BiliBiliMainView()
                .tabItem {
                    Label("bilibi", image: "bilibili")
                }
                HuyaMainView()
                .tabItem {
                    Label("虎牙", image: "huya")
                }
                DouyuMainView()
                .tabItem {
                    Label("斗鱼", image: "douyu")
                }
                DouyinMainView()
                .tabItem {
                    Label("抖音", image: "douyin")
                }
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
