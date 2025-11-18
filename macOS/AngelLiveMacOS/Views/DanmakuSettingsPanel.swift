//
//  DanmakuSettingsPanel.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/17/25.
//

import SwiftUI
import AngelLiveCore

struct DanmakuSettingsPanel: View {
    @State private var danmuModel = DanmuSettingModel()

    var body: some View {
        Form {
            Section("弹幕显示") {
                Toggle("显示弹幕", isOn: $danmuModel.showDanmu)
                Toggle("彩色弹幕", isOn: $danmuModel.showColorDanmu)
            }

            Section("字号 & 透明度") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(danmuModel.danmuFontSize) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(danmuModel.danmuFontSize) },
                        set: { danmuModel.danmuFontSize = Int($0.rounded()) }
                    ), in: 16...80, step: 1)
                    Text("示例：这是一条弹幕")
                        .font(.system(size: CGFloat(danmuModel.danmuFontSize)))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text(String(format: "%.1f", danmuModel.danmuAlpha))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                }
            }

            Section("速度 & 区域") {
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
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
    }
}
