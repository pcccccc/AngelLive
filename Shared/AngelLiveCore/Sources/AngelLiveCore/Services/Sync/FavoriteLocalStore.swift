//
//  FavoriteLocalStore.swift
//  AngelLiveCore
//
//  收藏的本地持久化(Phase ②,见 docs/SyncResilienceAndErrorModel.md)。
//
//  目的:让本地成为收藏的真相来源 ——
//  - iOS / macOS:durable,断网 / 分流环境下离线可用;
//  - tvOS:落 Caches(系统可清),作为 best-effort 快取,iCloud 仍是该端兜底。
//
//  仅负责「存/取一份 [LiveModel] 快照」,不涉及 CloudKit。LiveModel 是 Codable,
//  直接落 JSON 文件,无需新增依赖。
//

import Foundation

public actor FavoriteLocalStore {
    public static let shared = FavoriteLocalStore()

    private let fileName = "favorites.json"
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    private let decoder = JSONDecoder()

    public init() {}

    // MARK: - 路径

    /// 存储目录:tvOS 用 Caches(唯一可写且不保证持久),其余用 Application Support。
    private func storeDirectory() -> URL {
        let fm = FileManager.default
        #if os(tvOS)
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #else
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("AngelLive", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func storeURL() -> URL {
        storeDirectory().appendingPathComponent(fileName)
    }

    // MARK: - 读 / 写

    /// 读取本地收藏快照。无文件 / 解码失败返回空数组(不抛,本地缺失视作"暂无")。
    public func load() -> [LiveModel] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let rooms = try? decoder.decode([LiveModel].self, from: data) else {
            Logger.warning("本地收藏解码失败,已忽略本地缓存", category: .general)
            return []
        }
        return rooms
    }

    /// 原子写入本地收藏快照。
    @discardableResult
    public func save(_ rooms: [LiveModel]) -> Bool {
        let url = storeURL()
        do {
            let data = try encoder.encode(rooms)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            Logger.warning("本地收藏写入失败: \(error.localizedDescription)", category: .general)
            return false
        }
    }

    /// 清空本地收藏。
    public func clear() {
        try? FileManager.default.removeItem(at: storeURL())
    }
}
