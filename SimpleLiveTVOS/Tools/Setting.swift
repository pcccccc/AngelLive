//
//  Setting.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import Foundation


class SettingStore : ObservableObject {
    
    private init(){}
    
    static let globalShowDanmu = "SimpleLive.Setting.showDanmu"
    static let globalShowColorDanmu = "SimpleLive.Setting.showColorDanmu"
    static let globalDanmuTopMargin = "SimpleLive.Setting.danmuTopMargin"
    static let globalDanmuBottomMargin = "SimpleLive.Setting.danmuBottomMargin"
    static let globalDanmuFontSize = "SimpleLive.Setting.danmuFontSize"
    static let globalDanmuSpeed = "SimpleLive.Setting.danmuSpeed"
    static let globalDanmuAlpha = "SimpleLive.Setting.danmuAlpha"
    static let shared = SettingStore()
    
    public var showDanmu: Bool {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalShowDanmu)
        }
        get {
            print(UserDefaults.standard.value(forKey: SettingStore.globalShowDanmu))
            return UserDefaults.standard.value(forKey: SettingStore.globalShowDanmu) as? Bool ?? true
        }
    }
    
    var showColorDanmu: Bool {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalShowColorDanmu)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalShowColorDanmu) as? Bool ?? true
        }
    }
    
    var danmuTopMargin: Float {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalDanmuTopMargin)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalDanmuTopMargin) as? Float ?? 0
        }
    }
    
    var danmuBottomMargin: Float {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalDanmuBottomMargin)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalDanmuBottomMargin) as? Float ?? 0
        }
    }
    
    var danmuFontSize: Int {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalDanmuFontSize)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalDanmuFontSize) as? Int ?? 50
        }
    }
    
    var danmuSpeed: Float {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalDanmuSpeed)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalDanmuSpeed) as? Float ?? 0.5
        }
    }
    
    var danmuAlpha: Float {
        set {
            UserDefaults.standard.setValue(newValue, forKey: SettingStore.globalDanmuAlpha)
        }
        get {
            return UserDefaults.standard.value(forKey: SettingStore.globalDanmuAlpha) as? Float ?? 1.0
        }
    }
}

