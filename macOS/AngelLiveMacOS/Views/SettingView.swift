//
//  SettingView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI

struct SettingView: View {
    @AppStorage("autoPlay") private var autoPlay = true
    @AppStorage("preferredQuality") private var preferredQuality = "原画"
    @AppStorage("showDanmu") private var showDanmu = false

    var body: some View {
        Form {
            Section("播放设置") {
                Toggle("自动播放", isOn: $autoPlay)
                    .help("进入直播间时自动开始播放")
            }

            Section("弹幕设置") {
                Toggle("显示弹幕", isOn: $showDanmu)
                    .help("macOS 版本暂不支持弹幕功能")
                    .disabled(true)

                Text("弹幕功能仅在 iOS 和 tvOS 版本可用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("关于") {
//                LabeledContent("版本", value: "2.0.0")
//                LabeledContent("平台", value: "macOS")
//                LabeledContent("构建", value: "Debug")

                Link(destination: URL(string: "https://github.com")!) {
                    Label("访问 GitHub", systemImage: "link")
                }
            }

            Section {
                Text("AngelLive - macOS 直播应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}

#Preview {
    SettingView()
}
