//
//  SyncView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct SyncView: View {
    @Environment(AppFavoriteModel.self) var favoriteModel
    @State private var isSyncing = false
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""
    @State private var syncSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.lg) {
                // iCloud 状态卡片
                VStack(spacing: AppConstants.Spacing.md) {
                    HStack {
                        Image(systemName: statusIcon)
                            .font(.title)
                            .foregroundStyle(statusColor.gradient)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                            Text("iCloud 状态")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 同步统计卡片
                VStack(spacing: AppConstants.Spacing.md) {
                    Text("同步数据统计")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AppConstants.Spacing.lg) {
                        // 收藏数量
                        VStack(spacing: AppConstants.Spacing.xs) {
                            Text("\(favoriteModel.roomList.count)")
                                .font(.title.bold())
                                .foregroundStyle(AppConstants.Colors.link.gradient)

                            Text("收藏主播")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppConstants.Colors.materialBackground.opacity(0.5))
                        .cornerRadius(AppConstants.CornerRadius.md)

                        // 分组数量
                        VStack(spacing: AppConstants.Spacing.xs) {
                            Text("\(favoriteModel.groupedRoomList.count)")
                                .font(.title.bold())
                                .foregroundStyle(AppConstants.Colors.success.gradient)

                            Text("平台分组")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppConstants.Colors.materialBackground.opacity(0.5))
                        .cornerRadius(AppConstants.CornerRadius.md)
                    }

                    // 上次同步时间
                    if let lastSync = favoriteModel.lastSyncTime {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                            Text("上次同步：\(formatDate(lastSync))")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 同步进度卡片
                if isSyncing {
                    VStack(spacing: AppConstants.Spacing.md) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在同步...")
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.primaryText)
                        }

                        if !favoriteModel.syncProgressInfo.0.isEmpty {
                            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                                HStack {
                                    Text(favoriteModel.syncProgressInfo.0)
                                        .font(.caption)
                                        .foregroundStyle(AppConstants.Colors.primaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(favoriteModel.syncProgressInfo.2)
                                        .font(.caption)
                                        .foregroundStyle(
                                            favoriteModel.syncProgressInfo.2 == "成功" ?
                                            AppConstants.Colors.success :
                                                AppConstants.Colors.error
                                        )
                                }

                                Text(favoriteModel.syncProgressInfo.1)
                                    .font(.caption2)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)

                                ProgressView(
                                    value: Double(favoriteModel.syncProgressInfo.3),
                                    total: Double(favoriteModel.syncProgressInfo.4)
                                )
                                .tint(AppConstants.Colors.link)
                            }
                        }
                    }
                    .padding()
                    .background(AppConstants.Colors.materialBackground)
                    .cornerRadius(AppConstants.CornerRadius.lg)
                }

                // 手动同步按钮
                Button {
                    Task {
                        await performSync()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(isSyncing ? "同步中..." : "立即同步")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        isSyncing ?
                        Color.gray.gradient :
                        AppConstants.Colors.link.gradient
                    )
                    .cornerRadius(AppConstants.CornerRadius.md)
                }
                .disabled(isSyncing || !favoriteModel.cloudKitReady)

                // 使用说明
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("关于 iCloud 同步")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                        Label("收藏数据会自动同步到 iCloud", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("所有登录同一 iCloud 账号的设备共享收藏", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("下拉收藏页面可快速刷新数据", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("删除收藏后会自动从 iCloud 移除", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
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
        .navigationTitle("数据同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert(syncSuccess ? "同步成功" : "同步失败", isPresented: $showSyncResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(syncResultMessage)
        }
    }

    private var statusIcon: String {
        switch favoriteModel.syncStatus {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.icloud.fill"
        case .error:
            return "exclamationmark.icloud.fill"
        case .notLoggedIn:
            return "xmark.icloud.fill"
        }
    }

    private var statusColor: Color {
        switch favoriteModel.syncStatus {
        case .syncing:
            return AppConstants.Colors.link
        case .success:
            return AppConstants.Colors.success
        case .error:
            return AppConstants.Colors.error
        case .notLoggedIn:
            return AppConstants.Colors.warning
        }
    }

    private var statusText: String {
        if isSyncing {
            return "正在同步数据..."
        }

        switch favoriteModel.syncStatus {
        case .syncing:
            return "正在同步..."
        case .success:
            return "iCloud 已就绪，数据已同步"
        case .error:
            return favoriteModel.cloudKitStateString
        case .notLoggedIn:
            return "未登录 iCloud，请前往系统设置登录"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func performSync() async {
        isSyncing = true
        await favoriteModel.syncWithActor()
        isSyncing = false

        if favoriteModel.syncStatus == .success {
            syncSuccess = true
            syncResultMessage = "成功同步 \(favoriteModel.roomList.count) 个收藏"
        } else {
            syncSuccess = false
            syncResultMessage = favoriteModel.cloudKitStateString
        }
        showSyncResult = true
    }
}
