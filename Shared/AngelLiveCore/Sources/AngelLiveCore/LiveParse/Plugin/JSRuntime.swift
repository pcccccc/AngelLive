import Foundation
@preconcurrency import JavaScriptCore

/// 一次性所有权转移盒 —— **本文件私有,用途只有一个**:把插件调用的 `payload`
/// 从调用方隔离域搬进 JSContext 所在的串行队列。
///
/// ## 为什么需要逃生舱
///
/// `[String: Any]` 不是 `Sendable`(`Any` 可能装引用类型),而 `JSValue(object:)`
/// 必须在 JSContext 的队列上构造,payload 无法避免跨隔离域。
///
/// ## 为什么不用别的办法
///
/// - **`sending` 修饰符**:实测会沿调用链向上传播,`LiveParsePluginManager.call` /
///   `callDecodable`、`PluginJSDanmakuDriver.call`、`LiveParsePluginUpdater`、
///   `LiveParseJSPlatformManager` 逐个被要求标注,公开 API 被污染,
///   且警告总数不降反升(13 → 16),JSRuntime 内部那条始终未清。已回退,见 commit 30a0b41。
/// - **跨域前 JSON 序列化**:`JSValue(object:)` 能桥接 `Date` 等
///   `JSONSerialization` 会拒绝的类型。现有代码对 payload 序列化用的是 `try?`,
///   说明 payload 不保证 JSON 安全,改走 JSON 会把「容忍失败」变成「抛错」,
///   属运行时行为变更。
///
/// ## 安全依据
///
/// `Dictionary` 是值类型,传参即拷贝(COW),调用方后续修改不会影响盒内的值。
/// 残余风险仅在于 `Any` 内部可能嵌有引用类型;插件 payload 按契约只含
/// 字符串/数字/布尔/嵌套字典与数组,不含共享可变对象。
///
/// **不要把这个类型挪出本文件或用于其他场景。**
private struct PluginPayloadTransferBox: @unchecked Sendable {
    let value: [String: Any]
}

private actor LoginTransactionRedirectState {
    private var setCookieHeaders: [String] = []
    private var failure: LoginTransactionError?

    func append(setCookies: [String]) {
        setCookieHeaders.append(contentsOf: setCookies)
    }

    func record(failure: LoginTransactionError) {
        if self.failure == nil { self.failure = failure }
    }

    func snapshot() -> (setCookies: [String], failure: LoginTransactionError?) {
        (setCookieHeaders, failure)
    }
}

private func isAllowedManagedCredentialTransport(_ url: URL?) -> Bool {
    guard let url else { return false }
    if url.scheme?.lowercased() == "https" { return true }
    guard url.scheme?.lowercased() == "http" else { return false }
    let host = url.host?.lowercased() ?? ""
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

private func isManifestManagedCredentialDestination(
    _ url: URL?,
    credentialDomains: [String]
) -> Bool {
    guard let host = url?.host?.lowercased(), !host.isEmpty else { return false }
    return credentialDomains.contains { rawDomain in
        let domain = rawDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }
}

private final class LoginTransactionRedirectDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    let state = LoginTransactionRedirectState()

    private let pluginId: String
    private let transactionId: String
    private let store: LoginTransactionStore
    private let followRedirects: Bool
    private let explicitCookieHeader: String?
    private let pluginHeaderNames: Set<String>
    private let credentialDomains: [String]
    private let originalURL: URL?

    init(
        pluginId: String,
        transactionId: String,
        store: LoginTransactionStore,
        followRedirects: Bool,
        explicitCookieHeader: String?,
        pluginHeaderNames: Set<String>,
        credentialDomains: [String],
        originalURL: URL?
    ) {
        self.pluginId = pluginId
        self.transactionId = transactionId
        self.store = store
        self.followRedirects = followRedirects
        self.explicitCookieHeader = explicitCookieHeader
        self.pluginHeaderNames = pluginHeaderNames
        self.credentialDomains = credentialDomains
        self.originalURL = originalURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard followRedirects else {
            completionHandler(nil)
            return
        }

        let setCookies = LoginTransactionStore.setCookieHeaders(from: response)
        guard let responseURL = response.url else {
            completionHandler(nil)
            return
        }

        let pluginId = pluginId
        let transactionId = transactionId
        let store = store
        let state = state
        let credentialDomains = credentialDomains
        guard isAllowedManagedCredentialTransport(request.url) else {
            Task {
                await state.record(failure: .invalidCookieScope)
                completionHandler(nil)
            }
            return
        }
        let sameOrigin = Self.isSameOrigin(originalURL, request.url)
        let isHTTPSDowngrade = responseURL.scheme?.lowercased() == "https"
            && request.url?.scheme?.lowercased() != "https"
        guard !isHTTPSDowngrade else {
            completionHandler(nil)
            return
        }
        let explicitCookieHeader = sameOrigin ? explicitCookieHeader : nil
        Task {
            do {
                try await store.absorb(
                    pluginId: pluginId,
                    transactionId: transactionId,
                    setCookieHeaders: setCookies,
                    responseURL: responseURL
                )
                await state.append(setCookies: setCookies)

                var redirectedRequest = request
                if !sameOrigin {
                    Self.removeCrossOriginPluginHeaders(
                        from: &redirectedRequest,
                        pluginHeaderNames: pluginHeaderNames
                    )
                }
                // 登录事务必须完全绕过系统 Cookie storage 与本地 URLCache，
                // 不能只依赖调用方恰好传入的 URLSessionConfiguration。
                redirectedRequest.httpShouldHandleCookies = false
                redirectedRequest.cachePolicy = .reloadIgnoringLocalCacheData
                redirectedRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                redirectedRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
                let transactionCookie: String
                if isManifestManagedCredentialDestination(
                    redirectedRequest.url,
                    credentialDomains: credentialDomains
                ) {
                    transactionCookie = try await store.cookieHeaderForNativeRouting(
                        pluginId: pluginId,
                        transactionId: transactionId,
                        for: redirectedRequest.url ?? request.url!
                    )
                } else {
                    transactionCookie = try await store.cookieHeader(
                        pluginId: pluginId,
                        transactionId: transactionId,
                        for: redirectedRequest.url
                    )
                }
                redirectedRequest.setValue(
                    mergedCookieHeader(transaction: transactionCookie, explicit: explicitCookieHeader),
                    forHTTPHeaderField: "Cookie"
                )
#if DEBUG
                Logger.debug(
                    """
                    [JSRuntime][HTTP][REDIRECT]
                    pluginId=\(pluginId)
                    request.url=\(redirectedRequest.url.map(SensitivePluginHTTPConsoleSummary.redactedURL) ?? "<missing>")
                    request.cookie=\(SensitivePluginHTTPConsoleSummary.cookieHeaderDiagnostics(redirectedRequest.value(forHTTPHeaderField: "Cookie")))
                    request.headers=\(SensitivePluginHTTPConsoleSummary.redactedHeaders(redirectedRequest.allHTTPHeaderFields ?? [:]))
                    """,
                    category: .plugin
                )
#endif
                completionHandler(redirectedRequest)
            } catch let error as LoginTransactionError {
                await state.record(failure: error)
                completionHandler(nil)
            } catch {
                await state.record(failure: .notFound)
                completionHandler(nil)
            }
        }
    }

    private static func isSameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              lhs.scheme?.lowercased() == rhs.scheme?.lowercased(),
              lhs.host?.lowercased() == rhs.host?.lowercased() else {
            return false
        }
        func effectivePort(_ url: URL) -> Int? {
            if let port = url.port { return port }
            switch url.scheme?.lowercased() {
            case "https": return 443
            case "http": return 80
            default: return nil
            }
        }
        return effectivePort(lhs) == effectivePort(rhs)
    }

    private static func removeCrossOriginPluginHeaders(
        from request: inout URLRequest,
        pluginHeaderNames: Set<String>
    ) {
        let credentialHeaders: Set<String> = [
            "authorization", "proxy-authorization", "cookie", "cookie2"
        ]
        for header in request.allHTTPHeaderFields?.keys.map({ $0 }) ?? [] where
            pluginHeaderNames.contains(header.lowercased())
                || credentialHeaders.contains(header.lowercased()) {
            request.setValue(nil, forHTTPHeaderField: header)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class ManagedCredentialRequestDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let originalURL: URL?
    private let pluginHeaderNames: Set<String>
    private let rejectsCrossOriginRedirects: Bool

    init(
        originalURL: URL?,
        pluginHeaderNames: Set<String>,
        rejectsCrossOriginRedirects: Bool
    ) {
        self.originalURL = originalURL
        self.pluginHeaderNames = pluginHeaderNames
        self.rejectsCrossOriginRedirects = rejectsCrossOriginRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let sameOrigin = Self.isSameOrigin(originalURL, request.url)
        let isHTTPSDowngrade = response.url?.scheme?.lowercased() == "https"
            && request.url?.scheme?.lowercased() != "https"
        // A credential placed in a query string or request body cannot be
        // selectively removed from URLSession's proposed redirect without
        // changing the plugin request semantics. Stop at the 3xx boundary
        // instead of allowing a credential-bearing request to cross origins.
        guard isAllowedManagedCredentialTransport(request.url),
              !isHTTPSDowngrade,
              sameOrigin || !rejectsCrossOriginRedirects else {
            completionHandler(nil)
            return
        }

        var redirectedRequest = request
        redirectedRequest.httpShouldHandleCookies = false
        redirectedRequest.cachePolicy = .reloadIgnoringLocalCacheData

        if !sameOrigin {
            let credentialHeaders: Set<String> = [
                "authorization", "proxy-authorization", "cookie", "cookie2"
            ]
            for header in redirectedRequest.allHTTPHeaderFields?.keys.map({ $0 }) ?? [] where
                pluginHeaderNames.contains(header.lowercased())
                    || credentialHeaders.contains(header.lowercased()) {
                redirectedRequest.setValue(nil, forHTTPHeaderField: header)
            }
        }
        // Host cache policy wins even if the plugin originally supplied these
        // header names and cross-origin stripping removed them above.
        redirectedRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        redirectedRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }

    private static func isSameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              lhs.scheme?.lowercased() == rhs.scheme?.lowercased(),
              lhs.host?.lowercased() == rhs.host?.lowercased() else {
            return false
        }
        func effectivePort(_ url: URL) -> Int? {
            if let port = url.port { return port }
            return url.scheme?.lowercased() == "https" ? 443 : (url.scheme?.lowercased() == "http" ? 80 : nil)
        }
        return effectivePort(lhs) == effectivePort(rhs)
    }
}

