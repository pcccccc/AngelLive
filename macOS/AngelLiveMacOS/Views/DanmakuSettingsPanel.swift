//
//  DanmakuSettingsPanel.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/17/25.
//

import SwiftUI
import AngelLiveCore

struct DanmakuSettingsPanel: View {
    @Bindable var viewModel: RoomInfoViewModel
    var usesFullUI = false
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder private func numericValue(_ text: Text) -> some View {
        if usesFullUI {
            text.monospacedDigit()
        } else {
            text
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            ZStack {
                // 标题居中
                Text("弹幕设置")
                    .font(.headline)

                HStack {
                    if usesFullUI {
                        Spacer()
                        PanelCloseButton(expandsHitTarget: true) { dismiss() }
                            .accessibilityLabel("关闭")
                            .help("关闭")
                    } else {
                        PanelCloseButton { dismiss() }
                        Spacer()
                    }
                }
            }
            .padding()

            Form {
                Section("弹幕显示") {
                    Toggle("显示弹幕", isOn: $viewModel.danmuSettings.showDanmu)
                        .onChange(of: viewModel.danmuSettings.showDanmu) { _, _ in
                            viewModel.applyDanmuSettings()
                        }
                    Toggle("彩色弹幕", isOn: $viewModel.danmuSettings.showColorDanmu)
                }

                Section("字号 & 透明度") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字号")
                            Spacer()
                            numericValue(Text("\(viewModel.danmuSettings.danmuFontSize) pt"))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.danmuSettings.danmuFontSize) },
                            set: { viewModel.danmuSettings.danmuFontSize = Int($0.rounded()) }
                        ), in: 16...80, step: 1)
                        .onChange(of: viewModel.danmuSettings.danmuFontSize) { _, _ in
                            viewModel.applyDanmuSettings()
                        }
                        Text("示例：这是一条弹幕")
                            .font(.system(size: CGFloat(viewModel.danmuSettings.danmuFontSize)))
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("透明度")
                            Spacer()
                            numericValue(Text(String(format: "%.1f", viewModel.danmuSettings.danmuAlpha)))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.danmuSettings.danmuAlpha, in: 0.1...1.0, step: 0.1)
                            .onChange(of: viewModel.danmuSettings.danmuAlpha) { _, _ in
                                viewModel.applyDanmuSettings()
                            }
                    }
                }

                Section("速度 & 区域") {
                    Picker("弹幕速度", selection: $viewModel.danmuSettings.danmuSpeedIndex) {
                        ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                            Text(DanmuSettingModel.danmuSpeedArray[index])
                                .tag(index)
                        }
                    }
                    .onChange(of: viewModel.danmuSettings.danmuSpeedIndex) { _, newValue in
                        viewModel.danmuSettings.getDanmuSpeed(index: newValue)
                        viewModel.applyDanmuSettings()
                    }

                    Picker("显示区域", selection: $viewModel.danmuSettings.danmuAreaIndex) {
                        ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                            Text(DanmuSettingModel.danmuAreaArray[index])
                                .tag(index)
                        }
                    }
                    .onChange(of: viewModel.danmuSettings.danmuAreaIndex) { _, _ in
                        viewModel.applyDanmuSettings()
                    }
                }

                Section("关键词屏蔽") {
                    DanmakuKeywordBlocklistForm(settings: viewModel.danmuSettings)
                }
            }
            .formStyle(.grouped)
            .modifier(MacFullUIFormControls(usesFullUI: usesFullUI))
        }
        .frame(minWidth: 380, minHeight: 420)
    }
}
