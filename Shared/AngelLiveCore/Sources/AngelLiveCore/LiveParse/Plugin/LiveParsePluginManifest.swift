import Foundation

public struct LiveParsePluginManifest: Codable, Equatable, Sendable {
    public let pluginId: String
    public let version: String
    public let apiVersion: Int
    public let displayName: String?
    /// 面向用户的平台简介，用于平台页等静态展示。
    public let platformDescription: String?
    /// 面向用户的简短更新日志，按条目展示。
    public let changelog: [String]?
    public let liveTypes: [String]
    public let entry: String
    public let minHostVersion: String?
    /// 插件入口脚本执行前需要预加载的脚本文件名列表（相对于插件根目录或 bundle 资源目录）
    public let preloadScripts: [String]?
    /// 凭证能力声明（可选）
    public let auth: ManifestAuth?
    /// 登录流程声明（可选）。未声明的插件不会出现在宿主的平台登录列表中。
    public let loginFlow: ManifestLoginFlow?
    /// 分享链接候选匹配规则（可选）。宿主只用它筛选候选平台，最终解析仍由插件完成。
    public let shareResolve: ManifestShareResolve?
    /// 原生流能力声明（可选）。插件声明后才允许调用 Host.stream / Host.nativeStream。
    public let nativeStream: ManifestNativeStream?
    /// 宿主运行时行为声明（可选）。用于把收藏、状态轮询等宿主策略从平台枚举分支迁到资源声明。
    public let hostBehavior: ManifestHostBehavior?
    /// 旧版本凭证/session 迁移声明（可选）。宿主只按声明迁移，不内置平台映射。
    public let sessionMigration: ManifestSessionMigration?

    public init(
        pluginId: String,
        version: String,
        apiVersion: Int,
        displayName: String? = nil,
        platformDescription: String? = nil,
        changelog: [String]? = nil,
        liveTypes: [String],
        entry: String,
        minHostVersion: String? = nil,
        preloadScripts: [String]? = nil,
        auth: ManifestAuth? = nil,
        loginFlow: ManifestLoginFlow? = nil,
        shareResolve: ManifestShareResolve? = nil,
        nativeStream: ManifestNativeStream? = nil,
        hostBehavior: ManifestHostBehavior? = nil,
        sessionMigration: ManifestSessionMigration? = nil
    ) {
        self.pluginId = pluginId
        self.version = version
        self.apiVersion = apiVersion
        self.displayName = displayName
        self.platformDescription = platformDescription
        self.changelog = changelog
        self.liveTypes = liveTypes
        self.entry = entry
        self.minHostVersion = minHostVersion
        self.preloadScripts = preloadScripts
        self.auth = auth
        self.loginFlow = loginFlow
        self.shareResolve = shareResolve
        self.nativeStream = nativeStream
        self.hostBehavior = hostBehavior
        self.sessionMigration = sessionMigration
    }
}

public struct ManifestNativeStream: Codable, Equatable, Hashable, Sendable {
    /// 未显式传 provider 时使用的原生能力 ID。
    public let defaultProviderId: String?
    /// 允许调用的原生能力 ID 列表。为空时仅允许 defaultProviderId。
    public let allowedProviderIds: [String]?

    public init(defaultProviderId: String? = nil, allowedProviderIds: [String]? = nil) {
        self.defaultProviderId = defaultProviderId
        self.allowedProviderIds = allowedProviderIds
    }
}

public struct ManifestHostBehavior: Codable, Equatable, Hashable, Sendable {
    /// 收藏记录的主匹配键。默认 roomId；当房间号会变动时可声明为 userId。
    public let favoriteIdentityKey: String?
    /// 收藏刷新成功后是否保留原收藏元信息，仅合并最新状态。
    public let preserveFavoriteRoomInfoOnRefresh: Bool?
    /// 收藏刷新失败时回填的直播状态 rawValue。默认 unknown。
    public let liveStateFailureFallback: String?
    /// 是否允许宿主定时轮询下播状态。默认跟随 liveState 能力。
    public let supportsLiveEndPolling: Bool?
    /// 允许进入播放页的直播状态 rawValue。默认仅 live。
    public let playableLiveStates: [String]?
    /// 外部打开直播间的 URL 模板，支持 {roomId}/{userId} 占位符。
    public let externalRoomURLTemplate: String?
    /// 展示用主题色，格式如 #RRGGBB 或 #AARRGGBB。
    public let themeColor: String?

    public init(
        favoriteIdentityKey: String? = nil,
        preserveFavoriteRoomInfoOnRefresh: Bool? = nil,
        liveStateFailureFallback: String? = nil,
        supportsLiveEndPolling: Bool? = nil,
        playableLiveStates: [String]? = nil,
        externalRoomURLTemplate: String? = nil,
        themeColor: String? = nil
    ) {
        self.favoriteIdentityKey = favoriteIdentityKey
        self.preserveFavoriteRoomInfoOnRefresh = preserveFavoriteRoomInfoOnRefresh
        self.liveStateFailureFallback = liveStateFailureFallback
        self.supportsLiveEndPolling = supportsLiveEndPolling
        self.playableLiveStates = playableLiveStates
        self.externalRoomURLTemplate = externalRoomURLTemplate
        self.themeColor = themeColor
    }
}

