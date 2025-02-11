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
    
    var appViewModel = SimpleLiveViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(appViewModel: appViewModel)
            .onAppear {
                print(11111)
            }   
        }
    }
}

