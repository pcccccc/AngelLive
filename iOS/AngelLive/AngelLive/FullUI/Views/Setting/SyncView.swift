//
//  SyncView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import UniformTypeIdentifiers

struct SyncView: View {
    @Environment(AppFavoriteModel.self) var favoriteModel
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var pluginSourceSyncService = PluginSourceSyncService()
    @State private var isSearching = false
    @State private var isSending = false
    @State private var sendResult: String?
    @State private var sendSuccess = false
    @State private var loggedInPlatformNames: [String] = []
    @State private var cloudPluginSourceCount = 0

    // iCloud 确认弹窗状态
    @State private var showUploadConfirm = false
    @State private var showDownloadConfirm = false
    @State private var showClearCloudConfirm = false
    @State private var confirmMessage = ""
    @State private var isFetchingPreview = false
    @State private var isClearingCloudLoginInfo = false

    // 收藏备份导入导出
    @State private var showExportFormatDialog = false
    @State private var showExporter = false
    @State private var pendingExportDocument: FavoriteBackupDocument?
    @State private var pendingExportFilename: String = ""
    @State private var showImporter = false
    @State private var importReport: FavoriteImportReport?
    @State private var showImportResult = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.lg) {
                iCloudStatusCard
                favoriteSyncToggleCard
                syncStatsCard
                syncProgressCard
                loginInfoSyncCard
                lanSyncCard
                accountICloudSyncCard
                favoriteBackupCard
                sendResultCard
                usageGuideCard
                clearCloudLoginInfoButton

                Spacer(minLength: AppConstants.Spacing.xxl)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("数据同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await syncService.refreshAllLoginStatus()
            await loadLoggedInPlatformNames()
            await loadCloudPluginSourceCount()
        }
        .onDisappear {
            syncService.stopBonjourBrowsing()
        }
        .alert("同步到 iCloud", isPresented: $showUploadConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定上传") {
                Task {
                    let outcome = await syncService.syncAllToICloud()
                    await loadLoggedInPlatformNames()
                    await MainActor.run {
                        applySyncOutcome(outcome, successMessage: "已同步到 iCloud")
                    }
                }
            }
        } message: {
            Text(confirmMessage)
        }
        .alert("从 iCloud 同步", isPresented: $showDownloadConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定下载") {
                Task {
                    let outcome = await syncService.syncAllFromICloud()
                    await loadLoggedInPlatformNames()
                    await MainActor.run {
                        applySyncOutcome(outcome, successMessage: "已从 iCloud 同步到本地")
                    }
                }
            }
        } message: {
            Text(confirmMessage)
        }
        .alert("清理云端登录信息", isPresented: $showClearCloudConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定清理", role: .destructive) {
                Task { await clearCloudLoginInfo() }
            }
        } message: {
            Text("确定要清理 iCloud 中保存的所有平台登录信息吗？此操作不会退出本机账号，但其他设备将无法再从 iCloud 下载这些登录信息。")
        }
        .confirmationDialog("选择导出格式", isPresented: $showExportFormatDialog, titleVisibility: .visible) {
            Button("Angel Live 完整格式（推荐）") {
                prepareExport(format: .angelLive)
            }
            Button("兼容 Simple Live 精简格式") {
                prepareExport(format: .simpleLive)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("完整格式保留全部信息；Simple Live 精简格式仅含 4 个核心字段，便于跨工具使用。")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: pendingExportDocument,
            contentType: .json,
            defaultFilename: pendingExportFilename
        ) { result in
            switch result {
            case .success:
                sendResult = "已导出收藏文件"
                sendSuccess = true
            case .failure(let error):
                sendResult = "导出失败：\(error.localizedDescription)"
                sendSuccess = false
            }
            pendingExportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                Task { await handleImportPickedFile(url) }
            case .failure(let error):
                importErrorMessage = "无法打开文件：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showImportResult) {
            if let report = importReport {
                FavoriteImportResultView(report: report) {
                    showImportResult = false
                }
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("好") { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    // MARK: - Cards

    private var iCloudStatusCard: some View {
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
    }

    private var favoriteSyncToggleCard: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Toggle(isOn: Binding(
                get: { favoriteModel.favoriteICloudSyncEnabled },
                set: { newValue in
                    favoriteModel.favoriteICloudSyncEnabled = newValue
                    if newValue {
                        Task { await favoriteModel.syncWithActor() }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("收藏 iCloud 同步")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                    Text("关闭后收藏仅保存在本机,不与 iCloud 同步")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            }

            if favoriteModel.favoriteICloudSyncEnabled, let syncError = favoriteModel.lastSyncError {
                HStack(spacing: 6) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(AppConstants.Colors.error)
                    Text("收藏同步失败：\(syncError.displayText)")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.error)
                    Spacer()
                }
            }
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
    }

    private var syncStatsCard: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Text("同步数据统计")
                .font(.headline)
                .foregroundStyle(AppConstants.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppConstants.Spacing.md) {
                SyncStatTile(
                    value: "\(favoriteModel.roomList.count)",
                    title: "收藏主播",
                    color: AppConstants.Colors.link
                )

                SyncStatTile(
                    value: "\(loggedInPlatformCount)",
                    title: "已登录平台",
                    color: AppConstants.Colors.warning
                )

                SyncStatTile(
                    value: "\(cloudPluginSourceCount)",
                    title: "订阅源",
                    color: Color.cyan
                )
            }

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
    }

    @ViewBuilder
    private var syncProgressCard: some View {
        if favoriteModel.syncStatus == .syncing {
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
    }

    private var loginInfoSyncCard: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            HStack {
                Image(systemName: hasAnyLogin ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                    .font(.title2)
                    .foregroundStyle(hasAnyLogin ? AppConstants.Colors.success.gradient : AppConstants.Colors.error.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("登录信息同步")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text(loggedInPlatformSummary)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                Spacer()
            }
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
    }

    private var accountICloudSyncCard: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            HStack {
                Image(systemName: "icloud.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cyan.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud 同步")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("手动上传或下载登录信息")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                Spacer()
            }

            if let lastSync = syncService.lastICloudSyncTime {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                    Text("上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                    Spacer()
                }
            }

            Divider()

            Button {
                Task { await prepareUploadConfirm() }
            } label: {
                ICloudSyncActionRow(
                    title: "同步到 iCloud",
                    subtitle: "上传本地登录信息到云端",
                    isLoading: isFetchingPreview,
                    systemImage: "icloud.and.arrow.up"
                )
            }
            .buttonStyle(.plain)
            .disabled(isFetchingPreview)

            Button {
                Task { await prepareDownloadConfirm() }
            } label: {
                ICloudSyncActionRow(
                    title: "从 iCloud 同步",
                    subtitle: "下载云端登录信息到本地",
                    isLoading: isFetchingPreview,
                    systemImage: "icloud.and.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .disabled(isFetchingPreview)
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
    }

    private var favoriteBackupCard: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            HStack {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title2)
                    .foregroundStyle(Color.indigo.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("备份与迁移")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("将收藏导出为 JSON 文件，或从文件导入")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                Spacer()
            }

            Divider()

            Button {
                guard !favoriteModel.roomList.isEmpty else {
                    sendResult = "当前没有收藏可导出"
                    sendSuccess = false
                    return
                }
                showExportFormatDialog = true
            } label: {
                ICloudSyncActionRow(
                    title: "导出收藏到文件",
                    subtitle: "选择 Angel Live 完整或 Simple Live 精简格式",
                    isLoading: false,
                    systemImage: "square.and.arrow.up",
                    tint: Color.indigo
                )
            }
            .buttonStyle(.plain)
            .disabled(favoriteModel.roomList.isEmpty)

            Button {
                showImporter = true
            } label: {
                ICloudSyncActionRow(
                    title: "从文件导入收藏",
                    subtitle: "支持 Angel Live / Simple Live 两种格式",
                    isLoading: isImporting,
                    systemImage: "square.and.arrow.down",
                    tint: Color.indigo
                )
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
    }

    private var clearCloudLoginInfoButton: some View {
        Button {
            showClearCloudConfirm = true
        } label: {
            HStack {
                if isClearingCloudLoginInfo {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "trash.fill")
                }
                Text(isClearingCloudLoginInfo ? "正在清理..." : "清理云端登录信息")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppConstants.Colors.error.gradient)
            .cornerRadius(AppConstants.CornerRadius.md)
        }
        .disabled(isClearingCloudLoginInfo)
    }

    private var lanSyncCard: some View {
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
                        .disabled(isSending)
                    }
                }
            } else if !isSearching {
                Text("未发现 tvOS 设备")
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .padding(.vertical, AppConstants.Spacing.sm)
            }

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
    }

    @ViewBuilder
    private var sendResultCard: some View {
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
    }

    private var usageGuideCard: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            Text("使用说明")
                .font(.headline)
                .foregroundStyle(AppConstants.Colors.primaryText)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("Wi-Fi 同步")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Label("确保 iPhone/iPad 和 Apple TV 在同一 WiFi 网络", systemImage: "1.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)

                Label("在 tvOS 设置中打开「账号管理 > 局域网同步」", systemImage: "2.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)

                Label("在此页面点击搜索并选择 tvOS 设备发送", systemImage: "3.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            Divider()

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("iCloud 同步")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppConstants.Colors.primaryText)

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

                Label("登录信息需要在此页面手动上传或下载", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.link)
            }
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
    }

    // MARK: - Status

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

    private var loggedInPlatformCount: Int {
        let serviceCount = syncService.loggedInByPluginId.values.filter { $0 }.count
        return max(loggedInPlatformNames.count, serviceCount)
    }

    private var hasAnyLogin: Bool {
        loggedInPlatformCount > 0
    }

    private var loggedInPlatformSummary: String {
        if loggedInPlatformNames.isEmpty {
            return "暂无已登录平台"
        }
        return "已登录：\(loggedInPlatformNames.joined(separator: "、"))"
    }

    private func loadLoggedInPlatformNames() async {
        let names = await syncService.getLocalAuthenticatedPlatformNames()
        await MainActor.run {
            loggedInPlatformNames = names
        }
    }

    private func loadCloudPluginSourceCount() async {
        await pluginSourceSyncService.checkCloudForSources()
        cloudPluginSourceCount = pluginSourceSyncService.syncedSourceURLs.count
    }

    // MARK: - iCloud 确认逻辑

    private func prepareUploadConfirm() async {
        isFetchingPreview = true
        defer { isFetchingPreview = false }

        let preview = await syncService.fetchCloudSyncPreview()
        let localNames = await syncService.getLocalAuthenticatedPlatformNames()

        var msg = ""
        if let lastSync = syncService.lastICloudSyncTime {
            msg += "上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))\n"
        }
        if !localNames.isEmpty {
            msg += "本地已登录: \(localNames.joined(separator: "、"))\n"
        } else {
            msg += "本地无已登录平台\n"
        }
        msg += "\n"
        if let cloudTime = preview.latestTime {
            msg += "云端同步时间: \(PlatformCredentialSyncService.formatSyncTime(cloudTime))\n"
            msg += "云端已有平台: \(preview.platformNames.joined(separator: "、"))\n"
            msg += "\n上传后云端数据将被覆盖"
        } else {
            msg += "云端暂无数据"
        }

        confirmMessage = msg
        showUploadConfirm = true
    }

    private func prepareDownloadConfirm() async {
        isFetchingPreview = true
        defer { isFetchingPreview = false }

        let preview = await syncService.fetchCloudSyncPreview()

        guard preview.latestTime != nil else {
            sendResult = "iCloud 中没有同步数据"
            sendSuccess = false
            return
        }

        let localNames = await syncService.getLocalAuthenticatedPlatformNames()

        var msg = ""
        if let lastSync = syncService.lastICloudSyncTime {
            msg += "上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))\n"
        }
        if !localNames.isEmpty {
            msg += "本地已登录: \(localNames.joined(separator: "、"))\n"
        }
        msg += "\n"
        if let cloudTime = preview.latestTime {
            msg += "云端同步时间: \(PlatformCredentialSyncService.formatSyncTime(cloudTime))\n"
        }
        if !preview.platformNames.isEmpty {
            msg += "云端平台: \(preview.platformNames.joined(separator: "、"))\n"
        }
        msg += "\n下载后本地数据将被覆盖"

        confirmMessage = msg
        showDownloadConfirm = true
    }

    /// 按同步结果展示明确反馈:成功 / 部分失败 / 失败(原因 + 错误码)。
    private func applySyncOutcome(_ outcome: OperationOutcome, successMessage: String) {
        switch outcome {
        case .success:
            sendResult = successMessage
            sendSuccess = true
        case .partial(let error):
            sendResult = "部分同步失败：\(error.displayText)"
            sendSuccess = false
        case .failure(let error):
            sendResult = "同步失败：\(error.displayText)"
            sendSuccess = false
        }
    }

    // MARK: - Bonjour

    private func toggleSearch() {
        if isSearching {
            syncService.stopBonjourBrowsing()
            isSearching = false
        } else {
            syncService.startBonjourBrowsing()
            isSearching = true
        }
    }

    private func sendToDevice(_ device: PlatformCredentialSyncService.DiscoveredDevice) async {
        isSending = true
        sendResult = nil

        let success = await syncService.sendAllToDevice(device)

        if success {
            sendResult = "已成功发送多平台登录信息到 \(device.name)"
            sendSuccess = true
        } else {
            sendResult = "发送失败，请重试"
            sendSuccess = false
        }

        isSending = false
    }

    private func clearCloudLoginInfo() async {
        isClearingCloudLoginInfo = true
        let deletedCount = await syncService.clearAllICloudSessions()
        await MainActor.run {
            sendResult = deletedCount > 0 ? "已清理云端登录信息" : "云端没有可清理的登录信息"
            sendSuccess = true
            isClearingCloudLoginInfo = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - 收藏备份

    private func prepareExport(format: FavoriteBackupFormat) {
        do {
            let data = try FavoriteBackupService.export(
                rooms: favoriteModel.roomList,
                format: format,
                deviceName: currentDeviceName()
            )
            pendingExportDocument = FavoriteBackupDocument(data: data)
            pendingExportFilename = makeBackupFilename(format: format)
            showExporter = true
        } catch {
            sendResult = "导出失败：\(error.localizedDescription)"
            sendSuccess = false
        }
    }

    private func makeBackupFilename(format: FavoriteBackupFormat) -> String {
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = timestampFormatter.string(from: Date())
        let device = currentDeviceName().replacingOccurrences(of: "/", with: "-")
        switch format {
        case .angelLive:
            return "\(format.fileNamePrefix)-\(device)-\(stamp)"
        case .simpleLive:
            return "\(format.fileNamePrefix)-\(stamp)"
        }
    }

    private func handleImportPickedFile(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            importErrorMessage = "读取文件失败：\(error.localizedDescription)"
            return
        }

        do {
            let report = try await favoriteModel.importBackup(data)
            importReport = report
            showImportResult = true
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}


private struct SyncStatTile: View {
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xs) {
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color.gradient)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppConstants.Colors.materialBackground.opacity(0.5))
        .cornerRadius(AppConstants.CornerRadius.md)
    }
}

private struct ICloudSyncActionRow: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    let systemImage: String
    var tint: Color = Color.cyan

    var body: some View {
        HStack(spacing: 12) {
            SyncIconTile {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint.gradient)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppConstants.Colors.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

private struct SyncIconTile<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppConstants.Colors.tertiaryBackground.opacity(0.55))
            content
        }
        .frame(width: 34, height: 34)
    }
}
