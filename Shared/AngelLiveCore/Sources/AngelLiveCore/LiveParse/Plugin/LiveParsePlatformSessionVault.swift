import Foundation

struct LiveParsePlatformSession: Sendable {
    let cookie: String
    let uid: String?
    let updatedAt: Date
}

enum LiveParsePlatformSessionVault {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: LiveParsePlatformSession] = [:]

    static func update(platformId: String, cookie: String, uid: String?) {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return }

        let normalizedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        // 空值保留为带时间戳的 tombstone，使登录→退出后不会复用旧匿名 session 缓存。
        sessions[normalizedId] = LiveParsePlatformSession(
            cookie: normalizedCookie,
            uid: uid?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    static func cookieValue(named name: String, for platformId: String) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        return mergedCookiePairs(for: platformId)
            .last { $0.0 == normalizedName }?
            .1
    }

    static func mergedCookieHeader(for platformId: String) -> String? {
        let merged = mergedCookiePairs(for: platformId)
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
        return merged.isEmpty ? nil : merged
    }

    static func revision(for platformId: String) -> String {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return "anonymous" }
        guard let updatedAt = session(for: normalizedId)?.updatedAt else { return "anonymous" }
        return String(updatedAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
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

    private static func mergedCookiePairs(for platformId: String) -> [(String, String)] {
        let normalizedId = canonicalPlatformId(platformId)
        guard !normalizedId.isEmpty else { return [] }

        var cookiePairs: [(String, String)] = []

        if let defaultCookie = defaultCookie(for: normalizedId) {
            cookiePairs.append(contentsOf: parseCookiePairs(defaultCookie))
        }

        if let sessionCookie = session(for: normalizedId)?.cookie,
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
