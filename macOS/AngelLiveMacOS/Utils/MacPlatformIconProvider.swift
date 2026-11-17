//
//  MacPlatformIconProvider.swift
//  AngelLiveMacOS
//
//  macOS 平台图标读取：优先沙盒插件 assets，失败时返回 nil。
//

import AppKit
import ImageIO
import AngelLiveCore

enum MacPlatformIconProvider {
    private static let tabIconPrefix = "assets/mini_live_card_"
    private static let managementIconPrefixes = [
        "assets/pad_live_card_",
        "assets/live_card_",
        tabIconPrefix
    ]

    /// 播放列表平台：用户设置并已缓存到本地的图标。
    static func playlistIcon(for liveType: LiveType, logicalSize: NSSize? = nil) -> NSImage? {
        guard let instance = PlaylistInstanceStore.shared.instance(for: liveType),
              let fileURL = PlaylistIconCache.cachedFileURL(for: instance),
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        if let logicalSize { image.size = logicalSize }
        return image
    }

    static func tabImage(for liveType: LiveType) -> NSImage? {
        if PlaylistPlatformIdentity.isPlaylist(liveType) {
            return playlistIcon(for: liveType, logicalSize: NSSize(width: 16, height: 16))
        }
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

    private static func loadManagementIcon(
        pluginId: String, fileNames: [String], targetPixels: CGFloat
    ) -> NSImage? {
        let versions = LiveParsePlugins.shared.storage.listInstalledVersions(pluginId: pluginId)
            .sorted { semverCompare($0.lastPathComponent, $1.lastPathComponent) > 0 }
        for version in versions {
            var smallestCovering: CGImage?
            var largest: CGImage?
            for fileName in fileNames {
                let url = version.appendingPathComponent(fileName).appendingPathExtension("png")
                guard FileManager.default.fileExists(atPath: url.path),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let bitmap = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                let area = Double(bitmap.width) * Double(bitmap.height)
                if largest.map({ area > Double($0.width) * Double($0.height) }) ?? true { largest = bitmap }
                if CGFloat(bitmap.width) >= targetPixels, CGFloat(bitmap.height) >= targetPixels,
                   smallestCovering.map({ area < Double($0.width) * Double($0.height) }) ?? true {
                    smallestCovering = bitmap
                }
            }
            // Keep the first available version; select resolution only among its resources.
            if let best = smallestCovering ?? largest {
                return NSImage(cgImage: best, size: NSSize(width: CGFloat(best.width), height: CGFloat(best.height)))
            }
        }
        return nil
    }

    /// 管理页按目标像素选择最小足够资源，不复用侧栏的逻辑尺寸。
    static func pluginManagementImage(
        for liveType: LiveType, targetSide: CGFloat, displayScale: CGFloat
    ) -> NSImage? {
        if PlaylistPlatformIdentity.isPlaylist(liveType) {
            return playlistIcon(for: liveType)
        }
        if let pluginId = resolveInstalledPluginId(for: liveType),
           let image = loadManagementIcon(
               pluginId: pluginId,
               fileNames: managementIconPrefixes.map { $0 + pluginId },
               targetPixels: targetSide * displayScale
           ) {
            return image
        }

        if let platform = SandboxPluginCatalog.platform(for: liveType) {
            return loadManagementIcon(
                pluginId: platform.pluginId,
                fileNames: managementIconPrefixes.map { $0 + platform.pluginId },
                targetPixels: targetSide * displayScale
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
