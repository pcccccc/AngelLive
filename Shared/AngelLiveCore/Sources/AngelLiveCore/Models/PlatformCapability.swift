//
//  PlatformCapability.swift
//  AngelLiveCore
//
//  Created by Claude on 2026/2/25.
//

import Foundation

// MARK: - 平台功能枚举

public enum PlatformFeature: String, CaseIterable, Sendable {
    case categories    // 分类列表
    case rooms         // 房间列表
    case playback      // 获取播放地址
    case search        // 搜索
    case roomDetail    // 主播详情
    case liveState     // 直播状态
    case shareResolve  // 分享码解析
    case danmaku       // 弹幕
    case homeFeed      // 首页内容

    public var displayName: String {
        switch self {
        case .categories:   return "分类列表"
        case .rooms:        return "房间列表"
        case .playback:     return "获取播放地址"
        case .search:       return "搜索"
        case .roomDetail:   return "主播详情"
        case .liveState:    return "直播状态"
        case .shareResolve: return "分享码解析"
        case .danmaku:      return "弹幕"
        case .homeFeed:     return "首页内容"
        }
    }

    public var iconName: String {
        switch self {
        case .categories:   return "square.grid.2x2"
        case .rooms:        return "list.bullet"
        case .playback:     return "play.circle"
        case .search:       return "magnifyingglass"
        case .roomDetail:   return "person.text.rectangle"
        case .liveState:    return "dot.radiowaves.left.and.right"
        case .shareResolve: return "link"
        case .danmaku:      return "text.bubble"
        case .homeFeed:     return "house"
        }
    }
}

// MARK: - 功能可用性状态

public enum FeatureStatus: Sendable {
    case available
    case partial(String)
    case unavailable

    public var isSupported: Bool {
        switch self {
        case .available, .partial:
            true
        case .unavailable:
            false
        }
    }
}

// MARK: - 功能登录要求

/// manifest `capabilities.<feature>.auth` 声明的登录要求（登录协议 v1）。
public enum FeatureAuthLevel: String, Sendable, Equatable {
    /// 不登录不能用
    case required
    /// 不登录能用，登录后更好（画质、稳定性、特定房间）
    case enhances
    /// 与登录无关 / 未声明
    case none

    /// 能力面板徽标文案；`none` 不显示徽标。
    public var badgeTitle: String? {
        switch self {
        case .required: "需登录"
        case .enhances: "登录增强"
        case .none: nil
        }
    }
}

public struct FeatureAuthRequirement: Sendable, Equatable {
    public let level: FeatureAuthLevel
    /// 写给用户看的登录前后差别说明。
    public let reason: String?

    public init(level: FeatureAuthLevel, reason: String?) {
        self.level = level
        self.reason = reason
    }

    public static let none = FeatureAuthRequirement(level: .none, reason: nil)
}

// MARK: - 平台功能可用性配置

public enum PlatformCapability {
    private struct PluginEntryCandidate {
        let version: String
        let entryURL: URL
    }

    private struct PluginCapabilityCandidate {
        let version: String
        let capabilities: [PlatformFeature: FeatureStatus]
        let authRequirements: [PlatformFeature: FeatureAuthRequirement]
    }

    // MARK: - Cache

    private final class Cache: @unchecked Sendable {
        private var storage: [String: [(PlatformFeature, FeatureStatus)]] = [:]
        private let lock = NSLock()

        func get(_ key: String) -> [(PlatformFeature, FeatureStatus)]? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        func set(_ key: String, value: [(PlatformFeature, FeatureStatus)]) {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = value
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
        }
    }

    private static let cache = Cache()

    private final class AuthCache: @unchecked Sendable {
        private var storage: [String: [PlatformFeature: FeatureAuthRequirement]] = [:]
        private let lock = NSLock()

        func get(_ key: String) -> [PlatformFeature: FeatureAuthRequirement]? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        func set(_ key: String, value: [PlatformFeature: FeatureAuthRequirement]) {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = value
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
        }
    }

    private static let authCache = AuthCache()

