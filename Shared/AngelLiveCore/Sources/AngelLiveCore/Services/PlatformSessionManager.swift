//
//  PlatformSessionManager.swift
//  AngelLiveCore
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Security

public enum PlatformSessionState: String, Codable, Sendable {
    case anonymous
    case authenticated
    case expired
    case invalid
}

public enum PlatformSessionSource: String, Codable, Sendable {
    case local
    case iCloud
    case bonjour
    case manual
    case legacy
}

public enum PlatformSessionValidationResult: Sendable {
    case valid
    case invalid(reason: String)
    case expired
    case networkError(String)
}

/// 插件侧 `validateCredential` / `getCredentialStatus` 的标准返回结构。
public struct CredentialStatus: Codable, Sendable {
    public let state: String
    public let expireAt: Double?
    public let userId: String?
    public let userName: String?
    public let message: String?

    public init(
        state: String,
        expireAt: Double? = nil,
        userId: String? = nil,
        userName: String? = nil,
        message: String? = nil
    ) {
        self.state = state
        self.expireAt = expireAt
        self.userId = userId
        self.userName = userName
        self.message = message
    }
}

public struct PlatformSession: Codable, Sendable {
    public let pluginId: String
    /// 关联的 liveType（rawValue），便于 UI 层查 manifest/icon。
    public var liveType: String?
    public var cookie: String?
    public var csrf: String?
    public var refreshToken: String?
    public var uid: String?
    public var expireAt: Date?
    public var source: PlatformSessionSource
    public var state: PlatformSessionState
    public var updatedAt: Date

