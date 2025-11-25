//
//  PlatformViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import SwiftUI
import AngelLiveDependencies

@Observable
class PlatformViewModel {
    var platformInfo: [Platformdescription] = {
        var temp = [Platformdescription]()
        for index in LiveParseTools.getAllSupportPlatform().indices {
            let item = LiveParseTools.getAllSupportPlatform()[index]
            temp.append(.init(title: item.livePlatformName, bigPic: "\(item.livePlatformName)-big", smallPic: "\(item.livePlatformName)-small", descripiton: item.description, liveType: item.liveType))
        }
        return temp
    }()
}


struct Platformdescription {
    let title: String
    let bigPic: String
    let smallPic: String
    let descripiton: String
    let liveType: LiveType
}
