//
//  PlaylistInstance.swift
//  AngelLiveCore
//
//  用户添加的 m3u 播放列表。一个实例在宿主中呈现为一个独立平台。
//

import Foundation
import os.lock
import Security

public struct PlaylistInstance: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var iconURL: String?
    /// 订阅地址常带访问令牌，按凭据级保存，不写入日志与诊断。
    public var sourceURL: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        iconURL: String?,
        sourceURL: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var liveType: LiveType {
        PlaylistPlatformIdentity.liveType(for: id)
    }

    /// 实例平台以 liveType 原值作为平台标识，供既有按 pluginId 索引的路径使用。
    public var platform: LiveParseJSPlatform {
        LiveParseJSPlatform(
            pluginId: liveType.rawValue,
            liveTypes: [liveType],
            platformName: name,
            platformDescription: "m3u 播放列表"
        )
    }
}

/// `playlist:` 是宿主保留的平台命名空间，插件 manifest 不得声明。
public enum PlaylistPlatformIdentity {
    public static let prefix = "playlist:"

    public static func liveType(for id: UUID) -> LiveType {
        LiveType(rawValue: prefix + id.uuidString.lowercased()) ?? .placeholder
    }

    public static func isPlaylist(_ rawValue: String) -> Bool {
        rawValue.hasPrefix(prefix)
    }

    public static func isPlaylist(_ liveType: LiveType) -> Bool {
        isPlaylist(liveType.rawValue)
    }

    public static func instanceID(from rawValue: String) -> UUID? {
        guard isPlaylist(rawValue) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

public extension Notification.Name {
    /// 播放列表实例增删改后发出；平台目录与界面据此刷新。
    static let playlistInstancesDidChange = Notification.Name("AngelLive.PlaylistInstancesDidChange")
}

public enum PlaylistInstanceError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName
    case invalidSourceURL
    case invalidIconURL
    case notFound
    case storage

    public var errorDescription: String? {
        switch self {
        case .emptyName: "请填写平台名称。"
        case .duplicateName: "名称已存在。"
        case .invalidSourceURL: "播放列表地址无效。"
        case .invalidIconURL: "图标地址无效。"
        case .notFound: "播放列表不存在。"
        case .storage: "无法保存播放列表。"
        }
    }
}

// MARK: - 持久化

protocol PlaylistInstancePersistence: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct PlaylistInstanceKeychain: PlaylistInstancePersistence {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.angellive.playlists",
         kSecAttrAccount as String: "instances",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PlaylistInstanceError.storage }
        return data
    }

    func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PlaylistInstanceError.storage }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PlaylistInstanceError.storage }
    }
}

final class PlaylistInstanceMemoryPersistence: PlaylistInstancePersistence {
    private let storage = OSAllocatedUnfairLock<Data?>(initialState: nil)
    func load() throws -> Data? { storage.withLock { $0 } }
    func save(_ data: Data) throws { storage.withLock { $0 = data } }
}

// MARK: - Store

/// 本地持久化格式：实例 + 删除墓碑（墓碑用于把删除同步到其他设备，防止被旧副本复活）。
struct PlaylistInstanceSnapshot: Codable, Sendable, Equatable {
    var instances: [PlaylistInstance]
    var tombstones: [UUID: Date]

    static let empty = PlaylistInstanceSnapshot(instances: [], tombstones: [:])

    /// 兼容早期仅保存实例数组的格式。
    static func decode(_ data: Data) throws -> PlaylistInstanceSnapshot {
        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(PlaylistInstanceSnapshot.self, from: data) {
            return snapshot
        }
        return PlaylistInstanceSnapshot(instances: try decoder.decode([PlaylistInstance].self, from: data), tombstones: [:])
    }
}

extension Notification.Name {
    /// userInfo 键：变更来源；值为 `PlaylistInstanceStore.syncChangeSource` 时表示由 iCloud 同步写入。
    static let playlistChangeSourceKey = "source"
}

/// 播放列表实例的唯一所有者。
///
/// 平台注册表在同步、非隔离的路径上读取实例（`LiveParseJSPlatformManager.availablePlatforms`），
/// 因此用 `OSAllocatedUnfairLock` 保护内存快照。不变量：所有读写都在锁内完成且锁内不挂起、
/// 不调用外部代码；持久化写入在锁内同步完成，失败时内存快照不变。
public final class PlaylistInstanceStore: Sendable {
    public static let shared = PlaylistInstanceStore(persistence: PlaylistInstanceKeychain())

    private let persistence: any PlaylistInstancePersistence
    private let state = OSAllocatedUnfairLock<PlaylistInstanceSnapshot?>(initialState: nil)
    static let syncChangeSource = "icloud"

    init(persistence: any PlaylistInstancePersistence) {
        self.persistence = persistence
    }

    public func all() -> [PlaylistInstance] {
        snapshot()?.instances ?? []
    }

