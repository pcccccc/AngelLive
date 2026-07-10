//
//  ApiManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/29.
//

import Foundation

public enum ApiManager {
    /**
     获取当前房间直播状态。

    - Returns: 直播状态
    */
    public static func getCurrentRoomLiveState(roomId: String, userId: String?, liveType: LiveType) async throws -> LiveState {
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            return .unknow
        }
        // 冷启动后用户立即点历史卡片时,插件 runtime 可能尚未 warm,getLiveState 首拍会
        // 间歇性假阴性(误判下播)。轻量重试 1 次:退避后 runtime 多半已 ready。
        // 用户点击场景不宜多重试,故 maxRetries=2(1 次原 + 1 次重试)。
        return try await withRetry(maxRetries: 2, delayNanoseconds: 400_000_000) {
            try await LiveParseJSPlatformManager.getLiveState(platform: platform, roomId: roomId, userId: userId)
        }
    }

    public static func fetchRoomList(
        liveCategory: LiveCategoryModel,
        page: Int,
        liveType: LiveType,
        context: [String: Any] = [:]
    ) async throws -> [LiveModel] {
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            return []
        }
        return try await withRetry(maxRetries: 3, delayNanoseconds: 500_000_000) {
            try await LiveParseJSPlatformManager.getRoomList(
                platform: platform,
                id: liveCategory.id,
                parentId: liveCategory.parentId,
                page: page,
                context: context
            )
        }
    }

    private static func withRetry<T: Sendable>(
        maxRetries: Int,
        delayNanoseconds: UInt64,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        let attempts = max(maxRetries, 1)

        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            }
        }

        throw lastError ?? LiveParseError.liveParseError("房间列表请求失败", "连续 \(attempts) 次请求失败")
    }

    public static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
            return []
        }
        return try await LiveParseJSPlatformManager.getCategoryList(platform: platform)
    }

    public static func fetchLastestLiveInfo(liveModel: LiveModel) async throws -> LiveModel {
        Logger.debug("[ApiManager] fetchLastestLiveInfo: \(liveModel.userName) liveType=\(liveModel.liveType.rawValue) roomId=\(liveModel.roomId)", category: .network)
        guard let platform = SandboxPluginCatalog.platform(for: liveModel.liveType) else {
            Logger.warning("[ApiManager] fetchLastestLiveInfo: SandboxPluginCatalog.platform 返回 nil, liveType=\(liveModel.liveType.rawValue)", category: .network)
            throw LiveParseError.liveParseError("不支持的平台", "\(liveModel.liveType)")
        }
        Logger.debug("[ApiManager] fetchLastestLiveInfo: 找到平台 pluginId=\(platform.pluginId), 准备调用 getLiveLastestInfo", category: .network)
        do {
            // 冷启动全量并发刷新收藏状态时,插件 JS runtime / 内部签名缓存尚未 warm,
            // 个别房间(如小红书 userId 查询)首拍会间歇性抛 NOT_FOUND 等假阴性错误,
            // 但下拉刷新(整体重跑)又能成功。有限重试:退避后插件已 warm,成功率与
            // 下拉刷新一致。与 fetchRoomList 同样的 withRetry 模式。
            let result = try await withRetry(maxRetries: 3, delayNanoseconds: 500_000_000) {
                try await LiveParseJSPlatformManager.getLiveLastestInfo(platform: platform, roomId: liveModel.roomId, userId: liveModel.userId)
            }
            Logger.debug("[ApiManager] fetchLastestLiveInfo: getLiveLastestInfo 返回成功 \(liveModel.userName)", category: .network)
            return result
        } catch {
            Logger.warning("[ApiManager] fetchLastestLiveInfo: getLiveLastestInfo 返回失败 \(liveModel.userName)：\(error)", category: .network)
            throw error
        }

    }

    /// 轻量版房间信息获取，用于收藏同步场景
    public static func fetchLastestLiveInfoFast(liveModel: LiveModel) async throws -> LiveModel {
        return try await fetchLastestLiveInfo(liveModel: liveModel)
    }

    public static func fetchSearchWithShareCode(shareCode: String) async throws -> LiveModel? {
        let platforms = matchedShareResolvePlatforms(for: shareCode)
        guard !platforms.isEmpty else {
            throw NSError(domain: "解析房间号失败，请检查分享码/分享链接是否正确", code: -10000, userInfo: ["desc": "解析房间号失败，请检查分享码/分享链接是否正确"])
        }

        var lastError: Error?
        for platform in platforms {
            do {
                return try await LiveParseJSPlatformManager.getRoomInfoFromShareCode(platform: platform, shareCode: shareCode)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "解析房间号失败，请检查分享码/分享链接是否正确", code: -10000, userInfo: ["desc": "解析房间号失败，请检查分享码/分享链接是否正确"])
    }

    private static func matchedShareResolvePlatforms(for text: String) -> [LiveParseJSPlatform] {
        let normalizedText = text.lowercased()
        let inputHosts = extractHosts(from: normalizedText)

        return SandboxPluginCatalog.availablePlatforms().filter { platform in
            guard PlatformCapability.supports(.shareResolve, for: platform.liveType),
                  let rule = platform.shareResolve else {
                return false
            }

            let hostMatched = normalizedValues(rule.hosts).contains { ruleHost in
                inputHosts.contains { inputHost in
                    inputHost == ruleHost || inputHost.hasSuffix(".\(ruleHost)")
                }
            }

            if hostMatched {
                return true
            }

            return normalizedValues(rule.keywords).contains { keyword in
                normalizedText.contains(keyword)
            }
        }
    }

    private static func normalizedValues(_ values: [String]?) -> [String] {
        values?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }

    private static func extractHosts(from text: String) -> [String] {
        let pattern = #"(?:(?:[a-z][a-z0-9+\-.]*):\/\/)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var hosts: [String] = []
        var seen = Set<String>()

        for match in matches where match.numberOfRanges > 1 {
            guard let hostRange = Range(match.range(at: 1), in: text) else { continue }
            let host = String(text[hostRange]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !host.isEmpty, !seen.contains(host) else { continue }
            seen.insert(host)
            hosts.append(host)
        }

        return hosts
    }
}
