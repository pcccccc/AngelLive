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
            return UserDefaults.shared.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEnd, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEnd) {
                 UserDefaults.shared.set(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEnd, synchronize: true)
            }
        }
    }
    
    public var openExitPlayerViewWhenLiveEndSecond: Int {
        get {
            access(keyPath: \.openExitPlayerViewWhenLiveEndSecond)
            return UserDefaults.shared.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecond, synchronize: true) as? Int ?? 180
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEndSecond) {
                UserDefaults.shared.set(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecond, synchronize: true)
            }
        }
    }
    
    var openExitPlayerViewWhenLiveEndSecondIndex: Int {
        get {
            access(keyPath: \.openExitPlayerViewWhenLiveEndSecondIndex)
            return UserDefaults.shared.value(forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecondIndex, synchronize: true) as? Int ?? 2
        }
        set {
            withMutation(keyPath: \.openExitPlayerViewWhenLiveEndSecondIndex) {
                UserDefaults.shared.set(newValue, forKey: PlayerSettingModel.globalOpenExitPlayerViewWhenLiveEndSecondIndex, synchronize: true)
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
