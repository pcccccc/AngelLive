//
//  PlatformViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import SwiftUI
import UIKit
import AngelLiveDependencies
import AngelLiveCore

@Observable
class PlatformViewModel {
    var platformInfo: [Platformdescription] = []

    init() {}

    private func normalizedDescription(_ description: String?, liveType: LiveType) -> String {
        let normalized = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty {
            return normalized
        }
        return LiveParseTools.getLivePlatformDescription(liveType)
    }

    func refreshPlatforms(installedPluginIds: [String]) {
        let platformBaseByType = Dictionary(
            LiveParseTools.getAllSupportPlatform().map { ($0.liveType, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let installedPlatforms = SandboxPluginCatalog.availablePlatforms(installedPluginIds: installedPluginIds)

        var seenPluginIds = Set<String>()
        platformInfo = installedPlatforms.compactMap { platform -> Platformdescription? in
            guard seenPluginIds.insert(platform.pluginId).inserted else { return nil }
            let fallbackTitle = LiveParseTools.getLivePlatformName(platform.liveType)
            let title = platformBaseByType[platform.liveType]?.livePlatformName ?? fallbackTitle
            let description = normalizedDescription(
                platformBaseByType[platform.liveType]?.description,
                liveType: platform.liveType
            )

            return Platformdescription(
                title: title,
                pluginId: platform.pluginId,
                bigPic: "tv_\(platform.pluginId)_big",
                smallPic: "tv_\(platform.pluginId)_small",
                descripiton: description,
                liveType: platform.liveType
            )
        }
    }
}


struct Platformdescription: Identifiable {
    let title: String
    let pluginId: String
    let bigPic: String
    let smallPic: String
    let descripiton: String
    let liveType: LiveType

    // pluginId 已在 refreshPlatforms 里 seenPluginIds 去重，保证唯一
    var id: String { pluginId }
}

enum TVPlatformIconProvider {
    private static let installedCardIconPrefix = "assets/tv_"
    private static let installedTabIconPrefix = "assets/live_card_"
    private static let imageCache = NSCache<NSString, UIImage>()

    /// FullUI management compares decoded pixels without changing other icon caches.
    static func managementImage(
        pluginID: String, targetSize: CGSize, displayScale: CGFloat, remote: LiveParseRemotePluginItem? = nil
    ) -> UIImage? {
        let names = [
            "assets/pad_live_card_" + pluginID, "assets/live_card_" + pluginID,
            "assets/mini_live_card_" + pluginID
        ] + [remote?.tvosIcon].compactMap { $0 }
        return managementResourceImage(pluginID: pluginID, names: names,
            targetSize: targetSize, displayScale: displayScale)
    }

    /// Shelf background color sampled from the icon. Cached per plugin and catalog revision.
    static func managementShelfColor(pluginID: String, revision: UInt, image: UIImage) -> UIColor? {
        guard let bitmap = image.cgImage,
              let color = PlatformIconDominantColor.extract(from: bitmap, cacheKey: "shelf|\(pluginID)|\(revision)")
        else { return nil }
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func managementResourceImage(
        pluginID: String, names: [String], targetSize: CGSize, displayScale: CGFloat
    ) -> UIImage? {
        let versions = LiveParsePlugins.shared.storage.listInstalledVersions(pluginId: pluginID)
            .sorted { semverCompare($0.lastPathComponent, $1.lastPathComponent) > 0 }
        func select(_ images: [UIImage]) -> UIImage? {
            let valid = images.filter { $0.cgImage != nil }
            let sorted = valid.sorted {
                let a = $0.cgImage!, b = $1.cgImage!
                return Double(a.width) * Double(a.height) < Double(b.width) * Double(b.height)
            }
            return sorted.first {
                guard let bitmap = $0.cgImage else { return false }
                return CGFloat(bitmap.width) >= targetSize.width * displayScale &&
                    CGFloat(bitmap.height) >= targetSize.height * displayScale
            } ?? sorted.last
        }
        for version in versions {
            let images = names.compactMap { name -> UIImage? in
                // Resource names remain relative to the installed package.
                guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."),
                      URL(string: name)?.scheme == nil else { return nil }
                let file = version.appendingPathComponent(name)
                let url = file.pathExtension.isEmpty ? file.appendingPathExtension("png") : file
                let key = url.path as NSString
                if let cached = imageCache.object(forKey: key) { return cached }
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                imageCache.setObject(image, forKey: key)
                return image
            }
            if let image = select(images) { return image }
        }
        return select(names.compactMap { UIImage(named: $0.replacingOccurrences(of: "assets/", with: "")) })
    }

    /// 播放列表平台：用户设置并已缓存到本地的图标。
    static func playlistIcon(for liveType: LiveType) -> UIImage? {
        guard let instance = PlaylistInstanceStore.shared.instance(for: liveType),
              let fileURL = PlaylistIconCache.cachedFileURL(for: instance) else {
            return nil
        }
        return UIImage(contentsOfFile: fileURL.path)
    }

    /// 获取平台 tab 尺寸图标（用于账号管理等列表）
    static func tabImage(for liveType: LiveType) -> UIImage? {
        if PlaylistPlatformIdentity.isPlaylist(liveType) {
            return playlistIcon(for: liveType)
        }
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            return nil
        }
        let pluginId = platform.pluginId

        if let installedImage = loadInstalledIcon(
            pluginId: pluginId,
            fileNames: [installedTabIconPrefix + pluginId]
        ) {
            return installedImage
        }

        return UIImage(named: "live_card_\(pluginId)")
    }

    static func bigCardImage(for platform: Platformdescription, isDarkMode: Bool) -> UIImage? {
        let primaryName = installedCardIconPrefix + platform.pluginId + (isDarkMode ? "_big_dark" : "_big")
        let fallbackName = installedCardIconPrefix + platform.pluginId + (isDarkMode ? "_big" : "_big_dark")

        if let image = loadInstalledIcon(
            pluginId: platform.pluginId,
            fileNames: [primaryName, fallbackName]
        ) {
            return image
        }

        return UIImage(named: platform.bigPic)
    }

    static func smallCardImage(for platform: Platformdescription, isDarkMode: Bool) -> UIImage? {
        let primaryName = installedCardIconPrefix + platform.pluginId + (isDarkMode ? "_small_dark" : "_small")
        let fallbackName = installedCardIconPrefix + platform.pluginId + (isDarkMode ? "_small" : "_small_dark")

        if let image = loadInstalledIcon(
            pluginId: platform.pluginId,
            fileNames: [primaryName, fallbackName]
        ) {
            return image
        }

        return UIImage(named: platform.smallPic)
    }

    private static func loadInstalledIcon(pluginId: String, fileNames: [String]) -> UIImage? {
        let storage = LiveParsePlugins.shared.storage
        let versionDirs = storage.listInstalledVersions(pluginId: pluginId)
            .sorted { semverCompare($0.lastPathComponent, $1.lastPathComponent) > 0 }

        for versionDir in versionDirs {
            for fileName in fileNames {
                let cacheKey = "\(pluginId)::\(fileName)" as NSString
                if let cached = imageCache.object(forKey: cacheKey) {
                    return cached
                }

                let iconURL = versionDir
                    .appendingPathComponent(fileName)
                    .appendingPathExtension("png")

                if FileManager.default.fileExists(atPath: iconURL.path),
                   let image = UIImage(contentsOfFile: iconURL.path) {
                    imageCache.setObject(image, forKey: cacheKey)
                    return image
                }
            }
        }

        return nil
    }

}
