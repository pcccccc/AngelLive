//
//  PlayerSettingModel.swift
//  AngelLiveCore
//
//  Created by Claude on 11/1/25.
//

import Foundation
import SwiftUI
import Observation

@Observable
public final class PlayerSettingModel {

    public static let globalOpenExitPlayerViewWhenLiveEnd = "SimpleLive.Setting.OpenExitPlayerViewWhenLiveEnd"
    public static let globalOpenExitPlayerViewWhenLiveEndSecond = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecond"
    public static let globalOpenExitPlayerViewWhenLiveEndSecondIndex = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecondIndex"
    public static let globalEnableBackgroundAudio = "SimpleLive.Setting.EnableBackgroundAudio"
    public static let globalEnableAutoPiPOnBackground = "SimpleLive.Setting.EnableAutoPiPOnBackground"

    public init() {}

    nonisolated public static let timeArray: [String] = ["1分钟", "2分钟", "3分钟", "5分钟", "10分钟"]

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

    public var openExitPlayerViewWhenLiveEndSecondIndex: Int {
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

    @ObservationIgnored
    public var enableBackgroundAudio: Bool {
        get {
            access(keyPath: \.enableBackgroundAudio)
            return UserDefaults.shared.value(forKey: PlayerSettingModel.globalEnableBackgroundAudio, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.enableBackgroundAudio) {
                UserDefaults.shared.set(newValue, forKey: PlayerSettingModel.globalEnableBackgroundAudio, synchronize: true)
            }
        }
    }

    @ObservationIgnored
    public var enableAutoPiPOnBackground: Bool {
        get {
            access(keyPath: \.enableAutoPiPOnBackground)
            return UserDefaults.shared.value(forKey: PlayerSettingModel.globalEnableAutoPiPOnBackground, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.enableAutoPiPOnBackground) {
                UserDefaults.shared.set(newValue, forKey: PlayerSettingModel.globalEnableAutoPiPOnBackground, synchronize: true)
            }
        }
    }

    public func getTimeSecond(index: Int) {
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
