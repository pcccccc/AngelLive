//
//  CacheMaintenanceService.swift
//  AngelLiveCore
//
//  统一管理 App 缓存大小的计算与清理：
//  - URLCache(.shared) 磁盘缓存
//  - tmp/ 临时目录
//  - LiveParse 插件旧版本(保留 pinnedVersion + lastGoodVersion + 最新版)
//
//  注意:Kingfisher 缓存大小/清理由各平台层(iOS/macOS/tvOS) 自行处理，
//  通过 `Sizes.imageCache` 字段汇总。
//

import Foundation

public struct CacheMaintenanceService: Sendable {

    public struct Sizes: Sendable, Equatable {
        public var imageCache: Int64
        public var urlCache: Int64
        public var tmp: Int64
        public var pluginOldVersions: Int64

        public init(imageCache: Int64 = 0, urlCache: Int64 = 0, tmp: Int64 = 0, pluginOldVersions: Int64 = 0) {
            self.imageCache = imageCache
            self.urlCache = urlCache
            self.tmp = tmp
            self.pluginOldVersions = pluginOldVersions
        }

        public var total: Int64 {
            imageCache + urlCache + tmp + pluginOldVersions
        }

        public var formattedTotal: String {
            CacheMaintenanceService.formatBytes(total)
        }
    }

    // MARK: - 大小汇总(平台无关部分)

    /// 计算除 Kingfisher 之外的缓存大小(URLCache + tmp + 插件旧版本)。
    /// Kingfisher 由调用方追加到返回结果的 imageCache 字段。
    public static func computeNonImageSizes() -> Sizes {
        var sizes = Sizes()
        sizes.urlCache = Int64(URLCache.shared.currentDiskUsage)
        sizes.tmp = directorySize(at: FileManager.default.temporaryDirectory)
        sizes.pluginOldVersions = pluginOldVersionsSize()
        return sizes
    }

    // MARK: - 清理动作

    /// 清理 URLCache.shared 磁盘缓存与 tmp/ 临时文件。
    public static func clearURLCacheAndTmp() {
        URLCache.shared.removeAllCachedResponses()

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let contents = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }

    /// 清理所有 LiveParse 插件的旧版本(保留 pinnedVersion + lastGoodVersion + 每个 pluginId 最新版)。
    /// - Returns: 被删除的 (pluginId, version) 列表
    @discardableResult
    public static func prunePluginOldVersions() -> [(pluginId: String, version: String)] {
        let storage = LiveParsePlugins.shared.storage
        let state = storage.loadState()
        let fm = FileManager.default
        let pluginsRoot = storage.pluginsRootDirectory

        guard let pluginDirs = try? fm.contentsOfDirectory(
            at: pluginsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var removed: [(String, String)] = []
        for pluginDir in pluginDirs where pluginDir.hasDirectoryPath {
            let pluginId = pluginDir.lastPathComponent
            let removedForPlugin = pruneOldVersions(pluginId: pluginId, state: state.plugins[pluginId])
            removed.append(contentsOf: removedForPlugin.map { (pluginId, $0) })
        }
        return removed
    }

    /// 清理指定 pluginId 的旧版本(供 LiveParsePluginUpdater 在 activateInstalled 后调用)。
    /// - Returns: 被删除的版本号列表
    @discardableResult
    public static func prunePluginOldVersions(pluginId: String) -> [String] {
        let storage = LiveParsePlugins.shared.storage
        let record = storage.loadState().plugins[pluginId]
        return pruneOldVersions(pluginId: pluginId, state: record)
    }

    // MARK: - 工具方法

    public static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    // MARK: - 私有

    /// 计算插件目录中所有"非最新且非保留"版本占用的字节数。
    private static func pluginOldVersionsSize() -> Int64 {
        let storage = LiveParsePlugins.shared.storage
        let state = storage.loadState()
        let fm = FileManager.default
        let pluginsRoot = storage.pluginsRootDirectory

        guard let pluginDirs = try? fm.contentsOfDirectory(
            at: pluginsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for pluginDir in pluginDirs where pluginDir.hasDirectoryPath {
            let pluginId = pluginDir.lastPathComponent
            let staleVersionDirs = staleVersionDirectories(
                pluginId: pluginId,
                state: state.plugins[pluginId]
            )
            for url in staleVersionDirs {
                total += directorySize(at: url)
            }
        }
        return total
    }

    /// 选出"应该被清理的"版本目录(保留 pinned + lastGood + 最新 semver)。
    private static func staleVersionDirectories(
        pluginId: String,
        state: LiveParsePluginState.PluginRecord?
    ) -> [URL] {
        let storage = LiveParsePlugins.shared.storage
        let versions = storage.listInstalledVersions(pluginId: pluginId)
        guard versions.count > 1 else { return [] }

        let pairs: [(version: String, url: URL)] = versions.map { url in
            (version: url.lastPathComponent, url: url)
        }

        var keep: Set<String> = []
        if let pinned = state?.pinnedVersion {
            keep.insert(pinned)
        }
        if let lastGood = state?.lastGoodVersion {
            keep.insert(lastGood)
        }
        if let latest = pairs.max(by: { semverCompare($0.version, $1.version) < 0 }) {
            keep.insert(latest.version)
        }

        return pairs.filter { !keep.contains($0.version) }.map(\.url)
    }

    @discardableResult
    private static func pruneOldVersions(pluginId: String, state: LiveParsePluginState.PluginRecord?) -> [String] {
        let stale = staleVersionDirectories(pluginId: pluginId, state: state)
        guard !stale.isEmpty else { return [] }

        let fm = FileManager.default
        var removed: [String] = []
        for url in stale {
            do {
                try fm.removeItem(at: url)
                removed.append(url.lastPathComponent)
            } catch {
                // 静默忽略单个版本的清理失败(下次启动还会尝试)
            }
        }
        return removed
    }

    private static func semverCompare(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ value: String) -> [Int] {
            value.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }
        let left = parts(lhs)
        let right = parts(rhs)
        for idx in 0..<3 {
            if left[idx] != right[idx] {
                return left[idx] < right[idx] ? -1 : 1
            }
        }
        return 0
    }
}
