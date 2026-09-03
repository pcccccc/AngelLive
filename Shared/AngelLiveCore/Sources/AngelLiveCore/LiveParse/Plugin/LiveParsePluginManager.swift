import Foundation

enum LoginChallengeConsoleOperation: Sendable {
    case create
    case poll
    case submitVerification
    case resendVerification
    case cancel
}

enum SensitivePluginConsolePolicy: Sendable {
    case omitted
    case loginChallenge(LoginChallengeConsoleOperation)
}

final class LiveParsePluginVersionLeaseToken: @unchecked Sendable {
    let pluginId: String
    let version: String

    init(pluginId: String, version: String) {
        self.pluginId = pluginId
        self.version = version
        LiveParsePluginVersionLeaseRegistry.retain(pluginId: pluginId, version: version)
    }

    deinit {
        LiveParsePluginVersionLeaseRegistry.release(pluginId: pluginId, version: version)
    }
}

enum LiveParsePluginVersionLeaseRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: [String: Int]] = [:]

    static func retain(pluginId: String, version: String) {
        lock.withLock {
            counts[pluginId, default: [:]][version, default: 0] += 1
        }
    }

    static func release(pluginId: String, version: String) {
        lock.withLock {
            guard var versions = counts[pluginId], let count = versions[version] else { return }
            if count <= 1 {
                versions.removeValue(forKey: version)
            } else {
                versions[version] = count - 1
            }
            if versions.isEmpty {
                counts.removeValue(forKey: pluginId)
            } else {
                counts[pluginId] = versions
            }
        }
    }

    static func protectedVersions(pluginId: String) -> Set<String> {
        lock.withLock {
            guard let versions = counts[pluginId] else { return [] }
            return Set(versions.keys)
        }
    }
}

struct LiveParsePluginRuntimeLease: Sendable {
    let pluginId: String
    let version: String
    let credentialDomains: [String]
    fileprivate let plugin: LiveParseLoadedPlugin
    fileprivate let versionLeaseToken: LiveParsePluginVersionLeaseToken
}

public final class LiveParsePluginManager: @unchecked Sendable {
    public typealias LogHandler = JSRuntime.LogHandler

    public let storage: LiveParsePluginStorage
    public let bundle: Bundle
    public let session: URLSession

    private let logHandler: LogHandler?
    private let lock = NSLock()
    private var loadedPlugins: [String: LiveParseLoadedPlugin] = [:]
    private var state: LiveParsePluginState
    private var stateRevision: UInt = 0

    public convenience init(bundle: Bundle? = nil, session: URLSession = .shared, logHandler: LogHandler? = nil) throws {
        try self.init(storage: LiveParsePluginStorage(), bundle: bundle, session: session, logHandler: logHandler)
    }

    public init(storage: LiveParsePluginStorage, bundle: Bundle? = nil, session: URLSession = .shared, logHandler: LogHandler? = nil) {
        self.storage = storage
        self.bundle = bundle ?? .main
        self.session = session
        self.logHandler = logHandler
        self.state = storage.loadState()
    }

    public func reload() throws {
        try storage.ensureDirectories()
        lock.lock()
        // 与 pin/unpin 的 state 写入使用同一临界区；否则锁外旧快照可能
        // 在一次 pin 完成后反向覆盖内存中的新选择。
        state = storage.loadState()
        stateRevision &+= 1
        loadedPlugins.removeAll()
        lock.unlock()
    }

    public func pin(pluginId: String, version: String) throws {
        try lock.withLock {
            var nextState = state
            var record = nextState.plugins[pluginId] ?? .init()
            record.pinnedVersion = version
            nextState.plugins[pluginId] = record
            try storage.saveState(nextState)
            state = nextState
            stateRevision &+= 1
            loadedPlugins.removeAll()
        }
    }

    public func unpin(pluginId: String) throws {
        try lock.withLock {
            var nextState = state
            var record = nextState.plugins[pluginId] ?? .init()
            record.pinnedVersion = nil
            nextState.plugins[pluginId] = record
            try storage.saveState(nextState)
            state = nextState
            stateRevision &+= 1
            loadedPlugins.removeAll()
        }
    }

