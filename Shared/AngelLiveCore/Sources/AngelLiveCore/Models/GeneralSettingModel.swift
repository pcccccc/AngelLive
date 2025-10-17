//
//  GeneralSettingModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 2024/9/21.
//

import Foundation
import SwiftUI
import Observation

public enum AngelLiveFavoriteStyle: Int, CaseIterable, CustomStringConvertible, Sendable {

    public var description: String {
        switch self {
        case .normal:
            return "普通视图"
        case .section:
            return "按平台分组"
        case .liveState:
            return "按直播状态分组"
        }
    }

    case normal = 0
    case section = 1
    case liveState = 2
}

@Observable
public final class GeneralSettingModel: Sendable {

    public static let globalGeneralDisableMaterialBackground = "SimpleLive.Setting.globalGeneralDisableMaterialBackground"
    public static let globalGeneralSettingFavoriteStyle = "SimpleLive.Setting.favorite.style"

    public init() {}

    @ObservationIgnored
    public var generalDisableMaterialBackground: Bool {
        get {
            access(keyPath: \.generalDisableMaterialBackground)
            return UserDefaults.shared.value(forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.generalDisableMaterialBackground) {
                 UserDefaults.shared.set(newValue, forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground, synchronize: true)
            }
        }
    }

    @ObservationIgnored
    public var globalGeneralSettingFavoriteStyle: Int {
        get {
            access(keyPath: \.globalGeneralSettingFavoriteStyle)
            return UserDefaults.shared.value(forKey: GeneralSettingModel.globalGeneralSettingFavoriteStyle, synchronize: true) as? Int ?? 0
        }
        set {
            withMutation(keyPath: \.globalGeneralSettingFavoriteStyle) {
                 UserDefaults.shared.set(newValue, forKey: GeneralSettingModel.globalGeneralSettingFavoriteStyle, synchronize: true)
            }
        }
    }
}