private func mergedCookieHeader(transaction: String?, explicit: String?) -> String? {
    func pairs(from header: String?) -> [(name: String, raw: String)] {
        guard let header else { return [] }
        return header.split(separator: ";", omittingEmptySubsequences: true).compactMap { component in
            let raw = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = raw.firstIndex(of: "=") else { return nil }
            let name = raw[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { return nil }
            return (name, raw)
        }
    }

    let explicitPairs = pairs(from: explicit)
    let explicitNames = Set(explicitPairs.map(\.name))
    let transactionPairs = pairs(from: transaction).filter { !explicitNames.contains($0.name) }
    let merged = (transactionPairs + explicitPairs).map(\.raw).joined(separator: "; ")
    return merged.isEmpty ? nil : merged
}

enum SensitivePluginHTTPConsoleSummary {
    static func responseBody(
        requestContainsCookieHeader: Bool? = nil
    ) -> String? {
        var summary: [String: Any] = [:]
        if let requestContainsCookieHeader {
            summary["request"] = [
                "cookieHeader": requestContainsCookieHeader ? "attached" : "missing"
            ]
        }

        guard !summary.isEmpty else { return nil }
        guard let encoded = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }

    static func containsCookieHeader(_ header: String?) -> Bool {
        header?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func cookieHeaderDiagnostics(_ header: String?) -> String {
        guard let header, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "missing"
        }
        let pairs = header.split(separator: ";", omittingEmptySubsequences: true).compactMap { component -> String? in
            let raw = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = raw.firstIndex(of: "=") else { return nil }
            let name = String(raw[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(raw[raw.index(after: separator)...])
            guard !name.isEmpty else { return nil }
            return "\(name){length=\(value.utf8.count),fingerprint=\(String(value.md5.prefix(12)))}"
        }
        return pairs.isEmpty ? "present(unparseable)" : pairs.joined(separator: ", ")
    }

    static func redactedHeaders(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "{}" }
        let sanitized = headers.reduce(into: [String: String]()) { result, item in
            let key = item.key.lowercased()
            if key == "cookie" {
                result[item.key] = cookieHeaderDiagnostics(item.value)
            } else if key == "set-cookie" {
                result[item.key] = "present{length=\(item.value.utf8.count),fingerprint=\(String(item.value.md5.prefix(12)))}"
            } else if isSensitiveHeaderKey(key) {
                result[item.key] = "<redacted>"
            } else {
                result[item.key] = item.value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "<unavailable>"
        }
        return string
    }

    static func redactedBody(_ rawBody: String?) -> String {
        guard let rawBody else { return "<non-UTF8 or empty>" }
        guard let data = rawBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return redactFormEncodedSecrets(in: rawBody)
        }
        let sanitized = redactJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let encoded = try? JSONSerialization.data(
                withJSONObject: sanitized,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: encoded, encoding: .utf8) else {
            return "<JSON serialization unavailable>"
        }
        return string
    }

    static func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "\(url.scheme ?? "?")://\(url.host ?? "?")\(url.path)"
        }
        let queryNames = components.queryItems?.map(\.name) ?? []
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let base = components.string ?? "\(url.scheme ?? "?")://\(url.host ?? "?")\(url.path)"
        return queryNames.isEmpty ? base : "\(base)?<keys:\(queryNames.joined(separator: ","))>"
    }

    static func redactedText(_ value: String) -> String {
        redactFormEncodedSecrets(in: value)
    }

    private static func redactJSONObject(_ value: Any, key: String? = nil) -> Any {
        if let key, isSensitiveKey(key) { return "<redacted>" }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redactJSONObject(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] {
            return array.map { redactJSONObject($0) }
        }
        if let string = value as? String {
            return redactFormEncodedSecrets(in: string)
        }
        return value
    }

    private static func isSensitiveHeaderKey(_ key: String) -> Bool {
        key == "authorization"
            || key == "proxy-authorization"
            || key.contains("auth")
            || key.contains("credential")
            || key.contains("csrf")
            || key.contains("vault")
            || key.contains("token")
            || key.contains("secret")
            || key.contains("session")
            || key.contains("ticket")
            || key.contains("signature")
    }

    private static func isSensitiveKey(_ rawKey: String) -> Bool {
        let key = rawKey.lowercased()
        if key == "code" || key == "uid" || key == "user_id" || key == "userid" {
            return true
        }
        return [
            "cookie", "token", "ticket", "credential", "password", "secret",
            "captcha", "mobile", "phone", "passport", "session", "verify",
            "qrcode", "qr_code", "qrcontent", "qr_content"
        ].contains { key.contains($0) }
    }

    private static func redactFormEncodedSecrets(in value: String) -> String {
        let pattern = #"(?i)(cookie|token|ticket|credential|password|secret|captcha|mobile|phone|passport|session|verify|code)=([^&\s]+)"#
        return value.replacingOccurrences(
            of: pattern,
            with: "$1=<redacted>",
            options: .regularExpression
        )
    }
}

/// A task may be cancelled while JavaScriptCore is evaluating a function or
/// waiting for a Promise that the plugin never settles. Keep continuation
/// completion one-shot and cancellation-aware without moving JSValue objects
/// off the runtime's serial queue.
private final class PluginCallCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Any, Error>?
    private var completed = false

    var isCompleted: Bool {
        lock.withLock { completed }
    }

    func install(_ continuation: CheckedContinuation<Any, Error>) {
        let wasCancelled = lock.withLock { () -> Bool in
            if completed { return true }
            self.continuation = continuation
            return false
        }
        if wasCancelled { continuation.resume(throwing: CancellationError()) }
    }

    func resume(returning value: sending Any) {
        let continuation = lock.withLock { () -> CheckedContinuation<Any, Error>? in
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let continuation = lock.withLock { () -> CheckedContinuation<Any, Error>? in
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: error)
    }

    func cancel() {
        resume(throwing: CancellationError())
    }
}

