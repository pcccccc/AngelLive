//
//  TvOSSyncSheet.swift
//  AngelLiveMacOS
//
//  Created by Claude on 11/29/25.
//

import SwiftUI
import AngelLiveCore

// MARK: - tvOS Sync Sheet

struct TvOSSyncSheet: View {
    @ObservedObject var syncService: BilibiliCookieSyncService
    let cookie: String
    @Environment(\.dismiss) private var dismiss

    @State private var isSearching = false
    @State private var isSending = false
    @State private var sendResult: SendResult?

    enum SendResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xl) {
            // Header
            HStack {
                Text("同步到 tvOS")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            VStack(spacing: AppConstants.Spacing.xl) {
                statusIcon
                    .padding(.top, AppConstants.Spacing.xl)

                statusText

                if !syncService.discoveredDevices.isEmpty && sendResult == nil {
                    deviceList
                }

                Spacer()

                if sendResult == nil {
                    instructionsView
                }
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            startSearching()
        }
        .onDisappear {
            syncService.stopBonjourBrowsing()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        if let result = sendResult {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppConstants.Colors.success)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppConstants.Colors.error)
            }
        } else if isSending {
            ProgressView()
                .scaleEffect(2)
                .frame(height: 60)
        } else if syncService.discoveredDevices.isEmpty {
            Image(systemName: "appletvremote.gen4.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppConstants.Colors.link)
        } else {
            Image(systemName: "tv.and.mediabox.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppConstants.Colors.success)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let result = sendResult {
            switch result {
            case .success:
                VStack(spacing: AppConstants.Spacing.xs) {
                    Text("同步成功")
                        .font(.title2.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                    Text("Cookie 已发送到 tvOS 设备")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            case .failure(let error):
                VStack(spacing: AppConstants.Spacing.xs) {
                    Text("同步失败")
                        .font(.title2.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.error)
                        .multilineTextAlignment(.center)

                    Button {
                        sendResult = nil
                        startSearching()
                    } label: {
                        Text("重试")
                            .font(.subheadline.bold())
                    }
                    .padding(.top, AppConstants.Spacing.sm)
                }
            }
        } else if isSending {
            Text("正在发送...")
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)
        } else if syncService.discoveredDevices.isEmpty {
            VStack(spacing: AppConstants.Spacing.xs) {
                Text("正在搜索设备...")
                    .font(.title2.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)
                ProgressView()
                    .padding(.top, AppConstants.Spacing.sm)
            }
        } else {
            Text("发现 \(syncService.discoveredDevices.count) 台设备")
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)
        }
    }

    private var deviceList: some View {
        VStack(spacing: AppConstants.Spacing.sm) {
            ForEach(syncService.discoveredDevices) { device in
                Button {
                    sendToDevice(device)
                } label: {
                    HStack {
                        Image(systemName: "appletv.fill")
                            .font(.title3)
                            .foregroundStyle(AppConstants.Colors.link)

                        Text(device.name.replacingOccurrences(of: "AngelLive-tvOS-", with: ""))
                            .font(.body)
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                    .padding()
                    .background(AppConstants.Colors.secondaryBackground)
                    .cornerRadius(AppConstants.CornerRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            Text("使用说明")
                .font(.caption.bold())
                .foregroundStyle(AppConstants.Colors.secondaryText)

            Text("1. 确保 Mac 和 Apple TV 在同一 Wi-Fi 网络")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)

            Text("2. 在 Apple TV 上打开 Angel Live → 设置 → 账号管理 → 局域网同步")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)

            Text("3. 点击上方发现的设备即可同步")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(AppConstants.CornerRadius.md)
    }

    // MARK: - Methods

    private func startSearching() {
        isSearching = true
        syncService.startBonjourBrowsing()
    }

    private func sendToDevice(_ device: BilibiliCookieSyncService.DiscoveredDevice) {
        isSending = true

        Task {
            let success = await syncService.sendCookieToDevice(device)

            await MainActor.run {
                isSending = false
                if success {
                    sendResult = .success
                } else {
                    sendResult = .failure("无法连接到设备，请确保 tvOS 端已打开局域网同步页面")
                }
            }
        }
    }
}
