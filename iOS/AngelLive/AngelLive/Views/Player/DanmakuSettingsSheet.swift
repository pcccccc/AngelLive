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
    @Binding var isPresented: Bool
    @Environment(RoomInfoViewModel.self) private var viewModel

    var body: some View {
        
        @Bindable var viewModel = viewModel
        
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Spacing.lg) {
                    // 基本设置
                    settingSection(title: "基本设置") {
                        VStack(spacing: 0) {
                            settingRow {
                                Toggle("开启弹幕", isOn: $viewModel.danmuSettings.showDanmu)
                                    .tint(AppConstants.Colors.link)
                            }

                            Divider()
                                .padding(.leading)

                            settingRow {
                                Toggle("开启彩色弹幕", isOn: $viewModel.danmuSettings.showColorDanmu)
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
                                Text("\(viewModel.danmuSettings.danmuFontSize)")
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                                    .font(.system(.body, design: .monospaced))
                            }

                            // 字体大小调节按钮
                            HStack(spacing: AppConstants.Spacing.md) {
                                Button {
                                    if viewModel.danmuSettings.danmuFontSize > 15 {
                                        viewModel.danmuSettings.danmuFontSize -= 5
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title2)
                                        Text("-5")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(AppConstants.Colors.link)
                                }

                                Button {
                                    if viewModel.danmuSettings.danmuFontSize > 10 {
                                        viewModel.danmuSettings.danmuFontSize -= 1
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "minus.circle")
                                            .font(.title3)
                                        Text("-1")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(AppConstants.Colors.link)
                                }

                                Spacer()

                                Text("这是测试弹幕")
                                    .font(.system(size: CGFloat(viewModel.danmuSettings.danmuFontSize)))
                                    .foregroundStyle(AppConstants.Colors.primaryText)

                                Spacer()

                                Button {
                                    if viewModel.danmuSettings.danmuFontSize < 100 {
                                        viewModel.danmuSettings.danmuFontSize += 1
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                            .font(.title3)
                                        Text("+1")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(AppConstants.Colors.link)
                                }

                                Button {
                                    if viewModel.danmuSettings.danmuFontSize < 95 {
                                        viewModel.danmuSettings.danmuFontSize += 5
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                        Text("+5")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(AppConstants.Colors.link)
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
                                        Text(String(format: "%.1f", viewModel.danmuSettings.danmuAlpha))
                                            .foregroundStyle(AppConstants.Colors.secondaryText)
                                            .font(.system(.body, design: .monospaced))
                                    }

                                    Slider(value: $viewModel.danmuSettings.danmuAlpha, in: 0.1...1.0, step: 0.1)
                                        .tint(AppConstants.Colors.link)
                                }
                            }

                            Divider()
                                .padding(.leading)

                            // 弹幕速度
                            settingRow {
                                HStack {
                                    Text("弹幕速度")
                                        .foregroundStyle(AppConstants.Colors.primaryText)
                                    Spacer()
                                    Picker("", selection: $viewModel.danmuSettings.danmuSpeedIndex) {
                                        ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                                            Text(DanmuSettingModel.danmuSpeedArray[index])
                                                .tag(index)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppConstants.Colors.link)
                                    .onChange(of: viewModel.danmuSettings.danmuSpeedIndex) { _, newValue in
                                        viewModel.danmuSettings.getDanmuSpeed(index: newValue)
                                    }
                                }
                            }

                            Divider()
                                .padding(.leading)

                            // 显示区域
                            settingRow {
                                HStack {
                                    Text("显示区域")
                                        .foregroundStyle(AppConstants.Colors.primaryText)
                                    Spacer()
                                    Picker("", selection: $viewModel.danmuSettings.danmuAreaIndex) {
                                        ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                                            Text(DanmuSettingModel.danmuAreaArray[index])
                                                .tag(index)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppConstants.Colors.link)
                                }
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
