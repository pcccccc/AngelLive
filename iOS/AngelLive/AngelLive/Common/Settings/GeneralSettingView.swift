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
    @State private var appIconSettings = AppIconSettingsModel()
    @AppStorage(HomePagePreference.storageKey, store: .shared)
    private var homePagePreference = HomePagePreference.recommendations
    @AppStorage(HomePagePreference.selectedPluginStorageKey, store: .shared)
    private var selectedHomePluginId = ""

    var body: some View {
        @Bindable var appIconSettings = appIconSettings

        List {
            Section {
                Picker(selection: $homePagePreference) {
                    ForEach(HomePagePreference.allCases, id: \.self) { preference in
                        Text(preference.displayName)
                            .tag(preference)
                    }
                } label: {
                    GeneralSettingLabel(
                        title: "首页内容",
                        systemImage: "house.fill",
                        tint: .orange
                    )
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("首页")
            } footer: {
                Text("选择首页展示插件提供的推荐内容，或直接展示原来的收藏页面。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            Section {
                Picker(
                    selection: Binding(
                        get: { appIconSettings.selection },
                        set: { choice in
                            Task { await appIconSettings.select(choice) }
                        }
                    )
                ) {
                    ForEach(AppIconSettingsModel.Choice.allCases) { choice in
                        Text(choice.title)
                            .tag(choice)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(appIconSettings.selection.previewAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(.rect(cornerRadius: 7))

                        Text("应用图标")
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(appIconSettings.applyingChoice != nil)

                Toggle(isOn: materialBackgroundEnabled) {
                    GeneralSettingLabel(
                        title: "动态渐变背景",
                        systemImage: "circle.lefthalf.filled",
                        tint: .purple
                    )
                }
                .tint(AppConstants.Colors.accent)
            } header: {
                Text("外观")
            } footer: {
                Text("动态渐变背景会根据直播封面生成沉浸式背景效果。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            Section {
                Toggle(isOn: $generalSettingModel.enablePlayerGesture) {
                    GeneralSettingLabel(
                        title: "播放层滑动手势",
                        systemImage: "hand.draw.fill",
                        tint: .blue
                    )
                }
                .tint(AppConstants.Colors.accent)
            } header: {
                Text("播放")
            } footer: {
                Text("开启后，在播放器左侧上下滑动调节亮度，右侧上下滑动调节音量。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: homePagePreference) { _, preference in
            if preference == .recommendations {
                selectedHomePluginId = ""
            }
        }
        .alert("无法更换应用图标", isPresented: $appIconSettings.isShowingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(appIconSettings.errorMessage)
        }
    }

    private var materialBackgroundEnabled: Binding<Bool> {
        Binding(
            get: { !generalSettingModel.generalDisableMaterialBackground },
            set: { generalSettingModel.generalDisableMaterialBackground = !$0 }
        )
    }
}

private struct GeneralSettingLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint.gradient)
                .frame(width: 30, height: 30)

            Text(title)
        }
    }
}
