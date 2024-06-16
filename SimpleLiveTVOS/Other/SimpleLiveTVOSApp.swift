//
//  SimpleLiveTVOSApp.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import LiveParse

@main
struct SimpleLiveTVOSApp: App {
    
    var danmuSettingModel = DanmuSettingModel()
    var favoriteModel = FavoriteModel()
    var favoriteLiveViewModel = LiveViewModel(roomListType: .favorite, liveType: .bilibili)
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(danmuSettingModel)
                .environment(favoriteModel)
                .environment(favoriteLiveViewModel)
        }
    }
}
