//
//  BilibiliCookieManager.swift
//  AngelLiveCore
//
//  Created by pangchong on 11/26/25.
//

import SwiftUI
#if !os(tvOS)
import WebKit
#endif
import LiveParse

/// Bilibili Cookie 自动获取管理器
/// 通过透明 WebView 访问 PC 版页面来获取必要的 Cookie
@MainActor
public final class BilibiliCookieManager: ObservableObject {
    public static let shared = BilibiliCookieManager()

    @Published public var isLoading = false
    @Published public var cookieReady = false
    @Published public var error: String?

    private init() {}

    /// 检查并在需要时自动获取 Cookie
    /// - Parameter forceRefresh: 是否强制刷新（清除旧 cookie 重新获取）
    public func setupCookieIfNeeded(forceRefresh: Bool = false) {
        if forceRefresh {
            print("[BilibiliCookieManager] 强制刷新 Cookie")
            clearAndRefetch()
            return
        }

        // 如果已经有 cookie，跳过
        let currentCookie = getBilibiliCookie()
        guard currentCookie.isEmpty else {
            print("[BilibiliCookieManager] Cookie 已存在，跳过获取")
            cookieReady = true
            return
        }

        print("[BilibiliCookieManager] Cookie 为空，需要获取")
        isLoading = true
    }

    /// 清除旧 Cookie 并强制重新获取
    public func clearAndRefetch() {
        print("[BilibiliCookieManager] 清除旧 Cookie 并重新获取")

        // 清除 UserDefaults 中的 cookie
        clearBilibiliCookie()

        clearWebViewCookies()

        // 重置状态并重新获取
        cookieReady = false
        error = nil
        isLoading = true
    }

    /// 仅清除 WebView 中的 Bilibili 相关缓存，不触发重新获取
    public func clearWebViewCookies() {
        #if !os(tvOS)
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let bilibiliRecords = records.filter { $0.displayName.contains("bilibili") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: bilibiliRecords) {
                print("[BilibiliCookieManager] 已清除 WebView 中的 Bilibili cookie")
            }
        }
        #endif
    }

    #if !os(tvOS)
    /// 设置获取到的 Cookie (仅 iOS/macOS，tvOS 不支持 WebView)
    public func setCookie(from cookies: [HTTPCookie]) {
        // 只保留 bilibili 域名的 cookie
        let bilibiliCookies = cookies.filter { cookie in
            cookie.domain.contains("bilibili")
        }

        let cookieString = bilibiliCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        print("[BilibiliCookieManager] 获取到 \(cookies.count) 个 Cookie，过滤后 \(bilibiliCookies.count) 个 Bilibili Cookie")
        print("[BilibiliCookieManager] Cookie 字符串: \(cookieString.prefix(100))...")

        // 统一通过 SyncService 持久化（含 uid）
        let dedeUserID = bilibiliCookies.first(where: { $0.name == "DedeUserID" })?.value
        setBilibiliCookie(cookieString, uid: dedeUserID)
        if let dedeUserID {
            print("[BilibiliCookieManager] 设置 uid = \(dedeUserID)")
        }

        isLoading = false
        cookieReady = true
        error = nil
    }
    #endif

    /// 设置错误
    public func setError(_ message: String) {
        print("[BilibiliCookieManager] 错误: \(message)")
        error = message
        isLoading = false
    }

    private func getBilibiliCookie() -> String {
        BilibiliCookieSyncService.shared.getCurrentCookie()
    }

    private func setBilibiliCookie(_ value: String, uid: String?) {
        BilibiliCookieSyncService.shared.setCookie(value, uid: uid, source: .local, save: true)
    }

    private func clearBilibiliCookie() {
        BilibiliCookieSyncService.shared.clearCookie(clearICloud: false)
    }
}

// MARK: - Transparent WebView for Cookie Fetching

#if os(macOS)
public struct BilibiliCookieFetcherView: NSViewRepresentable {
    @ObservedObject var manager: BilibiliCookieManager

    private let targetURL = URL(string: "https://live.bilibili.com/p/eden/area-tags?parentAreaId=2&areaId=0")!
    private let pcUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    public init(manager: BilibiliCookieManager = .shared) {
        self.manager = manager
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = pcUserAgent
        webView.setValue(false, forKey: "drawsBackground")

        let request = URLRequest(url: targetURL)
        webView.load(request)

        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        let manager: BilibiliCookieManager

        init(manager: BilibiliCookieManager) {
            self.manager = manager
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor in
                    self?.manager.setCookie(from: cookies)
                }
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                manager.setError(error.localizedDescription)
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                manager.setError(error.localizedDescription)
            }
        }
    }
}

#elseif os(iOS)
public struct BilibiliCookieFetcherView: UIViewRepresentable {
    @ObservedObject var manager: BilibiliCookieManager

    private let targetURL = URL(string: "https://live.bilibili.com/p/eden/area-tags?parentAreaId=2&areaId=0")!
    private let pcUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    public init(manager: BilibiliCookieManager = .shared) {
        self.manager = manager
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = pcUserAgent
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        let request = URLRequest(url: targetURL)
        webView.load(request)

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        let manager: BilibiliCookieManager

        init(manager: BilibiliCookieManager) {
            self.manager = manager
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor in
                    self?.manager.setCookie(from: cookies)
                }
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                manager.setError(error.localizedDescription)
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                manager.setError(error.localizedDescription)
            }
        }
    }
}

#elseif os(tvOS)
// tvOS 不支持 WKWebView，使用空视图占位
// tvOS 通过 BilibiliCookieSyncService 的 iCloud 同步或局域网同步获取 Cookie
public struct BilibiliCookieFetcherView: View {
    @ObservedObject var manager: BilibiliCookieManager

    public init(manager: BilibiliCookieManager = .shared) {
        self.manager = manager
    }

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                // tvOS 尝试从 iCloud 同步
                await tryICloudSync()
            }
    }

    private func tryICloudSync() async {
        let syncService = BilibiliCookieSyncService.shared

        // 如果启用了 iCloud 同步，尝试从 iCloud 获取
        if syncService.iCloudSyncEnabled {
            let success = await syncService.syncFromICloud()
            if success {
                manager.cookieReady = true
                manager.isLoading = false
                print("[BilibiliCookieManager] tvOS: 从 iCloud 同步成功")
                return
            }
        }

        // 如果 iCloud 同步失败或未启用，标记为需要手动登录
        manager.isLoading = false
        manager.cookieReady = false
        print("[BilibiliCookieManager] tvOS: 需要通过账号管理页面登录")
    }
}
#endif

// MARK: - View Modifier for Auto Cookie Setup

public struct BilibiliCookieSetupModifier: ViewModifier {
    @StateObject private var cookieManager = BilibiliCookieManager.shared
    let forceRefresh: Bool

    public init(forceRefresh: Bool = false) {
        self.forceRefresh = forceRefresh
    }

    public func body(content: Content) -> some View {
        content
            .background {
                if cookieManager.isLoading {
                    BilibiliCookieFetcherView(manager: cookieManager)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
            }
            .onAppear {
                cookieManager.setupCookieIfNeeded(forceRefresh: forceRefresh)
            }
    }
}

public extension View {
    /// 在视图出现时自动检查并设置 Bilibili Cookie
    /// - Parameter forceRefresh: 是否强制刷新（清除旧 cookie 重新获取）
    func setupBilibiliCookieIfNeeded(forceRefresh: Bool = false) -> some View {
        modifier(BilibiliCookieSetupModifier(forceRefresh: forceRefresh))
    }
}
