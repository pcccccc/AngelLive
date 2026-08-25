//
//  PluginHomeFeedCacheStore.swift
//  AngelLiveCore
//
//  Stale-while-revalidate snapshot storage for the plugin-driven home page.
//

import Foundation

public actor PluginHomeFeedCacheStore {
    public static let shared = PluginHomeFeedCacheStore()

    private struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        let savedAt: Date
        let feeds: [PluginHomeFeed]
    }

    private enum Constants {
        static let schemaVersion = 1
        static let maximumCacheBytes = 8 * 1_024 * 1_024
        static let directoryName = "AngelLive"
        static let fileName = "home-feed-v1.json"
    }

    private let customFileURL: URL?

    public init(fileURL: URL? = nil) {
        customFileURL = fileURL
    }

    public func load() -> [PluginHomeFeed] {
        let url = cacheURL()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= Constants.maximumCacheBytes else {
                Logger.warning("首页缓存超过大小限制，已忽略", category: .plugin)
                return []
            }

            let snapshot = try decoder.decode(Snapshot.self, from: data)
            guard snapshot.schemaVersion == Constants.schemaVersion else {
                Logger.warning(
                    "首页缓存版本不兼容: \(snapshot.schemaVersion)",
                    category: .plugin
                )
                return []
            }
            return snapshot.feeds.filter {
                $0.schemaVersion == PluginHomeFeedRequest.supportedSchemaVersion
            }
        } catch {
            Logger.warning(
                "首页缓存读取失败: \(error.localizedDescription)",
                category: .plugin
            )
            return []
        }
    }

    @discardableResult
    public func save(_ feeds: [PluginHomeFeed]) -> Bool {
        do {
            let snapshot = Snapshot(
                schemaVersion: Constants.schemaVersion,
                savedAt: Date(),
                feeds: feeds
            )
            let data = try encoder.encode(snapshot)
            guard data.count <= Constants.maximumCacheBytes else {
                Logger.warning("首页缓存写入内容超过大小限制", category: .plugin)
                return false
            }
            try data.write(to: cacheURL(), options: [.atomic])
            return true
        } catch {
            Logger.warning(
                "首页缓存写入失败: \(error.localizedDescription)",
                category: .plugin
            )
            return false
        }
    }
}

private extension PluginHomeFeedCacheStore {
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    func cacheURL() -> URL {
        let fileManager = FileManager.default
        if let customFileURL {
            let directoryURL = customFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directoryURL.path) {
                do {
                    try fileManager.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                } catch {
                    Logger.warning(
                        "首页缓存目录创建失败: \(error.localizedDescription)",
                        category: .plugin
                    )
                }
            }
            return customFileURL
        }

        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directoryURL = baseURL.appendingPathComponent(
            Constants.directoryName,
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                Logger.warning(
                    "首页缓存目录创建失败: \(error.localizedDescription)",
                    category: .plugin
                )
            }
        }
        return directoryURL.appendingPathComponent(Constants.fileName)
    }
}
