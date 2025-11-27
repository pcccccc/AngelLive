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

    var body: some View {
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
                        Text("\(viewModel.danmuSettings.danmuFontSize) pt")
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
                        Text(String(format: "%.1f", viewModel.danmuSettings.danmuAlpha))
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
                    viewModel.applyDanmuSettings() // 即时应用速度
                }

                Picker("显示区域", selection: $viewModel.danmuSettings.danmuAreaIndex) {
                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Text(DanmuSettingModel.danmuAreaArray[index])
                            .tag(index)
                    }
                }
                .onChange(of: viewModel.danmuSettings.danmuAreaIndex) { _, _ in
                    viewModel.applyDanmuSettings() // 及时刷新区域配置
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
    }
}