private final class PluginEvaluationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    var isCompleted: Bool {
        lock.withLock { completed }
    }

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        let wasCancelled = lock.withLock { () -> Bool in
            if completed { return true }
            self.continuation = continuation
            return false
        }
        if wasCancelled { continuation.resume(throwing: CancellationError()) }
    }

    func resume() {
        takeContinuation()?.resume()
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    func cancel() {
        resume(throwing: CancellationError())
    }

    private func takeContinuation() -> CheckedContinuation<Void, Error>? {
        lock.withLock {
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
    }
}

public final class JSRuntime: @unchecked Sendable {
    public typealias LogHandler = @Sendable (String) -> Void

    private struct HostHTTPCallback {
        let resolve: JSValue
        let reject: JSValue
        let envelope: HostHTTPRequestEnvelope
        let requestHeaders: [String: String]
        let parentSensitive: Bool
        let startedAt: CFAbsoluteTime
    }

    private struct HostSessionCallback {
        let resolve: JSValue
        let reject: JSValue
    }

    private struct PendingPromiseCall {
        let globalKey: String
        let completion: PluginCallCompletion
    }

    public static let supportedAPIVersion = 1

    private let queue: DispatchQueue
    private let context: JSContext
    private let pluginId: String
    private let session: URLSession
    private let nativeStream: ManifestNativeStream?
    private let httpFlightCoordinator: PluginHTTPFlightCoordinator
    private let loginTransactionStore: LoginTransactionStore
    /// Manifest-declared platform hosts that may receive a committed or
    /// isolated credential through native Host.http injection.
    private let credentialDomains: [String]
    /// An isolated candidate credential used only by this runtime. Login
    /// validation uses a short-lived runtime so an unconfirmed Cookie never
    /// enters the canonical vault observed by concurrent business calls.
    private let platformSessionOverride: LiveParsePlatformSession?
    /// 只允许在 `queue` 上读写。敏感插件调用执行期间，JS console 与
    /// runtime 异常日志都静默，防止插件把 Cookie/token 拼进任意字符串。
    private var sensitiveLoggingDepth = 0
    /// 只允许在 `queue` 上读写；JSValue 永不跨出 JavaScriptCore 串行队列。
    private var hostHTTPCallbacks: [UUID: HostHTTPCallback] = [:]
    /// Retain cancellable host request tasks until their matching JS callback
    /// is finished. An evicted sensitive runtime must not keep network work
    /// alive and deliver a late credential-bearing response.
    private var hostHTTPTasks: [UUID: Task<Void, Never>] = [:]
    /// 只允许在 `queue` 上读写；actor 任务仅携带 UUID 回到该队列。
    private var hostSessionCallbacks: [UUID: HostSessionCallback] = [:]
    /// 只允许在 `queue` 上读写。Promise 的 JS reaction 只捕获 call id；
    /// Swift continuation 在取消时会从这里移除，避免永不 settle 的插件
    /// Promise 永久保留 continuation 和敏感调用生命周期。
    private var pendingPromiseCalls: [String: PendingPromiseCall] = [:]

    public convenience init(
        pluginId: String,
        session: URLSession = .shared,
        nativeStream: ManifestNativeStream? = nil,
        loginTransactionStore: LoginTransactionStore = .shared,
        credentialDomains: [String] = [],
        logHandler: LogHandler? = nil
    ) {
        self.init(
            pluginId: pluginId,
            session: session,
            nativeStream: nativeStream,
            loginTransactionStore: loginTransactionStore,
            credentialDomains: credentialDomains,
            platformSessionOverride: nil,
            logHandler: logHandler
        )
    }

    init(
        pluginId: String,
        session: URLSession,
        nativeStream: ManifestNativeStream?,
        loginTransactionStore: LoginTransactionStore,
        credentialDomains: [String],
        platformSessionOverride: LiveParsePlatformSession?,
        logHandler: LogHandler?
    ) {
        self.queue = DispatchQueue(label: "liveparse.jsruntime.\(UUID().uuidString)")
        self.pluginId = pluginId
        self.session = session
        self.nativeStream = nativeStream
        self.httpFlightCoordinator = PluginHTTPFlightCoordinator()
        self.loginTransactionStore = loginTransactionStore
        self.credentialDomains = credentialDomains
        self.platformSessionOverride = platformSessionOverride

        var createdContext: JSContext?
        queue.sync {
            createdContext = JSContext()
        }
        self.context = createdContext!

        queue.sync {
            self.configureConsole(in: context, logHandler: logHandler)
            Self.configureExceptionHandler(in: context)
            self.configureHostHTTP(in: context)
            Self.configureHostCrypto(in: context)
            self.configureHostSession(in: context)
            self.configureHostPromiseCallbacks(in: context)
            Self.configureHostRuntime(in: context)
            Self.configureHostBootstrap(in: context)
            Self.configureHostNativeStream(in: context, queue: queue, nativeStream: nativeStream)
            Self.configureHostWebSocket(
                in: context,
                queue: queue,
                pluginId: pluginId,
                credentialDomains: credentialDomains,
                platformSessionOverride: platformSessionOverride
            )
        }
    }

    public func evaluate(script: String, sourceURL: URL? = nil) async throws {
        let completion = PluginEvaluationCompletion()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async {
                    guard !completion.isCompleted else { return }
                    if let sourceURL {
                        self.context.evaluateScript(script, withSourceURL: sourceURL)
                    } else {
                        self.context.evaluateScript(script)
                    }
                    if let exception = self.context.exception {
                        completion.resume(throwing: LiveParsePluginError.fromJSException(
                            exception.toString() ?? "<unknown>"
                        ))
                    } else {
                        completion.resume()
                    }
                }
            }
        } onCancel: {
            completion.cancel()
        }
    }

    public func evaluate(contentsOf url: URL) async throws {
        let script = try String(contentsOf: url, encoding: .utf8)
        try await evaluate(script: script, sourceURL: url)
    }

    public func pluginAPIVersion() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let pluginObject = self.context.objectForKeyedSubscript("LiveParsePlugin") else {
                        throw LiveParsePluginError.invalidReturnValue("Missing globalThis.LiveParsePlugin")
                    }
                    let apiVersionValue = pluginObject.forProperty("apiVersion")
                    let apiVersion = apiVersionValue?.toInt32() ?? 0
                    continuation.resume(returning: Int(apiVersion))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func callPluginFunction(name: String, payload: [String: Any] = [:]) async throws -> Any {
        // payload 必须跨到 JSContext 的串行队列才能构造 JSValue;
        // 装盒完成一次性所有权转移,理由与安全依据见 PluginPayloadTransferBox 文档。
        let payloadBox = PluginPayloadTransferBox(value: payload)
        let callID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let completion = PluginCallCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async {
                    guard !completion.isCompleted else { return }
                    do {
                        guard let pluginObject = self.context.objectForKeyedSubscript("LiveParsePlugin") else {
                            throw LiveParsePluginError.invalidReturnValue("Missing globalThis.LiveParsePlugin")
                        }
                        guard let fn = pluginObject.objectForKeyedSubscript(name), fn.isObject else {
                            throw LiveParsePluginError.invalidReturnValue("Missing function: \(name)")
                        }

                        let jsPayload = JSValue(object: payloadBox.value, in: self.context) as Any
                        guard let result = pluginObject.invokeMethod(name, withArguments: [jsPayload]) else {
                            if let exception = self.context.exception {
                                throw LiveParsePluginError.fromJSException(exception.toString() ?? "<unknown>")
                            }
                            throw LiveParsePluginError.invalidReturnValue("Function returned nil")
                        }

                        guard !completion.isCompleted else { return }
                        if Self.isPromise(result) {
                            self.awaitPromise(result, callID: callID, completion: completion)
                            return
                        }

                        completion.resume(returning: try Self.convertToJSONObject(result, in: self.context))
                    } catch {
                        if self.sensitiveLoggingDepth == 0 {
                            Logger.warning("[JSRuntime:\(self.pluginId)] callPluginFunction(\(name)) 异常: \(error)", category: .plugin)
                        }
                        completion.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            completion.cancel()
            queue.async {
                self.cancelPendingPromise(callID: callID)
            }
        }
    }

    public func invalidateHTTPFailureCache() async {
        await httpFlightCoordinator.invalidateFailures()
    }

    func pendingPromiseCallCountForTesting() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.pendingPromiseCalls.count)
            }
        }
    }

    /// 覆盖插件加载和函数调用的完整敏感区间。计数而非 Bool 是为了让同一
    /// runtime 的重叠调用保持保守静默，直到最后一个敏感调用结束。
    func beginSensitiveLoggingSuppression() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.sensitiveLoggingDepth += 1
                continuation.resume()
            }
        }
    }

    func endSensitiveLoggingSuppression() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.sensitiveLoggingDepth = max(0, self.sensitiveLoggingDepth - 1)
                continuation.resume()
            }
        }
    }

    /// Stop all host HTTP work owned by a runtime that will never be reused.
    /// Dropping callbacks is intentional: the parent plugin continuation has
    /// already been cancelled, so there is no remaining JS consumer to notify.
    func abandonInFlightOperations() async {
        await httpFlightCoordinator.cancelAll()
        await withCheckedContinuation { continuation in
            queue.async {
                for task in self.hostHTTPTasks.values {
                    task.cancel()
                }
                self.hostHTTPTasks.removeAll()
                self.hostHTTPCallbacks.removeAll()
                continuation.resume()
            }
        }
    }
}

