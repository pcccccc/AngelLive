//
//  SettingsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 播放器设置按钮（视频信息统计、弹幕设置、投屏、定时关闭、播放设置）
struct SettingsButton: View {
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool
    var onDismiss: () -> Void

    @State private var showActionSheet = false
    @State private var showAirPlayPicker = false
    @State private var showTimerPicker = false
    @State private var showPlayerSettings = false
    @State private var timerManager = TimerManager()
    @State private var playerSettingModel = PlayerSettingModel()

    var body: some View {
        ZStack {
            Button(action: {
                showActionSheet = true
            }) {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)

            // 定时器激活时显示倒计时
            if timerManager.isTimerActive {
                Text(timerManager.formattedTime)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.red)
                    )
                    .offset(y: -18)
            }
        }
        .confirmationDialog("播放器设置", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("弹幕设置") {
                showDanmakuSettings = true
            }

            Button("投屏") {
                showAirPlayPicker = true
            }

            // 根据定时器状态显示不同按钮
            if timerManager.isTimerActive {
                Button("取消定时关闭 (\(timerManager.formattedTime))") {
                    timerManager.cancelTimer()
                }
            } else {
                Button("定时关闭") {
                    showTimerPicker = true
                }
            }

            Button("播放设置") {
                showPlayerSettings = true
            }

            Button("视频信息统计") {
                showVideoSetting = true
            }

            Button("取消", role: .cancel) {
                showActionSheet = false
            }
        }
        .sheet(isPresented: $showAirPlayPicker) {
            AirPlayPickerSheet()
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTimerPicker) {
            TimerPickerView { minutes in
                timerManager.startTimer(minutes: minutes) {
                    onDismiss()
                }
            }
        }
        .sheet(isPresented: $showPlayerSettings) {
            PlayerSettingsSheet(playerSettingModel: $playerSettingModel)
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Player Settings Sheet

/// 播放设置弹窗
private struct PlayerSettingsSheet: View {
    @Binding var playerSettingModel: PlayerSettingModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("后台播放", isOn: $playerSettingModel.enableBackgroundAudio)
                    .onChange(of: playerSettingModel.enableBackgroundAudio) { _, newValue in
                        KSOptions.canBackgroundPlay = newValue
                    }
                Toggle("自动画中画", isOn: $playerSettingModel.enableAutoPiPOnBackground)
                    .onChange(of: playerSettingModel.enableAutoPiPOnBackground) { _, newValue in
                        if newValue && !playerSettingModel.enableBackgroundAudio {
                            playerSettingModel.enableBackgroundAudio = true
                            KSOptions.canBackgroundPlay = true
                        }
                    }
            }
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        KSOptions.canBackgroundPlay = playerSettingModel.enableBackgroundAudio
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            KSOptions.canBackgroundPlay = playerSettingModel.enableBackgroundAudio
        }
    }
}

// MARK: - AirPlay Picker Sheet

/// AirPlay 投屏选择器弹窗
private struct AirPlayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("选择投屏设备")
                    .font(.headline)
                    .padding(.top)

                AirPlayView()
                    .frame(width: 60, height: 60)

                Text("点击上方按钮选择 AirPlay 设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .navigationTitle("投屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SettingsButton(
            showVideoSetting: .constant(false),
            showDanmakuSettings: .constant(false),
            onDismiss: {}
        )
    }
}
