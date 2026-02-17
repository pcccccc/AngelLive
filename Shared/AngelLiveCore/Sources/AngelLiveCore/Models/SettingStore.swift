//
//  SettingStore.swift
//  AngelLiveCore
//
//  Created by pc on 2024/4/2.
//

import SwiftUI

public class SettingStore: ObservableObject {
    @AppStorage("SimpleLive.Setting.SyncSystemRate") public var syncSystemRate = true

    public init() {}
}
