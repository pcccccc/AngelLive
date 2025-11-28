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

                Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
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
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }

                    HStack(spacing: AppConstants.Spacing.md) {
                        Button {
                            if danmuModel.danmuFontSize > 15 {
                                danmuModel.danmuFontSize -= 5
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppConstants.Colors.error.gradient)
                        }

                        Button {
                            if danmuModel.danmuFontSize > 10 {
                                danmuModel.danmuFontSize -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.warning.gradient)
                        }

                        Spacer()

                        Text("这是测试弹幕")
                            .font(.system(size: CGFloat(danmuModel.danmuFontSize)))
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        Spacer()

                        Button {
                            if danmuModel.danmuFontSize < 100 {
                                danmuModel.danmuFontSize += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                        }

                        Button {
                            if danmuModel.danmuFontSize < 95 {
                                danmuModel.danmuFontSize += 5
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppConstants.Colors.link.gradient)
                        }
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("弹幕")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            alphaText = String(format: "%.1f", danmuModel.danmuAlpha)
        }
    }
}
