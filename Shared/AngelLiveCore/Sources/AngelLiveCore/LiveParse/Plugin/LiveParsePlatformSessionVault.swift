import Foundation

struct LiveParsePlatformSession: Sendable {
    let cookie: String
    let uid: String?
    let updatedAt: Date
    /// Opaque credential generation. A timestamp cannot safely serve as the
    /// generation because two writes may share the same clock value.
    let revision: String

    init(
        cookie: String,
        uid: String?,
        updatedAt: Date,
        revision: String = UUID().uuidString
    ) {
        self.cookie = cookie
        self.uid = uid
        self.updatedAt = updatedAt
        self.revision = revision
    }
}

enum LiveParsePlatformSessionVault {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: LiveParsePlatformSession] = [:]

    static func update(platformId: String, cookie: String, uid: String?) {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return }

        let normalizedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUID = uid?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        // A read-only status check commonly republishes the persisted session
        // before invoking plugin code. Preserve the revision when the effective
        // credential is unchanged so read-only checks do not evict a healthy
        // runtime or invalidate work tied to the current generation.
        if let current = sessions[normalizedId],
           current.cookie == normalizedCookie,
           current.uid == normalizedUID {
            lock.unlock()
            return
        }
        // 空值保留为带时间戳的 tombstone，使登录→退出后不会复用旧匿名 session 缓存。
        sessions[normalizedId] = LiveParsePlatformSession(
            cookie: normalizedCookie,
            uid: normalizedUID,
            updatedAt: .now
        )
        lock.unlock()
    }

    static func clear(platformId: String) {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return }
        lock.lock()
        sessions[normalizedId] = LiveParsePlatformSession(cookie: "", uid: nil, updatedAt: .now)
        lock.unlock()
    }

    static func session(for platformId: String) -> LiveParsePlatformSession? {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return nil }
        lock.lock()
        let session = sessions[normalizedId]
        lock.unlock()
        return session
    }

    /// 恢复一次临时凭据校验前的精确运行时快照。nil 表示此前没有覆盖值，
    /// 需要移除临时条目而不是留下空 Cookie tombstone。
    static func restore(platformId: String, session: LiveParsePlatformSession?) {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return }
        lock.lock()
        if let session {
            sessions[normalizedId] = session
        } else {
            sessions.removeValue(forKey: normalizedId)
        }
        lock.unlock()
    }

    static func cookieValue(named name: String, for platformId: String) -> String? {
        cookieValue(named: name, for: platformId, sessionOverride: nil)
    }

    static func cookieValue(
        named name: String,
        for platformId: String,
        sessionOverride: LiveParsePlatformSession?
    ) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        return mergedCookiePairs(for: platformId, sessionOverride: sessionOverride)
            .last { $0.0 == normalizedName }?
            .1
    }

    static func mergedCookieHeader(for platformId: String) -> String? {
        mergedCookieHeader(for: platformId, sessionOverride: nil)
    }

    static func mergedCookieHeader(
        for platformId: String,
        sessionOverride: LiveParsePlatformSession?
    ) -> String? {
        let merged = mergedCookiePairs(for: platformId, sessionOverride: sessionOverride)
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
        return merged.isEmpty ? nil : merged
    }

    static func revision(for platformId: String) -> String {
        revision(for: platformId, sessionOverride: nil)
    }

    static func revision(
        for platformId: String,
        sessionOverride: LiveParsePlatformSession?
    ) -> String {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return "anonymous" }
        guard let revision = (sessionOverride ?? session(for: normalizedId))?.revision else {
            return "anonymous"
        }
        return revision
    }

    private static func parseCookiePairs(_ cookie: String) -> [(String, String)] {
        cookie.split(separator: ";").compactMap { pair in
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { return nil }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? nil : (key, value)
        }
    }

    private static func mergedCookiePairs(
        for platformId: String,
        sessionOverride: LiveParsePlatformSession?
    ) -> [(String, String)] {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return [] }

        var cookiePairs: [(String, String)] = []

        if let defaultCookie = defaultCookie(for: normalizedId) {
            cookiePairs.append(contentsOf: parseCookiePairs(defaultCookie))
        }

        if let sessionCookie = (sessionOverride ?? session(for: normalizedId))?.cookie,
           !sessionCookie.isEmpty {
            cookiePairs.append(contentsOf: parseCookiePairs(sessionCookie))
        }

        var seen: [String: Int] = [:]
        var deduped: [(String, String)] = []
        for (key, value) in cookiePairs {
            if let index = seen[key] {
                deduped[index] = (key, value)
            } else {
                seen[key] = deduped.count
                deduped.append((key, value))
            }
        }
        return deduped
    }

    static func canonicalPlatformId(_ platformId: String) -> String {
        let raw = platformId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return "" }
        if let platform = LiveParseJSPlatformManager.platform(forPluginId: raw) {
            return platform.pluginId
        }
        if let platform = LiveParseJSPlatformManager.availablePlatforms.first(where: {
            $0.sessionMigration?.legacyPluginIds?.contains(raw) == true
        }) {
            return platform.pluginId
        }
        return raw
    }

    private static func defaultCookie(for platformId: String) -> String? {
        LiveParseJSPlatformManager.platform(forPluginId: platformId)?
            .sessionMigration?
            .defaultCookie?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