private extension JSRuntime {
    func configureConsole(in context: JSContext, logHandler: LogHandler?) {
        let console = JSValue(newObjectIn: context)
        let log: @convention(block) (JSValue) -> Void = { [weak self, logHandler] value in
            guard self?.sensitiveLoggingDepth == 0 else { return }
            logHandler?(value.toString() ?? "")
        }
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        console?.setObject(log, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    static func configureExceptionHandler(in context: JSContext) {
        context.exceptionHandler = { _, exception in
            _ = exception
        }
    }

    static func configureHostBootstrap(in context: JSContext) {
        // 给插件提供一个稳定的 Host API 表层（底层由 __lp_* 提供）。
        let script = """
        (function () {
          // 提供最小浏览器环境 shim，供依赖 window/document/navigator 的第三方脚本使用
          if (typeof globalThis.document === "undefined") globalThis.document = {};
          if (typeof globalThis.window === "undefined") globalThis.window = {};
          if (typeof globalThis.navigator === "undefined") globalThis.navigator = {};
          if (!globalThis.navigator.userAgent) {
            globalThis.navigator.userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
          }

          // JavaScriptCore 默认没有浏览器环境里的 btoa/atob，弹幕插件会用它处理二进制帧。
          var __lpBase64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
          if (typeof globalThis.btoa !== "function") {
            globalThis.btoa = function (input) {
              var source = String(input || "");
              var output = "";
              for (var i = 0; i < source.length; i += 3) {
                var byte1 = source.charCodeAt(i);
                var byte2 = i + 1 < source.length ? source.charCodeAt(i + 1) : NaN;
                var byte3 = i + 2 < source.length ? source.charCodeAt(i + 2) : NaN;

                if (byte1 > 0xff || (!isNaN(byte2) && byte2 > 0xff) || (!isNaN(byte3) && byte3 > 0xff)) {
                  throw new Error("InvalidCharacterError");
                }

                var chunk = (byte1 << 16) | ((isNaN(byte2) ? 0 : byte2) << 8) | (isNaN(byte3) ? 0 : byte3);
                output += __lpBase64Alphabet.charAt((chunk >> 18) & 63);
                output += __lpBase64Alphabet.charAt((chunk >> 12) & 63);
                output += isNaN(byte2) ? "=" : __lpBase64Alphabet.charAt((chunk >> 6) & 63);
                output += isNaN(byte3) ? "=" : __lpBase64Alphabet.charAt(chunk & 63);
              }
              return output;
            };
          }
          if (typeof globalThis.atob !== "function") {
            globalThis.atob = function (input) {
              var source = String(input || "").replace(/[\\t\\n\\f\\r ]+/g, "");
              if (source.length % 4 === 1) {
                throw new Error("InvalidCharacterError");
              }
              var output = "";
              for (var i = 0; i < source.length; i += 4) {
                var enc1 = source.charAt(i);
                var enc2 = source.charAt(i + 1);
                var enc3 = source.charAt(i + 2);
                var enc4 = source.charAt(i + 3);
                var idx1 = __lpBase64Alphabet.indexOf(enc1);
                var idx2 = __lpBase64Alphabet.indexOf(enc2);
                var idx3 = enc3 === "=" ? 0 : __lpBase64Alphabet.indexOf(enc3);
                var idx4 = enc4 === "=" ? 0 : __lpBase64Alphabet.indexOf(enc4);

                if (idx1 < 0 || idx2 < 0 || (enc3 !== "=" && idx3 < 0) || (enc4 !== "=" && idx4 < 0)) {
                  throw new Error("InvalidCharacterError");
                }

                var chunk = (idx1 << 18) | (idx2 << 12) | (idx3 << 6) | idx4;
                output += String.fromCharCode((chunk >> 16) & 0xff);
                if (enc3 !== "=") output += String.fromCharCode((chunk >> 8) & 0xff);
                if (enc4 !== "=") output += String.fromCharCode(chunk & 0xff);
              }
              return output;
            };
          }

          globalThis.Host = globalThis.Host || {};
          Host.makeError = function (code, message, context) {
            var normalizedContext = {};
            if (context && typeof context === "object" && !Array.isArray(context)) {
              Object.keys(context).forEach(function (key) {
                var value = context[key];
                if (value === undefined || value === null) return;
                normalizedContext[String(key)] = String(value);
              });
            }
            var payload = {
              code: String(code || "UNKNOWN"),
              message: String(message || ""),
              context: normalizedContext
            };
            return new Error("LP_PLUGIN_ERROR:" + JSON.stringify(payload));
          };
          Host.raise = function (code, message, context) {
            throw Host.makeError(code, message, context);
          };

          Host.capabilities = Host.capabilities || {};
          Host.capabilities.loginTransaction = true;
          Host.capabilities.loginChallengeProtocol = \(PlatformLoginChallengeProtocol.currentVersion);
          Host.capabilities.credentialExposure = true;
          Host.capabilities.webSocketPlatformCookie = true;

          Host.http = Host.http || {};
          Host.http.request = function (options) {
            return new Promise(function (resolve, reject) {
              __lp_host_http_request(
                JSON.stringify(options || {}),
                function (resultJSON) {
                  resolve(JSON.parse(resultJSON));
                },
                function (err) {
                  var message = String(err || "host http request failed");
                  if (message.indexOf("LP_PLUGIN_ERROR:") !== -1) {
                    reject(new Error(message));
                  } else {
                    reject(Host.makeError("NETWORK", message, {}));
                  }
                }
              );
            });
          };

          Host.crypto = Host.crypto || {};
          Host.crypto.md5 = function (input) {
            return __lp_crypto_md5(String(input));
          };
          Host.crypto.base64Decode = function (input) {
            return __lp_crypto_base64_decode(String(input));
          };

          Host.session = Host.session || {};
          Host.session.getCookieHeader = function (platformId) {
            return __lp_host_session_get_cookie_header(String(platformId || ""));
          };
          Host.session.getTransactionCookieHeader = function () {
            return Promise.reject(Host.makeError(
              "UNSUPPORTED",
              "Login transaction cookie values are host-managed and unavailable to plugins",
              {}
            ));
          };
          Host.session.seedTransactionCookies = function (transactionId, cookies, scope) {
            return new Promise(function (resolve, reject) {
              __lp_host_session_seed_transaction_cookies(
                String(transactionId || ""),
                JSON.stringify(cookies || {}),
                JSON.stringify(scope || {}),
                function () { resolve({ ok: true }); },
                function (err) { reject(Host.makeError("INVALID_RESPONSE", String(err || "login transaction unavailable"), {})); }
              );
            });
          };

          Host.runtime = Host.runtime || {};
          Host.runtime.loadBuiltinScript = function (name) {
            return !!__lp_host_load_builtin_script(String(name || ""));
          };

          Host.nativeStream = Host.nativeStream || {};
          Host.nativeStream.resolve = function (options) {
            var request = options && typeof options === "object" ? options : {};
            return new Promise(function (resolve, reject) {
              __lp_host_native_stream_resolve(
                JSON.stringify(request),
                function (resultJSON) {
                  try {
                    resolve(JSON.parse(resultJSON || "{}"));
                  } catch (err) {
                    reject(Host.makeError("PARSE", String(err || "native stream parse failed"), {}));
                  }
                },
                function (err) {
                  reject(Host.makeError("UPSTREAM", String(err || "native stream request failed"), {
                    provider: request.provider || request.providerId || request.platformId || ""
                  }));
                }
              );
            });
          };

          Host.stream = Host.stream || {};
          Host.stream.resolve = Host.nativeStream.resolve;
          Host.stream.getInfo = Host.nativeStream.resolve;

          // 通用 WebSocket 桥:平台特定协议(TARS / 心跳 / 鉴权)全部在 plugin JS 里实现,
          // 宿主只搬字节,对协议零知识。
          Host.ws = Host.ws || {};
          Host.ws.open = function (options) {
            return new Promise(function (resolve, reject) {
              var pending = [];
              var handler = null;
              var bridgeHandler = function (eventJSON) {
                var event;
                try { event = JSON.parse(eventJSON); }
                catch (e) { event = { type: "error", message: String(e) }; }
                if (handler) {
                  try { handler(event); }
                  catch (err) { /* 用户回调异常不影响传输层 */ }
                } else {
                  pending.push(event);
                }
              };

              var sessionId;
              try {
                sessionId = String(__lp_host_ws_open(JSON.stringify(options || {}), bridgeHandler) || "");
              } catch (err) {
                reject(Host.makeError("WS_OPEN", String(err && err.message ? err.message : err), {}));
                return;
              }
              if (!sessionId) {
                reject(Host.makeError("WS_OPEN", "ws open failed: invalid options", {}));
                return;
              }

              var session = {
                sessionId: sessionId,
                onMessage: function (cb) {
                  handler = (typeof cb === "function") ? cb : null;
                  if (handler) {
                    while (pending.length) {
                      var ev = pending.shift();
                      try { handler(ev); } catch (e) { /* swallow */ }
                    }
                  }
                },
                send: function (frame) {
                  return new Promise(function (res, rej) {
                    __lp_host_ws_send(sessionId, JSON.stringify(frame || {}),
                      function () { res(); },
                      function (err) { rej(Host.makeError("WS_SEND", String(err || "ws send failed"), { sessionId: sessionId })); }
                    );
                  });
                },
                close: function (opts) {
                  return new Promise(function (res, rej) {
                    __lp_host_ws_close(sessionId, JSON.stringify(opts || {}),
                      function () { handler = null; pending.length = 0; res(); },
                      function (err) { rej(Host.makeError("WS_CLOSE", String(err || "ws close failed"), { sessionId: sessionId })); }
                    );
                  });
                }
              };
              resolve(session);
            });
          };

        })();
        """
        context.evaluateScript(script)
    }

    static func configureHostRuntime(in context: JSContext) {
        let loadBuiltinScript: @convention(block) (String) -> Bool = { scriptName in
            let raw = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return false }

            let fileName = (raw as NSString).deletingPathExtension
            let ext = (raw as NSString).pathExtension.isEmpty ? "js" : (raw as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: fileName, withExtension: ext) else {
                return false
            }
            guard let script = try? String(contentsOf: url, encoding: .utf8) else {
                return false
            }

            context.evaluateScript(script, withSourceURL: url)
            return context.exception == nil
        }
        context.setObject(loadBuiltinScript, forKeyedSubscript: "__lp_host_load_builtin_script" as NSString)
    }

    func configureHostHTTP(in context: JSContext) {
        let requestBlock: @convention(block) (String, JSValue, JSValue) -> Void = { [weak self] optionsJSON, resolve, reject in
            guard let self else {
                reject.call(withArguments: ["Host HTTP runtime released"])
                return
            }
            let optionsData = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any]) ?? [:]

            guard let envelope = Self.makeHostHTTPRequestEnvelope(
                options: options,
                pluginId: self.pluginId,
                credentialDomains: self.credentialDomains,
                sessionOverride: self.platformSessionOverride
            ) else {
                reject.call(withArguments: ["Invalid url"]) // already on JS thread
                return
            }
            if envelope.authMode == .loginTransaction,
               envelope.transactionId?.isEmpty != false {
                reject.call(withArguments: [Self.standardErrorMessage(
                    code: .invalidResponse,
                    message: "Login transaction identifier is required",
                    context: [:]
                )])
                return
            }

            var request = URLRequest(url: envelope.url)
            request.httpMethod = envelope.method
            request.timeoutInterval = envelope.timeout
            request.httpBody = envelope.body
            let protectsManagedCredential = envelope.authMode != .none
                || !envelope.cookieInject.isEmpty
            if protectsManagedCredential {
                request.httpShouldHandleCookies = false
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }

            var requestHeaders = envelope.headers
            if envelope.authMode == .platformCookie {
                requestHeaders = Self.removeProtectedHeaders(requestHeaders)
                if let cookieHeader = LiveParsePlatformSessionVault.mergedCookieHeader(
                    for: envelope.platformId,
                    sessionOverride: self.platformSessionOverride
                ) {
                    requestHeaders["Cookie"] = cookieHeader
                }
            }

            // 通用 cookieInject：从 cookie 取值注入到 header、query 或 body
            var injectedIntoURLOrBody = false
            if !envelope.cookieInject.isEmpty,
               envelope.authMode != .loginTransaction {
                var mutableURL = envelope.urlString
                var bodyJSON: [String: Any]?

                for rule in envelope.cookieInject {
                    guard let value = LiveParsePlatformSessionVault.cookieValue(
                        named: rule.cookieName,
                        for: envelope.platformId,
                        sessionOverride: self.platformSessionOverride
                    ),
                          !value.isEmpty else { continue }
                    let injectedValue = (rule.prefix ?? "") + value

                    switch rule.target {
                    case .header:
                        guard let headerName = rule.headerName else { continue }
                        requestHeaders[headerName] = injectedValue
                    case .query:
                        guard let queryName = rule.queryName else { continue }
                        var components = URLComponents(string: mutableURL)
                        var queryItems = components?.queryItems ?? []
                        queryItems.removeAll { $0.name == queryName }
                        queryItems.append(URLQueryItem(name: queryName, value: injectedValue))
                        components?.queryItems = queryItems
                        mutableURL = components?.string ?? mutableURL
                    case .body:
                        guard let bodyPath = rule.bodyPath else { continue }
                        if bodyJSON == nil {
                            if let existing = request.httpBody,
                               let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
                                bodyJSON = parsed
                            } else {
                                bodyJSON = [:]
                            }
                        }
                        let keyPath = bodyPath.split(separator: ".").map(String.init)
                            bodyJSON = Self.setNestedValue(in: bodyJSON ?? [:], keyPath: keyPath, value: injectedValue)
                    }
                }

                if mutableURL != envelope.urlString, let newURL = URL(string: mutableURL) {
                    request.url = newURL
                    injectedIntoURLOrBody = true
                }
                if let bodyJSON,
                   let encodedBody = try? JSONSerialization.data(withJSONObject: bodyJSON) {
                    request.httpBody = encodedBody
                    injectedIntoURLOrBody = true
                }
            }

            for (key, value) in requestHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            if protectsManagedCredential {
                request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            }

