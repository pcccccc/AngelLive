//
//  BilibiliWebLoginView.swift
//  AngelLive
//
//  Created by pangchong on 11/28/25.
//

import SwiftUI
import WebKit
import AngelLiveCore

// MARK: - Bilibili User Info Model
struct BilibiliUserInfo: Codable {
    let mid: Int?
    let uname: String?
    let userid: String?
    let sign: String?
    let birthday: String?
    let sex: String?
    let rank: String?      // "正式会员" 等
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

struct BilibiliUserInfoResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: BilibiliUserInfo?

    enum CodingKeys: String, CodingKey {
        case code, message, ttl, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)
        // data 字段可能不存在（未登录时）
        data = try container.decodeIfPresent(BilibiliUserInfo.self, forKey: .data)
    }
}

// MARK: - Bilibili API Service
actor BilibiliUserService {
    static let shared = BilibiliUserService()

    private init() {}

    /// 获取用户信息，同时验证 Cookie 是否有效
    func loadUserInfo(cookie: String) async -> Result<BilibiliUserInfo, BilibiliUserError> {
        guard !cookie.isEmpty else {
            return .failure(.emptyCookie)
        }

        guard let url = URL(string: "https://api.bilibili.com/x/member/web/account") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // 调试：打印原始响应
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[BilibiliUserService] API Response: \(jsonString.prefix(500))")
            }

            let response = try JSONDecoder().decode(BilibiliUserInfoResponse.self, from: data)

            if response.code == 0, let userInfo = response.data {
                return .success(userInfo)
            } else {
                // code 不为 0，表示登录失效或其他错误
                // -101: 账号未登录
                // -400: 请求错误
                let errorMsg = response.message ?? "Cookie 已失效 (code: \(response.code))"
                return .failure(.cookieExpired(message: errorMsg))
            }
        } catch let error as DecodingError {
            print("[BilibiliUserService] Decoding error: \(error)")
            return .failure(.decodingError(error))
        } catch {
            print("[BilibiliUserService] Network error: \(error)")
            return .failure(.networkError(error))
        }
    }
}

enum BilibiliUserError: Error, LocalizedError {
    case emptyCookie
    case invalidURL
    case cookieExpired(message: String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .emptyCookie:
            return "Cookie 为空"
        case .invalidURL:
            return "无效的 URL"
        case .cookieExpired(let message):
            return "登录已失效: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError:
            return "数据解析错误"
        }
    }
}

