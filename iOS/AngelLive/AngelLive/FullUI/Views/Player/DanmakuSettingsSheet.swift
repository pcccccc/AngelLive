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
                                    .tint(AppConstants.Colors.accent)
                            }

                            Divider()
                                .padding(.leading)

                            settingRow {
                                Toggle("开启彩色弹幕", isOn: $viewModel.danmuSettings.showColorDanmu)
                                    .tint(AppConstants.Colors.accent)
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
                                    .monospacedDigit()
                            }

                            DanmakuFontControls(settings: viewModel.danmuSettings)
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
                                            .monospacedDigit()
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

                    settingSection(title: "关键词屏蔽") {
                        NavigationLink {
                            DanmakuKeywordBlocklistView(settings: viewModel.danmuSettings)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            HStack(spacing: AppConstants.Spacing.md) {
                                Image(systemName: "text.badge.xmark")
                                    .foregroundStyle(AppConstants.Colors.link)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("管理屏蔽关键词")
                                        .foregroundStyle(AppConstants.Colors.primaryText)
                                    Text("命中内容不会进入聊天或飞屏")
                                        .font(.caption)
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                                Spacer()
                                Text("\(viewModel.danmuSettings.blockedKeywords.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                            .padding()
                        }
                    }

                    Spacer(minLength: AppConstants.Spacing.xl)
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                FullUISheetHeader(title: Text("弹幕设置")) { isPresented = false }
                    .background(.regularMaterial)
            }
            .background(.ultraThinMaterial)
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
