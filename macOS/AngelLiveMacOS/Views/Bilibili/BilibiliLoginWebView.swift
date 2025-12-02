//
//  BilibiliLoginWebView.swift
//  AngelLiveMacOS
//
//  Created by Claude on 11/29/25.
//

import SwiftUI
import WebKit

// MARK: - WebView Container (macOS)

struct BilibiliLoginWebView: NSViewRepresentable {
    let url: String
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

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }

        context.coordinator.startPolling(webView: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
        nsView.stopLoading()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigationStateChange: (String?, URL?, Bool) -> Void
        private var pollingTimer: Timer?
        private weak var webView: WKWebView?

        init(onNavigationStateChange: @escaping (String?, URL?, Bool) -> Void) {
            self.onNavigationStateChange = onNavigationStateChange
        }

        func startPolling(webView: WKWebView) {
            self.webView = webView
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self, let webView = self.webView else { return }
                self.onNavigationStateChange(webView.title, webView.url, false)
            }
        }

        func stopPolling() {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationStateChange(webView.title, webView.url, true)
        }
    }
}
