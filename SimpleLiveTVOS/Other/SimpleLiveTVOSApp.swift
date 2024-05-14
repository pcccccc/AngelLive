//
//  SimpleLiveTVOSApp.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI

@main
struct SimpleLiveTVOSApp: App {
    
    var danmuSettingModel = DanmuSettingModel()
    var favoriteModel = FavoriteModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(danmuSettingModel)
                .environment(favoriteModel)
        }
    }
}
