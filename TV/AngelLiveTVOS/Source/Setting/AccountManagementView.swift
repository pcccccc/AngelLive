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

    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧图标区
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 400, height: 400)
                    Text("账号管理")
                        .font(.headline)
                        .padding(.top, 30)
                    Text("管理您的直播平台账号")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                // 右侧列表区
                VStack(spacing: 18) {
                    Spacer(minLength: 180)

                    HStack {
                        Text("直播平台")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    NavigationLink {
                        BilibiliAccountDetailView()
                            .environmentObject(settingStore)
                    } label: {
                        HStack {
                            Text("哔哩哔哩")
                            Spacer()
                            Text(syncService.isLoggedIn ? "已登录" : "未登录")
                                .font(.system(size: 30))
                                .foregroundStyle(syncService.isLoggedIn ? .green : .gray)
                        }
                    }

                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
    }
}

// MARK: - 哔哩哔哩账号详情视图

struct BilibiliAccountDetailView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore

    var body: some View {
        if syncService.isLoggedIn {
            BilibiliLoggedInView()
                .environmentObject(settingStore)
        } else {
            BilibiliLoginOptionsView()
                .environmentObject(settingStore)
        }
    }
}

// MARK: - 已登录视图

struct BilibiliLoggedInView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore

    @State private var userInfo: BilibiliUserInfoTV?
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showLogoutConfirm = false

    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧用户信息区
                VStack {
                    Spacer()

                    if isValidating {
                        ProgressView()
                            .scaleEffect(2)
                        Text("正在验证...")
                            .font(.headline)
                            .padding(.top, 30)
                    } else if let user = userInfo {
                        // 登录状态图标
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.green)

                        Text(user.displayName)
                            .font(.title)
                            .padding(.top, 20)

                        if let mid = user.mid {
                            Text("UID: \(mid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }

                        if let sign = user.sign, !sign.isEmpty {
                            Text(sign)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 40)
                                .padding(.top, 8)
                        }

                    } else if let error = validationError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.orange)

                        Text("验证失败")
                            .font(.title)
                            .padding(.top, 20)

                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(.blue)

                        Text("已登录")
                            .font(.title)
                            .padding(.top, 20)

                        if syncService.loginStatusDescription != "未登录" {
                            Text(syncService.loginStatusDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                // 右侧操作区
                VStack(spacing: 18) {
                    Spacer(minLength: 180)

                    HStack {
                        Text("账号操作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Button {
                        Task {
                            await validateCookie()
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Text("验证 Cookie")
                            Spacer()
                            if isValidating {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(isValidating)

                    NavigationLink {
                        BilibiliLoginOptionsView()
                            .environmentObject(settingStore)
                    } label: {
                        HStack(spacing: 16) {
                            Text("重新登录")
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 24))
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 8)
                    }

                    Button {
                        showLogoutConfirm = true
                    } label: {
                        HStack(spacing: 16) {
                            Text("退出登录")
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 24))
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 8)
                    }

                    Spacer().frame(height: 20)

                    HStack {
                        Text("iCloud 同步")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Toggle(isOn: $syncService.iCloudSyncEnabled) {
                        HStack {
                            Text("iCloud 自动同步")
                            Spacer()
                        }
                    }
                    .frame(height: 45)

                    if syncService.iCloudSyncEnabled {
                        Button {
                            Task {
                                _ = await syncService.syncFromICloud()
                                await validateCookie()
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Text("立即从 iCloud 同步")
                                Spacer()
                                Image(systemName: "icloud.and.arrow.down")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                logout()
            }
        } message: {
            Text("确定要退出哔哩哔哩登录吗？")
        }
        .task {
            await validateCookie()
        }
    }

    // MARK: - 方法

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
                    // 使用 BilibiliCookieSyncService 统一管理 uid
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

        // 同步到 iCloud（清空状态）
        if syncService.iCloudSyncEnabled {
            syncService.syncToICloud()
        }

        settingStore.bilibiliCookie = ""
        userInfo = nil
        validationError = nil
    }
}

// MARK: - 登录选项视图

struct BilibiliLoginOptionsView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore

    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧提示区
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 400, height: 400)
                    Text("哔哩哔哩登录")
                        .font(.headline)
                        .padding(.top, 30)
                    Text("请从右侧选择一种方式登录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                // 右侧列表区
                VStack(spacing: 18) {
                    Spacer(minLength: 180)

                    HStack {
                        Text("登录方式")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    NavigationLink {
                        BilibiliLANSyncView()
                            .environmentObject(settingStore)
                    } label: {
                        HStack {
                            Text("局域网同步")
                            Spacer()
                            Text("推荐")
                                .font(.system(size: 30))
                                .foregroundStyle(.green)
                        }
                    }

                    NavigationLink {
                        BilibiliManualInputView()
                            .environmentObject(settingStore)
                    } label: {
                        HStack {
                            Text("手动输入 Cookie")
                            Spacer()
                        }
                    }

                    Spacer().frame(height: 20)

                    HStack {
                        Text("iCloud 同步")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Toggle(isOn: $syncService.iCloudSyncEnabled) {
                        HStack {
                            Text("iCloud 自动同步")
                            Spacer()
                        }
                    }
                    .frame(height: 45)

                    if syncService.iCloudSyncEnabled {
                        Button {
                            Task {
                                _ = await syncService.syncFromICloud()
                            }
                        } label: {
                            HStack {
                                Text("立即从 iCloud 同步")
                                Spacer()
                                Image(systemName: "icloud.and.arrow.down")
                                    .foregroundStyle(.gray)
                            }
                        }
                    }

                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - 局域网同步视图

struct BilibiliLANSyncView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    @Environment(\.dismiss) private var dismiss

    @State private var isWaiting = true
    @State private var statusMessage = "正在等待 iOS/macOS 设备连接..."
    @State private var isSuccess = false

    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧状态区
                VStack {
                    Spacer()
                    if isSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.green)
                        Text("同步成功")
                            .font(.title)
                            .padding(.top, 20)
                        Text("请返回上一页")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "wifi")
                            .font(.system(size: 100))
                            .foregroundColor(.blue)
                        Text("局域网同步")
                            .font(.headline)
                            .padding(.top, 20)
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 5)
                        if isWaiting {
                            ProgressView()
                                .padding(.top, 30)
                        }
                    }
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                // 右侧说明区
                VStack(alignment: .leading, spacing: 15) {
                    Spacer()

                    Text("操作步骤")
                        .font(.headline)
                        .padding(.bottom, 10)

                    StepRow(number: 1, text: "确保 Apple TV 和 iOS 在同一 Wi-Fi 网络")
                    StepRow(number: 2, text: "在 iOS 端 Angel Live 中登录哔哩哔哩")
                    StepRow(number: 3, text: "点击「同步到 tvOS」按钮")
                    StepRow(number: 4, text: "选择此 Apple TV 设备")

                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
        .background(.thinMaterial)
        .task {
            syncService.startBonjourListener()
        }
        .onDisappear {
            syncService.stopBonjourListener()
        }
        .onChange(of: syncService.isLoggedIn) { _, newValue in
            if newValue && syncService.lastSyncedData?.source == .bonjour {
                // 等待一小段时间确保 UserDefaults 写入完成
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    await MainActor.run {
                        isSuccess = true
                        settingStore.bilibiliCookie = syncService.getCurrentCookie()
                    }
                }
            }
        }
    }
}

