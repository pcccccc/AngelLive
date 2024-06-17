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
    
    var appViewModel = SimpleLiveViewModel()
    
    @State var broadcastConnection: UDPBroadcastConnection?
    
    var body: some View {
        
        @Bindable var contentVM = appViewModel
        
        NavigationView {
            TabView(selection:$contentVM.selection) {
                FavoriteMainView()
                    .tabItem {
                        if appViewModel.favoriteModel.isLoading == true || appViewModel.favoriteModel.cloudKitReady == false {
                            Label(
                                title: {  },
                                icon: {
                                    Image(systemName: appViewModel.favoriteModel.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : appViewModel.favoriteModel.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                }
                            )
                            .contentTransition(.symbolEffect(.replace))
                        }else {
                            Text("收藏")
                        }
                    }
                    .environment(appViewModel.favoriteModel)
                    .environment(appViewModel.danmuSettingModel)
                    .environment(appViewModel.favoriteLiveViewModel)
                    .tag(0)

//                PlatformView()
//                    .tabItem {
//                        Text("平台")
//                    }
//                    .tag(1)
//
//                SearchRoomView()
//                    .tabItem {
//                        Text("搜索")
//                    }
//                    .tag(2)
//
//                SettingView()
//                    .tabItem {
//                        Text("设置")
//                    }
//                .tag(3)

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


