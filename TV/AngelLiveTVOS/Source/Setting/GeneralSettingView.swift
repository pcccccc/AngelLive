//
//  PlaySettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/9/21.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct GeneralSettingView: View {
    
    @Environment(AppState.self) var appViewModel
    @FocusState var focused: Bool
    @StateObject var settingStore = SettingStore()
    
    var body: some View {

        @Bindable var playerSettingModel = appViewModel.playerSettingsViewModel
        @Bindable var generalSettingModel = appViewModel.generalSettingsViewModel

        VStack(spacing: 50) {
            Spacer()

            Toggle("直播结束后自动退出直播间（不推荐）", isOn: $playerSettingModel.openExitPlayerViewWhenLiveEnd)
                .frame(height: 45)
                .focused($focused)

            if playerSettingModel.openExitPlayerViewWhenLiveEnd {
                HStack {
                    Text("自动退出直播间时间：")
                    Spacer()
                    Menu(content: {
                        ForEach(PlayerSettingModel.timeArray.indices, id: \.self) { index in
                            Button(PlayerSettingModel.timeArray[index]) {
                                playerSettingModel.getTimeSecond(index: index)
                            }
                        }
                    }, label: {
                        Text("\(PlayerSettingModel.timeArray[playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex])")
                            .frame(width: 250, alignment: .center)
                    })
                }
                .frame(height: 45)
            }

            Toggle("匹配系统帧率", isOn: $settingStore.syncSystemRate)
                .frame(height: 45)

            Toggle("禁用渐变背景", isOn: $generalSettingModel.generalDisableMaterialBackground)
                .frame(height: 45)

            Text("如果您的页面部分背景不正常（如页面背景透明）,请尝试打开这个选项。")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(height: 45)

            Spacer()
        }
    }
}

