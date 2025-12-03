//
//  BilibiliCookieDebugView.swift
//  AngelLive
//
//  Created by Claude on 12/3/25.
//

import SwiftUI
import WebKit

/// B站Cookie调试视图 - 注入Cookie并显示网页状态
struct BilibiliCookieDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    let cookie: String
    let debugURL = URL(string: "https://live.bilibili.com/p/eden/area-tags?parentAreaId=2&areaId=0")!

    var body: some View {
        NavigationStack {
            ZStack {
                CookieInjectedWebView(
                    url: debugURL,
                    cookie: cookie,
                    isLoading: $isLoading
                )

                if isLoading {
                    ProgressView("加载中...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
            }
            .navigationTitle("B站登录状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 支持Cookie注入的WebView
struct CookieInjectedWebView: UIViewRepresentable {
    let url: URL
    let cookie: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        // 在创建时注入Cookie并加载页面（只执行一次）
        injectCookies(into: webView) {
            let request = URLRequest(url: url)
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 不在这里做任何操作，避免重复加载
    }

    private func injectCookies(into webView: WKWebView, completion: @escaping () -> Void) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        // 解析cookie字符串
        let cookiePairs = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }

        var cookiesAdded = 0
        let totalCookies = cookiePairs.count

        guard totalCookies > 0 else {
            completion()
            return
        }

        for pair in cookiePairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { continue }

            let name = String(components[0])
            let value = String(components[1])

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: ".bilibili.com",
                .path: "/",
                .secure: true
            ]

            if let cookie = HTTPCookie(properties: properties) {
                cookieStore.setCookie(cookie) {
                    cookiesAdded += 1
                    if cookiesAdded == totalCookies {
                        // 等待一小段时间确保Cookie设置完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            completion()
                        }
                    }
                }
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CookieInjectedWebView

        init(_ parent: CookieInjectedWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
