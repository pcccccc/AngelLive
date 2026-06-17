//
//  AccountManagementView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/11/28.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

// MARK: - 账号管理主视图

struct AccountManagementView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var platforms: [LoginPlatformEntry] = []
    @State private var currentPage: AccountPage = .main

    // iCloud 确认弹窗
    @State private var showUploadConfirm = false
    @State private var showDownloadConfirm = false
    @State private var showClearCloudConfirm = false
    @State private var iCloudConfirmMessage = ""
    @State private var isFetchingPreview = false
    @State private var isClearingCloudLoginInfo = false
    @State private var clearResultMessage: String?
    @State private var iCloudSyncResultMessage: String?
    @State private var iCloudSyncResultSuccess = false

    enum AccountPage: Equatable {
        case main
        case platformDetail(LoginPlatformEntry)
        case lanSync
        case manualInput(LoginPlatformEntry)

        static func == (lhs: AccountPage, rhs: AccountPage) -> Bool {
            switch (lhs, rhs) {
            case (.main, .main): return true
            case (.lanSync, .lanSync): return true
            case (.platformDetail(let a), .platformDetail(let b)): return a.pluginId == b.pluginId
            case (.manualInput(let a), .manualInput(let b)): return a.pluginId == b.pluginId
            default: return false
            }
        }
    }

    var body: some View {
        ZStack {
            switch currentPage {
            case .main:
                accountMainView
                    .transition(.opacity)
            case .platformDetail(let entry):
                PlatformDetailPageView(
                    entry: entry,
                    onBack: {
                        currentPage = .main
                    },
                    onManualInput: { e in
                        currentPage = .manualInput(e)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .lanSync:
                LANSyncPageView(onBack: { currentPage = .main })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .manualInput(let entry):
                PlatformManualInputPageView(
                    entry: entry,
                    onBack: { currentPage = .platformDetail(entry) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentPage)
    }

    // MARK: - 主页面

    private var accountMainView: some View {
        // 平台列表 + iCloud 同步控件加起来在半屏容器里会溢出,套 ScrollView 让 tvOS 焦点引擎自动滚动。
        // scrollClipDisabled: tvOS Button 聚焦时会放大,默认 ScrollView 会裁掉左右溢出部分,关掉裁剪让放大动画完整显示。
        ScrollView {
            VStack(spacing: 15) {
                sectionHeader("登录同步")

                // 局域网同步
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

            Toggle(isOn: $syncService.iCloudSyncEnabled) {
                Text("iCloud 自动同步")
            }

            if syncService.iCloudSyncEnabled {
                // 上次同步时间
                if let lastSync = syncService.lastICloudSyncTime {
                    HStack(spacing: 15) {
                        Text("上次同步: \(PlatformCredentialSyncService.formatSyncTime(lastSync))")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }

                // 上传 / 下载并排,减少半屏内的纵向高度
                HStack(spacing: 20) {
                    Button {
                        Task { await prepareUploadConfirm() }
                    } label: {
                        HStack(spacing: 12) {
                            if isFetchingPreview { ProgressView() }
                            Text("同步到 iCloud")
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isFetchingPreview)

                    Button {
                        Task { await prepareDownloadConfirm() }
                    } label: {
                        HStack(spacing: 12) {
                            if isFetchingPreview { ProgressView() }
                            Text("从 iCloud 下载")
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isFetchingPreview)
                }

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
                    HStack(spacing: 15) {
                        Text(isClearingCloudLoginInfo ? "正在清理..." : "清理云端登录信息")
                            .foregroundColor(.primary)
                        Spacer()
                        if isClearingCloudLoginInfo {
                            ProgressView()
                        }
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

            sectionHeader("平台账号")

            // 平台列表
            ForEach(platforms) { entry in
                Button {
                    currentPage = .platformDetail(entry)
                } label: {
                    HStack(spacing: 15) {
                        Text(entry.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(loginStatusText(for: entry))
                            .font(.system(size: 30))
                            .foregroundStyle(loginStatusColor(for: entry))
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

                Spacer(minLength: 200)
            }
        }
        .scrollClipDisabled()
        .task {
            platforms = await PlatformLoginRegistry.shared.availablePlatforms()
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
            Text("确定要清理 iCloud 中保存的所有平台登录信息吗？此操作不会退出本机账号，但其他设备将无法再从 iCloud 下载这些登录信息。")
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

    // MARK: - 登录状态辅助方法

    private func loginStatusText(for entry: LoginPlatformEntry) -> String {
        syncService.isLoggedIn(pluginId: entry.pluginId) ? "已登录" : "未登录"
    }

    private func loginStatusColor(for entry: LoginPlatformEntry) -> Color {
        syncService.isLoggedIn(pluginId: entry.pluginId) ? .green : .gray
    }

    // MARK: - 分组标题

    /// 半屏列表里的分组标题,用层次替代一堵平铺的按钮墙。
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 10)
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

        iCloudConfirmMessage = msg
        showUploadConfirm = true
    }

    private func prepareDownloadConfirm() async {
        isFetchingPreview = true
        defer { isFetchingPreview = false }

        let preview = await syncService.fetchCloudSyncPreview()

        guard preview.latestTime != nil else {
            // 无云端数据，不弹确认
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

// MARK: - 平台详情页面

struct PlatformDetailPageView: View {
    let entry: LoginPlatformEntry
    let onBack: () -> Void
    let onManualInput: (LoginPlatformEntry) -> Void

    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var isLoggedIn = false
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var showLogoutConfirm = false

    /// 是否支持服务端 Cookie 验证
    private var supportsValidation: Bool {
        entry.auth?.supportsValidation ?? false
    }

    var body: some View {
        VStack(spacing: 15) {
            Spacer()

            // 状态显示区域
            statusSection
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            // 已登录时的操作
            if isLoggedIn {
                // 支持验证的平台：验证 Cookie
                if supportsValidation {
                    Button {
                        Task { await validateCookie() }
                    } label: {
                        HStack {
                            Text("验证 Cookie")
                                .foregroundColor(.primary)
                            Spacer()
                            if isValidating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isValidating)
                }

                // 退出登录
                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Text("退出登录")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }

            // 手动输入 Cookie（始终可用）
            Button {
                onManualInput(entry)
            } label: {
                HStack {
                    Text("手动输入 Cookie")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 200)
        }
        .onExitCommand { onBack() }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) { logout() }
        } message: {
            Text("确定要退出\(entry.displayName)登录吗？")
        }
        .task {
            await refreshStatus()
        }
    }

    // MARK: - 状态显示

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 16) {
            if isValidating {
                ProgressView()
                    .scaleEffect(1.5)
                Text("正在验证...")
                    .font(.headline)
            } else if let error = validationMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("验证失败")
                    .font(.title2)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isLoggedIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("已登录")
                    .font(.title2)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("未登录")
                    .font(.title2)
            }
        }
    }

    // MARK: - 状态刷新

    private func refreshStatus() async {
        await syncService.refreshLoginStatus(pluginId: entry.pluginId)
        isLoggedIn = syncService.isLoggedIn(pluginId: entry.pluginId)
        if isLoggedIn && supportsValidation {
            await validateCookie()
        }
    }

    // MARK: - Cookie 验证

    private func validateCookie() async {
        isValidating = true
        validationMessage = nil

        let result = await PlatformSessionManager.shared.validateSession(pluginId: entry.pluginId)

        switch result {
        case .valid:
            validationMessage = nil
        case .invalid(let reason):
            validationMessage = "Cookie 无效: \(reason)"
        case .expired:
            validationMessage = "Cookie 已过期"
        case .networkError(let message):
            validationMessage = "网络错误: \(message)"
        }

        isValidating = false
    }

    // MARK: - 退出登录

    private func logout() {
        Task {
            await syncService.clearSession(pluginId: entry.pluginId)
        }
        isLoggedIn = false
        validationMessage = nil
    }
}

// MARK: - 通用手动输入页面

struct PlatformManualInputPageView: View {
    let entry: LoginPlatformEntry
    let onBack: () -> Void

    @Environment(AppState.self) private var appViewModel
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var cookieInput = ""
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var isSuccess = false

    /// 网站域名（从 manifest 获取，可能为 nil）
    private var websiteHost: String {
        entry.loginFlow.websiteHost ?? entry.pluginId
    }

    /// Cookie 格式提示（从 manifest 获取）
    private var requiredCookieHint: String {
        entry.loginFlow.requiredCookieHint ?? "需包含有效的登录 Cookie"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 80) {
            // 左侧：输入区域
            VStack(alignment: .leading, spacing: 15) {
                Spacer()

                if isSuccess {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        Text("设置成功")
                            .font(.title2.bold())
                        Button {
                            onBack()
                        } label: {
                            Text("完成")
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    Text("手动输入 \(entry.displayName) Cookie")
                        .font(.system(size: 38, weight: .bold))

                    TextField("请输入 \(entry.displayName) Cookie 字符串", text: $cookieInput)
                        .frame(maxWidth: 700, alignment: .leading)

                    if let message = validationMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }

                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        HStack {
                            Text("验证并保存")
                                .foregroundColor(.primary)
                            Spacer()
                            if isValidating {
                                ProgressView()
                            }
                        }
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .disabled(cookieInput.isEmpty || isValidating)

                    // 帮助信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("如何获取 Cookie")
                            .font(.headline)

                        Text("1. 在电脑浏览器中登录 \(websiteHost)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("2. 按 F12 打开开发者工具")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("3. 切换到 Network (网络) 标签")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("4. 刷新页面，点击任意请求")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("5. 在 Headers 中找到 Cookie 字段并复制")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("提示：\(requiredCookieHint)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                }

                Spacer(minLength: 100)
            }
            .frame(maxWidth: 900, alignment: .leading)

            // 右侧：远程输入二维码
            cookieRemoteInputQRPanel
        }
        .padding(80)
        .safeAreaPadding()
        .onExitCommand {
            onBack()
        }
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent,
                  event.field == .cookie else { return }
            cookieInput = event.value
            Task { await validateAndSave() }
        }
    }

    // MARK: - 远程输入二维码面板

    private var cookieRemoteInputQRPanel: some View {
        let service = appViewModel.remoteInputService
        let platformEncoded = entry.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.displayName
        let hintEncoded = requiredCookieHint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = "http://\(service.localIPAddress):\(service.port)/cookie?platform=\(platformEncoded)&hint=\(hintEncoded)"
        return VStack(spacing: 16) {
            Spacer()
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 18)

                Text("扫码用手机输入")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("在手机上粘贴 Cookie 更方便")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                Text("正在启动远程输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func validateAndSave() async {
        isValidating = true
        validationMessage = nil

        let result = await syncService.setManualCookie(pluginId: entry.pluginId, cookie: cookieInput)
        switch result {
        case .valid:
            isSuccess = true
        case .invalid(let reason):
            validationMessage = "Cookie 无效: \(reason)"
        case .expired:
            validationMessage = "Cookie 已过期"
        case .networkError(let message):
            validationMessage = "网络错误: \(message)"
        }

        isValidating = false
    }
}

// MARK: - 局域网同步页面视图

struct LANSyncPageView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    let onBack: () -> Void

    @State private var isSuccess = false
    @State private var syncedPlatformSummary = ""

    var body: some View {
        VStack(spacing: 15) {
            Spacer()

            // 状态区域
            VStack(spacing: 20) {
                if isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("同步成功")
                        .font(.title2.bold())
                    Text(syncedPlatformSummary.isEmpty ? "登录信息已保存" : syncedPlatformSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button {
                        onBack()
                    } label: {
                        Text("完成")
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 20)
                } else {
                    Image(systemName: "wifi")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    Text("等待连接...")
                        .font(.title2.bold())
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

            // 操作步骤
            VStack(alignment: .leading, spacing: 16) {
                Text("操作步骤")
                    .font(.headline)

                StepRow(number: 1, text: "确保 Apple TV 和 iOS 在同一 Wi-Fi 网络")
                StepRow(number: 2, text: "在 iOS/macOS 端 Angel Live 中登录平台账号")
                StepRow(number: 3, text: "点击「同步到 tvOS」按钮")
                StepRow(number: 4, text: "选择此 Apple TV 设备")
            }
            .padding(.top, 20)

            Button {
                onBack()
            } label: {
                HStack {
                    Text("返回")
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 200)
        }
        .onExitCommand {
            onBack()
        }
        .task {
            syncService.startBonjourListener()
        }
        .onDisappear {
            syncService.stopBonjourListener()
        }
        .onChange(of: syncService.lastBonjourSyncAt) { _, newValue in
            guard newValue != nil else { return }
            syncedPlatformSummary = platformSummary(syncService.lastBonjourSyncedPlatformIds)
            isSuccess = true
        }
    }

    private func platformSummary(_ pluginIds: [String]) -> String {
        guard !pluginIds.isEmpty else { return "登录信息已保存" }

        // 动态查找平台名称：从注册表获取 displayName
        let names: [String] = pluginIds.compactMap { pluginId in
            // 尝试通过 LiveType 获取名称（同步方式 fallback）
            if let liveType = LiveType(rawValue: pluginId) {
                return LiveParseTools.getLivePlatformName(liveType)
            }
            return pluginId
        }

        guard !names.isEmpty else { return "登录信息已保存" }
        return "已保存：\(names.joined(separator: "、"))"
    }
}

// MARK: - 辅助视图

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 15) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)

            Spacer()
        }
    }
}

#Preview {
    AccountManagementView()
}
