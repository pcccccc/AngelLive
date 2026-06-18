//
//  SyncManagementView.swift
//  AngelLiveTVOS
//
//  设置二级页:同步管理。三端对齐 iOS / macOS 的「同步管理」结构,集中管理:
//   - iCloud 自动同步登录态(开关 + 上传/下载 + 清理)
//   - 收藏 iCloud 同步
//   - 局域网同步(接收端,等待 iOS / macOS 推送)
//   - Simple Live 同步(扫码协议,给安卓 Simple Live 用,沿用老 SyncView)
//
//  视觉上对齐 AccountManagementView:半屏容器、纯文字行 + 状态 + chevron、二级详情页处理操作。
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

// MARK: - 同步管理主视图

struct SyncManagementView: View {
    @Environment(AppState.self) private var appViewModel
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var currentPage: SyncPage = .main
    /// Simple Live 老扫码同步页内部硬编码了 1920×1080,半屏宽度容不下,
    /// 走 fullScreenCover 让它盖掉半屏容器和左侧 logo。
    @State private var showSimpleLiveCover = false

    enum SyncPage: Equatable {
        case main
        case lanSync
        case iCloud
        case favorite
    }

    var body: some View {
        ZStack {
            switch currentPage {
            case .main:
                mainView
                    .transition(.opacity)
            case .lanSync:
                LANSyncPageView(onBack: { currentPage = .main })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .iCloud:
                ICloudSyncDetailView(onBack: { currentPage = .main })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .favorite:
                FavoriteSyncDetailView(onBack: { currentPage = .main })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentPage)
        .fullScreenCover(isPresented: $showSimpleLiveCover) {
            SyncView()
                .environment(appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand { showSimpleLiveCover = false }
        }
    }

    // MARK: - 主页面

    private var mainView: some View {
        // 半屏容器内容会溢出,套 ScrollView 让 tvOS 焦点引擎自动滚动。
        // scrollClipDisabled: tvOS Button 聚焦时会放大,默认 ScrollView 会裁掉左右溢出部分。
        ScrollView {
            VStack(spacing: 15) {
                sectionHeader("登录信息同步")

                // 局域网同步:推荐路径
                Button {
                    currentPage = .lanSync
                } label: {
                    HStack(spacing: 15) {
                        Text("局域网同步")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("推荐")
                            .font(.system(size: 30))
                            .foregroundStyle(.green)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                // iCloud 同步:开关状态展示在右侧
                Button {
                    currentPage = .iCloud
                } label: {
                    HStack(spacing: 15) {
                        Text("iCloud 同步")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(syncService.iCloudSyncEnabled ? "已开启" : "已关闭")
                            .font(.system(size: 30))
                            .foregroundStyle(syncService.iCloudSyncEnabled ? .green : .gray)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                sectionHeader("收藏同步")

                // 收藏 iCloud 同步:开关状态展示在右侧
                Button {
                    currentPage = .favorite
                } label: {
                    HStack(spacing: 15) {
                        Text("收藏 iCloud 同步")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(appViewModel.favoriteViewModel.favoriteICloudSyncEnabled ? "已开启" : "已关闭")
                            .font(.system(size: 30))
                            .foregroundStyle(appViewModel.favoriteViewModel.favoriteICloudSyncEnabled ? .green : .gray)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                sectionHeader("其他设备")

                // Simple Live 同步:扫码协议,留给安卓 Simple Live 用户。
                Button {
                    showSimpleLiveCover = true
                } label: {
                    HStack(spacing: 15) {
                        Text("Simple Live 同步")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("扫码")
                            .font(.system(size: 30))
                            .foregroundStyle(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 200)
            }
        }
        .scrollClipDisabled()
        .task {
            await syncService.refreshAllLoginStatus()
        }
    }

    // MARK: - 分组标题

    /// 半屏列表里的分组标题,跟 AccountManagementView 用同一规格,保持视觉一致。
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 10)
    }
}

// MARK: - iCloud 同步详情页

struct ICloudSyncDetailView: View {
    let onBack: () -> Void

    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var showUploadConfirm = false
    @State private var showDownloadConfirm = false
    @State private var showClearCloudConfirm = false
    @State private var iCloudConfirmMessage = ""
    @State private var isFetchingPreview = false
    @State private var isClearingCloudLoginInfo = false
    @State private var clearResultMessage: String?
    @State private var iCloudSyncResultMessage: String?
    @State private var iCloudSyncResultSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                Spacer(minLength: 10)

                // 状态显示区域,跟 PlatformDetailPageView.statusSection 同款大图标
                statusSection
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)

                // 自动同步开关
                Toggle(isOn: $syncService.iCloudSyncEnabled) {
                    Text("iCloud 自动同步")
                }

                if syncService.iCloudSyncEnabled {
                    if let lastSync = syncService.lastICloudSyncTime {
                        HStack(spacing: 15) {
                            Text("上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }

                    Button {
                        Task { await prepareUploadConfirm() }
                    } label: {
                        HStack {
                            Text("同步到 iCloud")
                                .foregroundColor(.primary)
                            Spacer()
                            if isFetchingPreview { ProgressView() }
                        }
                    }
                    .disabled(isFetchingPreview)

                    Button {
                        Task { await prepareDownloadConfirm() }
                    } label: {
                        HStack {
                            Text("从 iCloud 下载")
                                .foregroundColor(.primary)
                            Spacer()
                            if isFetchingPreview { ProgressView() }
                        }
                    }
                    .disabled(isFetchingPreview)

                    if let syncResult = iCloudSyncResultMessage {
                        HStack(spacing: 15) {
                            Image(systemName: iCloudSyncResultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(iCloudSyncResultSuccess ? .green : .red)
                            Text(syncResult)
                                .font(.system(size: 28))
                                .foregroundStyle(iCloudSyncResultSuccess ? .green : .red)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }

                    Button(role: .destructive) {
                        showClearCloudConfirm = true
                    } label: {
                        HStack {
                            Text(isClearingCloudLoginInfo ? "正在清理..." : "清理云端登录信息")
                                .foregroundColor(.primary)
                            Spacer()
                            if isClearingCloudLoginInfo { ProgressView() }
                        }
                    }
                    .disabled(isClearingCloudLoginInfo)

                    if let result = clearResultMessage {
                        HStack(spacing: 15) {
                            Text(result)
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                }

                Spacer(minLength: 100)
            }
        }
        .scrollClipDisabled()
        .onExitCommand { onBack() }
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
            Text("确定要清理 iCloud 中保存的所有平台登录信息吗？此操作不会退出本机账号，但其他设备将无法再从 iCloud 下载这些登录信息。")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 16) {
            if syncService.iCloudSyncEnabled {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.cyan)
                Text("iCloud 同步已开启")
                    .font(.title2)
                Text("登录后 Cookie 自动同步到其他设备")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("iCloud 同步已关闭")
                    .font(.title2)
                Text("仅在本机保留登录信息")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 按同步结果展示明确反馈:成功 / 部分失败 / 失败(原因 + 错误码)。
    private func applySyncOutcome(_ outcome: OperationOutcome, successMessage: String) {
        switch outcome {
        case .success:
            iCloudSyncResultMessage = successMessage
            iCloudSyncResultSuccess = true
        case .partial(let error):
            iCloudSyncResultMessage = "部分同步失败：\(error.displayText)"
            iCloudSyncResultSuccess = false
        case .failure(let error):
            iCloudSyncResultMessage = "同步失败：\(error.displayText)"
            iCloudSyncResultSuccess = false
        }
    }

    private func clearCloudLoginInfo() async {
        isClearingCloudLoginInfo = true
        clearResultMessage = nil
        let deletedCount = await syncService.clearAllICloudSessions()
        await MainActor.run {
            clearResultMessage = deletedCount > 0 ? "已清理云端登录信息" : "云端没有可清理的登录信息"
            isClearingCloudLoginInfo = false
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
            iCloudSyncResultMessage = "iCloud 中没有同步数据"
            iCloudSyncResultSuccess = false
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
}

// MARK: - 收藏同步详情页

struct FavoriteSyncDetailView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var appViewModel

    var body: some View {
        VStack(spacing: 15) {
            Spacer(minLength: 10)

            statusSection
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            Toggle(isOn: Binding(
                get: { appViewModel.favoriteViewModel.favoriteICloudSyncEnabled },
                set: { newValue in
                    appViewModel.favoriteViewModel.favoriteICloudSyncEnabled = newValue
                    if newValue {
                        Task { await appViewModel.favoriteViewModel.syncWithActor() }
                    }
                }
            )) {
                Text("收藏 iCloud 同步")
            }

            if appViewModel.favoriteViewModel.favoriteICloudSyncEnabled,
               let syncError = appViewModel.favoriteViewModel.lastSyncError {
                HStack(spacing: 15) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.red)
                    Text("同步失败：\(syncError.displayText)")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.vertical, 5)
            }

            Spacer(minLength: 200)
        }
        .onExitCommand { onBack() }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 16) {
            if appViewModel.favoriteViewModel.favoriteICloudSyncEnabled {
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("收藏会同步到 iCloud")
                    .font(.title2)
                Text(appViewModel.favoriteViewModel.syncStatusDisplayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "star.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("收藏仅保存在本机")
                    .font(.title2)
                Text("关闭后其他设备看不到本机的收藏")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SyncManagementView()
        .environment(AppState())
}