    private static let featureFunctionNames: [(PlatformFeature, [String])] = [
        (.categories, ["getCategories", "getCategoryList"]),
        (.rooms, ["getRooms", "getRoomList"]),
        (.playback, ["getPlayback", "getPlayArgs"]),
        (.search, ["search", "searchRooms"]),
        (.roomDetail, ["getRoomDetail", "getLiveLastestInfo"]),
        (.liveState, ["getLiveState"]),
        (.shareResolve, ["resolveShare", "getRoomInfoFromShareCode"]),
        (.danmaku, ["getDanmaku", "getDanmukuArgs"]),
        (.homeFeed, ["getHomeFeed"])
    ]

    public static func features(for liveType: LiveType) -> [(PlatformFeature, FeatureStatus)] {
        let cacheKey = liveType.rawValue
        if let cached = cache.get(cacheKey) {
            return cached
        }

        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            let result = featureFunctionNames.map { ($0.0, FeatureStatus.unavailable) }
            cache.set(cacheKey, value: result)
            return result
        }

        let result: [(PlatformFeature, FeatureStatus)]

        if let capabilities = loadPluginCapabilities(pluginId: platform.pluginId) {
            result = PlatformFeature.allCases.map { feature in
                (feature, capabilities[feature] ?? .unavailable)
            }
        } else if let entryScript = loadPluginEntryScript(pluginId: platform.pluginId) {
            result = featureFunctionNames.map { feature, functionNames in
                let isAvailable = functionNames.contains { containsFunction(named: $0, in: entryScript) }
                return (feature, isAvailable ? .available : .unavailable)
            }
        } else {
            result = featureFunctionNames.map { ($0.0, FeatureStatus.unavailable) }
        }

