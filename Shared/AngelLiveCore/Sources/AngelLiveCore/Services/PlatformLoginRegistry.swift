//
//  PlatformLoginRegistry.swift
//  AngelLiveCore
//
//  数据驱动的平台登录注册表。
//  从已安装/内置插件的 manifest.loginFlow 字段构建可登录平台列表，
//  宿主端 UI 基于此枚举显示登录选项，而不再依赖硬编码平台 enum。
//

import Foundation

/// 登录注册表条目。
public struct LoginPlatformEntry: Sendable, Equatable, Identifiable {
    public let pluginId: String
    /// manifest.displayName；缺失时回退 pluginId。
    public let displayName: String
    /// 关联的 liveType rawValue（取 manifest.liveTypes 首项），用于 UI 查图标。
    public let liveType: String
    /// manifest.loginFlow
    public let loginFlow: ManifestLoginFlow
    /// manifest.loginChallenge；仅透传显式声明，不从其他字段推断。
    public let loginChallenge: ManifestLoginChallenge?
    /// manifest.auth（可空）
    public let auth: ManifestAuth?
    /// manifest 版本。
    public let version: String

    public var id: String { pluginId }

    public init(
        pluginId: String,
        displayName: String,
        liveType: String,
        loginFlow: ManifestLoginFlow,
        loginChallenge: ManifestLoginChallenge? = nil,
        auth: ManifestAuth?,
        version: String
    ) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.liveType = liveType
        self.loginFlow = loginFlow
        self.loginChallenge = loginChallenge
        self.auth = auth
        self.version = version
    }
}

public actor PlatformLoginRegistry {
    public static let shared = PlatformLoginRegistry(pluginManager: LiveParsePlugins.shared)

    private let pluginManager: LiveParsePluginManager

    init(pluginManager: LiveParsePluginManager) {
        self.pluginManager = pluginManager
    }

    /// 读取当前所有已安装/内置插件中声明了 loginFlow 的平台。
    public func availablePlatforms() -> [LoginPlatformEntry] {
        let manifests = discoverAllManifests()
        var entries: [LoginPlatformEntry] = []
        for manifest in manifests {
            guard let loginFlow = manifest.loginFlow else { continue }
            let liveType = manifest.liveTypes.first ?? manifest.pluginId
            let displayName = manifest.displayName ?? manifest.pluginId
            let entry = LoginPlatformEntry(
                pluginId: manifest.pluginId,
                displayName: displayName,
                liveType: liveType,
                loginFlow: loginFlow,
                loginChallenge: manifest.loginChallenge,
                auth: manifest.auth,
                version: manifest.version
            )
            entries.append(entry)
        }
        return entries.sorted { $0.displayName < $1.displayName }
    }

    /// 查找特定 pluginId 的登录入口声明。
    public func entry(pluginId: String) -> LoginPlatformEntry? {
        availablePlatforms().first { $0.pluginId == pluginId }
    }

    // MARK: - 内部 manifest 发现

    private func discoverAllManifests() -> [LiveParsePluginManifest] {
        // 每个 pluginId 取 sandbox/builtIn 中可用的最高 semver manifest。
        let storage = pluginManager.storage
        let bundle = pluginManager.bundle

        var bestByPluginId: [String: LiveParsePluginManifest] = [:]

        func consider(_ manifest: LiveParsePluginManifest) {
            if let existing = bestByPluginId[manifest.pluginId] {
                if semverCompare(manifest.version, existing.version) > 0 {
                    bestByPluginId[manifest.pluginId] = manifest
                }
            } else {
                bestByPluginId[manifest.pluginId] = manifest
            }
        }

        // Sandbox
        let pluginsRoot = storage.pluginsRootDirectory
        if let pluginDirs = try? FileManager.default.contentsOfDirectory(
            at: pluginsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for pluginDir in pluginDirs {
                let isDir = (try? pluginDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                let pluginId = pluginDir.lastPathComponent
                for versionDir in storage.listInstalledVersions(pluginId: pluginId) {
                    let manifestURL = versionDir.appendingPathComponent("manifest.json", isDirectory: false)
                    if let manifest = try? LiveParsePluginManifest.load(from: manifestURL),
                       manifest.pluginId == pluginId {
                        consider(manifest)
                    }
                }
            }
        }

        // BuiltIn（只做补充，与 LiveParsePluginManager.discoverBuiltInCandidates 保持一致：
        // 支持 Plugins/<id>/manifest.json 及扁平化 lp_plugin_<id>_<ver>_manifest.json 两种布局）
        if let resourceURL = bundle.resourceURL {
            let pluginsRoot = resourceURL.appendingPathComponent("Plugins", isDirectory: true)
            if FileManager.default.fileExists(atPath: pluginsRoot.path) {
                discoverBuiltInFolderMode(root: pluginsRoot, consume: consider)
            } else {
                discoverBuiltInFlatMode(root: resourceURL, consume: consider)
            }
        }

        // 这里只用扫描结果取得 pluginId；最终 manifest 必须通过同一个 manager
        // resolve，才能与实际调用遵循完全一致的 enabled / pinned / last-good /
        // sandbox-vs-built-in 选择语义。否则 UI 可能展示新版能力，却调用到旧版脚本。
        return bestByPluginId.keys.compactMap { pluginId in
            try? pluginManager.resolve(pluginId: pluginId).manifest
        }
    }

    private nonisolated func discoverBuiltInFolderMode(
        root: URL,
        consume: (LiveParsePluginManifest) -> Void
    ) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "manifest.json" else { continue }
            if let manifest = try? LiveParsePluginManifest.load(from: url) {
                consume(manifest)
            }
        }
    }

    private nonisolated func discoverBuiltInFlatMode(
        root: URL,
        consume: (LiveParsePluginManifest) -> Void
    ) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "json",
                  url.lastPathComponent.hasSuffix("_manifest.json") else { continue }
            if let manifest = try? LiveParsePluginManifest.load(from: url) {
                consume(manifest)
            }
        }
    }
}
