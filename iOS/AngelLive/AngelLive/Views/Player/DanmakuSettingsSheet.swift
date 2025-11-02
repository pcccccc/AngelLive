//
//  DanmakuSettingsSheet.swift
//  AngelLive
//
//  Created by pangchong on 11/2/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 播放器弹幕设置面板（BottomSheet 样式）
struct DanmakuSettingsSheet: View {
    @State private var danmuModel = DanmuSettingModel()
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Spacing.lg) {
                    // 基本设置
                    settingSection(title: "基本设置") {
                        VStack(spacing: 0) {
                            settingRow {
                                Toggle("开启弹幕", isOn: $danmuModel.showDanmu)
                                    .tint(AppConstants.Colors.link)
                            }

                            Divider()
                                .padding(.leading)

                            settingRow {
                                Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
                                    .tint(AppConstants.Colors.link)
                            }
                        }
                    }

                    // 字体设置
                    settingSection(title: "字体设置") {
                        VStack(spacing: AppConstants.Spacing.md) {
                            HStack {
                                Text("字体大小")
                                    .foregroundStyle(AppConstants.Colors.primaryText)
                                Spacer()
                                Text("\(danmuModel.danmuFontSize)")
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                                    .font(.system(.body, design: .monospaced))
                            }

                            // 字体大小调节按钮
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
                        .padding()
                    }

                    // 显示设置
                    settingSection(title: "显示设置") {
                        VStack(spacing: 0) {
                            // 透明度
                            settingRow {
                                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                                    HStack {
                                        Text("透明度")
                                            .foregroundStyle(AppConstants.Colors.primaryText)
                                        Spacer()
                                        Text(String(format: "%.1f", danmuModel.danmuAlpha))
                                            .foregroundStyle(AppConstants.Colors.secondaryText)
                                            .font(.system(.body, design: .monospaced))
                                    }

                                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                                        .tint(AppConstants.Colors.link)
                                }
                            }

                            Divider()
                                .padding(.leading)

                            // 弹幕速度
                            settingRow {
                                Picker("弹幕速度", selection: $danmuModel.danmuSpeedIndex) {
                                    ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                                        Text(DanmuSettingModel.danmuSpeedArray[index])
                                            .tag(index)
                                    }
                                }
                                .tint(AppConstants.Colors.link)
                                .onChange(of: danmuModel.danmuSpeedIndex) { _, newValue in
                                    danmuModel.getDanmuSpeed(index: newValue)
                                }
                            }

                            Divider()
                                .padding(.leading)

                            // 显示区域
                            settingRow {
                                Picker("显示区域", selection: $danmuModel.danmuAreaIndex) {
                                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                                        Text(DanmuSettingModel.danmuAreaArray[index])
                                            .tag(index)
                                    }
                                }
                                .tint(AppConstants.Colors.link)
                            }
                        }
                    }

                    Spacer(minLength: AppConstants.Spacing.xl)
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    /// 设置分组
    @ViewBuilder
    private func settingSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .padding(.horizontal)

            content()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)
        }
    }

    /// 设置行
    @ViewBuilder
    private func settingRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding()
    }
}

#Preview {
    DanmakuSettingsSheet(isPresented: .constant(true))
}
