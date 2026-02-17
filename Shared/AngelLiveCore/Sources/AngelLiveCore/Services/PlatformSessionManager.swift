//
//  PlatformSessionManager.swift
//  AngelLiveCore
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Security

public enum PlatformSessionID: String, Codable, Sendable {
    case bilibili
}

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

public struct PlatformSession: Codable, Sendable {
    public let platformId: PlatformSessionID
    public var cookie: String?
    public var csrf: String?
    public var refreshToken: String?
    public var uid: String?
    public var expireAt: Date?
    public var source: PlatformSessionSource
    public var state: PlatformSessionState
    public var updatedAt: Date

    public init(
        platformId: PlatformSessionID,
        cookie: String?,
        csrf: String? = nil,
        refreshToken: String? = nil,
        uid: String? = nil,
        expireAt: Date? = nil,
        source: PlatformSessionSource = .local,
        state: PlatformSessionState = .anonymous,
        updatedAt: Date = Date()
    ) {
        self.platformId = platformId
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

    public init(
        cookie: String?,
        csrf: String? = nil,
        refreshToken: String? = nil,
        uid: String? = nil,
        expireAt: Date? = nil,
        source: PlatformSessionSource,
        state: PlatformSessionState
    ) {
        self.cookie = cookie
        self.csrf = csrf
        self.refreshToken = refreshToken
        self.uid = uid
        self.expireAt = expireAt
        self.source = source
        self.state = state
    }
}

public actor PlatformSessionManager {
    public static let shared = PlatformSessionManager()

    private let store = SessionStore()

    private init() {}

    public func getSession(platformId: PlatformSessionID) -> PlatformSession? {
        store.loadSession(for: platformId)
    }

    public func updateSession(platformId: PlatformSessionID, data: PlatformSessionData) {
        let session = PlatformSession(
            platformId: platformId,
            cookie: data.cookie,
            csrf: data.csrf,
            refreshToken: data.refreshToken,
            uid: data.uid,
            expireAt: data.expireAt,
            source: data.source,
            state: data.state,
            updatedAt: Date()
        )
        store.saveSession(session)
    }

    public func clearSession(platformId: PlatformSessionID) {
        store.clearSession(for: platformId)
    }

    public func validateSession(platformId: PlatformSessionID) async -> PlatformSessionValidationResult {
        guard let session = getSession(platformId: platformId),
              let cookie = session.cookie,
              !cookie.isEmpty else {
            return .invalid(reason: "Cookie 为空")
        }

        switch platformId {
        case .bilibili:
            return await validateBilibiliSession(cookie: cookie)
        }
    }

    private func validateBilibiliSession(cookie: String) async -> PlatformSessionValidationResult {
        let result = await BilibiliAccountService.shared.loadUserInfo(
            cookie: cookie,
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        )

        switch result {
        case .success:
            return .valid
        case .failure(let error):
            switch error {
            case .cookieExpired:
                return .expired
            case .networkError(let message):
                return .networkError(message)
            case .emptyCookie:
                return .invalid(reason: "Cookie 为空")
            case .invalidURL:
                return .invalid(reason: "无效的验证 URL")
            case .decodingError(let message), .invalidResponse(let message):
                return .invalid(reason: message)
            }
        }
    }
}

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
    }

    private struct SessionSensitivePayload: Codable {
        let cookie: String?
        let csrf: String?
        let refreshToken: String?
    }

    private struct LegacyKeys {
        static let bilibiliCookie = "SimpleLive.Setting.BilibiliCookie"
        static let bilibiliUid = "LiveParse.Bilibili.uid"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychain = KeychainStore(service: Constants.keychainService)

    func loadSession(for platformId: PlatformSessionID) -> PlatformSession? {
        migrateLegacyIfNeeded(for: platformId)

        guard let metadataData = defaults.data(forKey: metadataKey(for: platformId)),
              let metadata = try? decoder.decode(SessionMetadata.self, from: metadataData) else {
            return nil
        }

        let sensitive = loadSensitivePayload(for: platformId)
        return PlatformSession(
            platformId: platformId,
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

    func saveSession(_ session: PlatformSession) {
        let metadata = SessionMetadata(
            uid: session.uid,
            source: session.source,
            state: session.state,
            expireAt: session.expireAt,
            updatedAt: session.updatedAt
        )
        if let metadataData = try? encoder.encode(metadata) {
            defaults.set(metadataData, forKey: metadataKey(for: session.platformId))
        }

        let sensitive = SessionSensitivePayload(
            cookie: session.cookie,
            csrf: session.csrf,
            refreshToken: session.refreshToken
        )
        if let sensitiveData = try? encoder.encode(sensitive) {
            keychain.write(sensitiveData, account: keychainAccount(for: session.platformId))
        }

        defaults.set(true, forKey: migrationKey(for: session.platformId))
    }

    func clearSession(for platformId: PlatformSessionID) {
        defaults.removeObject(forKey: metadataKey(for: platformId))
        keychain.delete(account: keychainAccount(for: platformId))
    }

    private func migrateLegacyIfNeeded(for platformId: PlatformSessionID) {
        guard !defaults.bool(forKey: migrationKey(for: platformId)) else { return }

        guard platformId == .bilibili else {
            defaults.set(true, forKey: migrationKey(for: platformId))
            return
        }

        let legacyCookie = defaults.string(forKey: LegacyKeys.bilibiliCookie) ?? ""
        let legacyUid = defaults.string(forKey: LegacyKeys.bilibiliUid)
        guard !legacyCookie.isEmpty else {
            defaults.set(true, forKey: migrationKey(for: platformId))
            return
        }

        let migrated = PlatformSession(
            platformId: .bilibili,
            cookie: legacyCookie,
            uid: legacyUid,
            source: .legacy,
            state: legacyCookie.contains("SESSDATA") ? .authenticated : .invalid,
            updatedAt: Date()
        )
        saveSession(migrated)
    }

    private func loadSensitivePayload(for platformId: PlatformSessionID) -> SessionSensitivePayload? {
        guard let data = keychain.read(account: keychainAccount(for: platformId)) else { return nil }
        return try? decoder.decode(SessionSensitivePayload.self, from: data)
    }

    private func metadataKey(for platformId: PlatformSessionID) -> String {
        "AngelLive.SessionStore.\(platformId.rawValue).metadata"
    }

    private func migrationKey(for platformId: PlatformSessionID) -> String {
        "AngelLive.SessionStore.\(platformId.rawValue).migrated.v1"
    }

    private func keychainAccount(for platformId: PlatformSessionID) -> String {
        "session.\(platformId.rawValue)"
    }
}

private struct KeychainStore {
    let service: String

    func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(item as CFDictionary, nil)
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
