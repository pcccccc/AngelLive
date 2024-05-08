//
//  Setting.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import Foundation
import SwiftUI
import Observation


@Observable
final class DanmuSettingModel {
    
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

    @ObservationIgnored
    public var showDanmu: Bool {
        get {
            access(keyPath: \.showDanmu)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalShowDanmu) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showDanmu) {
                 UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalShowDanmu)
            }
        }
    }
    
    public var showColorDanmu: Bool {
        get {
            access(keyPath: \.showColorDanmu)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalShowColorDanmu) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showColorDanmu) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalShowColorDanmu)
            }
        }
    }
    
    public var danmuTopMargin: Double {
        get {
            access(keyPath: \.danmuTopMargin)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuTopMargin) as? Double ?? 0.0
        }
        set {
            withMutation(keyPath: \.danmuTopMargin) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuTopMargin)
            }
        }
    }
    
    public var danmuBottomMargin: Double {
        get {
            access(keyPath: \.danmuBottomMargin)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuBottomMargin) as? Double ?? 0.0
        }
        set {
            withMutation(keyPath: \.danmuBottomMargin) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuBottomMargin)
            }
        }
    }
    
    public var danmuFontSize: Int {
        get {
            access(keyPath: \.danmuFontSize)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuFontSize) as? Int ?? 50
        }
        set {
            withMutation(keyPath: \.danmuFontSize) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuFontSize)
            }
        }
    }
    
    public var danmuSpeed: Double {
        get {
            access(keyPath: \.danmuSpeed)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuSpeed) as? Double ?? 0.5
        }
        set {
            withMutation(keyPath: \.danmuSpeed) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuSpeed)
            }
        }
    }
    
    var danmuAlpha: Double {
        get {
            access(keyPath: \.danmuAlpha)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuAlpha) as? Double ?? 1.0
        }
        set {
            withMutation(keyPath: \.danmuAlpha) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuAlpha)
            }
        }
    }
    
    var danmuAreaIndex: Int {
        get {
            access(keyPath: \.danmuAreaIndex)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuAreaIndex) as? Int ?? 2
        }
        set {
            withMutation(keyPath: \.danmuAreaIndex) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuAreaIndex)
            }
        }
    }
    
    var danmuFontSizeIndex: Int {
        get {
            access(keyPath: \.danmuFontSizeIndex)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuFontSizeIndex) as? Int ?? 1
        }
        set {
            withMutation(keyPath: \.danmuFontSizeIndex) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuFontSizeIndex)
            }
        }
    }
    
    var danmuSpeedIndex: Int {
        get {
            access(keyPath: \.danmuSpeedIndex)
            return UserDefaults.standard.value(forKey: DanmuSettingModel.globalDanmuSpeedIndex) as? Int ?? 1
        }
        set {
            withMutation(keyPath: \.danmuSpeedIndex) {
                UserDefaults.standard.setValue(newValue, forKey: DanmuSettingModel.globalDanmuSpeedIndex)
            }
        }
    }
    
    var danmuAreaArray: [String] = ["顶部1/4", "顶部1/2", "全屏", "底部1/2", "底部1/4"]
    var danmuSpeedArray: [String] = ["慢速", "正常", "快速"]
    var danmuFontSizeArray: [String] = ["30", "40", "50", "60", "65"]
    var danmuAlphaString = ""
    
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

