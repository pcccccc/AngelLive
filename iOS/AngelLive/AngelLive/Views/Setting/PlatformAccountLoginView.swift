//
//  PlatformAccountLoginView.swift
//  AngelLive
//
//  Created by Codex on 2026/2/18.
//

import SwiftUI
import WebKit
import AngelLiveCore

private enum PlatformAccountItem: String, CaseIterable, Identifiable {
    case bilibili
    case douyin
    case kuaishou

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilibili:
            return "哔哩哔哩"
        case .douyin:
            return "抖音"
        case .kuaishou:
            return "快手"
        }
    }

    var iconSystemName: String {
        switch self {
        case .bilibili:
            return "play.tv.fill"
        case .douyin:
            return "music.note.tv"
        case .kuaishou:
            return "bolt.circle.fill"
        }
    }

    var iconTint: Color {
        switch self {
        case .bilibili:
            return .pink
        case .douyin:
            return .orange
        case .kuaishou:
            return .blue
        }
    }

    var sessionID: PlatformSessionID {
        switch self {
        case .bilibili:
            return .bilibili
        case .douyin:
            return .douyin
        case .kuaishou:
            return .kuaishou
        }
    }

    var loginURL: URL {
        switch self {
        case .bilibili:
            return URL(string: "https://passport.bilibili.com/h5-app/passport/login")!
        case .douyin:
            return URL(string: "https://sso.douyin.com/login")!
        case .kuaishou:
            return URL(string: "https://passport.kuaishou.com/pc/account/login")!
        }
    }

    var preferredUserAgent: String? {
        switch self {
        case .bilibili:
            return nil
        case .douyin, .kuaishou:
            return Self.desktopUserAgent
        }
    }

    var cookieDomainHints: [String] {
        switch self {
        case .bilibili:
            return ["bilibili.com"]
        case .douyin:
            return ["douyin.com", "iesdouyin.com"]
        case .kuaishou:
            return ["kuaishou.com", "gifshow.com"]
        }
    }

    var extraCookieNames: Set<String> {
        switch self {
        case .bilibili:
            return ["SESSDATA", "DedeUserID"]
        case .douyin:
            return ["ttwid", "__ac_nonce", "msToken", "sessionid", "sessionid_ss", "uid_tt"]
        case .kuaishou:
            return ["userId", "user_id", "kuaishou.server.web_st", "kuaishou.server.web_ph"]
        }
    }
}

struct PlatformAccountLoginView: View {
    @StateObject private var syncService = BilibiliCookieSyncService.shared
    @State private var douyinLoggedIn = false
    @State private var kuaishouLoggedIn = false
    @State private var selectedPlatform: PlatformAccountItem?

    var body: some View {
        List {
            Section {
                ForEach(PlatformAccountItem.allCases) { platform in
                    Button {
                        selectedPlatform = platform
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: platform.iconSystemName)
                                .font(.title3)
                                .foregroundStyle(platform.iconTint.gradient)
                                .frame(width: 32)

                            Text(platform.title)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(loginStatusText(for: platform))
                                .font(.caption)
                                .foregroundStyle(loginStatusColor(for: platform))

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("平台列表")
            } footer: {
                Text("点击平台后会弹出网页登录窗口，登录成功后会自动保存当前 Cookie。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("平台账号登录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshLoginStatus()
        }
        .sheet(item: $selectedPlatform, onDismiss: {
            Task {
                await refreshLoginStatus()
            }
        }) { platform in
            switch platform {
            case .bilibili:
                BilibiliWebLoginView()
            case .douyin, .kuaishou:
                PlatformCookieWebLoginSheet(platform: platform)
            }
        }
    }

    private func refreshLoginStatus() async {
        let douyinSession = await PlatformSessionManager.shared.getSession(platformId: .douyin)
        let kuaishouSession = await PlatformSessionManager.shared.getSession(platformId: .kuaishou)

        douyinLoggedIn = isAuthenticated(session: douyinSession)
        kuaishouLoggedIn = isAuthenticated(session: kuaishouSession)
    }

    private func isAuthenticated(session: PlatformSession?) -> Bool {
        guard let session,
              let cookie = session.cookie,
              !cookie.isEmpty else {
            return false
        }
        return session.state == .authenticated
    }

    private func loginStatusText(for platform: PlatformAccountItem) -> String {
        let loggedIn: Bool
        switch platform {
        case .bilibili:
            loggedIn = syncService.isLoggedIn
        case .douyin:
            loggedIn = douyinLoggedIn
        case .kuaishou:
            loggedIn = kuaishouLoggedIn
        }
        return loggedIn ? "已登录" : "未登录"
    }

    private func loginStatusColor(for platform: PlatformAccountItem) -> Color {
        let loggedIn: Bool
        switch platform {
        case .bilibili:
            loggedIn = syncService.isLoggedIn
        case .douyin:
            loggedIn = douyinLoggedIn
        case .kuaishou:
            loggedIn = kuaishouLoggedIn
        }
        return loggedIn ? AppConstants.Colors.success : .secondary
    }
}

private struct PlatformCookieWebLoginSheet: View {
    let platform: PlatformAccountItem

    @Environment(\.dismiss) private var dismiss

    @State private var currentWebView: WKWebView?
    @State private var statusText = "请在网页中完成登录，系统会自动保存登录信息。"
    @State private var isSavingCookie = false
    @State private var isLoggedIn = false
    @State private var errorMessage: String?
    @State private var lastSavedCookieSignature: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlatformLoginWebView(
                    platform: platform,
                    url: platform.loginURL,
                    onWebViewCreated: { webView in
                        currentWebView = webView
                    },
                    onNavigationStateChange: { title, url, didFinish in
                        updateNavigationStatus(title: title, url: url)
                        if didFinish {
                            autoSaveCookieIfNeeded()
                        }
                    }
                )
                .ignoresSafeArea(.container, edges: .bottom)

                VStack(alignment: .leading, spacing: 12) {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if isSavingCookie {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在保存登录信息...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("\(platform.title)登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoggedIn {
                        Button("退出登录", role: .destructive) {
                            logout()
                        }
                    }
                }
            }
            .task {
                await reloadLoginStatus()
            }
        }
    }

    private func updateNavigationStatus(title: String?, url: URL?) {
        guard !isSavingCookie else { return }
        if let title, !title.isEmpty {
            statusText = title
        } else if let host = url?.host(), !host.isEmpty {
            statusText = "当前页面：\(host)"
        } else {
            statusText = "请在网页中完成登录，系统会自动保存登录信息。"
        }
    }

    private func autoSaveCookieIfNeeded() {
        guard !isSavingCookie else { return }
        guard let currentWebView else {
            return
        }

        currentWebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let filteredCookies = cookies.filter { cookie in
                let domainMatch = platform.cookieDomainHints.contains { hint in
                    cookie.domain.contains(hint)
                }
                return domainMatch || platform.extraCookieNames.contains(cookie.name)
            }

            let cookieString = makeCookieString(from: filteredCookies)
            let uid = extractUID(from: filteredCookies)
            guard !cookieString.isEmpty else { return }
            guard containsAuthenticatedCookie(in: filteredCookies) else { return }

            let signature = makeCookieSignature(from: filteredCookies)

            Task { @MainActor in
                guard !isSavingCookie else { return }
                guard signature != lastSavedCookieSignature else { return }
                await saveCookie(cookieString, uid: uid, signature: signature)
            }
        }
    }

