//
//  PlatformCapability.swift
//  AngelLiveCore
//
//  Created by Claude on 2026/2/25.
//

import Foundation
import LiveParse

// MARK: - 平台功能枚举

public enum PlatformFeature: String, CaseIterable, Sendable {
    case categories    // 分类列表
    case rooms         // 房间列表
    case playback      // 获取播放地址
    case search        // 搜索
    case roomDetail    // 主播详情
    case liveState     // 直播状态
    case shareResolve  // 分享码解析
    case danmaku       // 弹幕

    public var displayName: String {
        switch self {
        case .categories:   return "分类列表"
        case .rooms:        return "房间列表"
        case .playback:     return "获取播放地址"
        case .search:       return "搜索"
        case .roomDetail:   return "主播详情"
        case .liveState:    return "直播状态"
        case .shareResolve: return "分享码解析"
        case .danmaku:      return "弹幕"
        }
    }

    public var iconName: String {
        switch self {
        case .categories:   return "square.grid.2x2"
        case .rooms:        return "list.bullet"
        case .playback:     return "play.circle"
        case .search:       return "magnifyingglass"
        case .roomDetail:   return "person.text.rectangle"
        case .liveState:    return "dot.radiowaves.left.and.right"
        case .shareResolve: return "link"
        case .danmaku:      return "text.bubble"
        }
    }
}

// MARK: - 功能可用性状态

public enum FeatureStatus: Sendable {
    case available
    case partial(String)
    case unavailable
}

// MARK: - 平台功能可用性配置

public enum PlatformCapability {

    public static func features(for liveType: LiveType) -> [(PlatformFeature, FeatureStatus)] {
        switch liveType {
        case .bilibili:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .available),
            ]
        case .douyu:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .available),
            ]
        case .huya:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .available),
            ]
        case .douyin:
            return [
                (.categories,   .available),
                (.rooms,        .partial("需要 Cookie")),
                (.playback,     .partial("需要 Cookie")),
                (.search,       .partial("需要 Cookie")),
                (.roomDetail,   .partial("需要 Cookie")),
                (.liveState,    .partial("需要 Cookie")),
                (.shareResolve, .partial("需要 Cookie")),
                (.danmaku,      .partial("需要 Cookie")),
            ]
        case .ks:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .unavailable),
            ]
        case .yy:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .unavailable),
            ]
        case .cc:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .available),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .unavailable),
            ]
        case .soop:
            return [
                (.categories,   .available),
                (.rooms,        .available),
                (.playback,     .partial("19+ 需要登录")),
                (.search,       .available),
                (.roomDetail,   .available),
                (.liveState,    .available),
                (.shareResolve, .available),
                (.danmaku,      .available),
            ]
        }
    }
}