    /// nil 表示本地数据暂时读取失败；同步不得在此状态下写入。
    func snapshot() -> PlaylistInstanceSnapshot? {
        state.withLock { cached in
            if let cached { return cached }
            // 读取失败不缓存空列表，避免后续写入覆盖掉尚未读出的已有实例。
            guard let loaded = try? loadFromPersistence() else { return nil }
            cached = loaded
            return loaded
        }
    }

    public func instance(id: UUID) -> PlaylistInstance? {
        all().first { $0.id == id }
    }

    public func instance(for liveType: LiveType) -> PlaylistInstance? {
        PlaylistPlatformIdentity.instanceID(from: liveType.rawValue).flatMap(instance(id:))
    }

    @discardableResult
    public func add(
        name: String,
        iconURL: String?,
        sourceURL: String,
        reservedNames: Set<String> = []
    ) throws -> PlaylistInstance {
        let instance = PlaylistInstance(
            name: try Self.validatedName(name),
            iconURL: try Self.validatedIconURL(iconURL),
            sourceURL: try Self.validatedSourceURL(sourceURL)
        )
        try mutate { instances in
            try Self.ensureUnique(instance.name, excluding: nil, in: instances.instances, reservedNames: reservedNames)
            instances.instances.append(instance)
        }
        return instance
    }

    @discardableResult
    public func update(
        id: UUID,
        name: String,
        iconURL: String?,
        sourceURL: String,
        reservedNames: Set<String> = []
    ) throws -> PlaylistInstance {
        let validatedName = try Self.validatedName(name)
        let validatedIcon = try Self.validatedIconURL(iconURL)
        let validatedSource = try Self.validatedSourceURL(sourceURL)
        var updated: PlaylistInstance?
        try mutate { instances in
            guard let index = instances.instances.firstIndex(where: { $0.id == id }) else {
                throw PlaylistInstanceError.notFound
            }
            try Self.ensureUnique(validatedName, excluding: id, in: instances.instances, reservedNames: reservedNames)
            instances.instances[index].name = validatedName
            instances.instances[index].iconURL = validatedIcon
            instances.instances[index].sourceURL = validatedSource
            instances.instances[index].updatedAt = .now
            updated = instances.instances[index]
        }
        guard let updated else { throw PlaylistInstanceError.notFound }
        return updated
    }

    public func remove(id: UUID) throws {
        try mutate { instances in
            guard instances.instances.contains(where: { $0.id == id }) else { return }
            instances.instances.removeAll { $0.id == id }
            instances.tombstones[id] = .now
        }
    }

    /// 写入同步合并结果。不做名称校验（以各端已保存的数据为准），以同步来源发出变更通知。
    func applySynced(_ snapshot: PlaylistInstanceSnapshot, expected: PlaylistInstanceSnapshot) throws -> Bool {
        var applied = false
        try mutate(source: Self.syncChangeSource) { current in
            // 合并期间本地又有改动时放弃本次写入，由下一轮同步重新合并。
            guard current == expected else { return }
            current = snapshot
            applied = true
        }
        return applied
    }

    // MARK: - Validation

    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaylistInstanceError.emptyName }
        return trimmed
    }

    static func validatedSourceURL(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw PlaylistInstanceError.invalidSourceURL
        }
        return trimmed
    }

    static func validatedIconURL(_ value: String?) throws -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw PlaylistInstanceError.invalidIconURL
        }
        return trimmed
    }

    private static func ensureUnique(
        _ name: String,
        excluding id: UUID?,
        in instances: [PlaylistInstance],
        reservedNames: Set<String>
    ) throws {
        let folded = name.lowercased()
        let clashesWithInstance = instances.contains { $0.id != id && $0.name.lowercased() == folded }
        let clashesWithReserved = reservedNames.contains { $0.lowercased() == folded }
        if clashesWithInstance || clashesWithReserved {
            throw PlaylistInstanceError.duplicateName
        }
    }

    // MARK: - Persistence

    private func mutate(source: String? = nil, _ change: (inout PlaylistInstanceSnapshot) throws -> Void) throws {
        // change 只在锁内同步执行、不逃逸，无需 Sendable。
        try state.withLockUnchecked { cached in
            var instances = try cached ?? loadFromPersistence()
            try change(&instances)
            let data: Data
            do {
                data = try JSONEncoder().encode(instances)
                try persistence.save(data)
            } catch {
                throw PlaylistInstanceError.storage
            }
            cached = instances
        }
        NotificationCenter.default.post(
            name: .playlistInstancesDidChange,
            object: nil,
            userInfo: source.map { [Notification.Name.playlistChangeSourceKey: $0] }
        )
    }

    private func loadFromPersistence() throws -> PlaylistInstanceSnapshot {
        do {
            guard let data = try persistence.load() else { return .empty }
            return try PlaylistInstanceSnapshot.decode(data)
        } catch {
            Logger.warning("Playlist instances could not be loaded: \(type(of: error))", category: .general)
            throw PlaylistInstanceError.storage
        }
    }
}