    private func saveCookie(_ cookieString: String, uid: String?, signature: String) async {
        guard !cookieString.isEmpty else {
            errorMessage = "未读取到有效 Cookie，请确认登录成功后重试。"
            statusText = "Cookie 读取失败"
            isSavingCookie = false
            return
        }

        isSavingCookie = true
        errorMessage = nil
        statusText = "检测到登录状态，正在保存..."

        let result = await PlatformSessionManager.shared.loginWithCookie(
            platformId: platform.sessionID,
            cookie: cookieString,
            uid: uid,
            source: .local,
            validateBeforeSave: true
        )

        switch result {
        case .valid:
            isLoggedIn = true
            lastSavedCookieSignature = signature
            statusText = "登录信息已保存"
            errorMessage = nil
        case .expired:
            isLoggedIn = false
            statusText = "登录信息已过期"
            errorMessage = "Cookie 已过期，请重新登录。"
        case .invalid(let reason):
            isLoggedIn = false
            statusText = "登录信息无效"
            errorMessage = reason
        case .networkError(let message):
            isLoggedIn = false
            statusText = "网络错误"
            errorMessage = message
        }

        isSavingCookie = false
    }

    private func containsAuthenticatedCookie(in cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        switch platform {
        case .bilibili:
            return names.contains("SESSDATA") || names.contains("DedeUserID")
        case .douyin:
            return names.contains("sessionid") || names.contains("sessionid_ss")
        case .kuaishou:
            return names.contains("userId")
                || names.contains("user_id")
                || names.contains("kuaishou.server.web_st")
                || names.contains("kuaishou.server.web_ph")
        }
    }

    private func makeCookieSignature(from cookies: [HTTPCookie]) -> String {
        cookies
            .sorted(by: { $0.name < $1.name })
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: ";")
    }

    private func logout() {
        Task {
            await PlatformSessionManager.shared.clearSession(platformId: platform.sessionID)
            await MainActor.run {
                isLoggedIn = false
                statusText = "已退出登录"
                errorMessage = nil
            }
        }
    }

    private func reloadLoginStatus() async {
        let session = await PlatformSessionManager.shared.getSession(platformId: platform.sessionID)
        await MainActor.run {
            isLoggedIn = session?.state == .authenticated
        }
    }

    private func makeCookieString(from cookies: [HTTPCookie]) -> String {
        var deduplicated = [String: String]()
        for cookie in cookies {
            deduplicated[cookie.name] = cookie.value
        }
        return deduplicated
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func extractUID(from cookies: [HTTPCookie]) -> String? {
        let uidCookieNames = ["DedeUserID", "sec_user_id", "userId", "user_id"]
        for name in uidCookieNames {
            if let value = cookies.first(where: { $0.name == name })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct PlatformLoginWebView: UIViewRepresentable {
    let platform: PlatformAccountItem
    let url: URL
    let onWebViewCreated: (WKWebView) -> Void
    let onNavigationStateChange: (String?, URL?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if let preferredUserAgent = platform.preferredUserAgent {
            webView.customUserAgent = preferredUserAgent
        }

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        var request = URLRequest(url: url)
        if let preferredUserAgent = platform.preferredUserAgent {
            request.setValue(preferredUserAgent, forHTTPHeaderField: "User-Agent")
        }
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigationStateChange: (String?, URL?, Bool) -> Void

        init(onNavigationStateChange: @escaping (String?, URL?, Bool) -> Void) {
            self.onNavigationStateChange = onNavigationStateChange
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, true)
        }
    }
}

#Preview {
    NavigationStack {
        PlatformAccountLoginView()
    }
}
