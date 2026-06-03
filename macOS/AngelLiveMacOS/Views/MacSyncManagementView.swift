//
//  MacSyncManagementView.swift
//  AngelLiveMacOS
//
//  设置二级页:同步管理。集中管理 iCloud 自动同步、手动上传/下载,以及云端登录信息清理。
//

import SwiftUI
import AngelLiveCore
import UniformTypeIdentifiers

struct MacSyncManagementView: View {
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var showUploadConfirm = false
    @State private var showDownloadConfirm = false
    @State private var showClearCloudConfirm = false
    @State private var iCloudConfirmMessage = ""
    @State private var isFetchingPreview = false
    @State private var iCloudSyncResult: String?
    @State private var iCloudSyncSuccess = false
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
    @State private var backupResult: String?
    @State private var backupResultSuccess = false

    var body: some View {
        Form {
            Section {
                PanelHintCard(
                    title: "iCloud 同步登录信息",
                    message: "登录的 Cookie 会通过 iCloud 同步到您其它设备,登录态不再需要重新登录。",
                    systemImage: "icloud.fill",
                    tint: .cyan
                )
            }

            Section {
                Toggle(isOn: $syncService.iCloudSyncEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.cyan.gradient)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("iCloud 自动同步")
                                .font(.body.weight(.medium))
                            Text("登录后 Cookie 自动同步到其他设备")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(AppConstants.Colors.accent)

                if let lastSync = syncService.lastICloudSyncTime {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } header: {
                Text("自动同步")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { favoriteModel.favoriteICloudSyncEnabled },
                    set: { newValue in
                        favoriteModel.favoriteICloudSyncEnabled = newValue
                        if newValue { Task { await favoriteModel.syncWithActor() } }
                    }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.orange.gradient)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("收藏 iCloud 同步")
                                .font(.body.weight(.medium))
                            Text("关闭后收藏仅保存在本机")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(AppConstants.Colors.accent)

                if let syncError = favoriteModel.lastSyncError {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.red)
                        Text("收藏同步失败：\(syncError.displayText)")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            } header: {
                Text("收藏同步")
            }

            favoriteBackupSection

            if syncService.iCloudSyncEnabled {
                Section {
                    Button {
                        Task { await prepareUploadConfirm() }
                    } label: {
                        PanelNavigationRow(
                            title: "同步到 iCloud",
                            subtitle: "上传本地登录信息到云端"
                        ) {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.cyan.gradient)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingPreview)

                    Button {
                        Task { await prepareDownloadConfirm() }
                    } label: {
                        PanelNavigationRow(
                            title: "从 iCloud 同步",
                            subtitle: "下载云端登录信息到本地"
                        ) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.cyan.gradient)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingPreview)

                    if let result = iCloudSyncResult {
                        HStack(spacing: 6) {
                            Image(systemName: iCloudSyncSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(iCloudSyncSuccess ? AppConstants.Colors.success : .red)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(iCloudSyncSuccess ? AppConstants.Colors.success : .red)
                        }
                    }
                } header: {
                    Text("手动同步")
                } footer: {
                    Text("上传或下载会覆盖目标侧的登录信息,执行前会展示对比预览。")
                }

                Section {
                    Button(role: .destructive) {
                        showClearCloudConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isClearingCloudLoginInfo ? "正在清理..." : "清理云端登录信息")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.red)
                                Text("仅清理 iCloud 中保存的登录信息,不影响本机")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isClearingCloudLoginInfo {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearingCloudLoginInfo)
                } header: {
                    Text("清理")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("同步管理")
        .task {
            await syncService.refreshAllLoginStatus()
        }
        .alert("同步到 iCloud", isPresented: $showUploadConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定上传") {
                Task {
                    let outcome = await syncService.syncAllToICloud()
                    await MainActor.run {
                        applySyncOutcome(outcome, successMessage: "已同步到 iCloud")
                    }
                }
            }
        } message: {
            Text(iCloudConfirmMessage)
        }
        .alert("从 iCloud 同步", isPresented: $showDownloadConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定下载") {
                Task {
                    let outcome = await syncService.syncAllFromICloud()
                    await MainActor.run {
                        applySyncOutcome(outcome, successMessage: "已从 iCloud 同步到本地")
                    }
                }
            }
        } message: {
            Text(iCloudConfirmMessage)
        }
        .alert("清理云端登录信息", isPresented: $showClearCloudConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定清理", role: .destructive) {
                Task { await clearCloudLoginInfo() }
            }
        } message: {
            Text("确定要清理 iCloud 中保存的所有平台登录信息吗?此操作不会退出本机账号,但其他设备将无法再从 iCloud 下载这些登录信息。")
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
                backupResult = "已导出收藏文件"
                backupResultSuccess = true
            case .failure(let error):
                backupResult = "导出失败：\(error.localizedDescription)"
                backupResultSuccess = false
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
                .frame(minWidth: 460, minHeight: 420)
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

    // MARK: - Favorite Backup Section

    @ViewBuilder
    private var favoriteBackupSection: some View {
        Section {
            Button {
                guard !favoriteModel.roomList.isEmpty else {
                    backupResult = "当前没有收藏可导出"
                    backupResultSuccess = false
                    return
                }
                showExportFormatDialog = true
            } label: {
                PanelNavigationRow(
                    title: "导出收藏到文件",
                    subtitle: "选择 Angel Live 完整或 Simple Live 精简格式"
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.indigo.gradient)
                }
            }
            .buttonStyle(.plain)
            .disabled(favoriteModel.roomList.isEmpty)

            Button {
                showImporter = true
            } label: {
                PanelNavigationRow(
                    title: "从文件导入收藏",
                    subtitle: "支持 Angel Live / Simple Live 两种格式"
                ) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.indigo.gradient)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            if let result = backupResult {
                HStack(spacing: 6) {
                    Image(systemName: backupResultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(backupResultSuccess ? AppConstants.Colors.success : .red)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(backupResultSuccess ? AppConstants.Colors.success : .red)
                }
            }
        } header: {
            Text("备份与迁移")
        } footer: {
            Text("将收藏导出为 JSON 文件以备份或迁移到其他设备；导入时按平台+用户去重，不会覆盖现有收藏。")
        }
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
            backupResult = "导出失败：\(error.localizedDescription)"
            backupResultSuccess = false
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

    @MainActor
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

    /// 按同步结果展示明确反馈:成功 / 部分失败 / 失败(原因 + 错误码)。
    private func applySyncOutcome(_ outcome: OperationOutcome, successMessage: String) {
        switch outcome {
        case .success:
            iCloudSyncResult = successMessage
            iCloudSyncSuccess = true
        case .partial(let error):
            iCloudSyncResult = "部分同步失败：\(error.displayText)"
            iCloudSyncSuccess = false
        case .failure(let error):
            iCloudSyncResult = "同步失败：\(error.displayText)"
            iCloudSyncSuccess = false
        }
    }

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

        iCloudConfirmMessage = msg
        showUploadConfirm = true
    }

    private func prepareDownloadConfirm() async {
        isFetchingPreview = true
        defer { isFetchingPreview = false }

        let preview = await syncService.fetchCloudSyncPreview()

        guard preview.latestTime != nil else {
            iCloudSyncResult = "iCloud 中没有同步数据"
            iCloudSyncSuccess = false
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

        iCloudConfirmMessage = msg
        showDownloadConfirm = true
    }

    private func clearCloudLoginInfo() async {
        isClearingCloudLoginInfo = true
        let deletedCount = await syncService.clearAllICloudSessions()
        await MainActor.run {
            iCloudSyncResult = deletedCount > 0 ? "已清理云端登录信息" : "云端没有可清理的登录信息"
            iCloudSyncSuccess = true
            isClearingCloudLoginInfo = false
        }
    }
}