    public func setLastGoodVersion(pluginId: String, version: String?) throws {
        try lock.withLock {
            var nextState = state
            var record = nextState.plugins[pluginId] ?? .init()
            record.lastGoodVersion = version
            nextState.plugins[pluginId] = record
            try storage.saveState(nextState)
            state = nextState
            stateRevision &+= 1
            loadedPlugins.removeValue(forKey: pluginId)
        }
    }

    public func evict(pluginId: String) {
        lock.lock()
        loadedPlugins.removeValue(forKey: pluginId)
        lock.unlock()
    }

    /// Evict only the runtime that produced a cancelled sensitive call. A
    /// replacement may already have won the cache lease and must not be lost.
    private func evict(pluginId: String, ifRuntime runtime: JSRuntime) {
        lock.withLock {
            guard loadedPlugins[pluginId]?.runtime === runtime else { return }
            loadedPlugins.removeValue(forKey: pluginId)
        }
    }

    public func invalidateHTTPFailureCaches() async {
        let plugins = lock.withLock { Array(loadedPlugins.values) }
        for plugin in plugins {
            await plugin.runtime.invalidateHTTPFailureCache()
        }
    }

    public func resolve(pluginId: String) throws -> LiveParseLoadedPlugin {
        while true {
            let snapshot: (record: LiveParsePluginState.PluginRecord?, revision: UInt)
            lock.lock()
            if let existing = loadedPlugins[pluginId] {
                lock.unlock()
                return existing
            }
            snapshot = (state.plugins[pluginId], stateRevision)
            lock.unlock()

            if snapshot.record?.enabled == false {
                throw LiveParsePluginError.pluginNotFound("\(pluginId) (disabled)")
            }

            let selected = try selectBestCandidate(
                pluginId: pluginId,
                pinnedVersion: snapshot.record?.pinnedVersion,
                lastGood: snapshot.record?.lastGoodVersion
            )
            let plugin = LiveParseLoadedPlugin(
                manifest: selected.manifest,
                rootDirectory: selected.rootDirectory,
                location: selected.location,
                runtime: JSRuntime(
                    pluginId: selected.manifest.pluginId,
                    session: session,
                    nativeStream: selected.manifest.nativeStream,
                    credentialDomains: selected.manifest.hostManagedCredentialDomains,
                    logHandler: logHandler
                )
            )

            // 首次并发 resolve 可能同时完成候选选择。只允许一个 runtime 赢得
            // cache lease；若期间 state 改变则丢弃旧候选并按新快照重选。
            lock.lock()
            if let winner = loadedPlugins[pluginId] {
                lock.unlock()
                return winner
            }
            guard snapshot.revision == stateRevision else {
                lock.unlock()
                continue
            }
            loadedPlugins[pluginId] = plugin
            lock.unlock()
            return plugin
        }
    }

    public func load(pluginId: String) async throws {
        let plugin = try resolve(pluginId: pluginId)
        try await plugin.load()
    }

    func runtimeLease(pluginId: String) throws -> LiveParsePluginRuntimeLease {
        let plugin = try resolve(pluginId: pluginId)
        return LiveParsePluginRuntimeLease(
            pluginId: plugin.manifest.pluginId,
            version: plugin.manifest.version,
            credentialDomains: plugin.manifest.hostManagedCredentialDomains,
            plugin: plugin,
            versionLeaseToken: LiveParsePluginVersionLeaseToken(
                pluginId: plugin.manifest.pluginId,
                version: plugin.manifest.version
            )
        )
    }

    public func call(
        pluginId: String,
        function: String,
        payload: [String: Any] = [:],
        sensitive: Bool = false,
        hostManagesCredentialVault: Bool = false
    ) async throws -> Any {
        try await performCall(
            pluginId: pluginId,
            function: function,
            payload: payload,
            sensitive: sensitive,
            sensitiveConsolePolicy: .omitted,
            hostManagesCredentialVault: hostManagesCredentialVault,
            isolatedPlatformSession: nil,
            runtimeLease: nil
        )
    }

