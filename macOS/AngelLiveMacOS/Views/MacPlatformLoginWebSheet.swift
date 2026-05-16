//
//  MacPlatformLoginWebSheet.swift
//  AngelLiveMacOS
//
//  通用平台 Web 登录面板（macOS 版）。
//  所有登录参数来自 manifest.loginFlow。
//

import SwiftUI
import WebKit
import AngelLiveCore

struct MacPlatformLoginWebSheet: View {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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
                cookiePollingTimer?.invalidate()
                cookiePollingTimer = nil
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
        Form {
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
                    HStack {
                        Button {
                            Task { await revalidate() }
                        } label: {
                            Text("重新校验凭证")
                        }
                        .disabled(isValidating)
                        if isValidating {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(validationMessage.hasPrefix("✅") ? AppConstants.Colors.success : .red)
                    }
                } footer: {
                    Text("插件会调用 validateCredential 向平台校验 Cookie 是否仍然有效。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("重新登录") {
                    Task { await prepareRelogin(entry: entry) }
                }
            } footer: {
                Text("Cookie 过期或切换账号时点这里，会打开登录页重新抓取。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
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
            MacPlatformLoginWebView(
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

            VStack(alignment: .leading, spacing: 8) {
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
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

    // MARK: - Cookie Polling (macOS 需要轮询)

    private func startCookiePolling(entry: LoginPlatformEntry) {
        cookiePollingTimer?.invalidate()
        pollCookieOnce(entry: entry)
        cookiePollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            pollCookieOnce(entry: entry)
        }
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
        guard !cookieString.isEmpty else { return }

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
            lastSavedCookieSignature = signature
            statusText = "登录信息已保存（宿主托管鉴权）"
            errorMessage = nil
            await syncService.refreshLoginStatus(pluginId: pluginId)
            if syncService.iCloudSyncEnabled {
                await syncService.syncAllToICloud()
            }
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
            if syncService.iCloudSyncEnabled {
                await syncService.syncAllToICloud()
            }
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
            showWebView = false
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

// MARK: - WebView (macOS)

private struct MacPlatformLoginWebView: NSViewRepresentable {
    let loginFlow: ManifestLoginFlow
    let onWebViewCreated: (WKWebView) -> Void
    let onNavigationStateChange: (String?, URL?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange)
    }

    func makeNSView(context: Context) -> WKWebView {
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

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private var effectiveUserAgent: String {
        let custom = loginFlow.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty {
            return custom
        }
        // 保持 UA 与 WebKit 能力一致，避免 Twitch 等站点把登录页判成异常浏览器。
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
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
            // 第三方登录按钮经常开新窗口；复用当前 WebView，Cookie 仍留在同一 dataStore。
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
