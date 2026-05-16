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
        auth: ManifestAuth?,
        version: String
    ) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.liveType = liveType
        self.loginFlow = loginFlow
        self.auth = auth
        self.version = version
    }
}

public actor PlatformLoginRegistry {
    public static let shared = PlatformLoginRegistry()

    private init() {}

    /// 读取当前所有已安装/内置插件中声明了 loginFlow 的平台。
    public func availablePlatforms() -> [LoginPlatformEntry] {
        let manifests = discoverAllManifests()
        var entries: [LoginPlatformEntry] = []
        for manifest in manifests {
            guard let loginFlow = PlatformLoginCompatibility.loginFlow(for: manifest) else { continue }
            let liveType = manifest.liveTypes.first ?? manifest.pluginId
            let displayName = manifest.displayName ?? manifest.pluginId
            let entry = LoginPlatformEntry(
                pluginId: manifest.pluginId,
                displayName: displayName,
                liveType: liveType,
                loginFlow: loginFlow,
                auth: PlatformLoginCompatibility.auth(for: manifest),
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
        let storage = LiveParsePlugins.shared.storage
        let bundle = LiveParsePlugins.shared.bundle

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

        return Array(bestByPluginId.values)
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
