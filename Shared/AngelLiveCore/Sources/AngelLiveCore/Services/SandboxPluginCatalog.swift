//
//  SandboxPluginCatalog.swift
//  AngelLiveCore
//
//  仅从沙盒插件目录读取已安装插件信息，禁止回退到 LiveParse 内置插件。
//

import Foundation

public struct SandboxPluginMetadata: Sendable, Hashable {
    public let pluginId: String
    public let version: String
    public let displayName: String?
    public let liveTypes: [String]
    public let requiresLogin: Bool
    public let hostBehavior: ManifestHostBehavior?

    public init(
        pluginId: String,
        version: String,
        displayName: String?,
        liveTypes: [String],
        requiresLogin: Bool = false,
        hostBehavior: ManifestHostBehavior? = nil
    ) {
        self.pluginId = pluginId
        self.version = version
        self.displayName = displayName
        self.liveTypes = liveTypes
        self.requiresLogin = requiresLogin
        self.hostBehavior = hostBehavior
    }
}

public enum SandboxPluginCatalog {
    /// 返回每个 pluginId 在沙盒中已安装的最高版本 manifest 信息。
    public static func installedPluginMap() -> [String: SandboxPluginMetadata] {
        let storage = LiveParsePlugins.shared.storage
        let pluginsRoot = storage.pluginsRootDirectory

        guard let pluginDirs = try? FileManager.default.contentsOfDirectory(
            at: pluginsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: SandboxPluginMetadata] = [:]

        for pluginDir in pluginDirs {
            let values = try? pluginDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let pluginId = pluginDir.lastPathComponent
            let versions = storage.listInstalledVersions(pluginId: pluginId)
            var best: SandboxPluginMetadata?

            for versionDir in versions {
                let manifestURL = versionDir.appendingPathComponent("manifest.json", isDirectory: false)
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(LiveParsePluginManifest.self, from: data),
                      manifest.pluginId == pluginId else {
                    continue
                }

                let entryURL = versionDir.appendingPathComponent(manifest.entry, isDirectory: false)
                guard FileManager.default.fileExists(atPath: entryURL.path) else {
                    continue
                }

                let metadata = SandboxPluginMetadata(
                    pluginId: manifest.pluginId,
                    version: manifest.version,
                    displayName: manifest.displayName,
                    liveTypes: manifest.liveTypes,
                    requiresLogin: manifest.requiresLogin,
                    hostBehavior: manifest.hostBehavior
                )

                if let current = best {
                    if semverCompare(metadata.version, current.version) > 0 {
                        best = metadata
                    }
                } else {
                    best = metadata
                }
            }

            if let best {
                result[pluginId] = best
            }
        }

        return result
    }

    public static func installedPluginIds() -> [String] {
        installedPluginMap().keys.sorted()
    }

    public static func isInstalled(pluginId: String) -> Bool {
        installedPluginMap()[pluginId] != nil
    }

    public static func availablePlatforms(installedPluginIds: [String]? = nil) -> [LiveParseJSPlatform] {
        let pluginMap = installedPluginMap()
        let idFilter = installedPluginIds.map(Set.init)

        return LiveParseJSPlatformManager.availablePlatforms.filter { platform in
            if let idFilter, !idFilter.contains(platform.pluginId) {
                return false
            }
            guard let metadata = pluginMap[platform.pluginId] else {
                return false
            }
            // liveTypes 缺失时按 pluginId == liveType 兼容
            if metadata.liveTypes.isEmpty {
                return true
            }
            return metadata.liveTypes.contains(platform.liveType.rawValue)
        }
    }

    public static func platform(for liveType: LiveType) -> LiveParseJSPlatform? {
        availablePlatforms().first { $0.liveType == liveType }
    }

}