// MARK: - Main Login View
struct BilibiliWebLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settingStore = SettingStore()

    @State private var statusText = "正在加载登录页面..."
    @State private var isLoading = true
    @State private var loginSuccess = false
    @State private var loopTimes = 0
    @State private var viewVisible = true
    @State private var showLogoutConfirm = false
    @State private var webViewKey = UUID()
    @State private var currentWebView: WKWebView?

    // 用户信息
    @State private var userInfo: BilibiliUserInfo?
    @State private var isValidatingCookie = false
    @State private var validationError: String?

    // tvOS 同步
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @State private var showTvOSSyncSheet = false

    // 登录页面 URL
    private let loginURL = "https://passport.bilibili.com/h5-app/passport/login?gourl=https%3A%2F%2Flive.bilibili.com%2Fp%2Feden%2Farea-tags%3FparentAreaId%3D2%26areaId%3D86"
    // 登录成功后的标题关键词
    private let successTitleKeyword = "直播"
    // 最大等待次数（登录成功后等待 cookie 稳定）
    private let maxWaitTimes = 2

    var body: some View {
        NavigationStack {
            ZStack {
                if settingStore.bilibiliCookie.isEmpty && !loginSuccess {
                    // 未登录状态 - 显示 WebView
                    VStack(spacing: 0) {
                        BilibiliLoginWebViewContainer(
                            url: loginURL,
                            onWebViewCreated: { webView in
                                currentWebView = webView
                            },
                            onTitleChanged: { title in
                                checkLoginStatus(title: title)
                            }
                        )
                        .id(webViewKey)
                        .ignoresSafeArea(.all, edges: .bottom)

                        // 底部状态栏
                        VStack(spacing: AppConstants.Spacing.xs) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppConstants.Spacing.md)
                        .padding(.horizontal)
                        .background(.ultraThinMaterial)
                    }
                } else {
                    // 已登录状态
                    loggedInView
                }
            }
            .navigationTitle("哔哩哔哩登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !settingStore.bilibiliCookie.isEmpty || loginSuccess {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("退出登录") {
                            showLogoutConfirm = true
                        }
                        .foregroundStyle(AppConstants.Colors.error)
                    }
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
        }
        .onAppear {
            viewVisible = true
            isLoading = true
            statusText = "正在加载登录页面..."
        }
        .onDisappear {
            viewVisible = false
        }
    }

    // MARK: - Logged In View
    private var loggedInView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppConstants.Spacing.xl) {
                // 用户头像和名称
                VStack(spacing: AppConstants.Spacing.lg) {
                    if isValidatingCookie {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(width: 80, height: 80)
                    } else if let user = userInfo {
                        // 用户头像
                        AsyncImage(url: URL(string: user.face ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppConstants.Colors.success, lineWidth: 3))

                        Text(user.displayName)
                            .font(.title.bold())
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        if let sign = user.sign, !sign.isEmpty {
                            Text(sign)
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    } else {
                        Image(systemName: validationError != nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(validationError != nil ? AppConstants.Colors.warning.gradient : AppConstants.Colors.success.gradient)

                        Text(validationError != nil ? "验证失败" : "登录成功")
                            .font(.title.bold())
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        if let error = validationError {
                            Text(error)
                                .font(.body)
                                .foregroundStyle(AppConstants.Colors.error)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.top, AppConstants.Spacing.xxl)

                // 账号信息卡片
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    Text("账号信息")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    if let user = userInfo {
                        HStack {
                            Text("用户名")
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                            Spacer()
                            Text(user.displayName)
                                .foregroundStyle(AppConstants.Colors.primaryText)
                        }

                        if let mid = user.mid {
                            HStack {
                                Text("用户 ID")
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                                Spacer()
                                Text("\(mid)")
                                    .foregroundStyle(AppConstants.Colors.primaryText)
                            }
                        }
                    } else if let uid = extractUidFromCookie() {
                        HStack {
                            Text("用户 ID")
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                            Spacer()
                            Text(uid)
                                .foregroundStyle(AppConstants.Colors.primaryText)
                        }
                    }

                    HStack {
                        Text("Cookie 状态")
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                        Spacer()
                        if isValidatingCookie {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("验证中...")
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        } else if validationError != nil {
                            Text("已失效")
                                .foregroundStyle(AppConstants.Colors.error)
                        } else {
                            Text("有效")
                                .foregroundStyle(AppConstants.Colors.success)
                        }
                    }

                    // 重新验证按钮
                    if validationError != nil {
                        Button {
                            Task {
                                await validateCookie()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("重新验证")
                            }
                            .font(.subheadline)
                            .foregroundStyle(AppConstants.Colors.link)
                        }
                        .padding(.top, AppConstants.Spacing.xs)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)
                .padding(.horizontal)

                // 同步到 tvOS 卡片
                tvOSSyncCard

                Spacer(minLength: AppConstants.Spacing.xxl)
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            // 进入页面时验证 Cookie
            if userInfo == nil && !settingStore.bilibiliCookie.isEmpty {
                await validateCookie()
            }
        }
        .sheet(isPresented: $showTvOSSyncSheet) {
            TvOSSyncSheet(syncService: syncService, cookie: settingStore.bilibiliCookie)
        }
    }

    // MARK: - tvOS 同步卡片
    private var tvOSSyncCard: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack {
                Image(systemName: "appletvremote.gen4.fill")
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.link)
                Text("同步到 tvOS")
                    .font(.headline)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                Spacer()
            }

            Text("将登录信息同步到同一局域网内的 Apple TV")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)

            Button {
                showTvOSSyncSheet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("开始同步")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppConstants.Spacing.sm)
                .background(AppConstants.Colors.link)
                .cornerRadius(AppConstants.CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
        .padding(.horizontal)
    }

    // MARK: - Methods

    /// 验证 Cookie 并获取用户信息
    private func validateCookie() async {
        isValidatingCookie = true
        validationError = nil

        let result = await BilibiliUserService.shared.loadUserInfo(cookie: settingStore.bilibiliCookie)

        switch result {
        case .success(let info):
            userInfo = info
            validationError = nil
            // 更新 uid
            if let mid = info.mid {
                UserDefaults.standard.set("\(mid)", forKey: "LiveParse.Bilibili.uid")
            }
            print("[BilibiliWebLogin] Cookie 验证成功: \(info.displayName)")

        case .failure(let error):
            userInfo = nil
            validationError = error.localizedDescription
            print("[BilibiliWebLogin] Cookie 验证失败: \(error.localizedDescription)")
        }

        isValidatingCookie = false
    }

    private func checkLoginStatus(title: String?) {
        guard viewVisible else { return }

        let pageTitle = title ?? ""
        statusText = pageTitle.isEmpty ? "正在加载..." : pageTitle

        // 检查是否已经跳转到目标页面（登录成功）
        if pageTitle.contains(successTitleKeyword) {
            loopTimes += 1
            if loopTimes >= maxWaitTimes {
                extractAndSaveCookie()
            }
        } else {
            loopTimes = 0
            isLoading = false
            if pageTitle.isEmpty {
                statusText = "请登录您的哔哩哔哩账号"
            }
        }
    }

    private func extractAndSaveCookie() {
        guard let webView = currentWebView else {
            statusText = "获取登录信息失败，请重试"
            return
        }

        isLoading = true
        statusText = "正在保存登录信息..."

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var cookieDict = [String: AnyObject]()
            for cookie in cookies {
                if cookie.domain.contains("bilibili") {
                    cookieDict[cookie.name] = cookie.properties as AnyObject?
                }
            }

            DispatchQueue.main.async {
                let cookieString = self.buildCookieString(from: cookieDict)

                if !cookieString.isEmpty {
                    // 保存 cookie
                    self.settingStore.bilibiliCookie = cookieString

                    // 提取并保存 uid
                    if let uid = self.extractValue(named: "DedeUserID", from: cookieDict) {
                        UserDefaults.standard.set(uid, forKey: "LiveParse.Bilibili.uid")
                    }

                    // 同步到 iCloud
                    BilibiliCookieSyncService.shared.syncToICloud()

                    self.loginSuccess = true
                    self.isLoading = false
                    self.statusText = "登录成功，正在验证..."

                    print("[BilibiliWebLogin] Login successful, cookie saved")

                    // 验证 Cookie 并获取用户信息
                    Task {
                        await self.validateCookie()
                    }
                } else {
                    self.isLoading = false
                    self.statusText = "获取登录信息失败，请重试"
                }
            }
        }
    }

    private func buildCookieString(from cookieDict: [String: Any]) -> String {
        var cookieString = ""

        for (key, value) in cookieDict {
            if let valueDict = value as? [String: AnyObject],
               let cookieValue = valueDict["Value"] {
                cookieString += "\(key)=\(cookieValue); "
            }
        }

        return cookieString.trimmingCharacters(in: .whitespaces)
    }

    private func extractValue(named name: String, from cookieDict: [String: Any]) -> String? {
        if let valueDict = cookieDict[name] as? [String: AnyObject],
           let value = valueDict["Value"] as? String {
            return value
        }
        return nil
    }

    private func extractUidFromCookie() -> String? {
        return UserDefaults.standard.string(forKey: "LiveParse.Bilibili.uid")
    }

    private func logout() {
        // 清除 cookie
        settingStore.bilibiliCookie = ""
        UserDefaults.standard.removeObject(forKey: "LiveParse.Bilibili.uid")

        // 清除 WebView 数据
        clearWebsiteData()

        // 同步到 iCloud
        BilibiliCookieSyncService.shared.syncToICloud()

        // 重置状态
        loginSuccess = false
        loopTimes = 0
        isLoading = true
        statusText = "正在加载登录页面..."
        currentWebView = nil
        userInfo = nil
        validationError = nil
        isValidatingCookie = false

        // 重新创建 WebView
        webViewKey = UUID()
    }

    private func clearWebsiteData() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let bilibiliRecords = records.filter { $0.displayName.contains("bilibili") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: bilibiliRecords) {
                print("[BilibiliWebLogin] Cleared Bilibili website data")
            }
        }
    }
}