    private func performCall(
        pluginId: String,
        function: String,
        payload: [String: Any],
        sensitive: Bool,
        sensitiveConsolePolicy: SensitivePluginConsolePolicy,
        hostManagesCredentialVault: Bool,
        isolatedPlatformSession: LiveParsePlatformSession?,
        runtimeLease: LiveParsePluginRuntimeLease?
    ) async throws -> Any {
        if function == "setCookie" || function == "setCredential" {
            let (cookie, uid): (String, String?)
            if function == "setCredential" {
                (cookie, uid) = extractCredentialCookie(from: payload)
            } else {
                cookie = (payload["cookie"] as? String) ?? ""
                uid = payload["uid"] as? String
            }
            if !hostManagesCredentialVault {
                LiveParsePlatformSessionVault.update(platformId: pluginId, cookie: cookie, uid: uid)
                evict(pluginId: pluginId)
            }
            return ["ok": true, "managedByHost": true, "hasCookie": !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty]
        }
        if function == "clearCookie" || function == "clearCredential" {
            if !hostManagesCredentialVault {
                LiveParsePlatformSessionVault.clear(platformId: pluginId)
                evict(pluginId: pluginId)
            }
            return ["ok": true, "managedByHost": true, "hasCookie": false]
        }

        // 开发者控制台关闭时完全跳过记录。收藏批量刷新会并发调用上百次，
        // 即使 UI 不展示，无条件写 @Observable entries 仍会造成主 actor 压力。
        let sensitivePluginCall = sensitive
            || Self.isSensitivePluginFunction(function)
            || Self.containsSensitiveConsoleValue(payload)
        let console = PluginConsoleService.shared
        let consoleEntryId: UUID?
        if console.isEnabled {
            // 敏感调用默认整段省略；登录挑战只输出宿主定义的字段白名单摘要。
            // 绝不对任意插件 JSON 做“猜测式”放行。
            let payloadStr: String
            if sensitivePluginCall {
                payloadStr = Self.sensitiveRequestSummary(
                    policy: sensitiveConsolePolicy,
                    payload: payload
                )
            } else {
                let consolePayload = Self.redactedLoginTransactionConsoleValue(payload)
                payloadStr = (try? String(
                    data: JSONSerialization.data(withJSONObject: consolePayload),
                    encoding: .utf8
                )) ?? "{}"
            }
            let entryId = await console.log(tag: pluginId, method: function)
            await console.updateRequest(id: entryId, body: payloadStr)
            console.setActiveCall(pluginId: pluginId, entryId: entryId)
            consoleEntryId = entryId
        } else {
            consoleEntryId = nil
        }
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            if let runtimeLease, runtimeLease.pluginId != pluginId {
                throw LiveParsePluginError.pluginNotFound(
                    "Runtime lease owner mismatch for \(pluginId)"
                )
            }

            let selected: LiveParseLoadedPlugin
            if let runtimeLease {
                selected = runtimeLease.plugin
            } else {
                selected = try resolve(pluginId: pluginId)
            }
            let plugin: LiveParseLoadedPlugin
            if let isolatedPlatformSession {
                plugin = LiveParseLoadedPlugin(
                    manifest: selected.manifest,
                    rootDirectory: selected.rootDirectory,
                    location: selected.location,
                    runtime: JSRuntime(
                        pluginId: selected.manifest.pluginId,
                        session: session,
                        nativeStream: selected.manifest.nativeStream,
                        loginTransactionStore: .shared,
                        credentialDomains: selected.manifest.hostManagedCredentialDomains,
                        platformSessionOverride: isolatedPlatformSession,
                        logHandler: logHandler
                    )
                )
            } else {
                plugin = selected
            }
            if sensitivePluginCall {
                await plugin.runtime.beginSensitiveLoggingSuppression()
            }
            do {
                try await plugin.load()
                let result = try await plugin.runtime.callPluginFunction(name: function, payload: payload)
                if sensitivePluginCall {
                    await plugin.runtime.endSensitiveLoggingSuppression()
                }

                if consoleEntryId != nil {
                    console.clearActiveCall(pluginId: pluginId)
                }
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
#if DEBUG
                if case .loginChallenge = sensitiveConsolePolicy {
                    Logger.debug(
                        """
                        [PluginLogin][FUNCTION]
                        pluginId=\(pluginId)
                        function=\(function)
                        request=\(Self.sensitiveRequestSummary(policy: sensitiveConsolePolicy, payload: payload))
                        response=\(Self.sensitiveResponseSummary(policy: sensitiveConsolePolicy, value: result))
                        duration=\(String(format: "%.3f", elapsed))s
                        """,
                        category: .plugin
                    )
                }
#endif
                if let consoleEntryId {
                    let responseStr: String?
                    if sensitivePluginCall {
                        responseStr = Self.sensitiveResponseSummary(
                            policy: sensitiveConsolePolicy,
                            value: result
                        )
                    } else {
                        let consoleResult = Self.redactedLoginTransactionConsoleValue(result)
                        responseStr = (try? String(data: JSONSerialization.data(withJSONObject: consoleResult), encoding: .utf8))
                            .map { String($0.prefix(2_000)) }
                    }
                    await console.updateStatus(
                        id: consoleEntryId,
                        status: .success,
                        duration: elapsed,
                        responseBody: responseStr
                    )
                }
                return result
            } catch {
                if sensitivePluginCall {
                    if error is CancellationError {
                        // A JavaScript Promise cannot be force-cancelled. Its
                        // late continuation could still print credential text,
                        // so leave the old runtime permanently muted and ensure
                        // future calls resolve a fresh runtime.
                        await plugin.runtime.abandonInFlightOperations()
                        evict(pluginId: pluginId, ifRuntime: plugin.runtime)
                    } else {
                        await plugin.runtime.endSensitiveLoggingSuppression()
                    }
                }
                throw error
            }
        } catch {
            if consoleEntryId != nil {
                console.clearActiveCall(pluginId: pluginId)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
#if DEBUG
            if case .loginChallenge = sensitiveConsolePolicy {
                Logger.debug(
                    """
                    [PluginLogin][FUNCTION][FAILURE]
                    pluginId=\(pluginId)
                    function=\(function)
                    request=\(Self.sensitiveRequestSummary(policy: sensitiveConsolePolicy, payload: payload))
                    error=\(Self.sensitiveErrorSummary(policy: sensitiveConsolePolicy, error: error))
                    duration=\(String(format: "%.3f", elapsed))s
                    """,
                    category: .plugin
                )
            }
#endif
            if let consoleEntryId {
                await console.updateStatus(
                    id: consoleEntryId,
                    status: .error,
                    duration: elapsed,
                    errorMessage: sensitivePluginCall
                        ? Self.sensitiveErrorSummary(
                            policy: sensitiveConsolePolicy,
                            error: error
                        )
                        : error.localizedDescription
                )
            }
            throw error
        }
    }

