//
//  DanmuSettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct DanmuSettingView: View {
    @State private var danmuModel = DanmuSettingModel()
    var body: some View {
        DanmakuSettingsList(danmuModel: danmuModel)
            .navigationTitle("弹幕")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct DanmakuSettingsList: View {
    @Bindable var danmuModel: DanmuSettingModel

    var body: some View {
        List {
            // 基本设置
            Section {
                Toggle("开启弹幕", isOn: $danmuModel.showDanmu)

                Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
            } header: {
                Text("基本设置")
            }

            // 字体设置
            Section {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    LabeledContent("字体大小") {
                        Text("\(danmuModel.danmuFontSize) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: Binding(
                            get: { Double(min(100, max(10, danmuModel.danmuFontSize))) },
                            set: { danmuModel.danmuFontSize = Int($0.rounded()) }
                        ), in: 10...100, step: 1)
                        .accessibilityLabel("字体大小")
                        .accessibilityValue("\(danmuModel.danmuFontSize) 点")
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, AppConstants.Spacing.sm)
            } header: {
                Text("字体设置")
            }

            // 显示设置
            Section {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text(String(format: "%.1f", danmuModel.danmuAlpha))
                            .monospacedDigit()
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }

                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                        .accessibilityLabel("透明度")
                }

                Picker("弹幕速度", selection: $danmuModel.danmuSpeedIndex) {
                    ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                        Text(DanmuSettingModel.danmuSpeedArray[index])
                            .tag(index)
                    }
                }
                .onChange(of: danmuModel.danmuSpeedIndex) { _, newValue in
                    danmuModel.getDanmuSpeed(index: newValue)
                }

                Picker("显示区域", selection: $danmuModel.danmuAreaIndex) {
                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Text(DanmuSettingModel.danmuAreaArray[index])
                            .tag(index)
                    }
                }
            } header: {
                Text("显示设置")
            }

            Section("关键词屏蔽") {
                NavigationLink {
                    DanmakuKeywordBlocklistView(settings: danmuModel)
                } label: {
                    HStack {
                        Image(systemName: "text.badge.xmark")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("管理屏蔽关键词")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(danmuModel.blockedKeywords.count)")
                            .monospacedDigit()
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(AppConstants.Colors.accent)
    }
}
