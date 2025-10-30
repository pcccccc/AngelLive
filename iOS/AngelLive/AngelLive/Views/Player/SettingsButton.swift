//
//  SettingsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI

/// 播放器设置按钮（包含视频信息统计、弹幕设置等）
struct SettingsButton: View {
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool
    @State private var showActionSheet = false

    var body: some View {
        Button(action: {
            showActionSheet = true
        }) {
            Image(systemName: "gearshape")
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("设置", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("视频信息统计") {
                showVideoSetting = true
            }

            Button("弹幕设置") {
                showDanmakuSettings = true
            }

            Button("取消", role: .cancel) {
                showActionSheet = false
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SettingsButton(
            showVideoSetting: .constant(false),
            showDanmakuSettings: .constant(false)
        )
    }
}
