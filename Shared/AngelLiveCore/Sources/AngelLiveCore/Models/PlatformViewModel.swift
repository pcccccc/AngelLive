//
//  PlatformViewModel.swift
//  AngelLiveCore
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import SwiftUI
import LiveParse

@Observable
public final class PlatformViewModel {
    public var platformInfo: [Platformdescription] = {
        var temp = [Platformdescription]()
        for index in LiveParseTools.getAllSupportPlatform().indices {
            let item = LiveParseTools.getAllSupportPlatform()[index]
            temp.append(.init(title: item.livePlatformName, bigPic: "\(item.livePlatformName)-big", smallPic: "\(item.livePlatformName)-small", descripiton: item.description, liveType: item.liveType))
        }
        return temp
    }()

    public init() {}
}


public struct Platformdescription: Hashable {
    public let title: String
    public let bigPic: String
    public let smallPic: String
    public let descripiton: String
    public let liveType: LiveType

    public init(title: String, bigPic: String, smallPic: String, descripiton: String, liveType: LiveType) {
        self.title = title
        self.bigPic = bigPic
        self.smallPic = smallPic
        self.descripiton = descripiton
        self.liveType = liveType
    }
}
