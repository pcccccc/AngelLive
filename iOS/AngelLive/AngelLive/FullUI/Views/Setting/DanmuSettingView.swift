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
    @State private var alphaText = ""

    var body: some View {
        List {
            // 基本设置
            Section {
                Toggle("开启弹幕", isOn: $danmuModel.showDanmu)
                    .tint(AppConstants.Colors.accent)

                Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
                    .tint(AppConstants.Colors.accent)
            } header: {
                Text("基本设置")
            }

            // 字体设置
            Section {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    HStack {
                        Text("字体大小")
                            .foregroundStyle(AppConstants.Colors.primaryText)
                        Spacer()
                        Text("\(danmuModel.danmuFontSize)")
                            .monospacedDigit()
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }

                    DanmakuFontControls(settings: danmuModel)
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
                        .tint(AppConstants.Colors.link)
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
                        Label("管理屏蔽关键词", systemImage: "text.badge.xmark")
                        Spacer()
                        Text("\(danmuModel.blockedKeywords.count)")
                            .monospacedDigit()
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("弹幕")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            alphaText = String(format: "%.1f", danmuModel.danmuAlpha)
        }
    }
}

struct DanmakuFontControls: View {
    let settings: DanmuSettingModel

    var body: some View {
        VStack(spacing: AppConstants.Spacing.sm) {
            Text("这是测试弹幕")
                .font(.system(size: CGFloat(settings.danmuFontSize)))
                .frame(maxWidth: .infinity)

            HStack {
                ForEach([-5, -1, 1, 5], id: \.self) { step in
                    Button {
                        settings.danmuFontSize += step
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: (step < 0 ? "minus.circle" : "plus.circle") + (abs(step) == 5 ? ".fill" : ""))
                            Text(verbatim: step > 0 ? "+\(step)" : "\(step)")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .tint(AppConstants.Colors.link)
                    .accessibilityLabel(step < 0 ? "字号减 \(abs(step))" : "字号加 \(step)")
                    .disabled(!(10...100).contains(settings.danmuFontSize + step))
                }
            }
        }
    }
}
