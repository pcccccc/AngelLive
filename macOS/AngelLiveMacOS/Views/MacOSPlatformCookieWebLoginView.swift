//
//  MacOSPlatformCookieWebLoginView.swift
//  AngelLiveMacOS
//
//  通用平台 Cookie 网页登录视图（macOS 版）
//

import SwiftUI
import WebKit
import AngelLiveCore

// MARK: - Platform Definition

enum MacOSPlatformAccountItem: String, CaseIterable, Identifiable {
    case douyin
    case kuaishou
    case soop

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .soop: return "SOOP"
        }
    }

    var iconSystemName: String {
        switch self {
        case .douyin: return "music.note.tv"
        case .kuaishou: return "bolt.circle.fill"
        case .soop: return "globe.asia.australia.fill"
        }
    }

    var iconTint: Color {
        switch self {
        case .douyin: return .orange
        case .kuaishou: return .blue
        case .soop: return .purple
        }
    }

    var sessionID: PlatformSessionID {
        switch self {
        case .douyin: return .douyin
        case .kuaishou: return .kuaishou
        case .soop: return .soop
        }
    }

    var loginURL: URL {
        switch self {
        case .douyin: return URL(string: "https://sso.douyin.com/login")!
        case .kuaishou: return URL(string: "https://passport.kuaishou.com/pc/account/login")!
        case .soop: return URL(string: "https://auth.m.sooplive.co.kr/login")!
        }
    }

    var preferredUserAgent: String? {
        Self.desktopUserAgent
    }

    var cookieDomainHints: [String] {
        switch self {
        case .douyin: return ["douyin.com", "iesdouyin.com"]
        case .kuaishou: return ["kuaishou.com", "gifshow.com"]
        case .soop: return ["sooplive.co.kr"]
        }
    }

    var extraCookieNames: Set<String> {
        switch self {
        case .douyin: return ["ttwid", "__ac_nonce", "msToken", "sessionid", "sessionid_ss", "uid_tt"]
        case .kuaishou: return ["userId", "user_id", "kuaishou.server.web_st", "kuaishou.server.web_ph"]
        case .soop: return ["AuthTicket", "BbsTicket", "UserTicket"]
        }
    }

    func containsAuthenticatedCookie(names: Set<String>) -> Bool {
        switch self {
        case .douyin:
            return names.contains("sessionid") || names.contains("sessionid_ss")
        case .kuaishou:
            return names.contains("userId")
                || names.contains("user_id")
                || names.contains("kuaishou.server.web_st")
                || names.contains("kuaishou.server.web_ph")
        case .soop:
            return names.contains("AuthTicket")
        }
    }
}

// MARK: - Login View

struct MacOSPlatformCookieWebLoginView: View {
    let platform: MacOSPlatformAccountItem

    @Environment(\.dismiss) private var dismiss
    @State private var currentWebView: WKWebView?
    @State private var statusText = "请在网页中完成登录，系统会自动保存登录信息。"
    @State private var isSavingCookie = false
    @State private var isLoggedIn = false
    @State private var errorMessage: String?
    @State private var lastSavedCookieSignature: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(platform.title)登录")
                    .font(.headline)

                Spacer()

                if isLoggedIn {
                    Button("退出登录") {
                        logout()
                    }
                    .foregroundStyle(.red)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding()
            .background(AppConstants.Colors.secondaryBackground)

            Divider()

            // WebView
            MacOSPlatformLoginWebView(
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

            // Status bar
            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if isSavingCookie {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("正在保存登录信息...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(AppConstants.Colors.secondaryBackground)
        }
        .frame(minWidth: 500, minHeight: 600)
        .task {
            await reloadLoginStatus()
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
        guard !isSavingCookie, let currentWebView else { return }

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

            let names = Set(filteredCookies.map(\.name))
            guard platform.containsAuthenticatedCookie(names: names) else { return }

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
        let uidCookieNames = ["DedeUserID", "sec_user_id", "userId", "user_id", "UserTicket"]
        for name in uidCookieNames {
            if let value = cookies.first(where: { $0.name == name })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func makeCookieSignature(from cookies: [HTTPCookie]) -> String {
        cookies
            .sorted(by: { $0.name < $1.name })
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: ";")
    }
}

// MARK: - macOS WebView

private struct MacOSPlatformLoginWebView: NSViewRepresentable {
    let platform: MacOSPlatformAccountItem
    let url: URL
    let onWebViewCreated: (WKWebView) -> Void
    let onNavigationStateChange: (String?, URL?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange)
    }

    func makeNSView(context: Context) -> WKWebView {
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

        context.coordinator.startPolling(webView: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
        nsView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigationStateChange: (String?, URL?, Bool) -> Void
        private var pollingTimer: Timer?
        private weak var webView: WKWebView?

        init(onNavigationStateChange: @escaping (String?, URL?, Bool) -> Void) {
            self.onNavigationStateChange = onNavigationStateChange
        }

        func startPolling(webView: WKWebView) {
            self.webView = webView
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self, let webView = self.webView else { return }
                self.onNavigationStateChange(webView.title, webView.url, false)
            }
        }

        func stopPolling() {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, true)
        }
    }
}
