//
//  TimerPickerView.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI

/// 定时关闭选择器
struct TimerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomPicker = false
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 30

    var onSelectTimer: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach([TimerPreset.minutes10, .minutes30, .hour1, .hour2, .hour5], id: \.self) { preset in
                        Button(action: {
                            onSelectTimer(preset.minutes)
                            dismiss()
                        }) {
                            HStack {
                                Text(preset.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("预设时间")
                }

                Section {
                    Button(action: {
                        showCustomPicker = true
                    }) {
                        HStack {
                            Text("自定义时间")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("自定义")
                }
            }
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCustomPicker) {
                CustomTimerPickerView(
                    hours: $customHours,
                    minutes: $customMinutes,
                    onConfirm: { totalMinutes in
                        onSelectTimer(totalMinutes)
                        dismiss()
                    }
                )
            }
        }
    }
}

/// 自定义时间选择器
private struct CustomTimerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hours: Int
    @Binding var minutes: Int

    var onConfirm: (Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("选择定时时长")
                    .font(.headline)
                    .padding(.top)

                HStack(spacing: 0) {
                    // 小时选择器
                    Picker("小时", selection: $hours) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour)")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text("时")
                        .font(.title2)
                        .frame(width: 40)

                    // 分钟选择器
                    Picker("分钟", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text("\(minute)")
                                .tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text("分")
                        .font(.title2)
                        .frame(width: 40)
                }
                .frame(height: 200)

                Text("总计: \(formatTotalTime())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .navigationTitle("自定义时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        let totalMinutes = hours * 60 + minutes
                        if totalMinutes > 0 {
                            onConfirm(totalMinutes)
                        }
                    }
                    .disabled(hours == 0 && minutes == 0)
                }
            }
        }
        .presentationDetents([.height(400)])
    }

    private func formatTotalTime() -> String {
        let totalMinutes = hours * 60 + minutes
        if totalMinutes == 0 {
            return "请选择时间"
        } else if hours > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        } else {
            return "\(minutes) 分钟"
        }
    }
}

#Preview {
    TimerPickerView { minutes in
        print("选择了 \(minutes) 分钟")
    }
}
