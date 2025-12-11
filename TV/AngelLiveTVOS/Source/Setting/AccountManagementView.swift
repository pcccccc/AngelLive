//
//  AccountManagementView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/11/28.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

// MARK: - Bilibili 用户信息模型 (tvOS)

struct BilibiliUserInfoTV: Codable {
    let mid: Int?
    let uname: String?
    let userid: String?
    let sign: String?
    let birthday: String?
    let sex: String?
    let rank: String?
    let face: String?
    let nickFree: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, uname, userid, sign, birthday, sex, rank, face
        case nickFree = "nick_free"
    }

    var displayName: String {
        uname ?? "未知用户"
    }
}

struct BilibiliUserInfoResponseTV: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: BilibiliUserInfoTV?

    enum CodingKeys: String, CodingKey {
        case code, message, ttl, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)
        data = try container.decodeIfPresent(BilibiliUserInfoTV.self, forKey: .data)
    }
}

// MARK: - 账号管理主视图

struct AccountManagementView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore

    @State private var currentPage: AccountPage = .main

    enum AccountPage {
        case main
        case bilibiliDetail
        case lanSync
        case manualInput
    }

    var body: some View {
        ZStack {
            switch currentPage {
            case .main:
                accountMainView
                    .transition(.opacity)
            case .bilibiliDetail:
                if syncService.isLoggedIn {
                    BilibiliLoggedInPageView(onBack: { currentPage = .main })
                        .environmentObject(settingStore)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    BilibiliLoginOptionsPageView(
                        onBack: { currentPage = .main },
                        onLanSync: { currentPage = .lanSync },
                        onManualInput: { currentPage = .manualInput }
                    )
                    .environmentObject(settingStore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            case .lanSync:
                BilibiliLANSyncPageView(onBack: { currentPage = .bilibiliDetail })
                    .environmentObject(settingStore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .manualInput:
                BilibiliManualInputPageView(onBack: { currentPage = .bilibiliDetail })
                    .environmentObject(settingStore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentPage)
    }

    // MARK: - 主页面（平台列表）
    private var accountMainView: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("直播平台")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 50)
                .padding(.top, 50)

                Button {
                    currentPage = .bilibiliDetail
                } label: {
                    HStack {
                        Image("live_card_bili")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .cornerRadius(10)
                        Text("哔哩哔哩")
                            .font(.system(size: 32))
                        Spacer()
                        Text(syncService.isLoggedIn ? "已登录" : "未登录")
                            .font(.system(size: 28))
                            .foregroundStyle(syncService.isLoggedIn ? .green : .gray)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.card)
                .padding(.horizontal, 50)

                Spacer()
            }
        }
    }
}

// MARK: - 已登录页面视图

struct BilibiliLoggedInPageView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    let onBack: () -> Void

    @State private var userInfo: BilibiliUserInfoTV?
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showLogoutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 用户信息卡片
                VStack(spacing: 16) {
                    if isValidating {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在验证...")
                            .font(.headline)
                    } else if let user = userInfo {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text(user.displayName)
                            .font(.title2.bold())
                        if let mid = user.mid {
                            Text("UID: \(mid)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = validationError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)
                        Text("验证失败")
                            .font(.title2)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        Text("已登录")
                            .font(.title2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal, 50)
                .padding(.top, 50)

                HStack {
                    Text("账号操作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 50)
                .padding(.top, 10)

                Button {
                    Task { await validateCookie() }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 24))
                            .frame(width: 40)
                        Text("验证 Cookie")
                        Spacer()
                        if isValidating {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .padding(.horizontal, 50)
                .disabled(isValidating)

                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 24))
                            .frame(width: 40)
                        Text("退出登录")
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .padding(.horizontal, 50)

                Divider()
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)

                HStack {
                    Text("iCloud 同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 50)

                Toggle(isOn: $syncService.iCloudSyncEnabled) {
                    Text("iCloud 自动同步")
                }
                .padding(.horizontal, 50)
                .frame(height: 60)

                if syncService.iCloudSyncEnabled {
                    Button {
                        Task {
                            _ = await syncService.syncFromICloud()
                            await validateCookie()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            Text("立即从 iCloud 同步")
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.card)
                    .padding(.horizontal, 50)
                }

                Spacer()
            }
        }
        .onExitCommand {
            onBack()
        }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) { logout() }
        } message: {
            Text("确定要退出哔哩哔哩登录吗？")
        }
        .task {
            await validateCookie()
        }
    }

    private func validateCookie() async {
        isValidating = true
        validationError = nil

        let cookie = syncService.getCurrentCookie()
        guard !cookie.isEmpty else {
            validationError = "Cookie 为空"
            isValidating = false
            return
        }

        guard let url = URL(string: "https://api.bilibili.com/x/member/web/account") else {
            validationError = "无效的 URL"
            isValidating = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BilibiliUserInfoResponseTV.self, from: data)

            if response.code == 0, let info = response.data {
                userInfo = info
                validationError = nil
                if let mid = info.mid {
                    let cookie = syncService.getCurrentCookie()
                    syncService.setCookie(cookie, uid: "\(mid)", source: .local, save: false)
                }
            } else {
                userInfo = nil
                validationError = response.message ?? "Cookie 已失效 (code: \(response.code))"
            }
        } catch {
            userInfo = nil
            validationError = "网络错误: \(error.localizedDescription)"
        }

        isValidating = false
    }

    private func logout() {
        syncService.clearCookie()
        if syncService.iCloudSyncEnabled {
            syncService.syncToICloud()
        }
        settingStore.bilibiliCookie = ""
        userInfo = nil
        validationError = nil
    }
}

