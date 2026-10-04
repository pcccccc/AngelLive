//
//  PluginHomeFeedCacheStore.swift
//  AngelLiveCore
//
//  Stale-while-revalidate snapshot storage for the plugin-driven home page.
//

import Foundation

public actor PluginHomeFeedCacheStore {
    public static let shared = PluginHomeFeedCacheStore()

    private struct LegacySnapshot: Codable, Sendable {
        let schemaVersion: Int
        let savedAt: Date
        let feeds: [PluginHomeFeed]
    }

    struct Snapshot: Codable, Sendable {
        struct Entry: Codable, Sendable {
            let feed: PluginHomeFeed
            let fetchedAt: Date
            let contextRevision: String?
        }

        let schemaVersion: Int
        let entries: [Entry]

        var feeds: [PluginHomeFeed] { entries.map(\.feed) }
    }

    private enum Constants {
        static let schemaVersion = 2
        static let legacySchemaVersion = 1
        static let maximumCacheBytes = 8 * 1_024 * 1_024
        static let directoryName = "AngelLive"
        static let fileName = "home-feed-v1.json"
    }

    private let customFileURL: URL?

    public init(fileURL: URL? = nil) {
        customFileURL = fileURL
    }

    public func load() -> [PluginHomeFeed] {
        loadSnapshot()?.feeds ?? []
    }

    func loadSnapshot() -> Snapshot? {
        let url = cacheURL()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= Constants.maximumCacheBytes else {
                Logger.warning("首页缓存超过大小限制，已忽略", category: .plugin)
                return nil
            }

            if let snapshot = try? decoder.decode(Snapshot.self, from: data),
               snapshot.schemaVersion == Constants.schemaVersion {
                return validated(snapshot)
            }

            let legacy = try decoder.decode(LegacySnapshot.self, from: data)
            guard legacy.schemaVersion == Constants.legacySchemaVersion else {
                Logger.warning(
                    "首页缓存版本不兼容: \(legacy.schemaVersion)",
                    category: .plugin
                )
                return nil
            }
            return Snapshot(
                schemaVersion: Constants.schemaVersion,
                entries: legacy.feeds.filter {
                    $0.schemaVersion == PluginHomeFeedRequest.supportedSchemaVersion
                }.map {
                    .init(feed: $0, fetchedAt: .distantPast, contextRevision: nil)
                }
            )
        } catch {
            Logger.warning(
                "首页缓存读取失败: \(error.localizedDescription)",
                category: .plugin
            )
            return nil
        }
    }

    @discardableResult
    public func save(_ feeds: [PluginHomeFeed]) -> Bool {
        save(feeds, contextRevisions: [:], fetchedAtByPluginId: [:])
    }

    @discardableResult
    func save(
        _ feeds: [PluginHomeFeed],
        contextRevisions: [String: String],
        fetchedAtByPluginId: [String: Date],
        defaultFetchedAt: Date = Date()
    ) -> Bool {
        do {
            let snapshot = Snapshot(
                schemaVersion: Constants.schemaVersion,
                entries: feeds.map {
                    .init(
                        feed: $0,
                        fetchedAt: fetchedAtByPluginId[$0.pluginId] ?? defaultFetchedAt,
                        contextRevision: contextRevisions[$0.pluginId]
                    )
                }
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

    public func remove(pluginId: String) {
        guard let snapshot = loadSnapshot() else { return }
        let retained = snapshot.entries.filter { $0.feed.pluginId != pluginId }
        save(
            retained.map(\.feed),
            contextRevisions: Dictionary(
                uniqueKeysWithValues: retained.compactMap { entry in
                    entry.contextRevision.map { (entry.feed.pluginId, $0) }
                }
            ),
            fetchedAtByPluginId: Dictionary(
                uniqueKeysWithValues: retained.map { ($0.feed.pluginId, $0.fetchedAt) }
            )
        )
    }
}

private extension PluginHomeFeedCacheStore {
    func validated(_ snapshot: Snapshot) -> Snapshot {
        Snapshot(
            schemaVersion: snapshot.schemaVersion,
            entries: snapshot.entries.filter {
                $0.feed.schemaVersion == PluginHomeFeedRequest.supportedSchemaVersion
            }
        )
    }

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
