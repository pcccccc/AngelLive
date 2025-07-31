//
//  SimpleLiveTVOSApp.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import LiveParse
import Bugsnag

@main
struct SimpleLiveTVOSApp: App {
    
    var appViewModel = SimpleLiveViewModel()
    
    init() {
        Bugsnag.start()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(appViewModel: appViewModel)
        }
    }
}

