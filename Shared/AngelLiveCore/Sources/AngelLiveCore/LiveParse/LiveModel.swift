//
//  LiveModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/8.
//

import Foundation
import Alamofire
import CloudKit

public struct LiveModel: Identifiable, Codable, Equatable, Hashable, Sendable {

    /// 稳定身份:平台 + roomId。与 `AppFavoriteModel.favoriteUniqueKey` 的主键口径一致,
    /// roomId 跨平台并不唯一,必须带上 liveType 才能区分(否则会跨平台串房)。
    public var id: String { "\(liveType.rawValue)-\(roomId)" }
    public let userName: String
    public let roomTitle: String
    public let roomCover: String
    public let userHeadImg: String
    public let liveType: LiveType
    public var liveState: String?
    public let userId: String
    public let roomId: String
    public let liveWatchedCount: String?
    /// 收藏身份元数据(roomId/userId/昵称/头像/标题)的最后更新时间。仅用于收藏同步的
    /// 多设备身份合并(远端新于本地→取远端身份),**不参与** `liveState` 同步,也不参与
    /// `==`/`hash`(身份相等口径仍是 liveType+roomId)。旧 JSON / 非收藏来源缺该字段时解码为 nil。
    public var identityUpdatedAt: Date?

    public init(userName: String, roomTitle: String, roomCover: String, userHeadImg: String, liveType: LiveType, liveState: String?, userId: String, roomId: String, liveWatchedCount: String?, identityUpdatedAt: Date? = nil) {
        self.userName = userName
        self.roomTitle = roomTitle
        self.roomCover = roomCover
        self.userHeadImg = userHeadImg
        self.liveType = liveType
        self.liveState = liveState
        self.userId = userId
        self.roomId = roomId
        self.liveWatchedCount = liveWatchedCount
        self.identityUpdatedAt = identityUpdatedAt
    }

    public var description: String {
        return "\(userName)-\(roomTitle)-\(roomCover)-\(userHeadImg)-\(liveType)-\(liveState ?? "")-\(userId)-\(roomId)"
    }

    public static func ==(lhs: LiveModel, rhs: LiveModel) -> Bool {
        return lhs.liveType == rhs.liveType && lhs.roomId == rhs.roomId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(liveType)
        hasher.combine(roomId)
    }
    
    public func liveStateFormat() -> String {
        switch LiveState(rawValue: liveState ?? "0") {
            case .close:
                return "已下播"
            case .live:
                return "正在直播"
            case .video:
                return "回放/轮播"
            case .unknow:
                return "未知状态"
            case .none:
                return "未知状态"
        }
    }
}

public struct LiveQualityModel: Codable, Sendable {
    public var cdn: String
    public var displayName: String?
    public var requestContext: [String: String]?
    public var qualitys: [LiveQualityDetail]
    
    init(
        cdn: String,
        displayName: String? = nil,
        requestContext: [String: String]? = nil,
        qualitys: [LiveQualityDetail]
    ) {
        self.cdn = cdn
        self.displayName = displayName
        self.requestContext = requestContext
        self.qualitys = qualitys
    }
}

public enum LivePlaybackStreamFormat: String, Codable, Sendable {
    case flv
    case hlsLive
    case hlsVod
    case dash
    case unknown
}

public enum LivePlaybackSelectionBehavior: String, Codable, Sendable {
    case direct
    case refreshOnSelect
}

public enum LivePlaybackLatencyMode: String, Codable, Sendable {
    case standard
    case lowLatency
}

/// KSPlayer engine preference exposed to plugins without leaking concrete Swift types.
public enum LivePlaybackEngine: String, Codable, Sendable, Hashable {
    case mePlayer
    case avPlayer
    case unknown

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

public struct LivePlaybackHints: Codable, Sendable {
    /// 描述流本身的格式/语义，资源侧不需要知道宿主有哪些播放器。
    public var streamFormat: LivePlaybackStreamFormat?
    /// 标准或低延迟播放语义。未提供时宿主才允许按 URL 特征推断。
    public var latencyMode: LivePlaybackLatencyMode?
    /// 插件建议的 KSPlayer 内核顺序；宿主会过滤与流格式不兼容的项。
    public var preferredEngines: [LivePlaybackEngine]?
    /// 插件明确声明直播/点播语义；未提供时由 streamFormat 推断。
    public var isLive: Bool?
    /// 流需要自定义分片/加载管线时置 true，由宿主映射到合适的播放器能力。
    public var requiresCustomSegmentLoader: Bool?
    /// 用户选中该项时是否需要重新请求真实播放地址。
    public var selectionBehavior: LivePlaybackSelectionBehavior?
    /// 开播后需要跳转到的初始时间点（秒），用于回放/轮播类切片流。
    public var startPositionSeconds: Double?

