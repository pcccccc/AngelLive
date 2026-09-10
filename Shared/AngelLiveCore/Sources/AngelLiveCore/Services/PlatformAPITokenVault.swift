import Foundation
import Security

public enum PlatformAPICredentialKind: String, Codable, Sendable {
    case token
    case clientCredentials = "client_credentials"
    case deviceCode = "oauth_device_code"
}

protocol APITokenStorage {
    func read(pluginId: String) throws -> Data?
    func write(_ data: Data, pluginId: String) throws
    func delete(pluginId: String) throws
}

struct APITokenKeychain: APITokenStorage {
    private func query(_ pluginId: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.angellive.api-credentials",
         kSecAttrAccount as String: "token.\(pluginId)",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func read(pluginId: String) throws -> Data? {
        var request = query(pluginId)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APITokenError.storage }
        return data
    }

    func write(_ data: Data, pluginId: String) throws {
        let request = query(pluginId)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw APITokenError.storage }
        var item = request
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APITokenError.storage }
    }

    func delete(pluginId: String) throws {
        let status = SecItemDelete(query(pluginId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APITokenError.storage }
    }
}

enum APITokenError: Error, LocalizedError {
    case storage, invalid, changed
    var errorDescription: String? {
        switch self {
        case .storage: "无法访问安全存储，请稍后重试。"
        case .invalid: "校验失败，请检查 API 凭据。"
        case .changed: "凭据已更改，请重试。"
        }
    }
}

/// API credential records never enter Cookie sessions, defaults, or credential sync.
/// This actor serializes persistence and generation changes without suspension.
actor PlatformAPITokenVault {
    static let shared = PlatformAPITokenVault(
        storage: APITokenKeychain(),
        hostPolicy: { PlatformAPICredentialHostPolicy.shared.isFullUI }
    )
    nonisolated let deviceAuth: PlatformDeviceAuthCoordinator
    struct Record: Codable, Sendable {
        let token: String?
        let clientId: String?
        let clientSecret: String?
        let deviceCredential: DeviceAPICredential?
        let status: CredentialStatus

        var kind: PlatformAPICredentialKind { deviceCredential != nil ? .deviceCode : clientSecret == nil ? .token : .clientCredentials }
        var payload: [String: String] {
            if let deviceCredential { return deviceCredential.browsePayload }
            if let clientId, let clientSecret { return ["clientId": clientId, "clientSecret": clientSecret] }
            return token.map { ["apiToken": $0] } ?? [:]
        }
        var secrets: [String] { [token, clientSecret, deviceCredential?.accessToken, deviceCredential?.refreshToken].compactMap { $0 } }

        init(token: String, status: CredentialStatus) {
            self.token = token
            self.clientId = nil
            self.clientSecret = nil
            self.deviceCredential = nil
            self.status = status
        }

        init(clientId: String, clientSecret: String, status: CredentialStatus) {
            self.token = nil
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.deviceCredential = nil
            self.status = status
        }

        init(deviceCredential: DeviceAPICredential, status: CredentialStatus) {
            self.token = nil
            self.clientId = nil
            self.clientSecret = nil
            self.deviceCredential = deviceCredential
            self.status = status
        }

        private enum CodingKeys: String, CodingKey { case token, clientId, clientSecret, deviceCredential, status }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            token = try values.decodeIfPresent(String.self, forKey: .token)
            clientId = try values.decodeIfPresent(String.self, forKey: .clientId)
            clientSecret = try values.decodeIfPresent(String.self, forKey: .clientSecret)
            deviceCredential = try values.decodeIfPresent(DeviceAPICredential.self, forKey: .deviceCredential)
            status = try values.decode(CredentialStatus.self, forKey: .status)
            guard (deviceCredential == nil && ((token != nil && clientId == nil && clientSecret == nil)
                    || (token == nil && clientId != nil && clientSecret != nil)))
                    || (deviceCredential?.isWellFormed == true && token == nil && clientId == nil && clientSecret == nil) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid API credential record"))
            }
        }

        func replacingStatus(_ status: CredentialStatus) -> Record {
            if let deviceCredential { return .init(deviceCredential: deviceCredential, status: status) }
            if let clientId, let clientSecret { return .init(clientId: clientId, clientSecret: clientSecret, status: status) }
            return .init(token: token ?? "", status: status)
        }
    }
    struct Snapshot: Sendable {
        let generation: UUID
        let record: Record?
        var token: String? { record?.token }
    }
    private let storage: any APITokenStorage
    private var generations: [String: UUID] = [:]
    private var runtimes: [String: [ObjectIdentifier: JSRuntime]] = [:]
    private var fullUIConsumers: Set<UUID> = []
    private let hostPolicy: @MainActor @Sendable () -> Bool
    // A rotated single-use refresh token must never fall back to the disk record.
    private var pendingRotations: [String: Record] = [:]

    init(
        storage: sending any APITokenStorage,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
        hostPolicy: @escaping @MainActor @Sendable () -> Bool = { false }
    ) {
        self.storage = storage
        self.deviceAuth = PlatformDeviceAuthCoordinator(now: now)
        self.hostPolicy = hostPolicy
    }

    func activate(_ consumer: UUID) { fullUIConsumers.insert(consumer) }
    func deactivate(_ consumer: UUID) { fullUIConsumers.remove(consumer) }
    var isEnabled: Bool {
        get async {
            if !fullUIConsumers.isEmpty { return true }
            return await hostPolicy()
        }
    }

    func record(pluginId: String) throws -> Record? {
        if let pending = pendingRotations[pluginId] { return pending }
        guard let data = try storage.read(pluginId: pluginId) else { return nil }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    func snapshot(pluginId: String) throws -> Snapshot {
        Snapshot(generation: generationSnapshot(pluginId: pluginId).generation, record: try record(pluginId: pluginId))
    }

    func generationSnapshot(pluginId: String) -> Snapshot {
        let generation = generations[pluginId] ?? UUID()
        generations[pluginId] = generation
        return Snapshot(generation: generation, record: nil)
    }

    func check(pluginId: String, generation: UUID) throws {
        guard generations[pluginId] == generation else { throw APITokenError.changed }
    }

    func register(_ runtime: JSRuntime, pluginId: String, generation: UUID) throws {
        try check(pluginId: pluginId, generation: generation)
        runtimes[pluginId, default: [:]][ObjectIdentifier(runtime)] = runtime
    }

    func updateStatus(_ status: CredentialStatus, pluginId: String, generation: UUID, manager: LiveParsePluginManager) throws -> [JSRuntime] {
        try check(pluginId: pluginId, generation: generation)
        guard let previous = try record(pluginId: pluginId) else { return [] }
        let next = previous.replacingStatus(status)
        if previous.status.state != status.state, ["invalid", "expired", "missing"].contains(status.state) {
            return try replace(pluginId: pluginId, record: next, expectedGeneration: generation, manager: manager)
        }
        try storage.write(JSONEncoder().encode(next), pluginId: pluginId)
        return []
    }

    /// Returns every runtime that ever saw this generation, including evicted versions.
    func replace(pluginId: String, record: Record?, expectedGeneration: UUID? = nil, manager: LiveParsePluginManager) throws -> [JSRuntime] {
        try Task.checkCancellation()
        if let expectedGeneration { try check(pluginId: pluginId, generation: expectedGeneration) }
        if let record { try storage.write(JSONEncoder().encode(record), pluginId: pluginId) }
        else { try storage.delete(pluginId: pluginId) }
        pendingRotations[pluginId] = nil
        generations[pluginId] = UUID()
        manager.evict(pluginId: pluginId)
        return Array(runtimes.removeValue(forKey: pluginId)?.values ?? [:].values)
    }

    func persistRotation(_ record: Record, pluginId: String, generation: UUID) throws {
        try check(pluginId: pluginId, generation: generation)
        pendingRotations[pluginId] = record
        try flushRotation(pluginId: pluginId)
    }

    func flushRotation(pluginId: String) throws {
        guard let record = pendingRotations[pluginId] else { return }
        try storage.write(JSONEncoder().encode(record), pluginId: pluginId)
        pendingRotations[pluginId] = nil
    }
}

