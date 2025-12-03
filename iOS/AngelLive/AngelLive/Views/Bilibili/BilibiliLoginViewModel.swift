//
//  BilibiliLoginViewModel.swift
//  AngelLive
//
//  Created by pangchong on 11/28/25.
//

import SwiftUI
import WebKit
import Combine
import AngelLiveCore

@MainActor
final class BilibiliLoginViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var statusText = "正在加载登录页面..."
    @Published var isLoading = true
    @Published var loginSuccess = false
    @Published var userInfo: BilibiliUserInfo?
    @Published var isValidatingCookie = false
    @Published var validationError: String?
    @Published var webViewKey = UUID()

    // MARK: - Properties

    nonisolated(unsafe) var currentWebView: WKWebView?
    private var viewVisible = true
    private var cookieExtractionWorkItem: DispatchWorkItem?

    // 登录页面 URL
    let loginURL = "https://passport.bilibili.com/h5-app/passport/login?gourl=https%3A%2F%2Flive.bilibili.com%2Fp%2Feden%2Farea-tags%3FparentAreaId%3D2%26areaId%3D86"

    // 登录成功后的标题关键词
    private let successTitleKeyword = "直播"
    private let targetRedirectKeyword = "live.bilibili.com/p/eden/area-tags"
    private let postRedirectDelay: TimeInterval = 3.0

    // MARK: - Cookie Management

    private let cookieKey = "SimpleLive.Setting.BilibiliCookie"
    private let uidKey = "LiveParse.Bilibili.uid"

    var cookie: String {
        get { UserDefaults.standard.string(forKey: cookieKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: cookieKey) }
    }

    var isLoggedIn: Bool {
        !cookie.isEmpty && cookie.contains("SESSDATA")
    }

    // MARK: - Lifecycle

    func onAppear() {
        viewVisible = true
        isLoading = true
        statusText = "正在加载登录页面..."
    }

    func onDisappear() {
        viewVisible = false
        cancelScheduledCookieExtraction()
    }

    // MARK: - Login Status Check

    func checkLoginStatus(title: String?, url: URL?, didFinish: Bool) {
        guard viewVisible else { return }

        if cookieExtractionWorkItem != nil && !didFinish {
            return
        }

        let pageTitle = title ?? ""
        statusText = pageTitle.isEmpty ? "正在加载..." : pageTitle

        guard didFinish else { return }

        guard let currentURL = url else {
            cancelScheduledCookieExtraction()
            return
        }

        if isTargetRedirect(url: currentURL) {
            isLoading = true
            statusText = "登录成功，正在获取登录信息..."
            scheduleCookieExtraction()
        } else if pageTitle.contains(successTitleKeyword) {
            // 登录成功后等待跳转到目标页
            isLoading = true
            statusText = "登录成功，正在跳转..."
            cancelScheduledCookieExtraction()
        } else {
            cancelScheduledCookieExtraction()
            isLoading = false
            if pageTitle.isEmpty {
                statusText = "请登录您的哔哩哔哩账号"
            }
        }
    }

    // MARK: - Cookie Extraction

    func extractAndSaveCookie() {
        cancelScheduledCookieExtraction()

        guard !loginSuccess else { return }
        guard let webView = currentWebView else {
            statusText = "获取登录信息失败，请重试"
            return
        }

        isLoading = true
        statusText = "正在保存登录信息..."

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            var cookieDict = [String: AnyObject]()
            for cookie in cookies {
                if cookie.domain.contains("bilibili") {
                    cookieDict[cookie.name] = cookie.properties as AnyObject?
                }
            }

            DispatchQueue.main.async {
                let cookieString = self.buildCookieString(from: cookieDict)

                if !cookieString.isEmpty {
                    self.cookie = cookieString

                    if let uid = self.extractValue(named: "DedeUserID", from: cookieDict) {
                        UserDefaults.standard.set(uid, forKey: self.uidKey)
                    }

                    BilibiliCookieSyncService.shared.syncToICloud()

                    // 仅清理 WebView 缓存，避免刚保存的 Cookie 被覆盖
                    BilibiliCookieManager.shared.clearWebViewCookies()

                    self.loginSuccess = true
                    self.isLoading = false
                    self.statusText = "登录成功，正在验证..."

                    print("[BilibiliLogin] Login successful, cookie saved")

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

    // MARK: - Cookie Validation

    func validateCookie() async {
        isValidatingCookie = true
        validationError = nil

        let result = await BilibiliUserService.shared.loadUserInfo(cookie: cookie)

        switch result {
        case .success(let info):
            userInfo = info
            validationError = nil
            if let mid = info.mid {
                UserDefaults.standard.set("\(mid)", forKey: uidKey)
            }
            print("[BilibiliLogin] Cookie 验证成功: \(info.displayName)")

        case .failure(let error):
            userInfo = nil
            validationError = error.localizedDescription
            print("[BilibiliLogin] Cookie 验证失败: \(error.localizedDescription)")
        }

        isValidatingCookie = false
    }

    // MARK: - Logout

    func logout() {
        cookie = ""
        UserDefaults.standard.removeObject(forKey: uidKey)

        clearWebsiteData()

        BilibiliCookieSyncService.shared.syncToICloud()

        // 清理 WebView 中的 Bilibili 缓存
        BilibiliCookieManager.shared.clearWebViewCookies()

        cancelScheduledCookieExtraction()
        loginSuccess = false
        isLoading = true
        statusText = "正在加载登录页面..."
        currentWebView = nil
        userInfo = nil
        validationError = nil
        isValidatingCookie = false

        webViewKey = UUID()
    }

    // MARK: - Helpers

    private func scheduleCookieExtraction() {
        guard !loginSuccess else { return }

        cancelScheduledCookieExtraction()

        let workItem = DispatchWorkItem { [weak self] in
            self?.extractAndSaveCookie()
        }
        cookieExtractionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + postRedirectDelay, execute: workItem)
    }

    private func cancelScheduledCookieExtraction() {
        cookieExtractionWorkItem?.cancel()
        cookieExtractionWorkItem = nil
    }

    private func isTargetRedirect(url: URL) -> Bool {
        url.absoluteString.contains(targetRedirectKeyword)
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

    func extractUidFromCookie() -> String? {
        UserDefaults.standard.string(forKey: uidKey)
    }

    private func clearWebsiteData() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let bilibiliRecords = records.filter { $0.displayName.contains("bilibili") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: bilibiliRecords) {
                print("[BilibiliLogin] Cleared Bilibili website data")
            }
        }
    }
}