    public init(
        pluginId: String,
        liveType: String? = nil,
        cookie: String?,
        csrf: String? = nil,
        refreshToken: String? = nil,
        uid: String? = nil,
        expireAt: Date? = nil,
        source: PlatformSessionSource = .local,
        state: PlatformSessionState = .anonymous,
        updatedAt: Date = Date()
    ) {
        self.pluginId = pluginId
        self.liveType = liveType
        self.cookie = cookie
        self.csrf = csrf
        self.refreshToken = refreshToken
        self.uid = uid
        self.expireAt = expireAt
        self.source = source
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct PlatformSessionData: Sendable {
    public var cookie: String?
    public var csrf: String?
    public var refreshToken: String?
    public var uid: String?
    public var expireAt: Date?
    public var source: PlatformSessionSource
    public var state: PlatformSessionState
    public var liveType: String?

    public init(
        cookie: String?,
        csrf: String? = nil,
        refreshToken: String? = nil,
        uid: String? = nil,
        expireAt: Date? = nil,
        source: PlatformSessionSource,
        state: PlatformSessionState,
        liveType: String? = nil
    ) {
        self.cookie = cookie
        self.csrf = csrf
        self.refreshToken = refreshToken
        self.uid = uid
        self.expireAt = expireAt
        self.source = source
        self.state = state
        self.liveType = liveType
    }
}

public actor PlatformSessionManager {
    public static let shared = PlatformSessionManager()

    private enum CredentialAcquireResult: Sendable {
        case acquired
        case cancelled
        case timedOut
    }

    private enum CredentialAcquireError: Error {
        case timedOut
    }

    private struct CredentialOperationWaiter {
        let id: UUID
        let continuation: CheckedContinuation<CredentialAcquireResult, Never>
        let timeoutTask: Task<Void, Never>?
    }

    private struct LoginAttemptToken: Sendable {
        let pluginKey: String
        let generation: UInt
        /// 多个可重入登录重叠时沿用最早尝试前的稳定快照，不能把另一个
        /// 尚未完成的候选 Cookie 当成回滚基线。
        let previousVaultSession: LiveParsePlatformSession?
    }

    private let store = SessionStore()
    private var loginAttemptGenerations: [String: UInt] = [:]
    private var activeLoginAttempts: [String: LoginAttemptToken] = [:]
    private var credentialOperationOwners: Set<String> = []
    private var credentialOperationWaiters: [String: [CredentialOperationWaiter]] = [:]

    private init() {}

    public func getSession(pluginId: String) -> PlatformSession? {
        store.loadSession(for: pluginId)
    }

    /// Publish persisted state into the runtime vault under the same per-plugin
    /// barrier used by login and validation. Loading outside this actor and
    /// writing later can overwrite an in-flight QR candidate or a newer login.
    public func hydratePersistedSessionToRuntime(pluginId: String) async {
        let canonical = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        let pluginKey = canonical.isEmpty
            ? pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : canonical
        do {
            try await acquireCredentialOperation(for: pluginKey, timeout: .seconds(30))
        } catch {
            return
        }
        defer { releaseCredentialOperation(for: pluginKey) }
        guard !Task.isCancelled else { return }

        if let session = store.loadSession(for: pluginId) {
            LiveParsePlatformSessionVault.update(
                platformId: pluginId,
                cookie: session.cookie ?? "",
                uid: session.uid
            )
            PlatformSessionLiveParseBridge.syncSessionToLiveParse(
                session,
                expectedVaultRevision: LiveParsePlatformSessionVault.revision(for: pluginId)
            )
        } else {
            LiveParsePlatformSessionVault.clear(platformId: pluginId)
            PlatformSessionLiveParseBridge.clearForPlatform(
                pluginId: pluginId,
                expectedVaultRevision: LiveParsePlatformSessionVault.revision(for: pluginId)
            )
        }
    }

    @discardableResult
    public func loginWithCookie(
        pluginId: String,
        cookie: String,
        uid: String? = nil,
        liveType: String? = nil,
        source: PlatformSessionSource = .local,
        validateBeforeSave: Bool = true,
        /// 扫码等替换式登录应传 true：只有新凭据校验为 valid 才覆盖旧会话；
        /// expired/invalid/网络失败或任务取消都会恢复校验前的运行时凭据。
        preserveExistingSessionOnFailure: Bool = false,
        /// 旧网页登录为兼容历史插件允许 fail-open；扫码协议必须传 true，
        /// 只有 validateCredential 明确返回 state=valid 才能提交正式凭据。
        requireExplicitValid: Bool = false,
        /// Optional validation-only deadline. It ends before the durable save,
        /// so a timeout can restore the previous vault session without racing
        /// an already-committed login result.
        validationTimeout: Duration? = nil
    ) async -> PlatformSessionValidationResult {
        await loginWithCookie(
            pluginId: pluginId,
            cookie: cookie,
            uid: uid,
            liveType: liveType,
            source: source,
            validateBeforeSave: validateBeforeSave,
            preserveExistingSessionOnFailure: preserveExistingSessionOnFailure,
            requireExplicitValid: requireExplicitValid,
            validationTimeout: validationTimeout,
            runtimeLease: nil
        )
    }

    @discardableResult
    func loginWithCookie(
        pluginId: String,
        cookie: String,
        uid: String?,
        liveType: String?,
        source: PlatformSessionSource,
        validateBeforeSave: Bool,
        preserveExistingSessionOnFailure: Bool,
        requireExplicitValid: Bool,
        validationTimeout: Duration?,
        runtimeLease: LiveParsePluginRuntimeLease?
    ) async -> PlatformSessionValidationResult {
        let normalizedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookieLength = normalizedCookie.count
        guard !normalizedCookie.isEmpty else {
            // 空输入不是一次候选登录，不能让它 supersede 正在校验的事务。
            let entryId = await MainActor.run {
                PluginConsoleService.shared.log(tag: "Credential", method: "login", status: .loading)
            }
            await MainActor.run {
                PluginConsoleService.shared.updateRequest(
                    id: entryId,
                    body: "pluginId: \(pluginId)\ncookieLength: 0"
                )
            }
            await Self.finishCredentialEntry(
                id: entryId,
                start: Date(),
                status: .error,
                errorMessage: "Cookie 为空"
            )
            return .invalid(reason: "Cookie 为空")
        }

        // 必须在第一个 await 之前登记。actor 方法可重入，较新的登录应使较旧
        // 校验结果失效，避免迟到结果覆盖用户刚完成的另一条登录/同步操作。
        let attempt = beginLoginAttempt(pluginId: pluginId)
        let acquisitionClock = ContinuousClock()
        let acquisitionStartedAt = acquisitionClock.now
        do {
            try await acquireCredentialOperation(
                for: attempt.pluginKey,
                timeout: validationTimeout
            )
        } catch is CancellationError {
            restoreAndFinishLoginAttemptIfCurrent(
                attempt,
                shouldRestore: preserveExistingSessionOnFailure
            )
            return .networkError("登录已取消或被新的操作替代")
        } catch {
            restoreAndFinishLoginAttemptIfCurrent(
                attempt,
                shouldRestore: preserveExistingSessionOnFailure
            )
            return .networkError("扫码凭据校验超时")
        }
        defer { releaseCredentialOperation(for: attempt.pluginKey) }
        let remainingValidationTimeout: Duration?
        if let validationTimeout {
            let elapsed = acquisitionStartedAt.duration(to: acquisitionClock.now)
            let remaining = validationTimeout - elapsed
            guard remaining > .zero else {
                restoreAndFinishLoginAttemptIfCurrent(
                    attempt,
                    shouldRestore: preserveExistingSessionOnFailure
                )
                return .networkError("扫码凭据校验超时")
            }
            remainingValidationTimeout = remaining
        } else {
            remainingValidationTimeout = nil
        }
        let consoleEntryId = await MainActor.run {
            PluginConsoleService.shared.log(tag: "Credential", method: "login", status: .loading)
        }
        let consoleStart = Date()
        await MainActor.run {
            PluginConsoleService.shared.updateRequest(
                id: consoleEntryId,
                body: """
                pluginId: \(pluginId)
                hasUID: \(uid?.isEmpty == false)
                liveType: \(liveType ?? "-")
                source: \(source)
                validateBeforeSave: \(validateBeforeSave)
                cookieLength: \(cookieLength)
                """
            )
        }
        guard isCurrentLoginAttempt(attempt), !Task.isCancelled else {
            restoreAndFinishLoginAttemptIfCurrent(
                attempt,
                shouldRestore: preserveExistingSessionOnFailure
            )
            await Self.finishCredentialEntry(
                id: consoleEntryId,
                start: consoleStart,
                status: .error,
                errorMessage: "登录已取消或被新的操作替代"
            )
            return .networkError("登录已取消或被新的操作替代")
        }

        let validationResult: PlatformSessionValidationResult
        if validateBeforeSave {
            if let remainingValidationTimeout {
                validationResult = await validateCookie(
                    pluginId: pluginId,
                    cookie: normalizedCookie,
                    uid: uid,
                    useIsolatedCredential: true,
                    runtimeLease: runtimeLease,
                    requireExplicitValid: requireExplicitValid,
                    timeout: remainingValidationTimeout
                )
            } else {
                validationResult = await validateCookie(
                    pluginId: pluginId,
                    cookie: normalizedCookie,
                    uid: uid,
                    useIsolatedCredential: true,
                    runtimeLease: runtimeLease,
                    requireExplicitValid: requireExplicitValid
                )
            }
        } else {
            validationResult = .valid
        }

        // 校验可能忽略协作式取消。持久化前必须重新检查，且下面直到
        // updateSession 之间没有 suspension point，避免已取消扫码覆盖旧账号。
        guard isCurrentLoginAttempt(attempt), !Task.isCancelled else {
            restoreAndFinishLoginAttemptIfCurrent(
                attempt,
                shouldRestore: preserveExistingSessionOnFailure
            )
            await Self.finishCredentialEntry(
                id: consoleEntryId,
                start: consoleStart,
                status: .error,
                errorMessage: "登录已取消或被新的操作替代"
            )
            return .networkError("登录已取消或被新的操作替代")
        }

        var committedResult = validationResult
        switch validationResult {
        case .valid:
            let sessionData = PlatformSessionData(
                cookie: normalizedCookie,
                uid: uid,
                source: source,
                state: .authenticated,
                liveType: liveType
            )
            do {
                try persistSession(pluginId: pluginId, data: sessionData)
            } catch {
                restoreVaultSession(for: attempt)
                committedResult = .invalid(reason: "无法安全保存登录凭据")
            }
        case .expired:
            if preserveExistingSessionOnFailure {
                restoreVaultSession(for: attempt)
            } else {
                let sessionData = PlatformSessionData(
                    cookie: normalizedCookie,
                    uid: uid,
                    source: source,
                    state: .expired,
                    liveType: liveType
                )
                do {
                    try persistSession(pluginId: pluginId, data: sessionData)
                } catch {
                    restoreVaultSession(for: attempt)
                    committedResult = .invalid(reason: "无法安全保存登录凭据")
                }
            }
        case .invalid, .networkError:
            if preserveExistingSessionOnFailure {
                restoreVaultSession(for: attempt)
            }
        }
        finishLoginAttemptIfCurrent(attempt)

        let consoleSummary = Self.credentialDescription(for: committedResult)
        let consoleStatus: PluginConsoleEntryStatus
        switch committedResult {
        case .valid, .expired:
            consoleStatus = .success
        case .invalid, .networkError:
            consoleStatus = .error
        }
        await Self.finishCredentialEntry(
            id: consoleEntryId,
            start: consoleStart,
            status: consoleStatus,
            responseBody: consoleStatus == .success ? consoleSummary : nil,
            errorMessage: consoleStatus == .error ? consoleSummary : nil
        )

        return committedResult
    }

    public func updateSession(pluginId: String, data: PlatformSessionData) {
        invalidateLoginAttempts(pluginId: pluginId)
        do {
            try persistSession(pluginId: pluginId, data: data)
        } catch {
            Logger.error("Failed to persist platform session: \(pluginId)", category: .plugin)
        }
    }

    private func persistSession(pluginId: String, data: PlatformSessionData) throws {
        let session = PlatformSession(
            pluginId: pluginId,
            liveType: data.liveType,
            cookie: data.cookie,
            csrf: data.csrf,
            refreshToken: data.refreshToken,
            uid: data.uid,
            expireAt: data.expireAt,
            source: data.source,
            state: data.state,
            updatedAt: Date()
        )
        try store.saveSession(session)
        LiveParsePlatformSessionVault.update(
            platformId: pluginId,
            cookie: session.cookie ?? "",
            uid: session.uid
        )
        PlatformSessionLiveParseBridge.syncSessionToLiveParse(
            session,
            expectedVaultRevision: LiveParsePlatformSessionVault.revision(for: pluginId)
        )
    }

    public func clearSession(pluginId: String) {
        invalidateLoginAttempts(pluginId: pluginId)
        store.clearSession(for: pluginId)
        LiveParsePlatformSessionVault.clear(platformId: pluginId)
        PlatformSessionLiveParseBridge.clearForPlatform(
            pluginId: pluginId,
            expectedVaultRevision: LiveParsePlatformSessionVault.revision(for: pluginId)
        )
        let snapshot = pluginId
        Task { @MainActor in
            let id = PluginConsoleService.shared.log(tag: "Credential", method: "logout", status: .loading)
            PluginConsoleService.shared.updateRequest(id: id, body: "pluginId: \(snapshot)")
            PluginConsoleService.shared.updateStatus(
                id: id,
                status: .success,
                responseBody: "已清除本地会话与共享凭证池"
            )
        }
    }

    private func beginLoginAttempt(pluginId: String) -> LoginAttemptToken {
        let canonical = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        let pluginKey = canonical.isEmpty
            ? pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : canonical
        let generation = (loginAttemptGenerations[pluginKey] ?? 0) &+ 1
        loginAttemptGenerations[pluginKey] = generation
        let baseline = activeLoginAttempts[pluginKey]?.previousVaultSession
            ?? LiveParsePlatformSessionVault.session(for: pluginKey)
        let token = LoginAttemptToken(
            pluginKey: pluginKey,
            generation: generation,
            previousVaultSession: baseline
        )
        activeLoginAttempts[pluginKey] = token
        return token
    }

    private func isCurrentLoginAttempt(_ token: LoginAttemptToken) -> Bool {
        activeLoginAttempts[token.pluginKey]?.generation == token.generation
    }

    private func restoreVaultSession(for token: LoginAttemptToken) {
        guard isCurrentLoginAttempt(token) else { return }
        LiveParsePlatformSessionVault.restore(
            platformId: token.pluginKey,
            session: token.previousVaultSession
        )
    }

    private func finishLoginAttemptIfCurrent(_ token: LoginAttemptToken) {
        guard isCurrentLoginAttempt(token) else { return }
        activeLoginAttempts.removeValue(forKey: token.pluginKey)
    }

    private func restoreAndFinishLoginAttemptIfCurrent(
        _ token: LoginAttemptToken,
        shouldRestore: Bool
    ) {
        guard isCurrentLoginAttempt(token) else { return }
        if shouldRestore {
            restoreVaultSession(for: token)
        }
        activeLoginAttempts.removeValue(forKey: token.pluginKey)
    }

    private func invalidateLoginAttempts(pluginId: String) {
        let canonical = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        let pluginKey = canonical.isEmpty
            ? pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : canonical
        loginAttemptGenerations[pluginKey] = (loginAttemptGenerations[pluginKey] ?? 0) &+ 1
        activeLoginAttempts.removeValue(forKey: pluginKey)
    }

    /// actor 在 await 处可重入；同一插件的凭据校验必须额外串行，避免两个
    /// validateCredential 调用交替覆盖全局 runtime vault。
    private func acquireCredentialOperation(
        for pluginKey: String,
        timeout: Duration? = nil
    ) async throws {
        try Task.checkCancellation()
        if let timeout, timeout <= .zero {
            throw CredentialAcquireError.timedOut
        }
        if credentialOperationOwners.insert(pluginKey).inserted {
            return
        }

        let waiterId = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CredentialAcquireResult, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                let timeoutTask = timeout.map { timeout in
                    Task { [weak self] in
                        do {
                            try await Task.sleep(for: timeout)
                        } catch {
                            return
                        }
                        await self?.finishCredentialWaiter(
                            pluginKey: pluginKey,
                            waiterId: waiterId,
                            result: .timedOut
                        )
                    }
                }
                credentialOperationWaiters[pluginKey, default: []].append(
                    CredentialOperationWaiter(
                        id: waiterId,
                        continuation: continuation,
                        timeoutTask: timeoutTask
                    )
                )
            }
        } onCancel: {
            Task { [weak self] in
                await self?.finishCredentialWaiter(
                    pluginKey: pluginKey,
                    waiterId: waiterId,
                    result: .cancelled
                )
            }
        }

        switch result {
        case .acquired:
            // Ownership may have been handed over at the same instant the
            // waiter was cancelled. Pass it onward before propagating cancel.
            if Task.isCancelled {
                releaseCredentialOperation(for: pluginKey)
                throw CancellationError()
            }
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            throw CredentialAcquireError.timedOut
        }
    }

