//
//  TVOSSyncView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct TVOSSyncView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @State private var isSearching = false
    @State private var isSending = false
    @State private var sendResult: String?
    @State private var sendSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.lg) {
                // Cookie 状态卡片
                VStack(spacing: AppConstants.Spacing.md) {
                    HStack {
                        Image(systemName: syncService.isLoggedIn ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(syncService.isLoggedIn ? AppConstants.Colors.success.gradient : AppConstants.Colors.error.gradient)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bilibili Cookie")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Text(syncService.isLoggedIn ? "Cookie 已就绪，可以同步" : "请先登录 Bilibili")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // iCloud 同步
                VStack(spacing: AppConstants.Spacing.md) {
                    HStack {
                        Image(systemName: "icloud.fill")
                            .font(.title2)
                            .foregroundStyle(Color.cyan.gradient)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud 自动同步")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Text("开启后 Cookie 会自动同步到 tvOS")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()

                        Toggle("", isOn: $syncService.iCloudSyncEnabled)
                            .labelsHidden()
                    }

                    if syncService.iCloudSyncEnabled && syncService.isLoggedIn {
                        Button {
                            syncService.syncToICloud()
                            sendResult = "已同步到 iCloud"
                            sendSuccess = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("立即同步到 iCloud")
                            }
                            .font(.subheadline)
                            .foregroundStyle(AppConstants.Colors.link)
                        }
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 局域网同步
                VStack(spacing: AppConstants.Spacing.md) {
                    HStack {
                        Image(systemName: "wifi")
                            .font(.title2)
                            .foregroundStyle(Color.blue.gradient)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("局域网同步")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Text("搜索同一局域网内的 tvOS 设备")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()
                    }

                    Divider()

                    if isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在搜索 tvOS 设备...")
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .padding(.vertical, AppConstants.Spacing.sm)
                    }

                    // 发现的设备列表
                    if !syncService.discoveredDevices.isEmpty {
                        VStack(spacing: AppConstants.Spacing.sm) {
                            ForEach(syncService.discoveredDevices) { device in
                                Button {
                                    Task {
                                        await sendToDevice(device)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "appletv.fill")
                                            .foregroundStyle(Color.purple.gradient)

                                        Text(device.name)
                                            .foregroundStyle(AppConstants.Colors.primaryText)

                                        Spacer()

                                        if isSending {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundStyle(AppConstants.Colors.link)
                                        }
                                    }
                                    .padding()
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(AppConstants.CornerRadius.md)
                                }
                                .disabled(isSending || !syncService.isLoggedIn)
                            }
                        }
                    } else if !isSearching {
                        Text("未发现 tvOS 设备")
                            .font(.subheadline)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                            .padding(.vertical, AppConstants.Spacing.sm)
                    }

                    // 搜索按钮
                    Button {
                        toggleSearch()
                    } label: {
                        HStack {
                            Image(systemName: isSearching ? "stop.fill" : "magnifyingglass")
                            Text(isSearching ? "停止搜索" : "搜索 tvOS 设备")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSearching ? Color.gray.gradient : AppConstants.Colors.link.gradient)
                        .cornerRadius(AppConstants.CornerRadius.md)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 结果提示
                if let result = sendResult {
                    HStack {
                        Image(systemName: sendSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(sendSuccess ? AppConstants.Colors.success : AppConstants.Colors.error)
                        Text(result)
                            .font(.subheadline)
                            .foregroundStyle(sendSuccess ? AppConstants.Colors.success : AppConstants.Colors.error)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(sendSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(AppConstants.CornerRadius.md)
                }

                // 使用说明
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("使用说明")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                        Label("确保 iPhone/iPad 和 Apple TV 在同一 WiFi 网络", systemImage: "1.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("在 tvOS 设置中打开「账号管理 > 局域网同步」", systemImage: "2.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("在此页面点击搜索并选择 tvOS 设备发送", systemImage: "3.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("也可以开启 iCloud 同步，Cookie 会自动同步", systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.link)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                Spacer(minLength: AppConstants.Spacing.xxl)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("同步到 tvOS")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            syncService.stopBonjourBrowsing()
        }
    }

    private func toggleSearch() {
        if isSearching {
            syncService.stopBonjourBrowsing()
            isSearching = false
        } else {
            syncService.startBonjourBrowsing()
            isSearching = true
        }
    }

    private func sendToDevice(_ device: BilibiliCookieSyncService.DiscoveredDevice) async {
        isSending = true
        sendResult = nil

        let success = await syncService.sendCookieToDevice(device)

        if success {
            sendResult = "已成功发送到 \(device.name)"
            sendSuccess = true
        } else {
            sendResult = "发送失败，请重试"
            sendSuccess = false
        }

        isSending = false
    }
}