// MARK: - WebView Container
struct BilibiliLoginWebViewContainer: UIViewRepresentable {
    let url: String
    let onWebViewCreated: (WKWebView) -> Void
    let onTitleChanged: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChanged: onTitleChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // 通知父视图 WebView 已创建
        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }

        // 启动轮询检查标题
        context.coordinator.startPolling(webView: webView)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
        uiView.stopLoading()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onTitleChanged: (String?) -> Void
        private var pollingTimer: Timer?
        private weak var webView: WKWebView?

        init(onTitleChanged: @escaping (String?) -> Void) {
            self.onTitleChanged = onTitleChanged
        }

        func startPolling(webView: WKWebView) {
            self.webView = webView
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self, let webView = self.webView else { return }
                self.onTitleChanged(webView.title)
            }
        }

        func stopPolling() {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onTitleChanged(webView.title)
        }
    }
}

// MARK: - tvOS 同步 Sheet
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
        NavigationStack {
            VStack(spacing: AppConstants.Spacing.xl) {
                // 状态图标
                statusIcon
                    .padding(.top, AppConstants.Spacing.xxl)

                // 状态文本
                statusText

                // 设备列表
                if !syncService.discoveredDevices.isEmpty && sendResult == nil {
                    deviceList
                }

                Spacer()

                // 底部说明
                if sendResult == nil {
                    instructionsView
                }
            }
            .padding()
            .navigationTitle("同步到 tvOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            startSearching()
        }
        .onDisappear {
            syncService.stopBonjourBrowsing()
        }
    }

    // MARK: - 子视图

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
                    .background(AppConstants.Colors.materialBackground)
                    .cornerRadius(AppConstants.CornerRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            Text("使用说明")
                .font(.caption.bold())
                .foregroundStyle(AppConstants.Colors.secondaryText)

            Text("1. 确保 iPhone 和 Apple TV 在同一 Wi-Fi 网络")
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

    // MARK: - 方法

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

#Preview {
    BilibiliWebLoginView()
}