        cache.set(cacheKey, value: result)
        return result
    }

    public static func status(for feature: PlatformFeature, liveType: LiveType) -> FeatureStatus {
        features(for: liveType)
            .first(where: { $0.0 == feature })?
            .1 ?? .unavailable
    }

    public static func supports(_ feature: PlatformFeature, for liveType: LiveType) -> Bool {
        status(for: feature, liveType: liveType).isSupported
    }

    /// 功能的登录要求（manifest `capabilities.<feature>.auth`），未声明时为 `.none`。
    public static func auth(
        for feature: PlatformFeature,
        liveType: LiveType
    ) -> (level: FeatureAuthLevel, reason: String?) {
        let requirement = authRequirements(for: liveType)[feature] ?? .none
        return (requirement.level, requirement.reason)
    }

    private static func authRequirements(for liveType: LiveType) -> [PlatformFeature: FeatureAuthRequirement] {
        let cacheKey = liveType.rawValue
        if let cached = authCache.get(cacheKey) {
            return cached
        }

        let result: [PlatformFeature: FeatureAuthRequirement]
        if let platform = SandboxPluginCatalog.platform(for: liveType),
           let candidate = loadSandboxPluginCapabilityCandidate(pluginId: platform.pluginId) {
            result = candidate.authRequirements
        } else {
            result = [:]
        }

        authCache.set(cacheKey, value: result)
        return result
    }

    /// 清除缓存，在插件 reload 后调用
    public static func invalidateCache() {
        cache.clear()
        authCache.clear()
    }

    private static func loadPluginCapabilities(pluginId: String) -> [PlatformFeature: FeatureStatus]? {
        loadSandboxPluginCapabilities(pluginId: pluginId)
    }

    private static func loadPluginEntryScript(pluginId: String) -> String? {
        loadSandboxPluginEntryScript(pluginId: pluginId)
    }

    private static func loadSandboxPluginEntryScript(pluginId: String) -> String? {
        let versionDirectories = LiveParsePlugins.shared.storage.listInstalledVersions(pluginId: pluginId)
        var candidates: [PluginEntryCandidate] = []

        for versionDirectory in versionDirectories {
            let manifestURL = versionDirectory.appendingPathComponent("manifest.json", isDirectory: false)
            guard let manifest = loadManifest(from: manifestURL), manifest.pluginId == pluginId else {
                continue
            }

            let entryURL = versionDirectory.appendingPathComponent(manifest.entry, isDirectory: false)
            guard FileManager.default.fileExists(atPath: entryURL.path) else { continue }
            candidates.append(PluginEntryCandidate(version: manifest.version, entryURL: entryURL))
        }

        guard let candidate = candidates.max(by: { semverCompare($0.version, $1.version) < 0 }) else {
            return nil
        }
        return try? String(contentsOf: candidate.entryURL, encoding: .utf8)
    }

    private static func loadSandboxPluginCapabilities(pluginId: String) -> [PlatformFeature: FeatureStatus]? {
        loadSandboxPluginCapabilityCandidate(pluginId: pluginId)?.capabilities
    }

    private static func loadSandboxPluginCapabilityCandidate(pluginId: String) -> PluginCapabilityCandidate? {
        let versionDirectories = LiveParsePlugins.shared.storage.listInstalledVersions(pluginId: pluginId)
        var candidates: [PluginCapabilityCandidate] = []

        for versionDirectory in versionDirectories {
            let manifestURL = versionDirectory.appendingPathComponent("manifest.json", isDirectory: false)
            guard let manifest = loadManifest(from: manifestURL),
                  manifest.pluginId == pluginId,
                  let data = try? Data(contentsOf: manifestURL),
                  let capabilities = parseCapabilities(from: data) else {
                continue
            }
            candidates.append(PluginCapabilityCandidate(
                version: manifest.version,
                capabilities: capabilities,
                authRequirements: parseAuthRequirements(from: data)
            ))
        }

        return candidates.max(by: { semverCompare($0.version, $1.version) < 0 })
    }

    private static func loadManifest(from url: URL) -> LiveParsePluginManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LiveParsePluginManifest.self, from: data)
    }

    static func parseCapabilities(from data: Data) -> [PlatformFeature: FeatureStatus]? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let json = jsonObject as? [String: Any],
              let rawCapabilities = json["capabilities"] as? [String: Any] else {
            return nil
        }

        var result: [PlatformFeature: FeatureStatus] = [:]
        for feature in PlatformFeature.allCases {
            guard let rawValue = rawCapabilities[feature.rawValue],
                  let status = parseFeatureStatus(rawValue) else {
                continue
            }
            result[feature] = status
        }

        return result.isEmpty ? nil : result
    }

    /// 解析 `capabilities.<feature>.auth`（required / enhances / none，大小写不敏感）及其 `reason`。
    /// 未声明或取值无法识别的功能不出现在结果中，调用方按 `.none` 处理。
    static func parseAuthRequirements(from data: Data) -> [PlatformFeature: FeatureAuthRequirement] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let json = jsonObject as? [String: Any],
              let rawCapabilities = json["capabilities"] as? [String: Any] else {
            return [:]
        }

        var result: [PlatformFeature: FeatureAuthRequirement] = [:]
        for feature in PlatformFeature.allCases {
            guard let dictionary = rawCapabilities[feature.rawValue] as? [String: Any],
                  let rawAuth = dictionary["auth"] as? String else {
                continue
            }
            let level: FeatureAuthLevel
            switch rawAuth.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "required": level = .required
            case "enhances": level = .enhances
            default: continue
            }
            let reason = (dictionary["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            result[feature] = FeatureAuthRequirement(
                level: level,
                reason: reason?.isEmpty == false ? reason : nil
            )
        }
        return result
    }

    private static func parseFeatureStatus(_ raw: Any) -> FeatureStatus? {
        if let status = raw as? String {
            return mapFeatureStatus(status: status, reason: nil)
        }
        if let dictionary = raw as? [String: Any] {
            guard let status = dictionary["status"] as? String else { return nil }
            let reason = dictionary["reason"] as? String
            return mapFeatureStatus(status: status, reason: reason)
        }
        return nil
    }

    private static func mapFeatureStatus(status: String, reason: String?) -> FeatureStatus? {
        switch status.lowercased() {
        case "available":
            return .available
        case "partial":
            let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .partial((normalizedReason?.isEmpty == false ? normalizedReason : "部分可用") ?? "部分可用")
        case "unavailable":
            return .unavailable
        default:
            return nil
        }
    }

    static func containsFunction(named name: String, in script: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "\\b\(escaped)\\s*\\(",
            "\\b\(escaped)\\s*:",
            "[\"']\(escaped)[\"']\\s*:"
        ]

        let searchRange = NSRange(script.startIndex..<script.endIndex, in: script)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            if regex.firstMatch(in: script, options: [], range: searchRange) != nil {
                return true
            }
        }
        return false
    }

}
