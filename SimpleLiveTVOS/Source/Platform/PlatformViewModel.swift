//
//  PlatformViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import LiveParse

@Observable
class PlatformViewModel: ObservableObject {
    var platformInfo = [Platformdescription]()
    
    func getPlatformInfo() {
//        platformInfo.removeAll()
        if platformInfo.count != LiveParseTools.getAllSupportPlatform().count {
            for index in LiveParseTools.getAllSupportPlatform().indices {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(0.05 * Double(index))) {
                    let item = LiveParseTools.getAllSupportPlatform()[index]
                    if self.platformInfo.contains(where: { $0.title == item.livePlatformName }) == false {
                        self.platformInfo.append(.init(title: item.livePlatformName, bigPic: "\(item.livePlatformName)-big", smallPic: "\(item.livePlatformName)-small", descripiton: "", liveType: item.liveType))
                    }
                }
            }
        }
    }
}


struct Platformdescription {
    let title: String
    let bigPic: String
    let smallPic: String
    let descripiton: String
    let liveType: LiveType
}