public struct ManifestSessionMigration: Codable, Equatable, Hashable, Sendable {
    /// 旧 session/keychain 使用过的 pluginId/rawValue，迁移到当前 pluginId。
    public let legacyPluginIds: [String]?
    /// 旧 UserDefaults Cookie 键名列表，按顺序取第一个非空值。
    public let userDefaultsCookieKeys: [String]?
    /// 旧 UserDefaults UID 键名列表，按顺序取第一个非空值。
    public let userDefaultsUIDKeys: [String]?
    /// 迁移完成后需要清理的旧 UserDefaults 键名。
    public let cleanupUserDefaultsKeys: [String]?
    /// 旧 CloudKit recordName 列表，迁移到通用 recordName。
    public let legacyCloudRecordNames: [String]?
    /// 用于粗略判断旧 Cookie 是否已认证的关键片段。
    public let authCookieMarkers: [String]?
    /// 旧同步开关键名列表。
    public let legacyICloudSyncEnabledKeys: [String]?
    /// 旧同步时间键名列表。
    public let legacyICloudSyncTimeKeys: [String]?
    /// 无登录态时仍需附带的默认 Cookie。
    public let defaultCookie: String?

    public init(
        legacyPluginIds: [String]? = nil,
        userDefaultsCookieKeys: [String]? = nil,
        userDefaultsUIDKeys: [String]? = nil,
        cleanupUserDefaultsKeys: [String]? = nil,
        legacyCloudRecordNames: [String]? = nil,
        authCookieMarkers: [String]? = nil,
        legacyICloudSyncEnabledKeys: [String]? = nil,
        legacyICloudSyncTimeKeys: [String]? = nil,
        defaultCookie: String? = nil
    ) {
        self.legacyPluginIds = legacyPluginIds
        self.userDefaultsCookieKeys = userDefaultsCookieKeys
        self.userDefaultsUIDKeys = userDefaultsUIDKeys
        self.cleanupUserDefaultsKeys = cleanupUserDefaultsKeys
        self.legacyCloudRecordNames = legacyCloudRecordNames
        self.authCookieMarkers = authCookieMarkers
        self.legacyICloudSyncEnabledKeys = legacyICloudSyncEnabledKeys
        self.legacyICloudSyncTimeKeys = legacyICloudSyncTimeKeys
        self.defaultCookie = defaultCookie
    }
}

public struct ManifestShareResolve: Codable, Equatable, Hashable, Sendable {
    /// 可识别的 URL host，如 ["live.example.com", "short.example"]。
    public let hosts: [String]?
    /// 非 URL 文本兜底关键词，如 App scheme、口令前缀等。
    public let keywords: [String]?

    public init(hosts: [String]? = nil, keywords: [String]? = nil) {
        self.hosts = hosts
        self.keywords = keywords
    }
}

public struct ManifestAuth: Codable, Equatable, Sendable {
    public let required: Bool?
    public let credentialKinds: [String]?
    public let supportsStatusCheck: Bool?
    public let supportsValidation: Bool?

    public init(
        required: Bool? = nil,
        credentialKinds: [String]? = nil,
        supportsStatusCheck: Bool? = nil,
        supportsValidation: Bool? = nil
    ) {
        self.required = required
        self.credentialKinds = credentialKinds
        self.supportsStatusCheck = supportsStatusCheck
        self.supportsValidation = supportsValidation
    }
}

public struct ManifestLoginFlow: Codable, Equatable, Sendable {
    /// 交互类型，默认 "webview"；tvOS 端仅使用通用字段做手动输入引导。
    public let kind: String?
    public let loginURL: String
    public let userAgent: String?
    public let cookieDomains: [String]
    /// 任一出现即视为登录成功。
    public let authSignalCookies: [String]
    /// 可选的 uid 源 Cookie 名称（按顺序尝试）。
    public let uidCookieNames: [String]?
    /// 成功后跳转 URL 包含该关键词。
    public let successURLKeyword: String?
    /// 成功后页面标题包含该关键词（辅助判定）。
    public let successTitleKeyword: String?
    /// 检测到成功后延迟多少秒抓取 Cookie（默认 0）。
    public let postRedirectDelay: Double?
    /// tvOS 手动输入时展示给用户的提示。
    public let requiredCookieHint: String?
    /// tvOS 手动输入帮助文本中出现的网站域名。
    public let websiteHost: String?

    public init(
        kind: String? = nil,
        loginURL: String,
        userAgent: String? = nil,
        cookieDomains: [String],
        authSignalCookies: [String],
        uidCookieNames: [String]? = nil,
        successURLKeyword: String? = nil,
        successTitleKeyword: String? = nil,
        postRedirectDelay: Double? = nil,
        requiredCookieHint: String? = nil,
        websiteHost: String? = nil
    ) {
        self.kind = kind
        self.loginURL = loginURL
        self.userAgent = userAgent
        self.cookieDomains = cookieDomains
        self.authSignalCookies = authSignalCookies
        self.uidCookieNames = uidCookieNames
        self.successURLKeyword = successURLKeyword
        self.successTitleKeyword = successTitleKeyword
        self.postRedirectDelay = postRedirectDelay
        self.requiredCookieHint = requiredCookieHint
        self.websiteHost = websiteHost
    }
}

extension LiveParsePluginManifest {
    static func load(from url: URL) throws -> LiveParsePluginManifest {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(LiveParsePluginManifest.self, from: data)
        } catch {
            throw LiveParsePluginError.invalidManifest(error.localizedDescription)
        }
    }

    /// 该插件是否需要用户登录平台账号(用于安装前的凭证泄露风险确认)。
    public var requiresLogin: Bool {
        PlatformLoginCompatibility.requiresLogin(self)
    }
}
