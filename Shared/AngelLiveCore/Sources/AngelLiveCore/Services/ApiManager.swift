//
//  ApiManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/29.
//

import Foundation
import LiveParse

public enum ApiManager {
    /**
     获取当前房间直播状态。

     - Returns: 直播状态
    */
    public static func getCurrentRoomLiveState(roomId: String, userId: String?, liveType: LiveType) async throws -> LiveState {
        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else {
            return .unknow
        }
        return try await LiveParseJSPlatformManager.getLiveState(platform: platform, roomId: roomId, userId: userId)
    }

    public static func fetchRoomList(liveCategory: LiveCategoryModel, page: Int, liveType: LiveType) async throws -> [LiveModel] {
        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else {
            return []
        }
        if liveType == .bilibili {
            return try await fetchBilibiliRoomListWithRetry(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
        }
        return try await LiveParseJSPlatformManager.getRoomList(platform: platform, id: liveCategory.id, parentId: liveCategory.parentId, page: page)
    }

    /// B站请求带重试
    private static func fetchBilibiliRoomListWithRetry(id: String, parentId: String?, page: Int, maxRetries: Int = 3) async throws -> [LiveModel] {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await LiveParseJSPlatformManager.getRoomList(platform: .bilibili, id: id, parentId: parentId, page: page)
            } catch {
                lastError = error

                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                }
            }
        }

        throw lastError ?? LiveParseError.liveParseError("B站请求失败", "连续 \(maxRetries) 次请求失败")
    }

    public static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else {
            return []
        }
        return try await LiveParseJSPlatformManager.getCategoryList(platform: platform)
    }

    public static func fetchLastestLiveInfo(liveModel: LiveModel) async throws -> LiveModel {
        guard let platform = LiveParseJSPlatformManager.platform(for: liveModel.liveType) else {
            throw LiveParseError.liveParseError("不支持的平台", "\(liveModel.liveType)")
        }
        return try await LiveParseJSPlatformManager.getLiveLastestInfo(platform: platform, roomId: liveModel.roomId, userId: liveModel.userId)
    }

    /// 轻量版房间信息获取，用于收藏同步场景
    public static func fetchLastestLiveInfoFast(liveModel: LiveModel) async throws -> LiveModel {
        return try await fetchLastestLiveInfo(liveModel: liveModel)
    }

    public static func fetchSearchWithShareCode(shareCode: String) async throws -> LiveModel? {

        // 确定平台类型
        let liveType: LiveType? = {
            if shareCode.contains("b23.tv") || shareCode.contains("bilibili") { return .bilibili }
            if shareCode.contains("douyin") { return .douyin }
            if shareCode.contains("huya") { return .huya }
            if shareCode.contains("hy.fan") { return .huya }
            if shareCode.contains("douyu") { return .douyu }
            if shareCode.contains("cc.163.com") { return .cc }
            if shareCode.contains("kuaishou.com") { return .ks }
            if shareCode.contains("yy.com") { return .yy }
            if shareCode.contains("sooplive") || shareCode.contains("afreecatv") { return .soop }
            return nil
        }()

        if let liveType = liveType {
            return try await handlePlatformSearch(shareCode, liveType: liveType)
        } else {
            throw NSError(domain: "解析房间号失败，请检查分享码/分享链接是否正确", code: -10000, userInfo: ["desc": "解析房间号失败，请检查分享码/分享链接是否正确"])
        }
    }

    private static func handlePlatformSearch(_ text: String, liveType: LiveType) async throws -> LiveModel? {
        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else {
            return nil
        }
        return try await LiveParseJSPlatformManager.getRoomInfoFromShareCode(platform: platform, shareCode: text)
    }
}
