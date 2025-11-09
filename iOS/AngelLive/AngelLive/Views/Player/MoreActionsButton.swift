//
//  MoreActionsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import AVKit

/// 更多功能按钮（投屏、清屏、定时关闭）
struct MoreActionsButton: View {
    @State private var showActionSheet = false
    @State private var showAirPlayPicker = false
    @State private var showTimerPicker = false
    @State private var timerManager = TimerManager()
    @State private var buttonPressed = false

    var onClearChat: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Button(action: {
            buttonPressed.toggle()
            showActionSheet = true
        }) {
            ZStack {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )

                // 定时器激活时显示倒计时
                if timerManager.isTimerActive {
                    Text(timerManager.formattedTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(
                            Capsule()
                                .fill(.red)
                        )
                        .offset(y: -30)
                }
            }
        }
        .conditionalEffect(.pushDown, condition: buttonPressed)
        .confirmationDialog("更多功能", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("投屏") {
                handleAirPlay()
            }

            Button("清屏") {
                onClearChat()
            }

            // 根据定时器状态显示不同按钮
            if timerManager.isTimerActive {
                Button("取消定时关闭 (\(timerManager.formattedTime))") {
                    cancelTimer()
                }
            } else {
                Button("定时关闭") {
                    showTimerPicker = true
                }
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
                startTimer(minutes: minutes)
            }
        }
    }

    // MARK: - Action Handlers

    private func handleAirPlay() {
        showAirPlayPicker = true
    }

    private func startTimer(minutes: Int) {
        timerManager.startTimer(minutes: minutes) {
            // 定时结束，关闭播放器
            onDismiss()
        }
    }

    private func cancelTimer() {
        timerManager.cancelTimer()
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
        MoreActionsButton(
            onClearChat: {
                print("清屏")
            },
            onDismiss: {
                print("关闭")
            }
        )
    }
}
