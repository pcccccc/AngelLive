//
//  AngelLiveApp.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

@main
struct AngelLiveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    GeneralSettingModel().globalGeneralSettingFavoriteStyle = AngelLiveFavoriteStyle.liveState.rawValue
                }
        }
    }
}
