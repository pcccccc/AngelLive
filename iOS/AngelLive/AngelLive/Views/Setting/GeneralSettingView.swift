//
//  GeneralSettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct GeneralSettingView: View {
    @State private var generalSettingModel = GeneralSettingModel()
    @StateObject private var settingStore = SettingStore()

    var body: some View {
        List {
            // 通用设置
            Section {
                Toggle("匹配系统帧率", isOn: $settingStore.syncSystemRate)

                Toggle("禁用渐变背景", isOn: $generalSettingModel.generalDisableMaterialBackground)

                Toggle("播放层滑动手势", isOn: $generalSettingModel.enablePlayerGesture)
            } header: {
                Text("通用设置")
            } footer: {
                Text("播放层滑动手势：开启后可在播放器左侧上下滑动调节亮度，右侧上下滑动调节音量。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
    }
}
