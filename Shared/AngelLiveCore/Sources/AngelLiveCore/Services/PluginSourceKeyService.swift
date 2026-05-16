//
//  PluginSourceKeyService.swift
//  AngelLiveCore
//
//  APP 启动时从远程拉取 keys.json，缓存 key→urls 映射。
//  用户添加订阅源时，若输入内容匹配某个 key，则自动展开为对应 urls。
//

import Foundation

/// keys.json 中单条 key 映射
private struct PluginSourceKey: Decodable {
    let key: String
    let urls: [String]
}

/// keys.json 根结构
private struct PluginSourceKeysResponse: Decodable {
    let keys: [PluginSourceKey]
}

/// 管理远程 key→urls 映射的服务（线程安全）
public actor PluginSourceKeyService {

    public static let shared = PluginSourceKeyService()

    /// key → urls 映射缓存
    private var keyMap: [String: [String]] = [:]

    /// 是否已成功加载过
    private var loaded = false

    /// 内置兜底映射：keys.json 拉取失败时，官方订阅密钥仍可解析。
    static let bundledFallbackKeyMap: [String: [String]] = [
        "444222000": [
            "https://ghfast.top/https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/plugins.json",
            "https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/plugins.json"
        ]
    ]

    /// 远程 keys.json 的备用地址（依次尝试）
    private let remoteURLs: [URL] = [
        URL(string: "https://ghfast.top/https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/keys.json")!,
        URL(string: "https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/keys.json")!
    ]

    private init() {}

    // MARK: - 公开 API

    /// 启动时调用：从远程拉取 keys.json 并缓存
    public func fetchKeys() async {
        // 已加载过则跳过
        guard !loaded else { return }

        // 先放入稳定官方 key，远程成功后再覆盖/扩展。
        if keyMap.isEmpty {
            keyMap = Self.bundledFallbackKeyMap
        }

        for url in remoteURLs {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    continue
                }
                let decoded = try JSONDecoder().decode(PluginSourceKeysResponse.self, from: data)
                var map = Self.bundledFallbackKeyMap
                for entry in decoded.keys {
                    map[entry.key] = entry.urls
                }
                self.keyMap = map
                self.loaded = true
                Logger.info("PluginSourceKeyService: loaded \(map.count) key(s)", category: .plugin)
                return
            } catch {
                Logger.warning("PluginSourceKeyService: fetch failed from \(url): \(error.localizedDescription)", category: .plugin)
                continue
            }
        }
        Logger.warning("PluginSourceKeyService: all remote URLs failed", category: .plugin)
    }

    /// 根据用户输入解析实际的订阅源 URL 列表。
    /// 若输入匹配某个 key，返回对应 urls；否则返回 nil（表示按原样处理）。
    public func resolveKey(_ input: String) -> [String]? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return keyMap[trimmed] ?? Self.bundledFallbackKeyMap[trimmed]
    }
}