/// Host mode is known before browsing views mount. Only the three hosts' root
/// catalog services opt in; ShellUI, extensions and standalone managers default off.
/// Request tasks await this policy without delaying cached or local UI.
@MainActor
final class PlatformAPICredentialHostPolicy {
    static let shared = PlatformAPICredentialHostPolicy()
    private(set) var isFullUI = false
    private var isInitialized = false

    func initializeIfNeeded(hasInstalledPlugins: @autoclosure () -> Bool) {
        guard !isInitialized else { return }
        update(hasInstalledPlugins: hasInstalledPlugins())
    }

    func update(hasInstalledPlugins: Bool) {
        isFullUI = hasInstalledPlugins
        isInitialized = true
    }
}

enum APITokenCallPolicy {
    static let functions: Set<String> = [
        "validateCredential", "getCredentialStatus", "getCategories", "getRooms",
        "search", "getRoomDetail", "getLiveState", "resolveShare"
    ]

    static func safeError(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let error = error as? APITokenError { return error }
        if case let LiveParsePluginError.standardized(value) = error {
            let reasons: Set<String> = ["api_token_missing", "api_token_invalid", "api_token_expired", "api_token_revoked", "credential_changed", "device_login_changed", "oauth_reauth_required", "integrity_required"]
            let context = value.context["reason"].flatMap { reasons.contains($0) ? ["reason": $0] : nil } ?? [:]
            return LiveParsePluginError.standardized(.init(code: value.code, message: "插件请求失败（\(value.code.rawValue)）", context: context))
        }
        return LiveParsePluginError.invalidReturnValue("API 凭据请求失败，请稍后重试。")
    }
}