// MARK: - 登录选项页面视图

struct BilibiliLoginOptionsPageView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    let onBack: () -> Void
    let onLanSync: () -> Void
    let onManualInput: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("登录方式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 50)
                .padding(.top, 50)

                Button {
                    onLanSync()
                } label: {
                    HStack {
                        Image(systemName: "wifi")
                            .font(.system(size: 24))
                            .frame(width: 40)
                        Text("局域网同步")
                        Spacer()
                        Text("推荐")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .padding(.horizontal, 50)

                Button {
                    onManualInput()
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .font(.system(size: 24))
                            .frame(width: 40)
                        Text("手动输入 Cookie")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.card)
                .padding(.horizontal, 50)

                Divider()
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)

                HStack {
                    Text("iCloud 同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 50)

                Toggle(isOn: $syncService.iCloudSyncEnabled) {
                    Text("iCloud 自动同步")
                }
                .padding(.horizontal, 50)
                .frame(height: 60)

                if syncService.iCloudSyncEnabled {
                    Button {
                        Task {
                            _ = await syncService.syncFromICloud()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            Text("立即从 iCloud 同步")
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.card)
                    .padding(.horizontal, 50)
                }

                Spacer()
            }
        }
        .onExitCommand {
            onBack()
        }
    }
}

// MARK: - 局域网同步页面视图

struct BilibiliLANSyncPageView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    let onBack: () -> Void

    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 状态区域
                VStack(spacing: 20) {
                    if isSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        Text("同步成功")
                            .font(.title2.bold())
                        Text("Cookie 已保存")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                .padding(.vertical, 50)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal, 50)
                .padding(.top, 50)

                // 操作步骤
                VStack(alignment: .leading, spacing: 16) {
                    Text("操作步骤")
                        .font(.headline)

                    StepRow(number: 1, text: "确保 Apple TV 和 iOS 在同一 Wi-Fi 网络")
                    StepRow(number: 2, text: "在 iOS 端 Angel Live 中登录哔哩哔哩")
                    StepRow(number: 3, text: "点击「同步到 tvOS」按钮")
                    StepRow(number: 4, text: "选择此 Apple TV 设备")
                }
                .padding(.horizontal, 50)
                .padding(.top, 20)

                Spacer()
            }
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
        .onChange(of: syncService.isLoggedIn) { _, newValue in
            if newValue && syncService.lastSyncedData?.source == .bonjour {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await MainActor.run {
                        isSuccess = true
                        settingStore.bilibiliCookie = syncService.getCurrentCookie()
                    }
                }
            }
        }
    }
}

// MARK: - 手动输入页面视图

struct BilibiliManualInputPageView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    let onBack: () -> Void

    @State private var cookieInput = ""
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isSuccess {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        Text("设置成功")
                            .font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal, 50)
                    .padding(.top, 50)
                } else {
                    // 输入区域
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("请输入 Cookie 字符串", text: $cookieInput)
                            .padding(.top, 50)

                        if let message = validationMessage {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }

                        Button {
                            Task { await validateAndSave() }
                        } label: {
                            HStack {
                                if isValidating {
                                    ProgressView()
                                        .frame(width: 40)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 24))
                                        .frame(width: 40)
                                }
                                Text("验证并保存")
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.card)
                        .disabled(cookieInput.isEmpty || isValidating)
                    }
                    .padding(.horizontal, 50)

                    Divider()
                        .padding(.horizontal, 50)
                        .padding(.vertical, 20)

                    // 帮助信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("如何获取 Cookie")
                            .font(.headline)

                        Text("1. 在电脑浏览器中登录 bilibili.com")
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
                    }
                    .padding(.horizontal, 50)
                }

                Spacer()
            }
        }
        .onExitCommand {
            onBack()
        }
    }

    private func validateAndSave() async {
        isValidating = true
        validationMessage = nil

        let result = await syncService.setManualCookie(cookieInput)

        switch result {
        case .valid:
            settingStore.bilibiliCookie = cookieInput
            isSuccess = true
        case .invalid(let reason):
            validationMessage = "Cookie 无效: \(reason)"
        case .expired:
            validationMessage = "Cookie 已过期"
        case .networkError(let error):
            validationMessage = "网络错误: \(error.localizedDescription)"
        }

        isValidating = false
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