            // 至此 requestHeaders 不再变更。下面的响应闭包只用它做日志记录,
            // 捕获可变 var 会被判为「并发执行代码中引用捕获的 var」,
            // 故在此固化成不可变快照([String: String] 本身 Sendable)。
            let loggedRequestHeaders = requestHeaders
            let injectedHeaderNames = envelope.cookieInject.compactMap { rule in
                rule.target == .header ? rule.headerName?.lowercased() : nil
            }
            let pluginHeaderNames = Set(requestHeaders.keys.map { $0.lowercased() })
                .union(injectedHeaderNames)
            let rejectsCrossOriginRedirects = injectedIntoURLOrBody

            // 开发者控制台：记录请求开始时间
            let httpStartTime = CFAbsoluteTimeGetCurrent()

            let callbackID = UUID()
            self.hostHTTPCallbacks[callbackID] = HostHTTPCallback(
                resolve: resolve,
                reject: reject,
                envelope: envelope,
                requestHeaders: loggedRequestHeaders,
                parentSensitive: self.sensitiveLoggingDepth > 0,
                startedAt: httpStartTime
            )

            let flightKey = PluginHTTPFlightKey(
                pluginId: self.pluginId,
                sessionRevision: envelope.sessionRevision,
                method: envelope.method,
                singleFlightKey: envelope.singleFlightKey ?? "request:\(callbackID.uuidString)"
            )
            let coordinator = self.httpFlightCoordinator
            let session = self.session
            let finalRequest = request
            if envelope.authMode == .loginTransaction,
               let transactionId = envelope.transactionId {
                let pluginId = self.pluginId
                let store = self.loginTransactionStore
                let credentialDomains = self.credentialDomains
                let requestTask = Task { [weak self] in
                    do {
                        var transactionRequest = finalRequest
                        let transactionCookie: String
                        if isManifestManagedCredentialDestination(
                            finalRequest.url,
                            credentialDomains: credentialDomains
                        ) {
                            transactionCookie = try await store.cookieHeaderForNativeRouting(
                                pluginId: pluginId,
                                transactionId: transactionId,
                                for: finalRequest.url!
                            )
                        } else {
                            transactionCookie = try await store.cookieHeader(
                                pluginId: pluginId,
                                transactionId: transactionId,
                                for: finalRequest.url
                            )
                        }
                        let explicitCookie = Self.headerValue(named: "cookie", in: envelope.headers)
                        let mergedCookie = mergedCookieHeader(
                            transaction: transactionCookie,
                            explicit: explicitCookie
                        )
                        transactionRequest.setValue(
                            mergedCookie,
                            forHTTPHeaderField: "Cookie"
                        )
                        let allowsTransactionInjection = isManifestManagedCredentialDestination(
                            finalRequest.url,
                            credentialDomains: credentialDomains
                        )
                        var transactionInjectionValues: [String: String] = [:]
                        if allowsTransactionInjection {
                            for rule in envelope.cookieInject {
                                if let value = try await store.cookieValueForNativeInjection(
                                    pluginId: pluginId,
                                    transactionId: transactionId,
                                    named: rule.cookieName,
                                    for: finalRequest.url!
                                ) {
                                    transactionInjectionValues[rule.cookieName.lowercased()] = value
                                }
                            }
                        }
                        let injectedCookieHeader = Self.applyCookieInject(
                            envelope.cookieInject,
                            values: transactionInjectionValues,
                            to: &transactionRequest
                        )
                        let redirectCookieHeader = mergedCookieHeader(
                            transaction: explicitCookie,
                            explicit: injectedCookieHeader
                        )
                        let snapshot = try await Self.performLoginTransactionHTTPRequest(
                            session: session,
                            request: transactionRequest,
                            pluginId: pluginId,
                            transactionId: transactionId,
                            store: store,
                            followRedirects: envelope.followRedirects,
                            explicitCookieHeader: redirectCookieHeader,
                            pluginHeaderNames: pluginHeaderNames,
                            credentialDomains: credentialDomains
                        )
                        self?.queue.async { [weak self] in
                            self?.finishHostHTTPRequest(callbackID: callbackID, result: .success(snapshot))
                        }
                    } catch {
                        let failure = (error as? PluginHTTPFlightFailure)
                            ?? PluginHTTPFlightFailure(error: error)
                        self?.queue.async { [weak self] in
                            self?.finishHostHTTPRequest(callbackID: callbackID, result: .failure(failure))
                        }
                    }
                }
                self.hostHTTPTasks[callbackID] = requestTask
                return
            }

