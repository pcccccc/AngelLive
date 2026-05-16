import Foundation

/// Shared Cookie handling for platform login web views.
///
/// Some third-party platforms set auth cookies on sibling domains
/// (`www.twitch.tv` vs `.twitch.tv`, `kick.com` vs `.kick.com`). Keeping the
/// filtering and de-duplication rules here avoids iOS/macOS/tvOS drifting apart.
public enum PlatformCookieCollector {
    public static func filteredCookies(
        from cookies: [HTTPCookie],
        loginFlow: ManifestLoginFlow
    ) -> [HTTPCookie] {
        let hints = domainHints(for: loginFlow)
        guard !hints.isEmpty else { return cookies }
        return cookies.filter { cookie in
            hints.contains { hint in
                domainMatches(cookie.domain, hint: hint)
            }
        }
    }

    public static func containsAuthenticatedCookie(
        in cookies: [HTTPCookie],
        loginFlow: ManifestLoginFlow
    ) -> Bool {
        let names = Set(cookies.map(\.name))
        return loginFlow.authSignalCookies.contains { names.contains($0) }
    }

    public static func cookieHeader(from cookies: [HTTPCookie]) -> String {
        var bestByName: [String: HTTPCookie] = [:]
        for cookie in cookies {
            guard !cookie.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if let existing = bestByName[cookie.name] {
                if isPreferredCookie(cookie, over: existing) {
                    bestByName[cookie.name] = cookie
                }
            } else {
                bestByName[cookie.name] = cookie
            }
        }

        return bestByName.values
            .sorted(by: cookieSort)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    public static func signature(from cookies: [HTTPCookie]) -> String {
        cookies
            .sorted(by: cookieSort)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: ";")
    }

    public static func extractUID(
        from cookies: [HTTPCookie],
        loginFlow: ManifestLoginFlow
    ) -> String? {
        let uidNames = loginFlow.uidCookieNames ?? ["DedeUserID", "uid", "user_id", "userId"]
        for name in uidNames {
            if let value = cookies.first(where: { $0.name == name })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    public static func domainHints(for loginFlow: ManifestLoginFlow) -> [String] {
        var hints = loginFlow.cookieDomains
        if let host = URL(string: loginFlow.loginURL)?.host {
            hints.append(host)
        }
        if let host = loginFlow.websiteHost {
            hints.append(host)
        }
        return Array(Set(hints.map(normalizedDomain).filter { !$0.isEmpty })).sorted()
    }

    public static func domainMatches(_ cookieDomain: String, hint: String) -> Bool {
        let domain = normalizedDomain(cookieDomain)
        let normalizedHint = normalizedDomain(hint)
        guard !domain.isEmpty, !normalizedHint.isEmpty else { return false }

        return domain == normalizedHint
            || domain.hasSuffix("." + normalizedHint)
            || normalizedHint.hasSuffix("." + domain)
    }

    public static func normalizedDomain(_ domain: String) -> String {
        domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private static func isPreferredCookie(_ candidate: HTTPCookie, over current: HTTPCookie) -> Bool {
        // Prefer active session cookies and more specific domains/paths when
        // duplicate names appear on sibling domains during WebKit login.
        let candidatePriority = cookiePriorityValues(candidate)
        let currentPriority = cookiePriorityValues(current)

        for index in candidatePriority.indices {
            if candidatePriority[index] != currentPriority[index] {
                return candidatePriority[index] > currentPriority[index]
            }
        }
        return true
    }

    private static func cookiePriorityValues(_ cookie: HTTPCookie) -> [Int] {
        [
            cookie.value.isEmpty ? 0 : 1,
            cookie.isSessionOnly ? 1 : 0,
            normalizedDomain(cookie.domain).count,
            cookie.path.count,
            Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
        ]
    }

    private static func cookieSort(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        if lhs.domain != rhs.domain {
            return lhs.domain < rhs.domain
        }
        return lhs.path < rhs.path
    }
}