    private func finishCredentialWaiter(
        pluginKey: String,
        waiterId: UUID,
        result: CredentialAcquireResult
    ) {
        guard var waiters = credentialOperationWaiters[pluginKey],
              let index = waiters.firstIndex(where: { $0.id == waiterId }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        if waiters.isEmpty {
            credentialOperationWaiters.removeValue(forKey: pluginKey)
        } else {
            credentialOperationWaiters[pluginKey] = waiters
        }
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: result)
    }

    private func releaseCredentialOperation(for pluginKey: String) {
        if var waiters = credentialOperationWaiters[pluginKey], !waiters.isEmpty {
            let next = waiters.removeFirst()
            if waiters.isEmpty {
                credentialOperationWaiters.removeValue(forKey: pluginKey)
            } else {
                credentialOperationWaiters[pluginKey] = waiters
            }
            // owner 标记保持占用，所有权直接交给下一位等待者。
            next.timeoutTask?.cancel()
            next.continuation.resume(returning: .acquired)
        } else {
            credentialOperationOwners.remove(pluginKey)
        }
    }

    public func validateSession(pluginId: String) async -> PlatformSessionValidationResult {
        let pluginKey = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        do {
            try await acquireCredentialOperation(for: pluginKey, timeout: .seconds(30))
        } catch is CancellationError {
            return .networkError("凭据校验已取消")
        } catch {
            return .networkError("凭据校验等待超时")
        }
        defer { releaseCredentialOperation(for: pluginKey) }
        let consoleEntryId = await MainActor.run {
            PluginConsoleService.shared.log(tag: "Credential", method: "validate", status: .loading)
        }
        let consoleStart = Date()
        await MainActor.run {
            PluginConsoleService.shared.updateRequest(id: consoleEntryId, body: "pluginId: \(pluginId)")
        }
        guard let session = getSession(pluginId: pluginId),
              let cookie = session.cookie,
              !cookie.isEmpty else {
            await Self.finishCredentialEntry(
                id: consoleEntryId,
                start: consoleStart,
                status: .error,
                errorMessage: "本地无有效会话"
            )
            return .invalid(reason: "Cookie 为空")
        }

        let result = await validateCookie(
            pluginId: pluginId,
            cookie: cookie,
            uid: session.uid,
            useIsolatedCredential: false,
            runtimeLease: nil,
            requireExplicitValid: false,
            timeout: .seconds(30)
        )
        let summary = Self.credentialDescription(for: result)
        let consoleStatus: PluginConsoleEntryStatus
        switch result {
        case .valid, .expired:
            consoleStatus = .success
        case .invalid, .networkError:
            consoleStatus = .error
        }
        await Self.finishCredentialEntry(
            id: consoleEntryId,
            start: consoleStart,
            status: consoleStatus,
            responseBody: consoleStatus == .success ? summary : nil,
            errorMessage: consoleStatus == .error ? summary : nil
        )
        return result
    }

