//
//  GeneralSettingModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/9/21.
//

import Foundation
import SwiftUI
import Observation

@Observable
final class GeneralSettingModel {
    
    static let globalGeneralDisableMaterialBackground = "SimpleLive.Setting.globalGeneralDisableMaterialBackground"
    
    @ObservationIgnored
    public var generalDisableMaterialBackground: Bool {
        get {
            access(keyPath: \.generalDisableMaterialBackground)
            return UserDefaults.standard.value(forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.generalDisableMaterialBackground) {
                 UserDefaults.standard.setValue(newValue, forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground)
            }
        }
    }
}