// MARK: - 手动输入视图

struct BilibiliManualInputView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @EnvironmentObject var settingStore: SettingStore
    @Environment(\.dismiss) private var dismiss

    @State private var cookieInput = ""
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var isSuccess = false

    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧状态区
                VStack {
                    Spacer()
                    if isSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.green)
                        Text("设置成功")
                            .font(.title)
                            .padding(.top, 20)
                        Text("请返回上一页")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if isValidating {
                        ProgressView()
                            .scaleEffect(2)
                        Text("正在验证...")
                            .font(.headline)
                            .padding(.top, 30)
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 100))
                            .foregroundColor(.blue)
                        Text("手动输入 Cookie")
                            .font(.headline)
                            .padding(.top, 20)
                        if let message = validationMessage {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                                .padding(.top, 5)
                        }
                    }
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                // 右侧输入区
                VStack(alignment: .leading, spacing: 15) {
                    Spacer()

                    TextField("请输入 Cookie 字符串", text: $cookieInput)

                    Button {
                        Task {
                            await validateAndSave()
                        }
                    } label: {
                        Text("验证并保存")
                        Spacer()
                    }
                    .disabled(cookieInput.isEmpty || isValidating)

                    Divider()
                        .padding(.vertical, 10)

                    Text("如何获取 Cookie")
                        .font(.headline)
                        .padding(.bottom, 5)

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

                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
        .background(.thinMaterial)
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
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    AccountManagementView()
}
