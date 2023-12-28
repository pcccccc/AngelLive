//
//  Setting.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import Foundation
import SwiftUI

class SettingStore : ObservableObject {
    
    init(){}
    
    static let globalShowDanmu = "SimpleLive.Setting.showDanmu"
    static let globalShowColorDanmu = "SimpleLive.Setting.showColorDanmu"
    static let globalDanmuTopMargin = "SimpleLive.Setting.danmuTopMargin"
    static let globalDanmuBottomMargin = "SimpleLive.Setting.danmuBottomMargin"
    static let globalDanmuFontSize = "SimpleLive.Setting.danmuFontSize"
    static let globalDanmuSpeed = "SimpleLive.Setting.danmuSpeed"
    static let globalDanmuAlpha = "SimpleLive.Setting.danmuAlpha"
    static let shared = SettingStore()
    
    @AppStorage(globalShowDanmu) public var showDanmu: Bool = true
    @AppStorage(globalShowColorDanmu) public var showColorDanmu: Bool = true
    @AppStorage(globalDanmuTopMargin) public var danmuTopMargin: Double = 0.0
    @AppStorage(globalDanmuBottomMargin) public var danmuBottomMargin: Double = 0.0
    @AppStorage(globalDanmuFontSize) public var danmuFontSize: Int = 50
    @AppStorage(globalDanmuSpeed) public var danmuSpeed: Double = 0.5
    @AppStorage(globalDanmuAlpha) var danmuAlpha: Double = 1.0
}

