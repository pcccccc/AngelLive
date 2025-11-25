//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import GameController
import Network
import Foundation
import Darwin
import AngelLiveDependencies

struct ContentView: View {
    
    var appViewModel: AppState
    var searchLiveViewModel: LiveViewModel
    var favoriteLiveViewModel: LiveViewModel

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        self.searchLiveViewModel = LiveViewModel(roomListType: .search, liveType: .bilibili, appViewModel: appViewModel)
        self.favoriteLiveViewModel = LiveViewModel(roomListType: .favorite, liveType: .bilibili, appViewModel: appViewModel)
    }
    
    var body: some View {
        
        @Bindable var contentVM = appViewModel
        
        NavigationView {
            TabView(selection:$contentVM.selection) {
                FavoriteMainView()
                    .tabItem {
                        if appViewModel.favoriteViewModel.isLoading == true || appViewModel.favoriteViewModel.cloudKitReady == false {
                            Label(
                                title: {  },
                                icon: {
                                    Image(systemName: appViewModel.favoriteViewModel.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : appViewModel.favoriteViewModel.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                }
                            )
                            .contentTransition(.symbolEffect(.replace))
                        }else {
                            Text("收藏")
                        }
                    }
                    .tag(0)
                    .environment(favoriteLiveViewModel)
                    .environment(appViewModel)
                
                PlatformView()
                    .tabItem {
                        Text("平台")
                    }
                    .tag(1)
                    .environment(appViewModel)

                
                SearchRoomView()
                    .tabItem {
                        Text("搜索")
                    }
                    .tag(2)
                    .environment(searchLiveViewModel)
                    .environment(appViewModel)

                
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                    .tag(3)
                    .environment(appViewModel)

            }
        }
        .onAppear {
//            Task {
//                do {
//                    try await Douyin.getRequestHeaders()
//                } catch {
//                    print("获取抖音请求头失败: \(error)")
//                    // 抖音headers获取失败不应该阻止APP运行
//                }
//            }
        }
        .onPlayPauseCommand(perform: {
            if contentVM.selection == 0 {
                NotificationCenter.default.post(name: SimpleLiveNotificationNames.favoriteRefresh, object: nil)
            }
        })
        
//        .simpleToast(isPresented: $contentVM.showToast, options: appViewModel.toastOptions) {
//            VStack(alignment: .leading) {
//                Label("提示", systemImage: appViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
//                    .font(.headline.bold())
//                Text(appViewModel.toastTitle)
//            }
//            .padding()
//            .background(.black.opacity(0.6))
//            .foregroundColor(Color.white)
//            .cornerRadius(10)
//        }
    }
}

