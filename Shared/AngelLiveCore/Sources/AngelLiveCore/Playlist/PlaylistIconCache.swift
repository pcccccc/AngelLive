//
//  PlaylistIconCache.swift
//  AngelLiveCore
//
//  播放列表平台图标的本地缓存。界面只读本地文件，不在显示时联网。
//

import CryptoKit
import Foundation
import ImageIO

public enum PlaylistIconCache {
    private static let maxByteCount = 2 * 1024 * 1024

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AngelLivePlaylistIcons", isDirectory: true)
    }

    private static func fileURL(for iconURL: String) -> URL? {
        let name = SHA256.hash(data: Data(iconURL.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name, isDirectory: false)
    }

    /// 已缓存的图标文件；未缓存或未设置图标时为 nil。
    public static func cachedFileURL(for instance: PlaylistInstance) -> URL? {
        guard let iconURL = instance.iconURL, let fileURL = fileURL(for: iconURL),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    /// 下载并校验为图片后写入缓存。失败返回 false，调用方回退到首字图标，不阻止保存。
    @discardableResult
    public static func fetch(iconURL: String) async -> Bool {
        guard let url = URL(string: iconURL), let fileURL = fileURL(for: iconURL), let directory else { return false }
        if FileManager.default.fileExists(atPath: fileURL.path) { return true }
        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return false }
            guard data.count <= maxByteCount, isImage(data) else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    /// 「更新于 8 分钟前」。固定中文，避免宿主未本地化时出现英文相对时间。
    public static func updatedText(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return "更新于" + formatter.localizedString(for: date, relativeTo: now)
    }

    /// 名称首字符，用于无图标时的占位。
    public static func monogram(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }
}
