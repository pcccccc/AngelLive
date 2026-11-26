import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

public struct PlatformAppearanceLibrary: Sendable {
    public let store: PlatformAppearanceStore
    let artwork: PlatformAppearanceArtworkLoader
    let assets: PlatformAppearanceAssetCache
}

public extension EnvironmentValues {
    @Entry var platformAppearanceLibrary: PlatformAppearanceLibrary?
}

struct PlatformAppearanceArtwork: Sendable {
    let wordmark: CGImage?
    let square: CGImage?
    let dominantColor: PlatformRGBAColor?
}

actor PlatformAppearanceArtworkLoader {
    static let shared = PlatformAppearanceArtworkLoader()

    private let storage: LiveParsePluginStorage?

    init(storage: LiveParsePluginStorage? = nil) {
        self.storage = storage
    }

    private struct Key: Hashable {
        let pluginID: String
        let dark: Bool
        let revision: UInt
        let playlistIconURL: URL?
        let includesWordmark: Bool
    }

    private var cache: [Key: PlatformAppearanceArtwork] = [:]

    func artwork(
        pluginID: String, liveType: LiveType, dark: Bool, revision: UInt, includesWordmark: Bool
    ) -> PlatformAppearanceArtwork {
        let isPlaylist = PlaylistPlatformIdentity.isPlaylist(liveType)
        let playlistURL = isPlaylist && storage == nil
            ? PlaylistInstanceStore.shared.instance(for: liveType).flatMap(PlaylistIconCache.cachedFileURL)
            : nil
        let key = Key(pluginID: pluginID, dark: dark, revision: revision, playlistIconURL: playlistURL,
                      includesWordmark: includesWordmark)
        if let existing = cache[key] { return existing }

        let wordmark: CGImage?
        let square: CGImage?
        let squareURL: URL?
        if isPlaylist {
            wordmark = nil
            squareURL = playlistURL
            square = playlistURL.flatMap { Self.decode($0, dimension: 256) }
        } else {
            let versions = (storage ?? LiveParsePlugins.shared.storage).listInstalledVersions(pluginId: pluginID)
                .sorted { semverCompare($0.lastPathComponent, $1.lastPathComponent) > 0 }
            let wordmarkNames = dark
                ? ["tv_\(pluginID)_big_dark", "tv_\(pluginID)_big"]
                : ["tv_\(pluginID)_big", "tv_\(pluginID)_big_dark"]
            let squareNames = ["pad_live_card_", "live_card_", "mini_live_card_"].map { $0 + pluginID }
            wordmark = includesWordmark ? Self.firstArtwork(in: versions, names: wordmarkNames, dimension: 768)?.0 : nil
            (square, squareURL) = Self.firstArtwork(in: versions, names: squareNames, dimension: 256)
                .map { ($0.0, $0.1) } ?? (nil, nil)
        }
        let result = PlatformAppearanceArtwork(
            wordmark: wordmark, square: square,
            dominantColor: square.flatMap {
                PlatformIconDominantColor.extract(from: $0, cacheKey: squareURL.map { "grid|\($0.path)|\(revision)" })
            }
        )
        if cache.count >= 48 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }

    private static func firstArtwork(in versions: [URL], names: [String], dimension: Int) -> (CGImage, URL)? {
        for version in versions {
            let assets = version.appendingPathComponent("assets", isDirectory: true)
            for name in names {
                let url = assets.appendingPathComponent(name).appendingPathExtension("png")
                if let image = decode(url, dimension: dimension) { return (image, url) }
            }
        }
        return nil
    }

    private static func decode(_ url: URL, dimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension
        ] as CFDictionary)
    }
}