    private static func credentialDescription(for result: PlatformSessionValidationResult) -> String {
        switch result {
        case .valid:
            return "valid"
        case .expired:
            return "expired"
        case .invalid:
            return "invalid"
        case .networkError:
            return "networkError"
        }
    }

    private static func finishCredentialEntry(
        id: UUID,
        start: Date,
        status: PluginConsoleEntryStatus,
        responseBody: String? = nil,
        errorMessage: String? = nil
    ) async {
        let duration = Date().timeIntervalSince(start)
        await MainActor.run {
            PluginConsoleService.shared.updateStatus(
                id: id,
                status: status,
                duration: duration,
                responseBody: responseBody,
                errorMessage: errorMessage
            )
        }
    }

    /// 返回所有已持久化会话（按 pluginId 去重后的最新版本）。
    public func allSessions() -> [PlatformSession] {
        store.loadAllSessions()
    }

    /// 调用插件 `validateCredential`，返回完整的 CredentialStatus（含 userId / userName / message / state）。
    /// 与 `validateSession` 的区别：后者把插件返回值归一化成 valid/expired/invalid/networkError，丢掉 userName。
    /// UI 需要展示昵称时用这个。
    public func fetchCredentialStatus(pluginId: String) async -> CredentialStatus? {
        let pluginKey = LiveParsePlatformSessionVault.canonicalPlatformId(pluginId)
        do {
            try await acquireCredentialOperation(for: pluginKey, timeout: .seconds(5))
        } catch {
            return nil
        }
        defer { releaseCredentialOperation(for: pluginKey) }
        guard let session = getSession(pluginId: pluginId),
              let cookie = session.cookie,
              !cookie.isEmpty else {
            return nil
        }

        LiveParsePlatformSessionVault.update(platformId: pluginId, cookie: cookie, uid: session.uid)

        return await withTaskGroup(of: CredentialStatus?.self) { group in
            group.addTask {
                await Self.fetchCredentialStatusFromPlugin(
                    pluginId: pluginId
                )
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func fetchCredentialStatusFromPlugin(pluginId: String) async -> CredentialStatus? {
        // The plugin may ask Host.http to use the host-managed credential, but
        // credential bytes never cross the Swift/JavaScriptCore boundary.
        let payload: [String: Any] = ["credentialAvailable": true]
        return try? await LiveParsePlugins.shared.callDecodable(
            pluginId: pluginId,
            function: "validateCredential",
            payload: payload
        )
    }

    // MARK: - 插件驱动的凭证校验

    private func validateCookie(
        pluginId: String,
        cookie: String,
        uid: String?,
        useIsolatedCredential: Bool,
        runtimeLease: LiveParsePluginRuntimeLease?,
        requireExplicitValid: Bool
    ) async -> PlatformSessionValidationResult {
        // Validation receives only a capability hint. For an isolated QR
        // candidate, `cookie` is supplied to JSRuntime as native-only state and
        // can be consumed solely by Host.http's protected credential modes.
        let payload: [String: Any] = ["credentialAvailable": true]

        do {
            let status: CredentialStatus
            if useIsolatedCredential {
                status = try await LiveParsePlugins.shared.callDecodableUsingIsolatedCredential(
                    pluginId: pluginId,
                    function: "validateCredential",
                    payload: payload,
                    cookie: cookie,
                    uid: uid,
                    runtimeLease: runtimeLease
                )
            } else {
                // This is an already-persisted session. A no-op update keeps
                // its bridge revision stable while making cold-start runtime
                // validation compatible with platform_cookie plugins.
                LiveParsePlatformSessionVault.update(
                    platformId: pluginId,
                    cookie: cookie,
                    uid: uid
                )
                status = try await LiveParsePlugins.shared.callDecodable(
                    pluginId: pluginId,
                    function: "validateCredential",
                    payload: payload
                )
            }
            return mapStatus(
                status,
                cookieFallback: cookie,
                requireExplicitValid: requireExplicitValid
            )
        } catch let error as LiveParsePluginError {
            switch error {
            case .pluginNotFound:
                // 插件尚未安装：cookie 暂无法校验，但保留本地会话（下次插件就绪再复验）。
                return requireExplicitValid
                    ? .invalid(reason: "插件不可用，无法明确校验扫码凭据")
                    : .valid
            case .jsException(let message), .invalidReturnValue(let message), .invalidManifest(let message):
                if message.lowercased().contains("network") {
                    return .networkError(requireExplicitValid ? "扫码凭据校验网络失败" : message)
                }
                // JS 未实现 validateCredential / 返回异常：按未知处理，不阻断登录。
                return requireExplicitValid
                    ? .invalid(reason: "插件未明确确认扫码凭据有效")
                    : .valid
            case .standardized(let std):
                switch std.code {
                case .network, .timeout:
                    return .networkError(requireExplicitValid ? "扫码凭据校验网络失败" : std.message)
                case .authRequired:
                    return .expired
                case .blocked:
                    return .invalid(reason: requireExplicitValid ? "扫码凭据校验被平台拒绝" : std.message)
                default:
                    return requireExplicitValid
                        ? .invalid(reason: "插件未明确确认扫码凭据有效")
                        : .valid
                }
            default:
                return .networkError(requireExplicitValid ? "扫码凭据校验失败" : error.localizedDescription)
            }
        } catch {
            return .networkError(requireExplicitValid ? "扫码凭据校验失败" : error.localizedDescription)
        }
    }

    private func validateCookie(
        pluginId: String,
        cookie: String,
        uid: String?,
        useIsolatedCredential: Bool,
        runtimeLease: LiveParsePluginRuntimeLease?,
        requireExplicitValid: Bool,
        timeout: Duration
    ) async -> PlatformSessionValidationResult {
        await withTaskGroup(of: PlatformSessionValidationResult.self) { group in
            group.addTask {
                await self.validateCookie(
                    pluginId: pluginId,
                    cookie: cookie,
                    uid: uid,
                    useIsolatedCredential: useIsolatedCredential,
                    runtimeLease: runtimeLease,
                    requireExplicitValid: requireExplicitValid
                )
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return .networkError("扫码凭据校验已取消")
                }
                return .networkError("扫码凭据校验超时")
            }
            let first = await group.next() ?? .networkError("扫码凭据校验失败")
            group.cancelAll()
            return first
        }
    }

    func mapStatus(
        _ status: CredentialStatus,
        cookieFallback: String,
        requireExplicitValid: Bool
    ) -> PlatformSessionValidationResult {
        switch status.state.lowercased() {
        case "valid":
            return .valid
        case "expired":
            return .expired
        case "invalid", "missing", "risk_control":
            return .invalid(reason: requireExplicitValid ? "扫码凭据校验失败" : (status.message ?? status.state))
        case "unknown":
            // 插件无法判定：只要 cookie 非空就暂按有效处理（由上层业务 401 触发再登录）。
            if requireExplicitValid {
                return .invalid(reason: "插件未明确确认扫码凭据有效")
            }
            return cookieFallback.isEmpty ? .invalid(reason: "Cookie 为空") : .valid
        default:
            return requireExplicitValid
                ? .invalid(reason: "插件返回未知凭据状态")
                : .valid
        }
    }
}

// MARK: - SessionStore

private final class SessionStore {
    private enum Constants {
        static let keychainService = "com.angellive.session"
    }

    private struct SessionMetadata: Codable {
        let uid: String?
        let source: PlatformSessionSource
        let state: PlatformSessionState
        let expireAt: Date?
        let updatedAt: Date
        let liveType: String?
    }

    private struct SessionSensitivePayload: Codable {
        let cookie: String?
        let csrf: String?
        let refreshToken: String?
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychain = KeychainStore(service: Constants.keychainService)

    func loadSession(for pluginId: String) -> PlatformSession? {
        migrateLegacyIfNeeded(for: pluginId)

        guard let metadataData = defaults.data(forKey: metadataKey(for: pluginId)),
              let metadata = try? decoder.decode(SessionMetadata.self, from: metadataData) else {
            return nil
        }

        let sensitive = loadSensitivePayload(for: pluginId)
        return PlatformSession(
            pluginId: pluginId,
            liveType: metadata.liveType,
            cookie: sensitive?.cookie,
            csrf: sensitive?.csrf,
            refreshToken: sensitive?.refreshToken,
            uid: metadata.uid,
            expireAt: metadata.expireAt,
            source: metadata.source,
            state: metadata.state,
            updatedAt: metadata.updatedAt
        )
    }

    func loadAllSessions() -> [PlatformSession] {
        // 遍历已安装插件 + manifest 可发现插件（防止插件暂时卸载时会话丢失）
        let manifestPluginIds = LiveParseJSPlatformManager.availablePlatforms.map(\.pluginId)
        let pluginIds = Set(SandboxPluginCatalog.installedPluginIds() + manifestPluginIds)
        return pluginIds.compactMap { loadSession(for: $0) }
    }

    func saveSession(_ session: PlatformSession) throws {
        let metadata = SessionMetadata(
            uid: session.uid,
            source: session.source,
            state: session.state,
            expireAt: session.expireAt,
            updatedAt: session.updatedAt,
            liveType: session.liveType
        )
        let sensitive = SessionSensitivePayload(
            cookie: session.cookie,
            csrf: session.csrf,
            refreshToken: session.refreshToken
        )
        // 两段数据先完成编码，再原子更新 Keychain，最后提交 metadata。
        // 任何敏感项写入失败都不会删除旧 secret 或留下“已登录但无 Cookie”。
        let metadataData = try encoder.encode(metadata)
        let sensitiveData = try encoder.encode(sensitive)
        try keychain.write(sensitiveData, account: keychainAccount(for: session.pluginId))
        defaults.set(metadataData, forKey: metadataKey(for: session.pluginId))

        defaults.set(true, forKey: migrationKey(for: session.pluginId))
    }

    func clearSession(for pluginId: String) {
        defaults.removeObject(forKey: metadataKey(for: pluginId))
        keychain.delete(account: keychainAccount(for: pluginId))
    }

    private func migrateLegacyIfNeeded(for pluginId: String) {
        guard !defaults.bool(forKey: migrationKey(for: pluginId)) else { return }
        defer { defaults.set(true, forKey: migrationKey(for: pluginId)) }

        guard let platform = LiveParseJSPlatformManager.platform(forPluginId: pluginId) else { return }
        let migration = platform.sessionMigration

        for legacyRaw in migration?.legacyPluginIds ?? [] where !legacyRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            migrateLegacyRawKeyed(from: legacyRaw, to: pluginId)
        }

        if let migration {
            migrateLegacyUserDefaults(for: platform, migration: migration)
        }
    }

    private func migrateLegacyRawKeyed(from legacyRaw: String, to pluginId: String) {
        let legacyMetadataKey = "AngelLive.SessionStore.\(legacyRaw).metadata"
        let legacyKeychainAccount = "session.\(legacyRaw)"

        if let legacyMetadataData = defaults.data(forKey: legacyMetadataKey) {
            defaults.set(legacyMetadataData, forKey: metadataKey(for: pluginId))
            defaults.removeObject(forKey: legacyMetadataKey)
        }

        if let legacyData = keychain.read(account: legacyKeychainAccount) {
            if (try? keychain.write(legacyData, account: keychainAccount(for: pluginId))) != nil {
                keychain.delete(account: legacyKeychainAccount)
            }
        }
    }

    private func migrateLegacyUserDefaults(for platform: LiveParseJSPlatform, migration: ManifestSessionMigration) {
        let legacyCookie = firstString(forKeys: migration.userDefaultsCookieKeys) ?? ""
        let legacyUid = firstString(forKeys: migration.userDefaultsUIDKeys)
        guard !legacyCookie.isEmpty else {
            return
        }

        let migrated = PlatformSession(
            pluginId: platform.pluginId,
            liveType: platform.liveType.rawValue,
            cookie: legacyCookie,
            uid: legacyUid,
            source: .legacy,
            state: legacyCookie.matchesAnyMarker(migration.authCookieMarkers) ? .authenticated : .invalid,
            updatedAt: Date()
        )
        try? saveSession(migrated)
    }

    private func firstString(forKeys keys: [String]?) -> String? {
        keys?
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { self.defaults.string(forKey: $0) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func loadSensitivePayload(for pluginId: String) -> SessionSensitivePayload? {
        guard let data = keychain.read(account: keychainAccount(for: pluginId)) else { return nil }
        return try? decoder.decode(SessionSensitivePayload.self, from: data)
    }

    private func metadataKey(for pluginId: String) -> String {
        "AngelLive.SessionStore.\(pluginId).metadata"
    }

    private func migrationKey(for pluginId: String) -> String {
        "AngelLive.SessionStore.\(pluginId).migrated.v2"
    }

    private func keychainAccount(for pluginId: String) -> String {
        "session.\(pluginId)"
    }
}

private extension String {
    func matchesAnyMarker(_ markers: [String]?) -> Bool {
        guard let markers, !markers.isEmpty else {
            return !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return markers.contains { marker in
            let normalized = marker.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalized.isEmpty && localizedCaseInsensitiveContains(normalized)
        }
    }
}

private enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
}

private struct KeychainStore {
    let service: String

    func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
