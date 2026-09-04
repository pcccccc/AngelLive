import Foundation

public enum LoginTransactionError: Error, LocalizedError, Sendable, Equatable {
    case invalidPluginId
    case invalidTransactionId
    case notFound
    case ownershipMismatch
    case expired
    case invalidCookieScope
    case ambiguousCookieName

    public var errorDescription: String? {
        switch self {
        case .invalidPluginId:
            return "Login transaction plugin identifier is empty"
        case .invalidTransactionId:
            return "Login transaction identifier is empty"
        case .notFound:
            return "Login transaction is no longer active"
        case .ownershipMismatch:
            return "Login transaction belongs to another plugin"
        case .expired:
            return "Login transaction expired"
        case .invalidCookieScope:
            return "Login transaction cookie scope is invalid"
        case .ambiguousCookieName:
            return "Login transaction contains conflicting scoped cookies with the same name"
        }
    }
}

/// Owns the short-lived Cookie jars used by plugin-driven login challenges.
///
/// All mutable cookie state stays inside this actor. A transaction is bound to the
/// plugin that created it, and a plugin can have at most one active transaction.
/// Nothing is persisted to the shared system Cookie storage.
public actor LoginTransactionStore {
    public static let shared = LoginTransactionStore()

    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
    }

    private struct StoredCookie {
        let cookie: HTTPCookie
        let hostOnly: Bool
    }

    private struct Transaction {
        let pluginId: String
        let expiresAt: ContinuousClock.Instant
        var cookies: [CookieKey: StoredCookie]
    }

    private let hardTimeout: Duration
    private let clock = ContinuousClock()
    private var transactions: [String: Transaction] = [:]
    private var activeTransactionByPlugin: [String: String] = [:]
    private var expirationTasks: [String: Task<Void, Never>] = [:]

    public init(hardTimeout: Duration = .seconds(600)) {
        self.hardTimeout = hardTimeout > .zero ? hardTimeout : .milliseconds(1)
    }

    @discardableResult
    public func begin(pluginId: String) throws -> String {
        let owner = pluginId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { throw LoginTransactionError.invalidPluginId }

        if let previous = activeTransactionByPlugin[owner] {
            destroy(transactionId: previous)
        }

        let transactionId = UUID().uuidString.lowercased()
        transactions[transactionId] = Transaction(
            pluginId: owner,
            expiresAt: clock.now.advanced(by: hardTimeout),
            cookies: [:]
        )
        activeTransactionByPlugin[owner] = transactionId

        let timeout = hardTimeout
        expirationTasks[transactionId] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                try Task.checkCancellation()
            } catch {
                return
            }
            await self?.expire(transactionId: transactionId)
        }
        return transactionId
    }

    /// Returns a Cookie header filtered for `url`. Passing nil returns every cookie
    /// in the transaction, which is useful to plugin-side request signers.
    public func cookieHeader(
        pluginId: String,
        transactionId: String,
        for url: URL? = nil
    ) throws -> String {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        removeExpiredCookies(from: &transaction)
        transactions[transactionId] = transaction

        let cookies = transaction.cookies.values
            .filter { stored in
                guard let url else { return true }
                return Self.cookie(stored, appliesTo: url)
            }
            .map(\.cookie)
            .sorted(by: Self.cookieSortOrder)

        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Builds a Cookie header for a host-authorized login destination. Cookies
    /// that directly satisfy RFC scope for the destination win. Only names
    /// without a scoped candidate fall back to a unique cross-domain value.
    /// This lets an external bootstrap retain its own anonymous cookie while a
    /// plugin seeds a destination-scoped replacement without losing that name.
    func cookieHeaderForNativeRouting(
        pluginId: String,
        transactionId: String,
        for url: URL
    ) throws -> String {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        removeExpiredCookies(from: &transaction)
        transactions[transactionId] = transaction

        let storedCookies = transaction.cookies.values.sorted {
            Self.cookieSortOrder($0.cookie, $1.cookie)
        }
        let scopedCookies = storedCookies.filter { Self.cookie($0, appliesTo: url) }.map(\.cookie)
        let scopedNames = Set(scopedCookies.map { $0.name.lowercased() })
        let fallbackCookies = storedCookies.map(\.cookie).filter {
            !scopedNames.contains($0.name.lowercased())
        }
        var valuesByName: [String: Set<String>] = [:]
        for cookie in fallbackCookies {
            valuesByName[cookie.name.lowercased(), default: []].insert(cookie.value)
        }

        var emittedNames: Set<String> = []
        let fallbackPairs = fallbackCookies.compactMap { cookie -> String? in
            let name = cookie.name.lowercased()
            guard emittedNames.insert(name).inserted,
                  valuesByName[name]?.count == 1 else {
                return nil
            }
            return "\(cookie.name)=\(cookie.value)"
        }
        return (scopedCookies.map { "\($0.name)=\($0.value)" } + fallbackPairs)
            .joined(separator: "; ")
    }

    /// Resolves one transaction Cookie for host-side injection without exposing
    /// its value to JavaScript. Unlike `cookieHeader(for:)`, this lookup is not
    /// constrained by the destination URL because the caller separately
    /// enforces the manifest destination allowlist before attaching it.
    func cookieValueForNativeInjection(
        pluginId: String,
        transactionId: String,
        named rawName: String,
        for url: URL
    ) throws -> String? {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        removeExpiredCookies(from: &transaction)
        transactions[transactionId] = transaction

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let matching = transaction.cookies.values.filter { stored in
            stored.cookie.name.caseInsensitiveCompare(name) == .orderedSame
        }
        let scoped = matching.filter { Self.cookie($0, appliesTo: url) }
        let candidates = scoped.isEmpty ? matching : scoped
        let values = Set(candidates.map { $0.cookie.value })
        guard values.count <= 1 else {
            throw LoginTransactionError.ambiguousCookieName
        }
        return values.first
    }

    /// Seeds plugin-generated anonymous device fields into a transaction jar.
    public func seed(
        pluginId: String,
        transactionId: String,
        cookies: [String: String],
        domain: String,
        path: String = "/",
        secure: Bool = false
    ) throws {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        let normalizedDomain = Self.normalizedDomain(domain)
        let normalizedPath = Self.normalizedPath(path)
        guard Self.isValidCookieDomain(normalizedDomain),
              Self.isAllowedSeedDomain(normalizedDomain) else {
            throw LoginTransactionError.invalidCookieScope
        }

        for (rawName, value) in cookies {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  Self.hasValidPrefix(
                    name: name,
                    isSecure: secure,
                    path: normalizedPath,
                    hasDomainAttribute: true,
                    hasExplicitRootPath: normalizedPath == "/"
                  ),
                  let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: normalizedDomain,
                    .path: normalizedPath,
                    .secure: secure ? "TRUE" : "FALSE"
                  ]) else {
                continue
            }
            let key = Self.key(for: cookie)
            transaction.cookies[key] = StoredCookie(cookie: cookie, hostOnly: false)
        }
        transactions[transactionId] = transaction
    }

    /// Absorbs every Set-Cookie field from one response hop.
    public func absorb(
        pluginId: String,
        transactionId: String,
        setCookieHeaders: [String],
        responseURL: URL
    ) throws {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        guard let responseHost = responseURL.host.map(Self.normalizedDomain),
              !responseHost.isEmpty else {
            throw LoginTransactionError.invalidCookieScope
        }

        for header in setCookieHeaders.flatMap(Self.splitCombinedSetCookieHeader) {
            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: ["Set-Cookie": header],
                for: responseURL
            )
            let hostOnly = !Self.hasDomainAttribute(header)
            for cookie in cookies {
                guard Self.cookie(
                    cookie,
                    fromHeader: header,
                    responseURL: responseURL,
                    responseHost: responseHost,
                    isHostOnly: hostOnly
                ) else {
                    continue
                }
                let key = Self.key(for: cookie)
                if Self.isExpired(cookie) {
                    transaction.cookies.removeValue(forKey: key)
                } else {
                    transaction.cookies[key] = StoredCookie(cookie: cookie, hostOnly: hostOnly)
                }
            }
        }
        transactions[transactionId] = transaction
    }

    /// Imports cookies harvested from a transaction-scoped native WebView.
    /// Only manifest-authorized domains enter the jar; values never cross into JavaScript.
    @discardableResult
    func absorbWebViewCookies(
        pluginId: String,
        transactionId: String,
        cookies: [HTTPCookie],
        allowedDomains: [String]
    ) throws -> Set<String> {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        let domains = allowedDomains
            .map(Self.normalizedDomain)
            .filter { Self.isValidCookieDomain($0) && Self.isAllowedSeedDomain($0) }
        guard !domains.isEmpty else { return [] }

        for cookie in cookies {
            let rawDomain = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines)
            let domain = Self.normalizedDomain(rawDomain)
            guard domains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }),
                  Self.isValidCookieDomain(domain),
                  Self.isAllowedSeedDomain(domain) else {
                continue
            }

            let hostOnly = !rawDomain.hasPrefix(".")
            let path = Self.normalizedPath(cookie.path)
            guard Self.hasValidPrefix(
                name: cookie.name,
                isSecure: cookie.isSecure,
                path: path,
                hasDomainAttribute: !hostOnly,
                hasExplicitRootPath: path == "/"
            ) else {
                continue
            }

            let key = Self.key(for: cookie)
            if Self.isExpired(cookie) {
                transaction.cookies.removeValue(forKey: key)
            } else {
                transaction.cookies[key] = StoredCookie(cookie: cookie, hostOnly: hostOnly)
            }
        }
        removeExpiredCookies(from: &transaction)
        transactions[transactionId] = transaction

        return Set(transaction.cookies.values.compactMap { stored in
            let domain = Self.normalizedDomain(stored.cookie.domain)
            guard domains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) else {
                return nil
            }
            return stored.cookie.name
        })
    }

    /// Serializes all cookies and destroys the transaction before returning.
    public func promote(
        pluginId: String,
        transactionId: String,
        preferredDomains: [String] = []
    ) throws -> String {
        var transaction = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        removeExpiredCookies(from: &transaction)
        transactions[transactionId] = transaction

        let normalizedPreferredDomains = preferredDomains
            .map(Self.normalizedDomain)
            .filter { !$0.isEmpty }
        let storedCookies: [StoredCookie]
        if normalizedPreferredDomains.isEmpty {
            storedCookies = Array(transaction.cookies.values)
        } else {
            storedCookies = transaction.cookies.values.filter { stored in
                normalizedPreferredDomains.contains { allowedDomain in
                    let domain = Self.normalizedDomain(stored.cookie.domain)
                    return domain == allowedDomain
                        || domain.hasSuffix(".\(allowedDomain)")
                        || allowedDomain.hasSuffix(".\(domain)")
                }
            }
        }
        var valueByName: [String: String] = [:]
        var promotedPairs: [String] = []
        for cookie in storedCookies.map(\.cookie).sorted(by: Self.cookieSortOrder) {
            if let existing = valueByName[cookie.name] {
                guard existing == cookie.value else {
                    // The legacy persisted credential is a flat Cookie string.
                    // Refuse an ambiguous promotion rather than silently choose
                    // one domain/path's account token for every later request.
                    throw LoginTransactionError.ambiguousCookieName
                }
                continue
            }
            valueByName[cookie.name] = cookie.value
            promotedPairs.append("\(cookie.name)=\(cookie.value)")
        }

        let header = promotedPairs.joined(separator: "; ")
        destroy(transactionId: transactionId)
        return header
    }

    public func discard(pluginId: String, transactionId: String) throws {
        _ = try activeTransaction(pluginId: pluginId, transactionId: transactionId)
        destroy(transactionId: transactionId)
    }

    func isActive(pluginId: String, transactionId: String) -> Bool {
        (try? activeTransaction(pluginId: pluginId, transactionId: transactionId)) != nil
    }

    private func activeTransaction(pluginId: String, transactionId: String) throws -> Transaction {
        let owner = pluginId.trimmingCharacters(in: .whitespacesAndNewlines)
        // Transaction identifiers are opaque capabilities. Do not normalize a
        // caller-supplied value: accepting a case/whitespace variant here and
        // then mutating `transactions[transactionId]` would create an orphan jar.
        let id = transactionId
        guard !owner.isEmpty else { throw LoginTransactionError.invalidPluginId }
        guard !id.isEmpty,
              id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw LoginTransactionError.invalidTransactionId
        }
        guard let transaction = transactions[id] else { throw LoginTransactionError.notFound }
        guard transaction.pluginId == owner else { throw LoginTransactionError.ownershipMismatch }
        guard activeTransactionByPlugin[owner] == id else {
            destroy(transactionId: id)
            throw LoginTransactionError.notFound
        }
        guard transaction.expiresAt > clock.now else {
            destroy(transactionId: id)
            throw LoginTransactionError.expired
        }
        return transaction
    }

    private func expire(transactionId: String) {
        guard let transaction = transactions[transactionId], transaction.expiresAt <= clock.now else { return }
        destroy(transactionId: transactionId)
    }

    private func destroy(transactionId: String) {
        if let transaction = transactions.removeValue(forKey: transactionId),
           activeTransactionByPlugin[transaction.pluginId] == transactionId {
            activeTransactionByPlugin.removeValue(forKey: transaction.pluginId)
        }
        expirationTasks.removeValue(forKey: transactionId)?.cancel()
    }

    private func removeExpiredCookies(from transaction: inout Transaction) {
        transaction.cookies = transaction.cookies.filter { !Self.isExpired($0.value.cookie) }
    }

    private static func key(for cookie: HTTPCookie) -> CookieKey {
        CookieKey(
            name: cookie.name,
            domain: normalizedDomain(cookie.domain),
            path: normalizedPath(cookie.path)
        )
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.newlines)).lowercased()
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private static func cookie(
        _ cookie: HTTPCookie,
        fromHeader header: String,
        responseURL: URL,
        responseHost: String,
        isHostOnly: Bool
    ) -> Bool {
        let cookieDomain = normalizedDomain(cookie.domain)
        if isHostOnly {
            // 不信任 Foundation 为 host-only Cookie 推导的 domain；必须与响应
            // host 完全一致，不能让解析器把它扩大到父域。
            guard cookieDomain == responseHost else { return false }
        } else {
            guard let rawDomain = attributeValue(named: "domain", in: header) else {
                return false
            }
            let declaredDomain = normalizedDomain(rawDomain)
            guard isValidCookieDomain(declaredDomain),
                  !isIPAddress(declaredDomain),
                  cookieDomain == declaredDomain,
                  responseHost == declaredDomain || responseHost.hasSuffix(".\(declaredDomain)"),
                  systemAcceptsDomainCookie(declaredDomain, from: responseURL) else {
                return false
            }
        }

        let secureAttribute = hasAttribute(named: "secure", in: header)
        // Secure Cookie（包括两种安全前缀）只能从 HTTPS 响应进入事务。
        if secureAttribute || cookie.isSecure {
            guard responseURL.scheme?.lowercased() == "https" else { return false }
        }
        let explicitPath = attributeValue(named: "path", in: header)
        return hasValidPrefix(
            name: cookie.name,
            isSecure: secureAttribute && cookie.isSecure,
            path: normalizedPath(cookie.path),
            hasDomainAttribute: !isHostOnly,
            hasExplicitRootPath: explicitPath == "/"
        )
    }

    private static func hasValidPrefix(
        name: String,
        isSecure: Bool,
        path: String,
        hasDomainAttribute: Bool,
        hasExplicitRootPath: Bool
    ) -> Bool {
        if name.hasPrefix("__Host-") {
            return isSecure
                && path == "/"
                && hasExplicitRootPath
                && !hasDomainAttribute
        }
        if name.hasPrefix("__Secure-") {
            return isSecure
        }
        return true
    }

    private static func isValidCookieDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.utf8.count <= 253 else { return false }
        if isIPAddress(domain) { return true }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
            }
        }
    }

    private static func isIPAddress(_ host: String) -> Bool {
        // URL.host removes IPv6 brackets. A colon identifies IPv6; four numeric
        // labels identify the IPv4 form relevant to Cookie Domain validation.
        if host.contains(":") { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return false }
        return labels.allSatisfy { label in
            guard let value = Int(label), (0...255).contains(value) else { return false }
            return String(value) == label || label == "0"
        }
    }

    private static func isAllowedSeedDomain(_ domain: String) -> Bool {
        guard !isIPAddress(domain), domain.contains("."),
              let childURL = URL(string: "https://login-scope-check.\(domain)/") else {
            return false
        }
        return systemAcceptsDomainCookie(domain, from: childURL)
    }

    /// `HTTPCookie.cookies(...)` 只负责语法解析，实测会接受 `Domain=com`、
    /// `Domain=github.io` 甚至无关域。独立 ephemeral storage 使用系统的
    /// Public Suffix/eTLD 规则做接收决策；它只存放无秘密的 probe，既不参与
    /// 网络请求，也不接触事务 Cookie 或共享 Cookie storage。
    private static func systemAcceptsDomainCookie(_ domain: String, from responseURL: URL) -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        guard let validator = configuration.httpCookieStorage,
              let probe = HTTPCookie(properties: [
                .name: "lp_domain_scope_probe",
                .value: "1",
                // leading dot 明确要求 storage 按 Domain cookie 而非 host-only
                // 处理，才能让系统 PSL 校验父域扩大是否成立。
                .domain: ".\(domain)",
                .path: "/"
              ]) else {
            return false
        }
        validator.cookieAcceptPolicy = .always
        validator.setCookies([probe], for: responseURL, mainDocumentURL: nil)
        return validator.cookies?.contains { candidate in
            candidate.name == probe.name
                && normalizedDomain(candidate.domain) == domain
        } == true
    }

    private static func isExpired(_ cookie: HTTPCookie) -> Bool {
        if let expires = cookie.expiresDate {
            return expires <= Date()
        }
        return false
    }

    private static func cookie(_ stored: StoredCookie, appliesTo url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = normalizedDomain(stored.cookie.domain)
        let domainMatches = stored.hostOnly
            ? host == domain
            : host == domain || host.hasSuffix(".\(domain)")
        guard domainMatches else { return false }
        guard !stored.cookie.isSecure || url.scheme?.lowercased() == "https" else { return false }

        let cookiePath = normalizedPath(stored.cookie.path)
        let requestPath = normalizedPath(url.path)
        if requestPath == cookiePath { return true }
        guard requestPath.hasPrefix(cookiePath) else { return false }
        if cookiePath.hasSuffix("/") { return true }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return boundary < requestPath.endIndex && requestPath[boundary] == "/"
    }

    private static func cookieSortOrder(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        if lhs.path.count != rhs.path.count { return lhs.path.count > rhs.path.count }
        if lhs.domain != rhs.domain { return lhs.domain < rhs.domain }
        return lhs.name < rhs.name
    }

    private static func hasDomainAttribute(_ header: String) -> Bool {
        hasAttribute(named: "domain", in: header)
    }

    private static func hasAttribute(named name: String, in header: String) -> Bool {
        header.split(separator: ";", omittingEmptySubsequences: true).dropFirst().contains { component in
            let attributeName = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return attributeName == name.lowercased()
        }
    }

    private static func attributeValue(named name: String, in header: String) -> String? {
        for component in header.split(separator: ";", omittingEmptySubsequences: true).dropFirst() {
            let parts = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = parts.first else { continue }
            let attributeName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard attributeName == name.lowercased(), parts.count == 2 else { continue }
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Foundation may expose repeated Set-Cookie fields as one comma-joined value.
    /// Split only when the text after a comma starts another cookie pair; commas in
    /// Expires attributes and quoted values remain untouched.
    static func splitCombinedSetCookieHeader(_ header: String) -> [String] {
        var result: [String] = []
        var start = header.startIndex
        var index = header.startIndex
        var quoted = false

        func append(_ range: Range<String.Index>) {
            let value = header[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(value) }
        }

        while index < header.endIndex {
            let character = header[index]
            if character == "\"" { quoted.toggle() }
            if !quoted, character == "\n" {
                append(start..<index)
                start = header.index(after: index)
            } else if !quoted, character == "," {
                let candidateStart = header.index(after: index)
                let remainder = header[candidateStart...]
                let firstSegment = remainder.prefix { $0 != ";" && $0 != "," && $0 != "\n" }
                if firstSegment.contains("=") {
                    append(start..<index)
                    start = candidateStart
                }
            }
            index = header.index(after: index)
        }
        append(start..<header.endIndex)
        return result
    }

    static func setCookieHeaders(from response: HTTPURLResponse) -> [String] {
        var values: [String] = []
        for (rawKey, rawValue) in response.allHeaderFields where String(describing: rawKey).lowercased() == "set-cookie" {
            if let array = rawValue as? [String] {
                values.append(contentsOf: array)
            } else if let array = rawValue as? NSArray {
                values.append(contentsOf: array.compactMap { $0 as? String })
            } else {
                values.append(String(describing: rawValue))
            }
        }
        if values.isEmpty, let combined = response.value(forHTTPHeaderField: "Set-Cookie") {
            values.append(combined)
        }
        return values.flatMap(splitCombinedSetCookieHeader)
    }
}