    static func sensitiveRequestSummary(
        policy: SensitivePluginConsolePolicy,
        payload: [String: Any]
    ) -> String {
        guard case .loginChallenge(let operation) = policy else {
            return "<sensitive request omitted>"
        }

        var summary: [String: Any] = ["privacy": "sensitive fields redacted"]
        switch operation {
        case .create:
            summary["transactionId"] = "<redacted>"
            summary["platform"] = allowedString(
                payload["platform"],
                values: ["ios", "macos", "tvos"]
            ) ?? "unknown"
        case .poll:
            summary["transactionId"] = "<redacted>"
            summary["challengeId"] = "<redacted>"
        case .submitVerification:
            summary["transactionId"] = "<redacted>"
            summary["challengeId"] = "<redacted>"
            summary["verificationId"] = "<redacted>"
            summary["code"] = "<redacted>"
        case .resendVerification:
            summary["transactionId"] = "<redacted>"
            summary["challengeId"] = "<redacted>"
            summary["verificationId"] = "<redacted>"
        case .cancel:
            summary["transactionId"] = "<redacted>"
            summary["challengeId"] = "<redacted>"
        }
        return consoleJSONString(summary)
    }

    static func sensitiveResponseSummary(
        policy: SensitivePluginConsolePolicy,
        value: Any
    ) -> String {
        guard case .loginChallenge(let operation) = policy,
              let response = value as? [String: Any] else {
            return "<sensitive response omitted>"
        }

        var summary: [String: Any] = ["privacy": "sensitive fields redacted"]
        switch operation {
        case .create:
            summary["kind"] = allowedString(response["kind"], values: ["qrcode"]) ?? "unknown"
            addBoundedInteger(response["pollIntervalMs"], key: "pollIntervalMs", to: &summary)
            summary["hasExpiration"] = numericValue(response["expiresAt"]) != nil
            summary["hasHint"] = nonemptyString(response["hint"])
            summary["challengeId"] = "<redacted>"
            summary["qrContent"] = "<redacted>"
            summary["hasQRImage"] = nonemptyString(response["qrImage"])
        case .poll:
            summary["state"] = allowedString(
                response["state"],
                values: ["waiting", "scanned", "verification_required", "confirmed", "expired", "failed"]
            ) ?? "unknown"
            addBoundedInteger(response["rawStatus"], key: "rawStatus", to: &summary)
            if let ready = response["credentialReady"] as? Bool {
                summary["credentialReady"] = ready
            }
            summary["hasMessage"] = nonemptyString(response["message"])
            if let verification = response["verification"] as? [String: Any] {
                summary["verification"] = verificationConsoleSummary(verification)
            }
        case .submitVerification:
            summary["state"] = allowedString(
                response["state"],
                values: ["accepted", "rejected"]
            ) ?? "unknown"
            summary["hasMessage"] = nonemptyString(response["message"])
            if let verification = response["verification"] as? [String: Any] {
                summary["verification"] = verificationConsoleSummary(verification)
            }
        case .resendVerification:
            summary["verification"] = verificationConsoleSummary(response)
        case .cancel:
            if let ok = response["ok"] as? Bool {
                summary["ok"] = ok
            }
        }
        return consoleJSONString(summary)
    }