            let requestTask = Task { [weak self] in
                do {
                    let snapshot = try await coordinator.execute(
                        key: flightKey,
                        successTTL: envelope.singleFlightKey == nil ? 0 : envelope.successCacheTTL,
                        failureTTL: envelope.singleFlightKey == nil ? 0 : envelope.failureCacheTTL,
                        bypassCache: envelope.bypassSingleFlightCache
                    ) {
                        try await Self.performHostHTTPRequest(
                            session: session,
                            request: finalRequest,
                            protectsManagedCredential: protectsManagedCredential,
                            pluginHeaderNames: pluginHeaderNames,
                            rejectsCrossOriginRedirects: rejectsCrossOriginRedirects
                        )
                    }
                    self?.queue.async { [weak self] in
                        self?.finishHostHTTPRequest(callbackID: callbackID, result: .success(snapshot))
                    }
                } catch {
                    let failure = (error as? PluginHTTPFlightFailure)
                        ?? PluginHTTPFlightFailure(error: error)
                    self?.queue.async { [weak self] in
                        self?.finishHostHTTPRequest(callbackID: callbackID, result: .failure(failure))
                    }
                }
            }
            self.hostHTTPTasks[callbackID] = requestTask
        }

        context.setObject(requestBlock, forKeyedSubscript: "__lp_host_http_request" as NSString)
    }

    private enum HostHTTPAuthMode: String {
        case none
        case platformCookie = "platform_cookie"
        case loginTransaction = "login_transaction"
    }

    /// 通用 cookie 值注入规则：从 cookie 取值注入到 header、query 或 JSON body
    private struct CookieInjectRule {
        enum Target: String { case header, query, body }
        let cookieName: String
        let target: Target
        /// header name（target=header）
        let headerName: String?
        /// query parameter name（target=query）
        let queryName: String?
        /// JSON body key path，如 "data.token" → {"data":{"token":"xxx"}}（target=body）
        let bodyPath: String?
        /// 值前缀，如 "OAuth "
        let prefix: String?
    }

    private struct HostHTTPRequestEnvelope {
        let url: URL
        let urlString: String
        let method: String
        let headers: [String: String]
        let body: Data?
        let timeout: TimeInterval
        let authMode: HostHTTPAuthMode
        let platformId: String
        let transactionId: String?
        let followRedirects: Bool
        let cookieInject: [CookieInjectRule]
        let singleFlightKey: String?
        let successCacheTTL: TimeInterval
        let failureCacheTTL: TimeInterval
        let bypassSingleFlightCache: Bool
        let sessionRevision: String
    }

    private static func makeHostHTTPRequestEnvelope(
        options: [String: Any],
        pluginId: String,
        credentialDomains: [String],
        sessionOverride: LiveParsePlatformSession?
    ) -> HostHTTPRequestEnvelope? {
        let request = (options["request"] as? [String: Any]) ?? options
        guard let urlString = (request["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        let method = (request["method"] as? String)?.uppercased() ?? "GET"
        var headers = normalizedHeaders(request["headers"])

        let timeout = resolveTimeout(request: request, options: options)
        let body = resolveBody(request: request)

        let authRaw = ((options["authMode"] as? String) ?? "none").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let authMode = HostHTTPAuthMode(rawValue: authRaw) ?? .none
        let runtimePluginId = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        let requestedPlatformId = LiveParsePlatformSessionVault.canonicalPlatformId(
            ((options["platformId"] as? String) ?? pluginId)
        )
        let transactionId = (options["transactionId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let followRedirects = (options["followRedirects"] as? Bool)
            ?? (request["followRedirects"] as? Bool)
            ?? true
        let cookieInject = resolveCookieInject(options: options)
        guard authMode != .loginTransaction
                || cookieInject.allSatisfy({ $0.target == .header }) else {
            return nil
        }
        let requestedSingleFlightKey = (options["singleFlightKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let protectsManagedCredential = authMode != .none || !cookieInject.isEmpty
        guard !protectsManagedCredential || isAllowedManagedCredentialURL(
            url,
            authMode: authMode,
            credentialDomains: credentialDomains
        ) else {
            return nil
        }
        let singleFlightKey: String?
        if !protectsManagedCredential, (method == "GET" || method == "HEAD") {
            singleFlightKey = requestedSingleFlightKey?.isEmpty == false
                ? requestedSingleFlightKey
                : nil
        } else {
            // Credential-bearing responses must never join or populate the
            // plugin response cache. Besides stale auth, an anonymous call
            // could otherwise log a cached sensitive response as non-sensitive.
            singleFlightKey = nil
        }
        // 任何读取正式 vault 的路径都只能访问当前 runtime owner。platformId
        // 仍保留给无凭据请求作业务路由，但不能成为跨插件凭据查询入口。
        if authMode == .platformCookie || !cookieInject.isEmpty {
            guard !runtimePluginId.isEmpty, requestedPlatformId == runtimePluginId else {
                return nil
            }
        }
        let platformId = authMode == .platformCookie || !cookieInject.isEmpty
            ? runtimePluginId
            : requestedPlatformId

        if authMode == .platformCookie {
            headers = removeProtectedHeaders(headers)
        }

        return HostHTTPRequestEnvelope(
            url: url,
            urlString: urlString,
            method: method,
            headers: headers,
            body: body,
            timeout: timeout,
            authMode: authMode,
            platformId: platformId,
            transactionId: transactionId,
            followRedirects: followRedirects,
            cookieInject: cookieInject,
            singleFlightKey: singleFlightKey,
            successCacheTTL: millisecondsOption(options["successCacheTTLms"]) / 1_000,
            failureCacheTTL: millisecondsOption(options["failureCacheTTLms"]) / 1_000,
            bypassSingleFlightCache: (options["bypassSingleFlightCache"] as? Bool) == true,
            sessionRevision: authMode == .loginTransaction
                ? "login-transaction"
                : LiveParsePlatformSessionVault.revision(
                    for: platformId,
                    sessionOverride: sessionOverride
                )
        )
    }

    private static func millisecondsOption(_ value: Any?) -> TimeInterval {
        if let number = value as? NSNumber { return max(0, number.doubleValue) }
        if let string = value as? String, let number = Double(string) { return max(0, number) }
        return 0
    }

    private static func isAllowedManagedCredentialURL(
        _ url: URL,
        authMode: HostHTTPAuthMode,
        credentialDomains: [String]
    ) -> Bool {
        guard isAllowedManagedCredentialTransport(url) else { return false }
        // A transaction may bootstrap anonymous state at a registration host
        // outside the manifest login domains. Let that request run, then gate
        // the actual cookieInject application at request construction time.
        // This avoids rejecting the bootstrap merely because it declares rules
        // whose cookie values do not exist yet, while still preventing values
        // from being injected outside the manifest allowlist.
        if authMode == .loginTransaction { return true }
        return isManifestManagedCredentialDestination(url, credentialDomains: credentialDomains)
    }

    private static func applyCookieInject(
        _ rules: [CookieInjectRule],
        values: [String: String],
        to request: inout URLRequest
    ) -> String? {
        guard !rules.isEmpty else { return nil }
        var injectedCookieHeader: String?
        for rule in rules {
            guard let value = values[rule.cookieName.lowercased()],
                  !value.isEmpty else { continue }
            let injectedValue = (rule.prefix ?? "") + value
            switch rule.target {
            case .header:
                guard let headerName = rule.headerName, !headerName.isEmpty else { continue }
                if headerName.caseInsensitiveCompare("Cookie") == .orderedSame {
                    guard injectedValue.contains("=") else { continue }
                    request.setValue(
                        mergedCookieHeader(
                            transaction: request.value(forHTTPHeaderField: "Cookie"),
                            explicit: injectedValue
                        ),
                        forHTTPHeaderField: "Cookie"
                    )
                    injectedCookieHeader = mergedCookieHeader(
                        transaction: injectedCookieHeader,
                        explicit: injectedValue
                    )
                } else {
                    request.setValue(injectedValue, forHTTPHeaderField: headerName)
                }
            case .query:
                continue
            case .body:
                continue
            }
        }
        return injectedCookieHeader
    }

    private static func resolveCookieInject(options: [String: Any]) -> [CookieInjectRule] {
        guard let rawArray = options["cookieInject"] as? [[String: Any]] else { return [] }
        var rules: [CookieInjectRule] = []
        for item in rawArray {
            guard let cookieName = (item["cookieName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cookieName.isEmpty else { continue }
            let targetRaw = (item["target"] as? String)?.lowercased() ?? "header"
            let target = CookieInjectRule.Target(rawValue: targetRaw) ?? .header
            let headerName = (item["headerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryName = (item["queryName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyPath = (item["bodyPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = item["prefix"] as? String

            // 校验对应 target 的必填字段
            switch target {
            case .header: guard headerName != nil && !headerName!.isEmpty else { continue }
            case .query:  guard queryName != nil && !queryName!.isEmpty else { continue }
            case .body:   guard bodyPath != nil && !bodyPath!.isEmpty else { continue }
            }

            rules.append(CookieInjectRule(
                cookieName: cookieName,
                target: target,
                headerName: headerName,
                queryName: queryName,
                bodyPath: bodyPath,
                prefix: prefix
            ))
        }
        return rules
    }

    private static func resolveTimeout(request: [String: Any], options: [String: Any]) -> TimeInterval {
        func seconds(from any: Any?) -> TimeInterval? {
            if let value = any as? Double { return value }
            if let value = any as? NSNumber { return value.doubleValue }
            if let value = any as? String, let doubleValue = Double(value) { return doubleValue }
            return nil
        }

        func milliseconds(from any: Any?) -> TimeInterval? {
            guard let millis = seconds(from: any), millis > 0 else { return nil }
            return millis / 1000.0
        }

        func bounded(_ value: TimeInterval?) -> TimeInterval? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return min(max(value, 0.1), 120)
        }

        if let timeoutMs = bounded(milliseconds(from: request["timeoutMs"])) {
            return timeoutMs
        }
        if let timeout = bounded(seconds(from: request["timeout"])) {
            return timeout
        }
        if let timeoutMs = bounded(milliseconds(from: options["timeoutMs"])) {
            return timeoutMs
        }
        if let timeout = bounded(seconds(from: options["timeout"])) {
            return timeout
        }
        return 20
    }

    private static func resolveBody(request: [String: Any]) -> Data? {
        if let bodyBase64 = request["bodyBase64"] as? String,
           let bodyData = Data(base64Encoded: bodyBase64) {
            return bodyData
        }
        if let body = request["body"] as? String {
            return body.data(using: .utf8)
        }
        return nil
    }

    private static func performHostHTTPRequest(
        session: URLSession,
        request: URLRequest,
        protectsManagedCredential: Bool,
        pluginHeaderNames: Set<String>,
        rejectsCrossOriginRedirects: Bool
    ) async throws -> PluginHTTPFlightSnapshot {
        do {
            let data: Data
            let response: URLResponse
            if protectsManagedCredential {
                let delegate = ManagedCredentialRequestDelegate(
                    originalURL: request.url,
                    pluginHeaderNames: pluginHeaderNames,
                    rejectsCrossOriginRedirects: rejectsCrossOriginRedirects
                )
                (data, response) = try await session.data(for: request, delegate: delegate)
            } else {
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else {
                throw PluginHTTPFlightFailure(
                    domain: "AngelLive.HostHTTP",
                    code: 1,
                    receivedHTTPResponse: false,
                    message: "Host HTTP response was not HTTP"
                )
            }
            var headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String {
                    result[key] = String(describing: item.value)
                }
            }
            if headers["Set-Cookie"] == nil,
               let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
                headers["Set-Cookie"] = setCookie
            }
            return PluginHTTPFlightSnapshot(
                data: data,
                statusCode: http.statusCode,
                headers: headers,
                responseURL: http.url?.absoluteString ?? request.url?.absoluteString ?? "",
                setCookies: LoginTransactionStore.setCookieHeaders(from: http),
                requestContainsCookieHeader: SensitivePluginHTTPConsoleSummary.containsCookieHeader(
                    request.value(forHTTPHeaderField: "Cookie")
                ),
                requestCookieDiagnostics: SensitivePluginHTTPConsoleSummary.cookieHeaderDiagnostics(
                    request.value(forHTTPHeaderField: "Cookie")
                )
            )
        } catch let failure as PluginHTTPFlightFailure {
            throw failure
        } catch {
            throw PluginHTTPFlightFailure(error: error)
        }
    }

    private static func performLoginTransactionHTTPRequest(
        session: URLSession,
        request: URLRequest,
        pluginId: String,
        transactionId: String,
        store: LoginTransactionStore,
        followRedirects: Bool,
        explicitCookieHeader: String?,
        pluginHeaderNames: Set<String>,
        credentialDomains: [String]
    ) async throws -> PluginHTTPFlightSnapshot {
        do {
            try Task.checkCancellation()
            let redirectDelegate = LoginTransactionRedirectDelegate(
                pluginId: pluginId,
                transactionId: transactionId,
                store: store,
                followRedirects: followRedirects,
                explicitCookieHeader: explicitCookieHeader,
                pluginHeaderNames: pluginHeaderNames,
                credentialDomains: credentialDomains,
                originalURL: request.url
            )
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let http = response as? HTTPURLResponse else {
                throw PluginHTTPFlightFailure(
                    domain: "AngelLive.HostHTTP",
                    code: 1,
                    receivedHTTPResponse: false,
                    message: "Host HTTP response was not HTTP"
                )
            }

            let redirectSnapshot = await redirectDelegate.state.snapshot()
            if let failure = redirectSnapshot.failure { throw failure }

            let finalSetCookies = LoginTransactionStore.setCookieHeaders(from: http)
            guard let responseURL = http.url ?? request.url else {
                throw PluginHTTPFlightFailure(
                    domain: "AngelLive.HostHTTP",
                    code: 1,
                    receivedHTTPResponse: true,
                    message: "Host HTTP response URL was missing"
                )
            }
            try await store.absorb(
                pluginId: pluginId,
                transactionId: transactionId,
                setCookieHeaders: finalSetCookies,
                responseURL: responseURL
            )
            try Task.checkCancellation()

            var headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String {
                    result[key] = String(describing: item.value)
                }
            }
            if headers["Set-Cookie"] == nil,
               let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
                headers["Set-Cookie"] = setCookie
            }

            return PluginHTTPFlightSnapshot(
                data: data,
                statusCode: http.statusCode,
                headers: headers,
                responseURL: responseURL.absoluteString,
                setCookies: redirectSnapshot.setCookies + finalSetCookies,
                requestContainsCookieHeader: SensitivePluginHTTPConsoleSummary.containsCookieHeader(
                    request.value(forHTTPHeaderField: "Cookie")
                ),
                requestCookieDiagnostics: SensitivePluginHTTPConsoleSummary.cookieHeaderDiagnostics(
                    request.value(forHTTPHeaderField: "Cookie")
                )
            )
        } catch let failure as PluginHTTPFlightFailure {
            throw failure
        } catch {
            throw PluginHTTPFlightFailure(error: error)
        }
    }

    /// 必须在 JavaScriptCore 串行队列调用。
    private func finishHostHTTPRequest(
        callbackID: UUID,
        result: Result<PluginHTTPFlightSnapshot, PluginHTTPFlightFailure>
    ) {
        hostHTTPTasks.removeValue(forKey: callbackID)
        guard let callback = hostHTTPCallbacks.removeValue(forKey: callbackID) else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - callback.startedAt

        switch result {
        case .success(let snapshot):
            var headers = snapshot.headers
            let hidesManagedCookieValues = callback.envelope.authMode != .none
                || !callback.envelope.cookieInject.isEmpty
            if hidesManagedCookieValues {
                headers = Self.removeSetCookieHeaders(headers)
            }
            let setCookies = hidesManagedCookieValues ? [] : snapshot.setCookies
            let responseURL = hidesManagedCookieValues
                ? Self.sanitizedManagedResponseURL(snapshot.responseURL)
                : snapshot.responseURL
            let bodyText = String(data: snapshot.data, encoding: .utf8)
            let bodyBase64 = snapshot.data.base64EncodedString()
            Logger.debug(
                "[JSRuntime][HTTP] pluginId=\(pluginId) method=\(callback.envelope.method) status=\(snapshot.statusCode) bytes=\(snapshot.data.count) duration=\(String(format: "%.3f", elapsed))s",
                category: .plugin
            )
#if DEBUG
            let requestBody = callback.envelope.body.flatMap { String(data: $0, encoding: .utf8) }
            let transactionLabel = callback.envelope.transactionId.map {
                String($0.prefix(8))
            } ?? "none"
            let cookieInjectionLabel: String
            if callback.envelope.cookieInject.isEmpty {
                cookieInjectionLabel = "none"
            } else if isManifestManagedCredentialDestination(
                callback.envelope.url,
                credentialDomains: credentialDomains
            ) {
                cookieInjectionLabel = "allowed_manifest_destination"
            } else {
                cookieInjectionLabel = "skipped_non_manifest_destination"
            }
            Logger.debug(
                """
                [JSRuntime][HTTP][DETAIL]
                pluginId=\(pluginId)
                request.method=\(callback.envelope.method)
                request.url=\(SensitivePluginHTTPConsoleSummary.redactedURL(callback.envelope.url))
                request.authMode=\(callback.envelope.authMode.rawValue)
                request.transaction=\(transactionLabel)
                request.cookieInject=\(cookieInjectionLabel)
                request.cookie=\(snapshot.requestCookieDiagnostics)
                request.headers=\(SensitivePluginHTTPConsoleSummary.redactedHeaders(callback.requestHeaders))
                request.body=\(SensitivePluginHTTPConsoleSummary.redactedBody(requestBody))
                response.status=\(snapshot.statusCode)
                response.headers=\(SensitivePluginHTTPConsoleSummary.redactedHeaders(snapshot.headers))
                response.body=
                \(SensitivePluginHTTPConsoleSummary.redactedBody(bodyText))
                """,
                category: .plugin
            )
#endif
            if PluginConsoleService.shared.isEnabled {
                Self.logHTTPRecord(
                    pluginId: pluginId,
                    envelope: callback.envelope,
                    requestHeaders: callback.requestHeaders,
                    parentSensitive: callback.parentSensitive,
                    statusCode: snapshot.statusCode,
                    responseHeaders: headers,
                    responseBody: bodyText,
                    requestContainsCookieHeader: callback.envelope.authMode == .loginTransaction
                        ? snapshot.requestContainsCookieHeader
                        : nil,
                    error: nil,
                    duration: elapsed
                )
            }
            let payload: [String: Any] = [
                "status": snapshot.statusCode,
                "headers": headers,
                "setCookies": setCookies,
                "url": responseURL,
                "bodyText": bodyText ?? NSNull(),
                "bodyBase64": bodyBase64
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            callback.resolve.call(withArguments: [String(data: data, encoding: .utf8) ?? "{}"])

        case .failure(let failure):
#if DEBUG
            let requestBody = callback.envelope.body.flatMap { String(data: $0, encoding: .utf8) }
            let transactionLabel = callback.envelope.transactionId.map {
                String($0.prefix(8))
            } ?? "none"
            let cookieInjectionLabel: String
            if callback.envelope.cookieInject.isEmpty {
                cookieInjectionLabel = "none"
            } else if isManifestManagedCredentialDestination(
                callback.envelope.url,
                credentialDomains: credentialDomains
            ) {
                cookieInjectionLabel = "allowed_manifest_destination"
            } else {
                cookieInjectionLabel = "skipped_non_manifest_destination"
            }
            Logger.debug(
                """
                [JSRuntime][HTTP][DETAIL][FAILURE]
                pluginId=\(pluginId)
                request.method=\(callback.envelope.method)
                request.url=\(SensitivePluginHTTPConsoleSummary.redactedURL(callback.envelope.url))
                request.authMode=\(callback.envelope.authMode.rawValue)
                request.transaction=\(transactionLabel)
                request.cookieInject=\(cookieInjectionLabel)
                request.headers=\(SensitivePluginHTTPConsoleSummary.redactedHeaders(callback.requestHeaders))
                request.body=\(SensitivePluginHTTPConsoleSummary.redactedBody(requestBody))
                failure.domain=\(failure.domain)
                failure.code=\(failure.code)
                failure.receivedHTTPResponse=\(failure.receivedHTTPResponse)
                failure.message=\(SensitivePluginHTTPConsoleSummary.redactedText(failure.message))
                """,
                category: .plugin
            )
#endif
            if PluginConsoleService.shared.isEnabled {
                Self.logHTTPRecord(
                    pluginId: pluginId,
                    envelope: callback.envelope,
                    requestHeaders: callback.requestHeaders,
                    parentSensitive: callback.parentSensitive,
                    statusCode: nil,
                    responseHeaders: nil,
                    responseBody: nil,
                    requestContainsCookieHeader: nil,
                    error: failure.message,
                    duration: elapsed
                )
            }
            if failure.domain == "AngelLive.HostHTTP", failure.code == 1 {
                callback.reject.call(withArguments: [Self.hostHTTPInvalidResponseMessage()])
            } else {
                callback.reject.call(withArguments: [
                    Self.hostHTTPFailureMessage(failure)
                ])
            }
        }
        context.evaluateScript("void(0)")
    }

    private static func normalizedHeaders(_ raw: Any?) -> [String: String] {
        guard let headers = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in headers {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                result[key] = numberValue.stringValue
            }
        }
        return result
    }

    /// Host HTTP 失败通过插件标准错误信封回到 Swift，保留底层 domain/code，
    /// 避免收藏策略退化为解析 localizedDescription。信封不包含请求 URL 或凭证。
    private static func hostHTTPFailureMessage(
        _ failure: PluginHTTPFlightFailure
    ) -> String {
        let code: LiveParsePluginStandardErrorCode =
            failure.domain == NSURLErrorDomain
            && failure.code == URLError.Code.timedOut.rawValue
            ? .timeout
            : .network
        return standardErrorMessage(
            code: code,
            message: code == .timeout ? "Host HTTP request timed out" : "Host HTTP request failed",
            context: [
                "underlyingDomain": failure.domain,
                "underlyingCode": String(failure.code),
                "receivedHTTPResponse": failure.receivedHTTPResponse ? "true" : "false"
            ]
        )
    }

    private static func hostHTTPFailureMessage(
        _ error: Error,
        receivedHTTPResponse: Bool
    ) -> String {
        let nsError = error as NSError
        let code: LiveParsePluginStandardErrorCode =
            nsError.domain == NSURLErrorDomain && nsError.code == URLError.Code.timedOut.rawValue
            ? .timeout
            : .network
        return standardErrorMessage(
            code: code,
            message: code == .timeout ? "Host HTTP request timed out" : "Host HTTP request failed",
            context: [
                "underlyingDomain": nsError.domain,
                "underlyingCode": String(nsError.code),
                "receivedHTTPResponse": receivedHTTPResponse ? "true" : "false"
            ]
        )
    }

    private static func hostHTTPInvalidResponseMessage() -> String {
        standardErrorMessage(
            code: .invalidResponse,
            message: "Host HTTP response was not HTTP",
            context: ["receivedHTTPResponse": "false"]
        )
    }

    private static func standardErrorMessage(
        code: LiveParsePluginStandardErrorCode,
        message: String,
        context: [String: String]
    ) -> String {
        let payload = LiveParsePluginStandardError(code: code, message: message, context: context)
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "LP_PLUGIN_ERROR:{\"code\":\"\(code.rawValue)\",\"message\":\"Host HTTP request failed\",\"context\":{}}"
        }
        return "LP_PLUGIN_ERROR:\(json)"
    }

    /// 将 HTTP 请求/响应记录到开发者控制台
    private static func logHTTPRecord(
        pluginId: String,
        envelope: HostHTTPRequestEnvelope,
        requestHeaders: [String: String],
        parentSensitive: Bool,
        statusCode: Int?,
        responseHeaders: [String: String]?,
        responseBody: String?,
        requestContainsCookieHeader: Bool?,
        error: String?,
        duration: TimeInterval
    ) {
        // 跟父调用对齐:无条件记录 HTTP 子请求,挂到当前活跃的 entry 上。
        // 没有活跃 entry(很罕见,通常意味着插件函数已结束)才跳过。
        let console = PluginConsoleService.shared
        guard let entryId = console.activeEntryId(for: pluginId) else { return }

        let hasProtectedHeader = requestHeaders.keys.contains { key in
            let lowered = key.lowercased()
            return lowered == "cookie" || lowered == "authorization" || lowered == "proxy-authorization"
        }
        let sensitive = parentSensitive
            || envelope.authMode == .loginTransaction
            || envelope.authMode == .platformCookie
            || !envelope.cookieInject.isEmpty
            || hasProtectedHeader
        let bodyStr: String? = sensitive
            ? nil
            : envelope.body.flatMap { String(data: $0, encoding: .utf8) }
        let loggedResponseBody = sensitive
            ? SensitivePluginHTTPConsoleSummary.responseBody(
                requestContainsCookieHeader: requestContainsCookieHeader
            )
            : responseBody.map { String($0.prefix(2_000)) }
        let loggedURL: String
        if sensitive {
            var components = URLComponents()
            components.scheme = envelope.url.scheme
            components.host = envelope.url.host
            components.port = envelope.url.port
            loggedURL = components.string ?? envelope.url.host ?? "<redacted>"
        } else {
            loggedURL = envelope.urlString
        }

        let record = PluginConsoleHTTPRecord(
            url: loggedURL,
            method: envelope.method,
            headers: sensitive ? [:] : requestHeaders,
            body: bodyStr,
            statusCode: statusCode,
            responseHeaders: sensitive ? nil : responseHeaders,
            responseBody: loggedResponseBody,
            error: sensitive && error != nil ? "Sensitive plugin request failed" : error,
            duration: duration
        )

        Task { @MainActor in
            console.appendHTTPRecord(entryId: entryId, record: record)
        }
    }

    /// 按 key path 设置嵌套字典值，如 ["data","token"] → {"data":{"token":"xxx"}}
    private static func setNestedValue(in dict: [String: Any], keyPath: [String], value: Any) -> [String: Any] {
        guard let first = keyPath.first else { return dict }
        var result = dict
        if keyPath.count == 1 {
            result[first] = value
        } else {
            let nested = (result[first] as? [String: Any]) ?? [:]
            result[first] = setNestedValue(in: nested, keyPath: Array(keyPath.dropFirst()), value: value)
        }
        return result
    }

    private static func removeProtectedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { key, _ in
            let lowered = key.lowercased()
            return lowered != "cookie" && lowered != "authorization"
        }
    }

    private static func removeSetCookieHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { key, _ in
            key.lowercased() != "set-cookie"
        }
    }

    private static func sanitizedManagedResponseURL(_ string: String) -> String {
        guard var components = URLComponents(string: string) else { return "" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? ""
    }

    private static func headerValue(named name: String, in headers: [String: String]) -> String? {
        headers.first { key, _ in key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func configureHostCrypto(in context: JSContext) {
        let md5Block: @convention(block) (String) -> String = { input in
            input.md5
        }
        let base64DecodeBlock: @convention(block) (String) -> String = { input in
            guard let decoded = input.removingPercentEncoding,
                  let data = Data(base64Encoded: decoded),
                  let str = String(data: data, encoding: .utf8)
            else {
                return ""
            }
            return str
        }
        context.setObject(md5Block, forKeyedSubscript: "__lp_crypto_md5" as NSString)
        context.setObject(base64DecodeBlock, forKeyedSubscript: "__lp_crypto_base64_decode" as NSString)
    }

    func configureHostSession(in context: JSContext) {
        // Some platform login/signing implementations must read the complete
        // Cookie header while building their own signature. Keep the legacy
        // synchronous API, but scope it to this runtime's plugin identity so a
        // plugin cannot inspect another platform's credential. Isolated login
        // validation runtimes read their candidate override, never the
        // concurrently committed vault value.
        let getCookieHeaderBlock: @convention(block) (String) -> String = {
            [pluginId, platformSessionOverride] requestedPlatformId in
            let owner = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
            let requested = requestedPlatformId.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = requested.isEmpty
                ? owner
                : LiveParsePlatformSessionVault.canonicalPlatformId(requested)
            guard !owner.isEmpty, target == owner else { return "" }
            return LiveParsePlatformSessionVault.mergedCookieHeader(
                for: owner,
                sessionOverride: platformSessionOverride
            ) ?? ""
        }
        context.setObject(
            getCookieHeaderBlock,
            forKeyedSubscript: "__lp_host_session_get_cookie_header" as NSString
        )

        let seedTransactionCookiesBlock: @convention(block) (String, String, String, JSValue, JSValue) -> Void = {
            [weak self] transactionId, cookiesJSON, scopeJSON, resolve, reject in
            guard let self else {
                reject.call(withArguments: ["Login transaction runtime released"])
                return
            }

            let cookiesObject = Self.jsonObject(from: cookiesJSON)
            let cookies = cookiesObject.reduce(into: [String: String]()) { result, item in
                if let string = item.value as? String {
                    result[item.key] = string
                } else if let number = item.value as? NSNumber {
                    result[item.key] = number.stringValue
                }
            }
            let scope = Self.jsonObject(from: scopeJSON)
            let domain = (scope["domain"] as? String) ?? ""
            let path = (scope["path"] as? String) ?? "/"
            let secure = (scope["secure"] as? Bool) ?? false

            let callbackID = UUID()
            self.hostSessionCallbacks[callbackID] = HostSessionCallback(resolve: resolve, reject: reject)
            let store = self.loginTransactionStore
            let pluginId = self.pluginId
            Task { [weak self] in
                let result: Result<Void, LoginTransactionError>
                do {
                    try await store.seed(
                        pluginId: pluginId,
                        transactionId: transactionId,
                        cookies: cookies,
                        domain: domain,
                        path: path,
                        secure: secure
                    )
                    result = .success(())
                } catch let error as LoginTransactionError {
                    result = .failure(error)
                } catch {
                    result = .failure(.notFound)
                }
                self?.queue.async { [weak self] in
                    self?.finishHostSessionSeed(callbackID: callbackID, result: result)
                }
            }
        }
        context.setObject(
            seedTransactionCookiesBlock,
            forKeyedSubscript: "__lp_host_session_seed_transaction_cookies" as NSString
        )
    }

    /// Must run on the JavaScriptCore queue.
    func finishHostSessionSeed(
        callbackID: UUID,
        result: Result<Void, LoginTransactionError>
    ) {
        guard let callback = hostSessionCallbacks.removeValue(forKey: callbackID) else { return }
        switch result {
        case .success:
            callback.resolve.call(withArguments: [])
        case .failure(let error):
            callback.reject.call(withArguments: [error.localizedDescription])
        }
        context.evaluateScript("void(0)")
    }

    static func jsonObject(from string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    static func isPromise(_ value: JSValue) -> Bool {
        guard value.isObject else { return false }
        let then = value.forProperty("then")
        return then?.isObject == true
    }

    func configureHostPromiseCallbacks(in context: JSContext) {
        let resolve: @convention(block) (String, JSValue) -> Void = { [weak self] callID, value in
            self?.finishPendingPromise(callID: callID, value: value, isRejection: false)
        }
        let reject: @convention(block) (String, JSValue) -> Void = { [weak self] callID, value in
            self?.finishPendingPromise(callID: callID, value: value, isRejection: true)
        }
        context.setObject(resolve, forKeyedSubscript: "__lp_host_promise_resolve" as NSString)
        context.setObject(reject, forKeyedSubscript: "__lp_host_promise_reject" as NSString)
    }

    /// Must run on the JavaScriptCore queue. Per-call JS reactions capture only
    /// an opaque id and invoke shared host callbacks; they never retain a Swift
    /// continuation if a plugin Promise remains pending forever.
    func awaitPromise(
        _ promise: JSValue,
        callID: String,
        completion: PluginCallCompletion
    ) {
        let key = "_lp_await_\(callID)"
        pendingPromiseCalls[callID] = PendingPromiseCall(
            globalKey: key,
            completion: completion
        )
        context.setObject(promise, forKeyedSubscript: key as NSString)
        context.evaluateScript("""
        globalThis.\(key).then(
          function(value) { __lp_host_promise_resolve("\(callID)", value); },
          function(error) { __lp_host_promise_reject("\(callID)", error); }
        );
        delete globalThis.\(key);
        """)
        if let exception = context.exception {
            pendingPromiseCalls.removeValue(forKey: callID)
            context.evaluateScript("delete globalThis.\(key);")
            completion.resume(throwing:
                LiveParsePluginError.fromJSException(exception.toString() ?? "<unknown>")
            )
        }
    }

    /// Must run on the JavaScriptCore queue.
    func finishPendingPromise(callID: String, value: JSValue, isRejection: Bool) {
        guard let pending = pendingPromiseCalls.removeValue(forKey: callID) else { return }
        context.evaluateScript("delete globalThis.\(pending.globalKey);")
        if isRejection {
            pending.completion.resume(throwing:
                LiveParsePluginError.fromJSException(value.toString() ?? "<unknown>")
            )
            return
        }
        do {
            pending.completion.resume(returning: try Self.convertToJSONObject(value, in: context))
        } catch {
            pending.completion.resume(throwing: error)
        }
    }

    /// Must run on the JavaScriptCore queue.
    func cancelPendingPromise(callID: String) {
        guard let pending = pendingPromiseCalls.removeValue(forKey: callID) else { return }
        context.evaluateScript("delete globalThis.\(pending.globalKey);")
    }

    static func convertToJSONObject(_ value: JSValue, in context: JSContext) throws -> Any {
        if value.isUndefined || value.isNull {
            return NSNull()
        }

        let json = context.objectForKeyedSubscript("JSON")
        guard let jsonStringValue = json?.invokeMethod("stringify", withArguments: [value]),
              let jsonString = jsonStringValue.toString()
        else {
            throw LiveParsePluginError.invalidReturnValue("JSON.stringify failed")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LiveParsePluginError.invalidReturnValue("Invalid UTF-8 JSON")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Native Stream Bridge

    static func configureHostNativeStream(in context: JSContext, queue: DispatchQueue, nativeStream: ManifestNativeStream?) {
        let resolveNativeStream: @convention(block) (String, JSValue, JSValue) -> Void = { optionsJSON, resolve, reject in
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject
            let data = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            Task {
                do {
                    let streamInfo = try await NativeStreamBridge.resolve(
                        options: options,
                        declaration: nativeStream
                    )

                    // 在跳到 JS 队列之前先完成序列化:这样跨隔离域传递的只有 String(Sendable),
                    // 而不是非 Sendable 的 [String: Any]。
                    // 序列化失败改由下面的 catch 统一走 reject,错误文案保持区分。
                    let jsonString: String
                    do {
                        jsonString = try Self.jsonString(from: streamInfo)
                    } catch {
                        throw LiveParsePluginError.invalidReturnValue(
                            "Native stream serialize failed: \(error.localizedDescription)"
                        )
                    }

                    queue.async {
                        resolve.call(withArguments: [jsonString])
                        context.evaluateScript("void(0)")
                    }
                } catch {
                    queue.async {
                        reject.call(withArguments: [error.localizedDescription])
                        context.evaluateScript("void(0)")
                    }
                }
            }
        }

        context.setObject(resolveNativeStream, forKeyedSubscript: "__lp_host_native_stream_resolve" as NSString)
    }

    static func jsonString(from object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(
                domain: "LiveParse.JSRuntime",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "object is not JSON serializable"]
            )
        }
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}
