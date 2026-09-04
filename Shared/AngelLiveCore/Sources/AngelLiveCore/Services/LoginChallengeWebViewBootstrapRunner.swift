import Foundation

#if canImport(WebKit)
@preconcurrency import WebKit
#endif

enum LoginChallengeWebViewBootstrapRunner {
    static let isSupported: Bool = {
        #if canImport(WebKit)
        true
        #else
        false
        #endif
    }()

    @MainActor
    static func run(
        pluginId: String,
        transactionId: String,
        configuration: ManifestLoginChallengeBootstrap,
        store: LoginTransactionStore = .shared
    ) async throws -> LoginChallengeBootstrapResult {
        #if canImport(WebKit)
        guard let url = configuration.runnableURL else {
            return .skipped
        }
        let session = LoginChallengeWebViewBootstrapSession(
            pluginId: pluginId,
            transactionId: transactionId,
            configuration: configuration,
            url: url,
            store: store
        )
        return try await session.run()
        #else
        return .skipped
        #endif
    }
}

#if canImport(WebKit)
@MainActor
private final class LoginChallengeWebViewBootstrapSession: NSObject, WKNavigationDelegate {
    private let pluginId: String
    private let transactionId: String
    private let bootstrap: ManifestLoginChallengeBootstrap
    private let url: URL
    private let store: LoginTransactionStore
    private let clock = ContinuousClock()

    private var webView: WKWebView?
    private var dataStore: WKWebsiteDataStore?
    private var navigationCount = 0
    private var loadFailed = false

    init(
        pluginId: String,
        transactionId: String,
        configuration: ManifestLoginChallengeBootstrap,
        url: URL,
        store: LoginTransactionStore
    ) {
        self.pluginId = pluginId
        self.transactionId = transactionId
        bootstrap = configuration
        self.url = url
        self.store = store
    }

    func run() async throws -> LoginChallengeBootstrapResult {
        let startedAt = clock.now
        let deadline = startedAt.advanced(by: .milliseconds(bootstrap.timeoutMs))
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = websiteDataStore

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.customUserAgent = bootstrap.userAgent
        dataStore = websiteDataStore
        self.webView = webView
        defer { tearDown() }

        guard webView.load(URLRequest(url: url)) != nil else {
            return try await result(
                state: .failed,
                cookies: [],
                startedAt: startedAt
            )
        }

        while true {
            try Task.checkCancellation()
            let cookies = await allCookies(in: websiteDataStore.httpCookieStore)
            let acceptedNames = try await store.absorbWebViewCookies(
                pluginId: pluginId,
                transactionId: transactionId,
                cookies: cookies,
                allowedDomains: bootstrap.cookieDomains
            )

            if loadFailed || navigationCount > bootstrap.maxNavigations {
                return result(
                    state: .failed,
                    acceptedNames: acceptedNames,
                    startedAt: startedAt
                )
            }
            if !bootstrap.readyCookies.isEmpty,
               bootstrap.readyCookies.allSatisfy(acceptedNames.contains) {
                return result(
                    state: .ok,
                    acceptedNames: acceptedNames,
                    startedAt: startedAt
                )
            }
            if clock.now >= deadline {
                return result(
                    state: .timeout,
                    acceptedNames: acceptedNames,
                    startedAt: startedAt
                )
            }

            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationCount += 1
        if navigationCount > bootstrap.maxNavigations {
            webView.stopLoading()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        recordLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        recordLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadFailed = true
    }

    private func allCookies(in cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func recordLoadFailure(_ error: any Error) {
        let failure = error as NSError
        // A script-triggered reload can supersede an in-flight navigation.
        // WebKit reports that cancellation even though the replacement load is valid.
        guard failure.domain != NSURLErrorDomain || failure.code != NSURLErrorCancelled else {
            return
        }
        loadFailed = true
    }

    private func result(
        state: LoginChallengeBootstrapState,
        cookies: [HTTPCookie],
        startedAt: ContinuousClock.Instant
    ) async throws -> LoginChallengeBootstrapResult {
        let names = try await store.absorbWebViewCookies(
            pluginId: pluginId,
            transactionId: transactionId,
            cookies: cookies,
            allowedDomains: bootstrap.cookieDomains
        )
        return result(state: state, acceptedNames: names, startedAt: startedAt)
    }

    private func result(
        state: LoginChallengeBootstrapState,
        acceptedNames: Set<String>,
        startedAt: ContinuousClock.Instant
    ) -> LoginChallengeBootstrapResult {
        let reportedNames = bootstrap.reportedCookieNames.filter(acceptedNames.contains)
        return LoginChallengeBootstrapResult(
            state: state,
            cookieNames: reportedNames,
            navigations: navigationCount,
            elapsedMs: elapsedMilliseconds(since: startedAt)
        )
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let components = start.duration(to: clock.now).components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard !seconds.overflow else { return Int.max }
        let milliseconds = seconds.partialValue + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: milliseconds)
    }

    private func tearDown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        dataStore = nil
    }
}
#endif
