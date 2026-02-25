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
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @State private var danmuModel = DanmuSettingModel()
    @State private var showBilibiliLogin = false
    @State private var showOpenSourceList = false
    @State private var selectedCookiePlatform: MacOSPlatformAccountItem?
    @State private var platformLoginStatus: [PlatformSessionID: Bool] = [:]

    var body: some View {
        Form {
            Section("账号管理") {
                bilibiliAccountRow

                ForEach(MacOSPlatformAccountItem.allCases) { platform in
                    Button {
                        selectedCookiePlatform = platform
                    } label: {
                        HStack {
                            Image(systemName: platform.iconSystemName)
                                .foregroundStyle(platform.iconTint.gradient)
                                .frame(width: 24, height: 24)

                            Text(platform.title)

                            Spacer()

                            if platformLoginStatus[platform.sessionID] == true {
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
                Button {
                    updaterViewModel.checkForUpdates()
                } label: {
                    HStack {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!updaterViewModel.canCheckForUpdates)

                Button {
                    showOpenSourceList = true
                } label: {
                    HStack {
                        Label("开源许可", systemImage: "doc.text.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

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
        .task {
            await refreshLoginStatus()
        }
        .sheet(isPresented: $showBilibiliLogin) {
            BilibiliWebLoginView()
        }
        .sheet(item: $selectedCookiePlatform, onDismiss: {
            Task { await refreshLoginStatus() }
        }) { platform in
            MacOSPlatformCookieWebLoginView(platform: platform)
        }
        .sheet(isPresented: $showOpenSourceList) {
            NavigationStack {
                OpenSourceListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showOpenSourceList = false
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 500)
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

                if syncService.isLoggedIn {
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

    private func refreshLoginStatus() async {
        for platform in MacOSPlatformAccountItem.allCases {
            let session = await PlatformSessionManager.shared.getSession(platformId: platform.sessionID)
            let loggedIn = session?.state == .authenticated
                && session?.cookie?.isEmpty == false
            platformLoginStatus[platform.sessionID] = loggedIn
        }
    }
}

#Preview {
    SettingView()
        .environmentObject(UpdaterViewModel())
}
