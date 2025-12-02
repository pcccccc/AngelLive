//
//  SettingView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore

struct SettingView: View {
    @AppStorage("autoPlay") private var autoPlay = true
    @AppStorage("preferredQuality") private var preferredQuality = "原画"
    @AppStorage("SimpleLive.Setting.BilibiliCookie") private var bilibiliCookie = ""
    @State private var danmuModel = DanmuSettingModel()
    @State private var showBilibiliLogin = false

    var body: some View {
        Form {
            Section("账号管理") {
                bilibiliAccountRow
            }

            Section("播放设置") {
                Toggle("自动播放", isOn: $autoPlay)
                    .help("进入直播间时自动开始播放")

                Picker("默认清晰度", selection: $preferredQuality) {
                    Text("原画").tag("原画")
                    Text("高清").tag("高清")
                    Text("流畅").tag("流畅")
                }
            }

            Section("弹幕设置") {
                Toggle("显示弹幕", isOn: $danmuModel.showDanmu)

                Toggle("彩色弹幕", isOn: $danmuModel.showColorDanmu)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Text("\(danmuModel.danmuFontSize) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(danmuModel.danmuFontSize) },
                        set: { newValue in
                            danmuModel.danmuFontSize = Int(newValue.rounded())
                        }
                    ), in: 20...80, step: 1)
                    Text("示例：这是一条弹幕")
                        .font(.system(size: CGFloat(danmuModel.danmuFontSize)))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text(String(format: "%.1f", danmuModel.danmuAlpha))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
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
            }

            Section("关于") {
                Link(destination: URL(string: "https://github.com/pcccccc/SimpleLiveTVOS")!) {
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
        .sheet(isPresented: $showBilibiliLogin) {
            BilibiliWebLoginView()
        }
    }

    // MARK: - Bilibili Account Row

    private var bilibiliAccountRow: some View {
        Button {
            showBilibiliLogin = true
        } label: {
            HStack {
                Image("bilibili")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)

                Text("哔哩哔哩")

                Spacer()

                if bilibiliCookie.contains("SESSDATA") {
                    Text("已登录")
                        .foregroundStyle(AppConstants.Colors.success)
                } else {
                    Text("未登录")
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingView()
}
