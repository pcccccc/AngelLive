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

    @AppStorage(globalShowDanmu) public var showDanmu: Bool = true
    @AppStorage(globalShowColorDanmu) public var showColorDanmu: Bool = true
    @AppStorage(globalDanmuTopMargin) public var danmuTopMargin: Double = 0.0
    @AppStorage(globalDanmuBottomMargin) public var danmuBottomMargin: Double = 0.0
    @AppStorage(globalDanmuFontSize) public var danmuFontSize: Int = 50
    @AppStorage(globalDanmuSpeed) public var danmuSpeed: Double = 0.5
    @AppStorage(globalDanmuAlpha) var danmuAlpha: Double = 1.0
    @AppStorage(globalDanmuAreaIndex) var danmuAreaIndex: Int = 2
    
    @Published var danmuArea: [String] = ["顶部1/4", "顶部1/2", "全屏", "底部1/2", "底部1/4"]
    
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
}