    public init(
        streamFormat: LivePlaybackStreamFormat? = nil,
        latencyMode: LivePlaybackLatencyMode? = nil,
        preferredEngines: [LivePlaybackEngine]? = nil,
        isLive: Bool? = nil,
        requiresCustomSegmentLoader: Bool? = nil,
        selectionBehavior: LivePlaybackSelectionBehavior? = nil,
        startPositionSeconds: Double? = nil
    ) {
        self.streamFormat = streamFormat
        self.latencyMode = latencyMode
        self.preferredEngines = preferredEngines
        self.isLive = isLive
        self.requiresCustomSegmentLoader = requiresCustomSegmentLoader
        self.selectionBehavior = selectionBehavior
        self.startPositionSeconds = startPositionSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case streamFormat
        case latencyMode
        case preferredEngines
        case isLive
        case requiresCustomSegmentLoader
        case selectionBehavior
        case startPositionSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Plugin hints are advisory. Unknown future values must not reject the
        // entire playback response; the resolver will infer any missing field.
        streamFormat = try? container.decode(LivePlaybackStreamFormat.self, forKey: .streamFormat)
        latencyMode = try? container.decode(LivePlaybackLatencyMode.self, forKey: .latencyMode)
        preferredEngines = try? container.decode([LivePlaybackEngine].self, forKey: .preferredEngines)
        isLive = try? container.decode(Bool.self, forKey: .isLive)
        requiresCustomSegmentLoader = try? container.decode(Bool.self, forKey: .requiresCustomSegmentLoader)
        selectionBehavior = try? container.decode(LivePlaybackSelectionBehavior.self, forKey: .selectionBehavior)
        startPositionSeconds = try? container.decode(Double.self, forKey: .startPositionSeconds)
    }
}

public struct LiveQualityDetail: Codable, Sendable {
    public var roomId: String
    public var title: String
    /// 资源侧用于标识清晰度或重取流参数的通用数值。
    public var qn: Int
    public var url: String
    public var liveCodeType: LiveCodeType
    public var liveType: LiveType
    /// 播放该线路时建议使用的 User-Agent（可选，缺省由宿主兜底）
    public var userAgent: String?
    /// 播放该线路时建议附带的请求头（可选）
    public var headers: [String: String]?
    /// 重新取流或切换线路时透传给资源侧的通用上下文。
    public var requestContext: [String: String]?
    /// 资源侧声明的流特性/能力需求，宿主据此映射播放计划。
    public var playbackHints: LivePlaybackHints?
}

public struct LiveCategoryModel: Codable {
    /// 资源侧分类 ID，宿主仅透传。
    public var id: String
    /// 资源侧父分类 ID，宿主仅透传。
    public var parentId: String
    public let title: String
    public let icon: String
    /// 资源侧分类附加参数，宿主仅透传。
    public var biz: String?
    
    init(id: String, parentId: String, title: String, icon: String, biz: String? = "") {
        self.id = id
        self.parentId = parentId
        self.title = title
        self.icon = icon
        self.biz = biz
    }
}

public struct LiveMainListModel: Codable {
    public let id: String
    public let title: String
    public let icon: String
    /// 资源侧分类附加参数，宿主仅透传。
    public let biz: String?
    public var subList: [LiveCategoryModel]
    
    init(id: String, title: String, icon: String, biz: String? = "", subList: [LiveCategoryModel]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.biz = biz
        self.subList = subList
    }
}

public struct LiveType: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        self.rawValue = normalized
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self),
           let liveType = LiveType(rawValue: stringValue) {
            self = liveType
            return
        }
        if let intValue = try? container.decode(Int.self),
           let liveType = LiveType(rawValue: String(intValue)) {
            self = liveType
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "LiveType must be a non-empty string or integer."
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let placeholder: LiveType = .init(rawValue: "__placeholder__")!
}

public enum LiveState: String, Codable {
    case close = "0", //关播
         live = "1", //直播中
         video = "2", //录播、轮播
         unknow = "3" //未知
}

public enum LiveCodeType: String, Codable, Sendable {
    case flv = "flv",
         hls = "m3u8"
}
