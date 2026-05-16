//
//  PlatformLoginWebSheet.swift
//  AngelLive
//
//  通用平台 Web 登录面板。
//  所有登录参数（URL、cookie 域名、认证信号等）来自 manifest.loginFlow。
//

import SwiftUI
import WebKit
import AngelLiveCore

struct PlatformLoginWebSheet: View {
    let pluginId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var entry: LoginPlatformEntry?
    @State private var currentWebView: WKWebView?
    @State private var statusText = "请在网页中完成登录，系统会自动保存会话并由宿主托管鉴权。"
    @State private var isSavingCookie = false
    @State private var isLoggedIn = false
    @State private var errorMessage: String?
    @State private var lastSavedCookieSignature: String?
    @State private var cookiePollingTimer: Timer?
    @State private var showWebView = false
    @State private var currentSession: PlatformSession?
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var userDisplayName: String?

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    if isLoggedIn && !showWebView {
                        statusContent(entry: entry)
                    } else {
                        loginContent(entry: entry)
                    }
                } else {
                    ProgressView("加载中...")
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoggedIn && !showWebView {
                        Button("退出登录", role: .destructive) {
                            logout()
                        }
                    }
                }
            }
            .task {
                entry = await PlatformLoginRegistry.shared.entry(pluginId: pluginId)
                await reloadLoginStatus()
            }
            .onDisappear {
                stopCookiePolling()
            }
        }
    }

    private var navigationTitle: String {
        let name = entry?.displayName ?? pluginId
        if isLoggedIn && !showWebView {
            return "\(name) 账号"
        }
        return "\(name) 登录"
    }

    @ViewBuilder
    private func statusContent(entry: LoginPlatformEntry) -> some View {
        List {
            Section("账号信息") {
                LabeledContent("平台", value: entry.displayName)
                if let name = userDisplayName, !name.isEmpty {
                    LabeledContent("昵称", value: name)
                }
                if let uid = currentSession?.uid, !uid.isEmpty {
                    LabeledContent("UID", value: uid)
                }
                if let updatedAt = currentSession?.updatedAt {
                    LabeledContent("登录时间", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("状态") {
                    Text(sessionStateLabel)
                        .foregroundStyle(isLoggedIn ? AppConstants.Colors.success : .secondary)
                }
            }

            if entry.auth?.supportsValidation == true {
                Section {
                    Button {
                        Task { await revalidate() }
                    } label: {
                        HStack {
                            Text("重新校验凭证")
                            Spacer()
                            if isValidating {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isValidating)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(validationMessage.hasPrefix("✅") ? AppConstants.Colors.success : .red)
                    }
                } footer: {
                    Text("插件会调用 validateCredential 向平台校验 Cookie 是否仍然有效。")
                }
            }

            Section {
                Button("重新登录") {
                    Task { await prepareRelogin(entry: entry) }
                }
            } footer: {
                Text("Cookie 过期或切换账号时点这里，会打开登录页重新抓取。")
            }
        }
    }

    private var sessionStateLabel: String {
        switch currentSession?.state {
        case .some(.authenticated): return "已登录"
        case .some(.anonymous): return "匿名"
        case .none: return "未登录"
        @unknown default: return "未知"
        }
    }

    private func revalidate() async {
        isValidating = true
        validationMessage = nil
        let status = await PlatformSessionManager.shared.fetchCredentialStatus(pluginId: pluginId)
        if let name = status?.userName, !name.isEmpty {
            userDisplayName = name
        }
        let result = await PlatformSessionManager.shared.validateSession(pluginId: pluginId)
        await syncService.refreshLoginStatus(pluginId: pluginId)
        await reloadLoginStatus()
        switch result {
        case .valid:
            validationMessage = "✅ 凭证有效"
        case .expired:
            validationMessage = "Cookie 已过期，请重新登录"
        case .invalid(let reason):
            validationMessage = reason
        case .networkError(let message):
            validationMessage = "网络错误：\(message)"
        }
        isValidating = false
    }

    @ViewBuilder
    private func loginContent(entry: LoginPlatformEntry) -> some View {
        VStack(spacing: 0) {
            PlatformLoginWebView(
                loginFlow: entry.loginFlow,
                onWebViewCreated: { webView in
                    currentWebView = webView
                    startCookiePolling(entry: entry)
                },
                onNavigationStateChange: { title, url, didFinish in
                    updateNavigationStatus(title: title, url: url)
                    if didFinish {
                        pollCookieOnce(entry: entry)
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
    }

    // MARK: - Navigation

    private func updateNavigationStatus(title: String?, url: URL?) {
        guard !isSavingCookie else { return }
        if let title, !title.isEmpty {
            statusText = title
        } else if let host = url?.host(), !host.isEmpty {
            statusText = "当前页面：\(host)"
        } else {
            statusText = "请在网页中完成登录，系统会自动保存会话并由宿主托管鉴权。"
        }
    }

    // MARK: - Cookie 抓取

    private func startCookiePolling(entry: LoginPlatformEntry) {
        cookiePollingTimer?.invalidate()
        pollCookieOnce(entry: entry)
        cookiePollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            pollCookieOnce(entry: entry)
        }
    }

    private func stopCookiePolling() {
        cookiePollingTimer?.invalidate()
        cookiePollingTimer = nil
    }

    private func pollCookieOnce(entry: LoginPlatformEntry) {
        guard !isSavingCookie, let currentWebView else { return }
        let loginFlow = entry.loginFlow

        currentWebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let filteredCookies = PlatformCookieCollector.filteredCookies(
                from: cookies,
                loginFlow: loginFlow
            )

            let cookieString = PlatformCookieCollector.cookieHeader(from: filteredCookies)
            guard !cookieString.isEmpty else { return }
            guard PlatformCookieCollector.containsAuthenticatedCookie(
                in: filteredCookies,
                loginFlow: loginFlow
            ) else { return }

            let signature = PlatformCookieCollector.signature(from: filteredCookies)

            Task { @MainActor in
                guard !isSavingCookie else { return }
                guard signature != lastSavedCookieSignature else { return }
                await saveCookie(cookieString, entry: entry, cookies: filteredCookies, signature: signature)
            }
        }
    }

    private func saveCookie(_ cookieString: String, entry: LoginPlatformEntry, cookies: [HTTPCookie], signature: String) async {
        guard !cookieString.isEmpty else {
            errorMessage = "未读取到有效 Cookie，请确认登录成功后重试。"
            statusText = "Cookie 读取失败"
            return
        }

        isSavingCookie = true
        errorMessage = nil
        statusText = "检测到登录状态，正在保存..."

        let uid = PlatformCookieCollector.extractUID(from: cookies, loginFlow: entry.loginFlow)
        let shouldValidate = entry.auth?.supportsValidation ?? false

        let result = await PlatformSessionManager.shared.loginWithCookie(
            pluginId: pluginId,
            cookie: cookieString,
            uid: uid,
            source: .local,
            validateBeforeSave: shouldValidate
        )

        switch result {
        case .valid:
            isLoggedIn = true
            stopCookiePolling()
            lastSavedCookieSignature = signature
            statusText = "登录信息已保存（宿主托管鉴权）"
            errorMessage = nil
            await syncService.refreshLoginStatus(pluginId: pluginId)
            // 登录成功后刷新 session 并切回状态页
            await reloadLoginStatus()
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

    // MARK: - Actions

    private func prepareRelogin(entry: LoginPlatformEntry) async {
        statusText = "正在清理网页登录缓存..."
        errorMessage = nil
        lastSavedCookieSignature = nil
        currentWebView = nil
        await clearWebLoginData(for: entry.loginFlow)
        showWebView = true
        statusText = "请在网页中完成登录，系统会自动保存会话并由宿主托管鉴权。"
    }

    private func logout() {
        Task {
            await syncService.clearSession(pluginId: pluginId)
            if let entry {
                await clearWebLoginData(for: entry.loginFlow)
            }
            await MainActor.run {
                isLoggedIn = false
                currentSession = nil
                validationMessage = nil
                userDisplayName = nil
                showWebView = false
                statusText = "已退出登录"
                errorMessage = nil
                lastSavedCookieSignature = nil
            }
        }
    }

    @MainActor
    private func clearWebLoginData(for loginFlow: ManifestLoginFlow) async {
        let dataStore = WKWebsiteDataStore.default()
        let domainHints = PlatformCookieCollector.domainHints(for: loginFlow)
        guard !domainHints.isEmpty else { return }

        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                let matchingCookies = cookies.filter { cookie in
                    domainHints.contains { hint in
                        PlatformCookieCollector.domainMatches(cookie.domain, hint: hint)
                    }
                }

                guard !matchingCookies.isEmpty else {
                    continuation.resume()
                    return
                }

                let group = DispatchGroup()
                for cookie in matchingCookies {
                    group.enter()
                    dataStore.httpCookieStore.delete(cookie) {
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }

        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                let matchingRecords = records.filter { record in
                    domainHints.contains { hint in
                        PlatformCookieCollector.domainMatches(record.displayName, hint: hint)
                    }
                }

                guard !matchingRecords.isEmpty else {
                    continuation.resume()
                    return
                }

                dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {
                    continuation.resume()
                }
            }
        }
    }

    private func reloadLoginStatus() async {
        let session = await PlatformSessionManager.shared.getSession(pluginId: pluginId)
        currentSession = session
        let loggedIn = session?.state == .authenticated
        isLoggedIn = loggedIn
        if loggedIn {
            // 已登录：默认显示状态页，只有用户点"重新登录"才切到 webview
            showWebView = false
            // 后台拉一次 validateCredential，把昵称显示出来；失败不打断 UI
            Task {
                if let status = await PlatformSessionManager.shared.fetchCredentialStatus(pluginId: pluginId),
                   let name = status.userName, !name.isEmpty {
                    await MainActor.run { userDisplayName = name }
                }
            }
        } else {
            userDisplayName = nil
        }
    }
}

// MARK: - WebView

private struct PlatformLoginWebView: UIViewRepresentable {
    let loginFlow: ManifestLoginFlow
    let onWebViewCreated: (WKWebView) -> Void
    let onNavigationStateChange: (String?, URL?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        let userAgent = effectiveUserAgent
        webView.customUserAgent = userAgent

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        if let url = URL(string: loginFlow.loginURL) {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var effectiveUserAgent: String {
        let custom = loginFlow.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty {
            return custom
        }
        // Twitch 会拒绝不完整的 WKWebView UA；默认伪装成同内核的移动 Safari。
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onNavigationStateChange: (String?, URL?, Bool) -> Void

        init(onNavigationStateChange: @escaping (String?, URL?, Bool) -> Void) {
            self.onNavigationStateChange = onNavigationStateChange
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // SOOP/Apple/Google 登录常用 window.open；在当前 WebView 内接管，避免按钮无响应。
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, true)
        }
    }
}
