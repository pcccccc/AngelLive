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

    /// 获取平台 tab 尺寸图标（用于账号管理等列表）
    static func tabImage(for liveType: LiveType) -> UIImage? {
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
