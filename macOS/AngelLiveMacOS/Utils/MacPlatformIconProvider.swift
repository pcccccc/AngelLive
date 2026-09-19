//
//  MacPlatformIconProvider.swift
//  AngelLiveMacOS
//
//  macOS 平台图标读取：优先沙盒插件 assets，失败时返回 nil。
//

import AppKit
import AngelLiveCore

enum MacPlatformIconProvider {
    private static let tabIconPrefix = "assets/mini_live_card_"
    private static let managementIconPrefixes = [
        "assets/pad_live_card_",
        "assets/live_card_",
        tabIconPrefix
    ]

    static func tabImage(for liveType: LiveType) -> NSImage? {
        // 直接按沙盒已安装插件目录匹配 liveType -> pluginId，避免依赖内置资源映射。
        if let pluginId = resolveInstalledPluginId(for: liveType),
           let image = loadInstalledIcon(
               pluginId: pluginId,
               fileNames: [tabIconPrefix + pluginId],
               logicalSize: NSSize(width: 16, height: 16)
           ) {
            return image
        }

        // 兜底：保持与现有平台映射行为一致。
        if let platform = SandboxPluginCatalog.platform(for: liveType) {
            return loadInstalledIcon(
                pluginId: platform.pluginId,
                fileNames: [tabIconPrefix + platform.pluginId],
                logicalSize: NSSize(width: 16, height: 16)
            )
        }

        return nil
    }

    /// 管理页使用原始插件图像数据，不复用 tabImage 的 16pt 逻辑尺寸。
    /// 这样由 SwiftUI 按管理列表的实际尺寸缩放，避免把 sidebar 用的尺寸
    /// 带进 36pt 的插件行。低分辨率资源仍按原始数据显示，不人为锐化或放大。
    static func pluginManagementImage(for liveType: LiveType) -> NSImage? {
        if let pluginId = resolveInstalledPluginId(for: liveType),
           let image = loadInstalledIcon(
               pluginId: pluginId,
               fileNames: managementIconPrefixes.map { $0 + pluginId }
           ) {
            return image
        }

        if let platform = SandboxPluginCatalog.platform(for: liveType) {
            return loadInstalledIcon(
                pluginId: platform.pluginId,
                fileNames: managementIconPrefixes.map { $0 + platform.pluginId }
            )
        }

        return nil
    }

    private static func resolveInstalledPluginId(for liveType: LiveType) -> String? {
        let rawValue = liveType.rawValue

        for (pluginId, metadata) in SandboxPluginCatalog.installedPluginMap() {
            if metadata.liveTypes.contains(rawValue) || metadata.liveTypes.isEmpty && pluginId == rawValue {
                return pluginId
            }
        }

        return nil
    }

    private static func loadInstalledIcon(
        pluginId: String,
        fileNames: [String],
        logicalSize: NSSize? = nil
    ) -> NSImage? {
        let storage = LiveParsePlugins.shared.storage
        let versionDirs = storage.listInstalledVersions(pluginId: pluginId)
            .sorted { semverCompare($0.lastPathComponent, $1.lastPathComponent) > 0 }

        for versionDir in versionDirs {
            for fileName in fileNames {
                let iconURL = versionDir
                    .appendingPathComponent(fileName)
                    .appendingPathExtension("png")
                if FileManager.default.fileExists(atPath: iconURL.path),
                   let image = NSImage(contentsOf: iconURL) {
                    if let logicalSize {
                        image.size = logicalSize
                    }
                    return image
                }
            }
        }

        return nil
    }

}