    static func sensitiveErrorSummary(
        policy: SensitivePluginConsolePolicy,
        error: Error
    ) -> String {
        guard case .loginChallenge = policy else {
            return "Sensitive plugin call failed"
        }
        if case .standardized(let standard)? = error as? LiveParsePluginError {
            return "Login challenge failed [\(standard.code.rawValue)]"
        }
        if error is CancellationError {
            return "Login challenge cancelled"
        }
        return "Login challenge failed [details omitted]"
    }

    private static func verificationConsoleSummary(_ value: [String: Any]) -> [String: Any] {
        var summary: [String: Any] = [
            "kind": allowedString(value["kind"], values: ["sms_code"]) ?? "unknown",
            "verificationId": "<redacted>",
            "hasPrompt": nonemptyString(value["prompt"]),
            "hasDestination": nonemptyString(value["maskedDestination"])
        ]
        addBoundedInteger(value["codeLength"], key: "codeLength", to: &summary)
        addBoundedInteger(value["resendAfterMs"], key: "resendAfterMs", to: &summary)
        if let canResend = value["canResend"] as? Bool {
            summary["canResend"] = canResend
        }
        return summary
    }

    private static func allowedString(_ value: Any?, values: Set<String>) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return values.contains(normalized) ? normalized : nil
    }

    private static func nonemptyString(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func numericValue(_ value: Any?) -> Int? {
        guard !(value is Bool), let number = value as? NSNumber else { return nil }
        let candidate = number.int64Value
        guard candidate >= -1_000_000_000_000, candidate <= 1_000_000_000_000 else { return nil }
        return Int(candidate)
    }

    private static func addBoundedInteger(
        _ value: Any?,
        key: String,
        to summary: inout [String: Any]
    ) {
        if let value = numericValue(value) {
            summary[key] = value
        }
    }

    private static func consoleJSONString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "<safe summary unavailable>"
        }
        return string
    }

    static func containsLoginTransactionIdentifier(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                if key.lowercased() == "transactionid" { return true }
                if containsLoginTransactionIdentifier(nested) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsLoginTransactionIdentifier)
        }
        return false
    }

    static func containsSensitiveConsoleValue(_ value: Any, key: String? = nil) -> Bool {
        if let key, isSensitiveConsoleKey(key) { return true }
        if let dictionary = value as? [String: Any] {
            return dictionary.contains { item in
                containsSensitiveConsoleValue(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] {
            return array.contains { containsSensitiveConsoleValue($0) }
        }
        return false
    }

    private static func isSensitivePluginFunction(_ function: String) -> Bool {
        switch function.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "setcredential", "clearcredential", "validatecredential", "getcredentialstatus":
            return true
        default:
            return false
        }
    }

    static func redactedLoginTransactionConsoleValue(_ value: Any, key: String? = nil) -> Any {
        if let key {
            let lowered = key.lowercased()
            if isSensitiveConsoleKey(lowered) {
                return "<redacted>"
            }
            if lowered == "url", let string = value as? String {
                guard var components = URLComponents(string: string) else { return "<redacted>" }
                components.query = nil
                components.fragment = nil
                return components.string ?? "<redacted>"
            }
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redactedLoginTransactionConsoleValue(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] {
            return array.map { redactedLoginTransactionConsoleValue($0) }
        }
        return value
    }

    private static func isSensitiveConsoleKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        let redactedKeys: Set<String> = [
            "transactionid", "challengeid", "qrcontent", "qrimage", "credential", "cookie", "set-cookie",
            "setcookies", "authorization", "location", "headers", "requestheaders",
            "responseheaders", "body", "bodytext", "bodybase64", "requestbody", "responsebody"
        ]
        return redactedKeys.contains(lowered)
            || lowered.contains("token")
            || lowered.contains("cookie")
    }

    public func callDecodable<T: Decodable>(
        pluginId: String,
        function: String,
        payload: [String: Any] = [:],
        sensitive: Bool = false,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        do {
            let value = try await call(
                pluginId: pluginId,
                function: function,
                payload: payload,
                sensitive: sensitive
            )
            let data = try JSONSerialization.data(withJSONObject: value)
            return try decoder.decode(T.self, from: data)
        } catch let error as LiveParsePluginError {
            throw error
        } catch {
            throw LiveParsePluginError.invalidReturnValue(
                "Decoding \(String(describing: T.self)) failed in \(pluginId).\(function): \(error.localizedDescription)"
            )
        }
    }

    /// Validate an uncommitted credential in a short-lived runtime. Host
    /// Native `platform_cookie` and `cookieInject` requests in that runtime use
    /// the candidate; JavaScript cannot read it, and cached business runtimes
    /// continue to use only the canonical committed vault entry.
    func callDecodableUsingIsolatedCredential<T: Decodable>(
        pluginId: String,
        function: String,
        payload: [String: Any],
        cookie: String,
        uid: String?,
        runtimeLease: LiveParsePluginRuntimeLease? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let isolatedSession = LiveParsePlatformSession(
            cookie: cookie.trimmingCharacters(in: .whitespacesAndNewlines),
            uid: uid?.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: .now
        )
        do {
            let value = try await performCall(
                pluginId: pluginId,
                function: function,
                payload: payload,
                sensitive: true,
                sensitiveConsolePolicy: .omitted,
                hostManagesCredentialVault: true,
                isolatedPlatformSession: isolatedSession,
                runtimeLease: runtimeLease
            )
            let data = try JSONSerialization.data(withJSONObject: value)
            return try decoder.decode(T.self, from: data)
        } catch let error as LiveParsePluginError {
            throw error
        } catch {
            throw LiveParsePluginError.invalidReturnValue(
                "Decoding \(String(describing: T.self)) failed in \(pluginId).\(function): \(error.localizedDescription)"
            )
        }
    }

    func callDecodable<T: Decodable>(
        using runtimeLease: LiveParsePluginRuntimeLease,
        function: String,
        payload: [String: Any],
        sensitive: Bool,
        sensitiveConsolePolicy: SensitivePluginConsolePolicy = .omitted,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        do {
            let value = try await performCall(
                pluginId: runtimeLease.pluginId,
                function: function,
                payload: payload,
                sensitive: sensitive,
                sensitiveConsolePolicy: sensitiveConsolePolicy,
                // Challenge function names are manifest-controlled. They must
                // never trigger the manager's reserved credential mutators.
                hostManagesCredentialVault: true,
                isolatedPlatformSession: nil,
                runtimeLease: runtimeLease
            )
            let data = try JSONSerialization.data(withJSONObject: value)
            return try decoder.decode(T.self, from: data)
        } catch let error as LiveParsePluginError {
            throw error
        } catch {
            throw LiveParsePluginError.invalidReturnValue(
                "Decoding \(String(describing: T.self)) failed in \(runtimeLease.pluginId).\(function): \(error.localizedDescription)"
            )
        }
    }

    private func extractCredentialCookie(from payload: [String: Any]) -> (String, String?) {
        // 支持 payload = { credential: { cookie, uid } } 或扁平 { cookie, uid }
        if let credential = payload["credential"] as? [String: Any] {
            let cookie = (credential["cookie"] as? String)
                ?? (credential["Cookie"] as? String)
                ?? ""
            let uid = credential["uid"] as? String
            return (cookie, uid)
        }
        if let cookie = payload["cookie"] as? String {
            return (cookie, payload["uid"] as? String)
        }
        return ("", nil)
    }
}

