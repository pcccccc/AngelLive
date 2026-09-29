import Foundation
import Observation
import Security

protocol RoomTranslationSecretStorage {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

struct RoomTranslationKeychain: RoomTranslationSecretStorage {
    private let service = "com.angellive.room-title-translation"
    private let account = "openai-compatible.api-key"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw RoomTranslationError.secureStorage
        }
        return data
    }

    func write(_ data: Data) throws {
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw RoomTranslationError.secureStorage
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw RoomTranslationError.secureStorage
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RoomTranslationError.secureStorage
        }
    }
}

@MainActor @Observable
public final class RoomTranslationSettings {
    public static let shared = RoomTranslationSettings()

    private enum Keys {
        static let enabled = "roomTranslation.enabled"
        static let danmakuEnabled = "roomTranslation.danmakuEnabled"
        static let engine = "roomTranslation.engine"
        static let targetLanguage = "roomTranslation.targetLanguage"
        static let cloudBaseURL = "roomTranslation.cloudBaseURL"
        static let cloudModel = "roomTranslation.cloudModel"
        static let revision = "roomTranslation.revision"
    }

    public var isEnabled: Bool {
        didSet { persistChange(oldValue: oldValue, newValue: isEnabled, key: Keys.enabled) }
    }

    public var isDanmakuEnabled: Bool {
        didSet {
            persistChange(
                oldValue: oldValue,
                newValue: isDanmakuEnabled,
                key: Keys.danmakuEnabled
            )
        }
    }

    public var engine: RoomTranslationEngine {
        didSet { persistChange(oldValue: oldValue.rawValue, newValue: engine.rawValue, key: Keys.engine) }
    }

    public var targetLanguage: String {
        didSet { persistChange(oldValue: oldValue, newValue: targetLanguage, key: Keys.targetLanguage) }
    }

    public private(set) var cloudBaseURL: String
    public private(set) var cloudModel: String
    public private(set) var hasAPIKey: Bool
    public private(set) var revision: Int

    private let defaults: UserDefaults
    private let secretStorage: any RoomTranslationSecretStorage

    private struct SecretRecord: Codable {
        let endpoint: String
        let apiKey: String
    }

    public convenience init() {
        self.init(defaults: .standard, secretStorage: RoomTranslationKeychain())
    }

    init(defaults: UserDefaults, secretStorage: any RoomTranslationSecretStorage) {
        self.defaults = defaults
        self.secretStorage = secretStorage
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        isDanmakuEnabled = defaults.object(forKey: Keys.danmakuEnabled) as? Bool ?? false
#if os(tvOS)
        let defaultEngine = RoomTranslationEngine.llm
#else
        let defaultEngine = RoomTranslationEngine.apple
#endif
        engine = defaults.string(forKey: Keys.engine).flatMap(RoomTranslationEngine.init(rawValue:)) ?? defaultEngine
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "zh-Hans"
        let savedBaseURL = defaults.string(forKey: Keys.cloudBaseURL) ?? ""
        cloudBaseURL = savedBaseURL
        cloudModel = defaults.string(forKey: Keys.cloudModel) ?? ""
        revision = defaults.integer(forKey: Keys.revision)
        hasAPIKey = Self.readSecret(from: secretStorage, matching: savedBaseURL) != nil
    }

    public func saveCloudConfiguration(baseURL: String, model: String, apiKey: String) throws {
        let normalizedURL = try Self.normalizedBaseURL(baseURL)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { throw RoomTranslationError.invalidModel }

        let candidateKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointChanged = normalizedURL != cloudBaseURL
        if endpointChanged && candidateKey.isEmpty {
            throw RoomTranslationError.apiKeyRequired
        }
        let committedSecret = Self.readSecret(from: secretStorage, matching: cloudBaseURL)
        if candidateKey.isEmpty, committedSecret == nil {
            throw RoomTranslationError.apiKeyRequired
        }

        // Persisting a replacement secret is the commit point for an endpoint
        // change. The old secret can therefore never be paired with the new URL.
        if !candidateKey.isEmpty {
            let record = SecretRecord(endpoint: normalizedURL, apiKey: candidateKey)
            do {
                try secretStorage.write(JSONEncoder().encode(record))
            } catch {
                throw RoomTranslationError.secureStorage
            }
        }

        cloudBaseURL = normalizedURL
        cloudModel = normalizedModel
        hasAPIKey = true
        defaults.set(cloudBaseURL, forKey: Keys.cloudBaseURL)
        defaults.set(cloudModel, forKey: Keys.cloudModel)
        advanceRevision()
    }

    public func deleteAPIKey() throws {
        try secretStorage.delete()
        hasAPIKey = false
        advanceRevision()
    }

    func cloudConfiguration() throws -> (baseURL: URL, model: String, apiKey: String) {
        guard let baseURL = URL(string: cloudBaseURL), !cloudModel.isEmpty else {
            throw RoomTranslationError.unavailable
        }
        guard let record = Self.readSecret(from: secretStorage, matching: cloudBaseURL) else {
            throw RoomTranslationError.apiKeyRequired
        }
        return (baseURL, cloudModel, record.apiKey)
    }

    private func persistChange<T: Equatable>(oldValue: T, newValue: T, key: String) {
        guard oldValue != newValue else { return }
        defaults.set(newValue, forKey: key)
        advanceRevision()
    }

    private func advanceRevision() {
        revision &+= 1
        defaults.set(revision, forKey: Keys.revision)
    }

    static func normalizedBaseURL(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw RoomTranslationError.invalidBaseURL
        }
        components.scheme = "https"
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let normalized = components.url?.absoluteString else {
            throw RoomTranslationError.invalidBaseURL
        }
        return normalized
    }

    private static func readSecret(
        from storage: any RoomTranslationSecretStorage,
        matching endpoint: String
    ) -> SecretRecord? {
        guard !endpoint.isEmpty,
              let data = try? storage.read(),
              let record = try? JSONDecoder().decode(SecretRecord.self, from: data),
              record.endpoint == endpoint,
              !record.apiKey.isEmpty else {
            return nil
        }
        return record
    }
}
