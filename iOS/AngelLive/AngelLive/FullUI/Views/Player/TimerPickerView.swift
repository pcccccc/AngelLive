//
//  TimerPickerView.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI
import AngelLiveCore

struct TimerPickerView: View {
    let timerManager: TimerManager
    let onSelectTimer: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if timerManager.isTimerActive {
                    Section {
                        LabeledContent {
                            Button("取消", role: .destructive) {
                                timerManager.cancelTimer()
                                dismiss()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("取消定时关闭")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("剩余时间")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(timerManager.formattedTime)
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section("预设时间") {
                    ForEach([TimerPreset.minutes10, .minutes30, .hour1, .hour2, .hour5], id: \.self) { preset in
                        let selected = timerManager.scheduledMinutes == preset.minutes
                        Button { select(preset.minutes) } label: {
                            HStack {
                                Text(preset.title).foregroundStyle(.primary)
                                Spacer()
                                if selected { Image(systemName: "checkmark").foregroundStyle(AppConstants.Colors.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    NavigationLink("自定义时间") {
                        CustomTimerPickerView(onConfirm: select)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .playerSheetNavigation(Text("定时关闭")) { dismiss() }
        }
    }

    private func select(_ minutes: Int) {
        onSelectTimer(minutes)
        dismiss()
    }
}

private struct CustomTimerPickerView: View {
    let onConfirm: (Int) -> Void
    @State private var hours = 0
    @State private var minutes = 30

    private var total: Int { hours * 60 + minutes }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    Picker("小时", selection: $hours) {
                        ForEach(0..<24, id: \.self) { Text("\($0) 小时").tag($0) }
                    }
                    Picker("分钟", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { Text("\($0) 分钟").tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                LabeledContent("总计", value: "\(total) 分钟")
            }
        }
        .navigationTitle("自定义时间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if #available(iOS 26.0, *) {
                    Button(role: .confirm) { onConfirm(total) }
                        .disabled(total == 0)
                } else {
                    Button("确定") { onConfirm(total) }
                        .disabled(total == 0)
                }
            }
        }
    }
}
