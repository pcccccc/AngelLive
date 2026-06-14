import Foundation

/// 全局插件系统入口。
///
/// 说明：`LiveParsePluginManager` 自带插件缓存（JSContext 等），但如果每次调用都重新创建 manager，会导致缓存失效。
/// 因此提供一个共享实例给各平台调用。
public enum LiveParsePlugins {
    public static let shared: LiveParsePluginManager = {
        // 使用独立的 URLSession，禁用自动 cookie 管理，
        // 避免 HTTPCookieStorage 干扰插件手动设置的 Cookie header。
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)

        let logHandler: LiveParsePluginManager.LogHandler = { msg in
            Logger.debug("[LiveParse:JS] \(msg)", category: .plugin)
        }

        do {
            return try LiveParsePluginManager(session: session, logHandler: logHandler)
        } catch {
            Logger.warning("[LiveParse] Failed to init plugin manager with default storage: \(error). Falling back to caches directory.", category: .plugin)
            // 回退到 Caches 目录（tvOS 等平台对 Application Support 目录权限可能受限）
            let fallbackDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("LiveParse", isDirectory: true)
            let storage = try! LiveParsePluginStorage(baseDirectory: fallbackDir)
            return LiveParsePluginManager(storage: storage, session: session, logHandler: logHandler)
        }
    }()

    public static func updatePlatformSession(platformId: String, cookie: String, uid: String? = nil) {
        LiveParsePlatformSessionVault.update(platformId: platformId, cookie: cookie, uid: uid)
    }

    public static func clearPlatformSession(platformId: String) {
        LiveParsePlatformSessionVault.clear(platformId: platformId)
    }
}