private extension LiveParsePluginManager {
    struct Candidate {
        let manifest: LiveParsePluginManifest
        let rootDirectory: URL
        let location: LiveParseLoadedPlugin.Location
    }

    func selectBestCandidate(pluginId: String, pinnedVersion: String?, lastGood: String?) throws -> Candidate {
        let sandboxCandidates = try discoverSandboxCandidates(pluginId: pluginId)
        let builtInCandidates = try discoverBuiltInCandidates(pluginId: pluginId)
        let allCandidates = sandboxCandidates + builtInCandidates

        func preferredCandidate(in candidates: [Candidate]) -> Candidate? {
            candidates.max { lhs, rhs in
                let versionCompare = semverCompare(lhs.manifest.version, rhs.manifest.version)
                if versionCompare != 0 {
                    return versionCompare < 0
                }
                if lhs.location != rhs.location {
                    return lhs.location == .builtIn && rhs.location == .sandbox
                }
                return lhs.rootDirectory.path < rhs.rootDirectory.path
            }
        }

        if let pinnedVersion {
            if let hit = preferredCandidate(in: allCandidates.filter({ $0.manifest.version == pinnedVersion })) {
                return hit
            }
            throw LiveParsePluginError.pluginNotFound("\(pluginId)@\(pinnedVersion)")
        }

        guard let best = preferredCandidate(in: allCandidates) else {
            throw LiveParsePluginError.pluginNotFound(pluginId)
        }

        if let lastGood,
           semverCompare(lastGood, best.manifest.version) >= 0,
           let hit = preferredCandidate(in: allCandidates.filter({ $0.manifest.version == lastGood })) {
            return hit
        }

        return best
    }

