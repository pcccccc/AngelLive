//
//  SettingStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI

class SettingStore: ObservableObject {
    @AppStorage("SimpleLive.Setting.SyncSystemRate") var syncSystemRate = true
}
