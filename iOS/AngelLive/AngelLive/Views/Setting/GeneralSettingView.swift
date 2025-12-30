//
//  GeneralSettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct GeneralSettingView: View {
    @State private var playerSettingModel = PlayerSettingModel()
    @State private var generalSettingModel = GeneralSettingModel()
    @StateObject private var settingStore = SettingStore()

    var body: some View {
        List {
            // 播放设置
            Section {
                Toggle("直播结束后自动退出直播间", isOn: $playerSettingModel.openExitPlayerViewWhenLiveEnd)

                if playerSettingModel.openExitPlayerViewWhenLiveEnd {
                    Picker("自动退出直播间时间", selection: $playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex) {
                        ForEach(PlayerSettingModel.timeArray.indices, id: \.self) { index in
                            Text(PlayerSettingModel.timeArray[index])
                                .tag(index)
                        }
                    }
                    .onChange(of: playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex) { _, newValue in
                        playerSettingModel.getTimeSecond(index: newValue)
                    }
                }
            } header: {
                Text("播放设置")
            }

            // 通用设置
            Section {
                Toggle("匹配系统帧率", isOn: $settingStore.syncSystemRate)

                Toggle("禁用渐变背景", isOn: $generalSettingModel.generalDisableMaterialBackground)
            } header: {
                Text("通用设置")
            } footer: {
                Text("如果您的页面部分背景不正常（如页面背景透明），请尝试打开这个选项。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
    }
}
