//
//  PlayerSettingModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/9/21.
//

import Foundation
import SwiftUI
import Observation

@Observable
final class PlayerSettingModel {
    
    static let globalOpenExitPlayerViewWhenLiveEnd = "SimpleLive.Setting.OpenExitPlayerViewWhenLiveEnd"
    static let globalOpenExitPlayerViewWhenLiveEndSecond = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecond"
    static let globalOpenExitPlayerViewWhenLiveEndSecondIndex = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecondIndex"
    
    @ObservationIgnored
    public var openExitPlayerViewWhenLiveEnd: Bool {
        get {
            access(keyPath: \.openExitPlayerViewWhenLiveEnd)
            return UserDefaults.standard.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEnd) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEnd) {
                 UserDefaults.standard.setValue(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEnd)
            }
        }
    }
    
    public var openExitPlayerViewWhenLiveEndSecond: Int {
        get {
            access(keyPath: \.openExitPlayerViewWhenLiveEndSecond)
            return UserDefaults.standard.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecond) as? Int ?? 180
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEndSecond) {
                UserDefaults.standard.setValue(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecond)
            }
        }
    }
    
    var openExitPlayerViewWhenLiveEndSecondIndex: Int {
        get {
            access(keyPath: \.openExitPlayerViewWhenLiveEndSecondIndex)
            return UserDefaults.standard.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecondIndex) as? Int ?? 2
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEndSecondIndex) {
                UserDefaults.standard.setValue(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecondIndex)
            }
        }
    }
    
    var timeArray: [String] = ["1分钟", "2分钟", "3分钟", "5分钟", "10分钟"]
    func getTimeSecond(index: Int) {
        openExitPlayerViewWhenLiveEndSecondIndex = index
        switch index {
            case 0:
                openExitPlayerViewWhenLiveEndSecond = 60
            case 1:
                openExitPlayerViewWhenLiveEndSecond = 120
            case 2:
                openExitPlayerViewWhenLiveEndSecond = 180
            case 3:
                openExitPlayerViewWhenLiveEndSecond = 300
            case 4:
                openExitPlayerViewWhenLiveEndSecond = 600
            default:
            openExitPlayerViewWhenLiveEndSecond = 180
        }
    }
}