    func discoverSandboxCandidates(pluginId: String) throws -> [Candidate] {
        let versionDirs = storage.listInstalledVersions(pluginId: pluginId)
        return try versionDirs.compactMap { dir in
            let manifestURL = dir.appendingPathComponent("manifest.json", isDirectory: false)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
            let manifest = try LiveParsePluginManifest.load(from: manifestURL)
            guard manifest.pluginId == pluginId else { return nil }
            return Candidate(manifest: manifest, rootDirectory: dir, location: .sandbox)
        }
    }

    func discoverBuiltInCandidates(pluginId: String) throws -> [Candidate] {
        guard let resourceURL = bundle.resourceURL else {
            return []
        }

        // 兼容两种内置资源布局：
        // 1) 目录结构：Plugins/<pluginId>/manifest.json (理想情况)
        // 2) 资源被“扁平化”拷贝到 bundle 根目录：lp_plugin_<id>_<ver>_manifest.json（当前 SwiftPM 构建常见）

        let pluginsRoot = resourceURL.appendingPathComponent("Plugins", isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginsRoot.path) {
            return try discoverBuiltInCandidatesFolderMode(pluginId: pluginId, pluginsRoot: pluginsRoot)
        }
        return try discoverBuiltInCandidatesFlatMode(pluginId: pluginId, resourceURL: resourceURL)
    }

    func discoverBuiltInCandidatesFolderMode(pluginId: String, pluginsRoot: URL) throws -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: pluginsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [Candidate] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "manifest.json" else { continue }
            let manifest = try LiveParsePluginManifest.load(from: url)
            guard manifest.pluginId == pluginId else { continue }
            results.append(Candidate(manifest: manifest, rootDirectory: url.deletingLastPathComponent(), location: .builtIn))
        }
        return results
    }

    func discoverBuiltInCandidatesFlatMode(pluginId: String, resourceURL: URL) throws -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [Candidate] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("lp_plugin_") && name.hasSuffix("_manifest.json") else { continue }
            let manifest = try LiveParsePluginManifest.load(from: url)
            guard manifest.pluginId == pluginId else { continue }
            results.append(Candidate(manifest: manifest, rootDirectory: url.deletingLastPathComponent(), location: .builtIn))
        }
        return results
    }

    func semverCompare(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }
        let a = parts(lhs)
        let b = parts(rhs)
        for i in 0..<3 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        }
        return 0
    }
}
