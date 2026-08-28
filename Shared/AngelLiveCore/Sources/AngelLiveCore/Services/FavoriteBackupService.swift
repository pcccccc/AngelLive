//
//  FavoriteBackupService.swift
//  AngelLiveCore
//
//  收藏导入导出。两种文件格式:
//    - Angel Live 信封:JSON 对象,带 app/version/exportedAt/deviceName,
//      payload 是完整 LiveModel(无损跨设备迁移)。
//    - Simple Live 兼容:JSON 数组,每条 {siteId,userName,face,roomId},
//      兼容原 SimpleLive 备份和 tvOS Bonjour /sync/follow payload。
//  Decode 时按顶层 token 自动分流;export 时由调用方选择格式。
//

import Foundation
#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers
#endif

// MARK: - Format Selection

public enum FavoriteBackupFormat: String, CaseIterable, Sendable {
    case angelLive
    case simpleLive

    public var fileNamePrefix: String {
        switch self {
        case .angelLive: return "AngelLive-Favorites"
        case .simpleLive: return "SimpleLive-Favorites"
        }
    }
}

// MARK: - Envelope (Angel Live 完整格式)

public struct AngelLiveFavoriteBackup: Codable, Sendable {
    public let app: String
    public let version: Int
    public let exportedAt: Date
    public let deviceName: String?
    public let favorites: [LiveModel]

    public static let currentVersion: Int = 1
    public static let appIdentifier: String = "AngelLive"

    public init(
        app: String = AngelLiveFavoriteBackup.appIdentifier,
        version: Int = AngelLiveFavoriteBackup.currentVersion,
        exportedAt: Date,
        deviceName: String?,
        favorites: [LiveModel]
    ) {
        self.app = app
        self.version = version
        self.exportedAt = exportedAt
        self.deviceName = deviceName
        self.favorites = favorites
    }
}

// MARK: - SimpleLive 兼容条目

public struct SimpleLiveFavoriteItem: Codable, Sendable {
    public let siteId: String
    public let userName: String
    public let face: String
    public let roomId: String

    public init(siteId: String, userName: String, face: String, roomId: String) {
        self.siteId = siteId
        self.userName = userName
        self.face = face
        self.roomId = roomId
    }
}

// MARK: - Errors

public enum FavoriteBackupError: LocalizedError {
    case unrecognizedFormat
    case encodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "无法识别的收藏备份格式:既不是 Angel Live 信封,也不是 Simple Live 数组"
        case .encodingFailed(let underlying):
            return "导出失败:\(underlying.localizedDescription)"
        }
    }
}

// MARK: - Report Types

public struct FavoriteImportReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public let id: UUID
        public let userName: String
        public let siteId: String?
        public let reason: String

        public init(id: UUID = UUID(), userName: String, siteId: String?, reason: String) {
            self.id = id
            self.userName = userName
            self.siteId = siteId
            self.reason = reason
        }
    }

    public let added: [LiveModel]
    public let skipped: [LiveModel]
    public let failed: [Failure]

    public init(added: [LiveModel], skipped: [LiveModel], failed: [Failure]) {
        self.added = added
        self.skipped = skipped
        self.failed = failed
    }

    public var addedCount: Int { added.count }
    public var skippedCount: Int { skipped.count }
    public var failedCount: Int { failed.count }
    public var hasFailures: Bool { !failed.isEmpty }
}

// MARK: - Service

public enum FavoriteBackupService {

    /// 按指定格式编码收藏列表。
    public static func export(
        rooms: [LiveModel],
        format: FavoriteBackupFormat,
        deviceName: String?
    ) throws -> Data {
        try export(
            rooms: rooms,
            format: format,
            deviceName: deviceName,
            siteIdForLiveType: { liveType in
                LiveParseJSPlatformManager.platform(for: liveType)?.pluginId ?? liveType.rawValue
            }
        )
    }

    /// Internal resolver seam keeps backup format tests independent from plugins installed
    /// in the current user's Application Support directory.
    static func export(
        rooms: [LiveModel],
        format: FavoriteBackupFormat,
        deviceName: String?,
        siteIdForLiveType: (LiveType) -> String
    ) throws -> Data {
        do {
            switch format {
            case .angelLive:
                let envelope = AngelLiveFavoriteBackup(
                    exportedAt: Date(),
                    deviceName: deviceName,
                    favorites: rooms
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                return try encoder.encode(envelope)

            case .simpleLive:
                let items = rooms.map { room in
                    SimpleLiveFavoriteItem(
                        siteId: siteIdForLiveType(room.liveType),
                        userName: room.userName,
                        face: room.userHeadImg,
                        roomId: room.roomId
                    )
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                return try encoder.encode(items)
            }
        } catch let error as FavoriteBackupError {
            throw error
        } catch {
            throw FavoriteBackupError.encodingFailed(error)
        }
    }

    /// 解析备份文件。顶层是 JSON 对象走 Angel Live 信封;是数组走 SimpleLive 列表。
    /// itemFailures 用于把 SimpleLive 路径上 siteId 无法解析的条目暴露给 UI,
    /// 让用户知道是哪个平台缺插件。
    public static func decode(_ data: Data) throws -> (rooms: [LiveModel], itemFailures: [FavoriteImportReport.Failure]) {
        try decode(data, liveTypeForSiteId: LiveParseJSPlatformManager.liveType(forSiteId:))
    }

    /// Internal resolver seam keeps backup format tests deterministic on clean machines.
    static func decode(
        _ data: Data,
        liveTypeForSiteId: (String?) -> LiveType?
    ) throws -> (rooms: [LiveModel], itemFailures: [FavoriteImportReport.Failure]) {
        let envelopeDecoder = JSONDecoder()
        envelopeDecoder.dateDecodingStrategy = .iso8601
        if let envelope = try? envelopeDecoder.decode(AngelLiveFavoriteBackup.self, from: data) {
            return (envelope.favorites, [])
        }

        // SimpleLive 裸数组兜底
        if let items = try? JSONDecoder().decode([SimpleLiveFavoriteItem].self, from: data) {
            var rooms: [LiveModel] = []
            var failures: [FavoriteImportReport.Failure] = []
            for item in items {
                if let liveType = liveTypeForSiteId(item.siteId) {
                    rooms.append(LiveModel(
                        userName: item.userName,
                        roomTitle: "",
                        roomCover: "",
                        userHeadImg: item.face,
                        liveType: liveType,
                        liveState: nil,
                        userId: "",
                        roomId: item.roomId,
                        liveWatchedCount: nil
                    ))
                } else {
                    failures.append(FavoriteImportReport.Failure(
                        userName: item.userName.isEmpty ? "(未知主播)" : item.userName,
                        siteId: item.siteId,
                        reason: "未找到对应插件,请先安装该平台插件 (siteId: \(item.siteId))"
                    ))
                }
            }
            return (rooms, failures)
        }

        throw FavoriteBackupError.unrecognizedFormat
    }
}

// MARK: - FileDocument

#if !os(tvOS)
/// 把已编码的备份字节包装成 SwiftUI FileDocument,
/// 供 iOS/macOS `.fileExporter(...)` 直接使用。tvOS 上不可用(FileDocument 在 tvOS 没有)。
public struct FavoriteBackupDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public static var writableContentTypes: [UTType] { [.json] }

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
