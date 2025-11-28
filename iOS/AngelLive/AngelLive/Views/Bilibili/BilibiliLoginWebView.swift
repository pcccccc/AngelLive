//
//  BilibiliLoginWebView.swift
//  AngelLive
//
//  Created by pangchong on 11/28/25.
//

import SwiftUI
import WebKit

// MARK: - WebView Container

struct BilibiliLoginWebView: UIViewRepresentable {
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

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }

        context.coordinator.startPolling(webView: webView)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
        uiView.stopLoading()
    }

    // MARK: - Coordinator

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
