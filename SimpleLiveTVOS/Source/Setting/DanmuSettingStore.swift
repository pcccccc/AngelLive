//
//  Setting.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import Foundation
import SwiftUI

class DanmuSettingStore : ObservableObject {
    
    static let globalShowDanmu = "SimpleLive.Setting.showDanmu"
    static let globalShowColorDanmu = "SimpleLive.Setting.showColorDanmu"
    static let globalDanmuTopMargin = "SimpleLive.Setting.danmuTopMargin"
    static let globalDanmuBottomMargin = "SimpleLive.Setting.danmuBottomMargin"
    static let globalDanmuFontSize = "SimpleLive.Setting.danmuFontSize"
    static let globalDanmuSpeed = "SimpleLive.Setting.danmuSpeed"
    static let globalDanmuAlpha = "SimpleLive.Setting.danmuAlpha"
    static let globalDanmuAreaIndex = "SimpleLive.Setting.danmuAreaIndex"
    static let globalDanmuFontSizeIndex = "SimpleLive.Setting.danmuFontSizeIndex"
    static let globalDanmuSpeedIndex = "SimpleLive.Setting.danmuSpeedIndex"

    @AppStorage(globalShowDanmu) public var showDanmu: Bool = true
    @AppStorage(globalShowColorDanmu) public var showColorDanmu: Bool = true
    @AppStorage(globalDanmuTopMargin) public var danmuTopMargin: Double = 0.0
    @AppStorage(globalDanmuBottomMargin) public var danmuBottomMargin: Double = 0.0
    @AppStorage(globalDanmuFontSize) public var danmuFontSize: Int = 50
    @AppStorage(globalDanmuSpeed) public var danmuSpeed: Double = 0.5
    @AppStorage(globalDanmuAlpha) var danmuAlpha: Double = 1.0
    @AppStorage(globalDanmuAreaIndex) var danmuAreaIndex: Int = 2
    @AppStorage(globalDanmuFontSizeIndex) var danmuFontSizeIndex: Int = 1
    @AppStorage(globalDanmuSpeedIndex) var danmuSpeedIndex: Int = 1 
    
    @Published var danmuAreaArray: [String] = ["顶部1/4", "顶部1/2", "全屏", "底部1/2", "底部1/4"]
    @Published var danmuSpeedArray: [String] = ["慢速", "正常", "快速"]
    @Published var danmuFontSizeArray: [String] = ["30", "40", "50", "60", "65"]
    @Published var danmuAlphaString = ""
    
    func getDanmuArea() -> (CGFloat, CGFloat) {
        switch danmuAreaIndex {
            case 0:
                return (1080 * 0.25, (1080 * 0.25))
            case 1:
                return (1080 * 0.5, 0)
            case 2:
                return (1080, 0)
            case 3:
                return (1080 * 0.5, 1080 / 2)
            case 4:
                return (1080 * 0.25, 1080 / 4)
            default:
                return (1080, 0)
        }
    }
    
    func getDanmuSize() {
        switch danmuFontSizeIndex {
            case 0:
                danmuFontSize = 30
            case 1:
                danmuFontSize = 40
            case 2:
                danmuFontSize = 50
            case 3:
                danmuFontSize = 60
            case 4:
                danmuFontSize = 65
            default:
                danmuFontSize = 50
        }
    }
}

