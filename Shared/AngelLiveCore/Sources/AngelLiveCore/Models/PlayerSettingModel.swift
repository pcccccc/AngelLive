//
//  PlayerSettingModel.swift
//  AngelLiveCore
//
//  Created by Claude on 11/1/25.
//

import Foundation
import SwiftUI
import Observation

// MARK: - Video Scale Mode

/// 视频缩放模式
public enum VideoScaleMode: Int, CaseIterable, Sendable {
    case fit = 0        // 适应（保持比例，可能有黑边）
    case stretch = 1    // 拉伸（填满屏幕，不保持比例）
    case fill = 2       // 铺满（保持比例，裁剪填满）
    case ratio16x9 = 3  // 16:9
    case ratio4x3 = 4   // 4:3

    public var title: String {
        switch self {
        case .fit: return "适应"
        case .stretch: return "拉伸"
        case .fill: return "铺满"
        case .ratio16x9: return "16:9"
        case .ratio4x3: return "4:3"
        }
    }

    public var iconName: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .stretch: return "arrow.up.left.and.arrow.down.right"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .ratio16x9: return "rectangle.ratio.16.to.9"
        case .ratio4x3: return "rectangle.ratio.4.to.3"
        }
    }
}

@Observable
public final class PlayerSettingModel {

    public static let globalVideoScaleMode = "SimpleLive.Setting.VideoScaleMode"

    public static let globalOpenExitPlayerViewWhenLiveEnd = "SimpleLive.Setting.OpenExitPlayerViewWhenLiveEnd"
    public static let globalOpenExitPlayerViewWhenLiveEndSecond = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecond"
    public static let globalOpenExitPlayerViewWhenLiveEndSecondIndex = "SimpleLive.Setting.globalOpenExitPlayerViewWhenLiveEndSecondIndex"
    public static let globalEnableBackgroundAudio = "SimpleLive.Setting.EnableBackgroundAudio"
    public static let globalEnableAutoPiPOnBackground = "SimpleLive.Setting.EnableAutoPiPOnBackground"

    public init() {}

    nonisolated public static let timeArray: [String] = ["1分钟", "2分钟", "3分钟", "5分钟", "10分钟"]

    @ObservationIgnored
    public var videoScaleMode: VideoScaleMode {
        get {
            access(keyPath: \.videoScaleMode)
            let rawValue = UserDefaults.shared.value(forKey: PlayerSettingModel.globalVideoScaleMode, synchronize: true) as? Int ?? 0
            return VideoScaleMode(rawValue: rawValue) ?? .fit
        }
        set {
            withMutation(keyPath: \.videoScaleMode) {
                UserDefaults.shared.set(newValue.rawValue, forKey: PlayerSettingModel.globalVideoScaleMode, synchronize: true)
            }
        }
    }

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
