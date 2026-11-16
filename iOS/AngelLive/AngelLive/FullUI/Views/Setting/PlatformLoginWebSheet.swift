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
    let startsWithLogin: Bool

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
    @State private var loginLifecycle = PlatformWebLoginLifecycle()

    init(pluginId: String, startsWithLogin: Bool = false) {
        self.pluginId = pluginId
        self.startsWithLogin = startsWithLogin
    }

    var body: some View {
        NavigationStack {
            Group {
                if loginLifecycle.isInitialStatusLoaded, let entry {
                    if let attemptID = loginLifecycle.attemptID {
                        loginContent(entry: entry, attemptID: attemptID)
                    } else {
                        statusContent(entry: entry)
                    }
                } else {
                    ProgressView("加载中...")
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        stopCookiePolling()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoggedIn && !showWebView {
                        Button("退出登录", role: .destructive) {
                            logout()
                        }
                    }
                }
            }
        }
        .task {
            let generation = loginLifecycle.beginLoading()
            let loadedEntry = await PlatformLoginRegistry.shared.entry(pluginId: pluginId)
            guard !Task.isCancelled, loginLifecycle.isCurrentGeneration(generation) else { return }
            if !startsWithLogin {
                await reloadLoginStatus(generation: generation)
            }
            guard !Task.isCancelled, loginLifecycle.isCurrentGeneration(generation) else { return }
            entry = loadedEntry
            loginLifecycle.completeInitialStatus(
                generation: generation,
                isAuthenticated: isLoggedIn,
                startsWithLogin: startsWithLogin
            )
        }
        .onDisappear {
            stopCookiePolling()
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
        let generation = loginLifecycle.generation
        isValidating = true
        validationMessage = nil
        let status = await PlatformSessionManager.shared.fetchCredentialStatus(pluginId: pluginId)
        guard loginLifecycle.isCurrentGeneration(generation) else { return }
        if let name = status?.userName, !name.isEmpty {
            userDisplayName = name
        }
        let result = await PlatformSessionManager.shared.validateSession(pluginId: pluginId)
        guard loginLifecycle.isCurrentGeneration(generation) else { return }
        await syncService.refreshLoginStatus(pluginId: pluginId)
        await reloadLoginStatus(generation: generation)
        guard loginLifecycle.isCurrentGeneration(generation) else { return }
        if !isLoggedIn {
            loginLifecycle.beginLoginAttempt()
        }
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
    private func loginContent(entry: LoginPlatformEntry, attemptID: UUID) -> some View {
        if let loginFlow = entry.loginFlow {
        VStack(spacing: 0) {
            PlatformLoginWebView(
                loginFlow: loginFlow,
                usesEphemeralSession: startsWithLogin,
                onWebViewCreated: { webView in
                    guard loginLifecycle.acceptsCallback(for: attemptID) else { return }
                    currentWebView = webView
                    startCookiePolling(entry: entry, attemptID: attemptID)
                },
                onNavigationStateChange: { title, url, didFinish in
                    guard loginLifecycle.acceptsCallback(for: attemptID) else { return }
                    updateNavigationStatus(title: title, url: url)
                    if didFinish {
                        pollCookieOnce(entry: entry, attemptID: attemptID)
                    }
                }
            )
            .id(attemptID)
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

    private func startCookiePolling(entry: LoginPlatformEntry, attemptID: UUID) {
        guard loginLifecycle.acceptsCallback(for: attemptID) else { return }
        cookiePollingTimer?.invalidate()
        pollCookieOnce(entry: entry, attemptID: attemptID)
        cookiePollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // startCookiePolling 在主线程调用,scheduledTimer 因而挂在主 runloop,回调也在主线程。
            MainActor.assumeIsolated {
                pollCookieOnce(entry: entry, attemptID: attemptID)
            }
        }
    }

    private func stopCookiePolling() {
        cookiePollingTimer?.invalidate()
        cookiePollingTimer = nil
        loginLifecycle.stopLoginAttempt()
        currentWebView = nil
        isSavingCookie = false
        isValidating = false
    }

    private func pollCookieOnce(entry: LoginPlatformEntry, attemptID: UUID) {
        guard loginLifecycle.acceptsCallback(for: attemptID),
              !isSavingCookie, let currentWebView else { return }
        guard let loginFlow = entry.loginFlow else { return }

        currentWebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                guard loginLifecycle.acceptsCallback(for: attemptID), !isSavingCookie else { return }
                let filteredCookies = cookies.filter { cookie in
                    loginFlow.cookieDomains.contains { hint in
                        cookie.domain.contains(hint)
                    }
                }

                let cookieString = makeCookieString(from: filteredCookies)
                guard !cookieString.isEmpty else { return }
                guard containsAuthenticatedCookie(in: filteredCookies, loginFlow: loginFlow) else { return }

                let signature = makeCookieSignature(from: filteredCookies)
                guard signature != lastSavedCookieSignature else { return }
                await saveCookie(cookieString, entry: entry, cookies: filteredCookies, signature: signature, attemptID: attemptID)
            }
        }
    }

    private func saveCookie(_ cookieString: String, entry: LoginPlatformEntry, cookies: [HTTPCookie], signature: String, attemptID: UUID) async {
        guard loginLifecycle.acceptsCallback(for: attemptID) else { return }
        guard !cookieString.isEmpty else {
            errorMessage = "未读取到有效 Cookie，请确认登录成功后重试。"
            statusText = "Cookie 读取失败"
            return
        }

        isSavingCookie = true
        errorMessage = nil
        statusText = "检测到登录状态，正在保存..."

        let uid = entry.loginFlow.flatMap { extractUID(from: cookies, loginFlow: $0) }
        let shouldValidate = entry.auth?.supportsValidation ?? false

        let result = await PlatformSessionManager.shared.loginWithCookie(
            pluginId: pluginId,
            cookie: cookieString,
            uid: uid,
            source: .local,
            validateBeforeSave: shouldValidate
        )

        // The session manager owns any committed result. A departed page only
        // discards its UI callback; it must not undo a completed login.
        guard loginLifecycle.acceptsCallback(for: attemptID) else { return }
        switch result {
        case .valid:
            isLoggedIn = true
            showWebView = false
            stopCookiePolling()
            let generation = loginLifecycle.generation
            lastSavedCookieSignature = signature
            statusText = "登录信息已保存（宿主托管鉴权）"
            errorMessage = nil
            await syncService.refreshLoginStatus(pluginId: pluginId)
            // 登录成功后刷新 session 并切回状态页
            await reloadLoginStatus(generation: generation)
            return
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

    // MARK: - Cookie 工具

    private func containsAuthenticatedCookie(in cookies: [HTTPCookie], loginFlow: ManifestLoginFlow) -> Bool {
        let names = Set(cookies.map(\.name))
        return loginFlow.authSignalCookies.contains { names.contains($0) }
    }

    private func makeCookieSignature(from cookies: [HTTPCookie]) -> String {
        cookies
            .sorted(by: { $0.name < $1.name })
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: ";")
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

    private func extractUID(from cookies: [HTTPCookie], loginFlow: ManifestLoginFlow) -> String? {
        let uidNames = loginFlow.uidCookieNames ?? []
        for name in uidNames {
            if let value = cookies.first(where: { $0.name == name })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Actions

    private func prepareRelogin(entry: LoginPlatformEntry) async {
        stopCookiePolling()
        let generation = loginLifecycle.generation
        statusText = "正在清理网页登录缓存..."
        errorMessage = nil
        lastSavedCookieSignature = nil
        currentWebView = nil
        if let flow = entry.loginFlow { await clearWebLoginData(for: flow) }
        guard !Task.isCancelled, loginLifecycle.isCurrentGeneration(generation) else { return }
        loginLifecycle.beginLoginAttempt()
        showWebView = true
        statusText = "请在网页中完成登录，系统会自动保存会话并由宿主托管鉴权。"
    }

    private func logout() {
        stopCookiePolling()
        let generation = loginLifecycle.generation
        Task {
            await syncService.clearSession(pluginId: pluginId)
            if let flow = entry?.loginFlow {
                await clearWebLoginData(for: flow)
            }
            await MainActor.run {
                guard loginLifecycle.isCurrentGeneration(generation) else { return }
                isLoggedIn = false
                currentSession = nil
                validationMessage = nil
                userDisplayName = nil
                showWebView = false
                statusText = "已退出登录"
                errorMessage = nil
                loginLifecycle.beginLoginAttempt()
                lastSavedCookieSignature = nil
            }
        }
    }

    @MainActor
    private func clearWebLoginData(for loginFlow: ManifestLoginFlow) async {
        let dataStore = WKWebsiteDataStore.default()
        let domainHints = webDataDomainHints(for: loginFlow)
        guard !domainHints.isEmpty else { return }

        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                let matchingCookies = cookies.filter { cookie in
                    domainHints.contains { hint in
                        normalizedDomain(cookie.domain).contains(hint)
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
                        normalizedDomain(record.displayName).contains(hint)
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

    private func webDataDomainHints(for loginFlow: ManifestLoginFlow) -> [String] {
        var hints = loginFlow.cookieDomains
        if let host = URL(string: loginFlow.loginURL)?.host {
            hints.append(host)
        }
        if let host = loginFlow.websiteHost {
            hints.append(host)
        }

        return Array(Set(hints.map(normalizedDomain).filter { !$0.isEmpty }))
    }

    private func normalizedDomain(_ domain: String) -> String {
        domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func reloadLoginStatus(generation: UUID) async {
        let session = await PlatformSessionManager.shared.getSession(pluginId: pluginId)
        guard !Task.isCancelled, loginLifecycle.isCurrentGeneration(generation) else { return }
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
                    guard loginLifecycle.isCurrentGeneration(generation) else { return }
                    userDisplayName = name
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
    let usesEphemeralSession: Bool
    let onWebViewCreated: (WKWebView) -> Void
    let onNavigationStateChange: (String?, URL?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = usesEphemeralSession
            ? WKWebsiteDataStore.nonPersistent()
            : WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        FullUINavigationStyle.configure(webView.scrollView)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if let userAgent = loginFlow.userAgent {
            webView.customUserAgent = userAgent
        }

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        if let url = URL(string: loginFlow.loginURL) {
            var request = URLRequest(url: url)
            if let userAgent = loginFlow.userAgent {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            webView.load(request)
        }
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
