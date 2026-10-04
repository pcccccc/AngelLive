//
//  FavoriteService.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/19.
//

import Foundation
import CloudKit

private enum CloudFavoriteFields {
    static let roomId = "room_id"
    static let userId = "user_id"
    static let userName = "user_name"
    static let roomTitle = "room_title"
    static let roomCover = "room_cover"
    static let userHeadImage = "user_head_img"
    static let liveType = "live_type"
    static let containerIdentifier = "iCloud.icloud.dev.igod.simplelive"
}

public final class FavoriteService: NSObject {
    
    public static func saveRecord(liveModel: LiveModel) async throws {
        let rec = CKRecord(recordType: "favorite_streamers")
        rec.setValue(liveModel.roomId, forKey: CloudFavoriteFields.roomId)
        rec.setValue(liveModel.userId, forKey: CloudFavoriteFields.userId)
        rec.setValue(liveModel.userName, forKey: CloudFavoriteFields.userName)
        rec.setValue(liveModel.roomTitle, forKey: CloudFavoriteFields.roomTitle)
        rec.setValue(liveModel.roomCover, forKey: CloudFavoriteFields.roomCover)
        rec.setValue(liveModel.userHeadImg, forKey: CloudFavoriteFields.userHeadImage)
        rec.setValue(liveModel.liveType.rawValue, forKey: CloudFavoriteFields.liveType)
        _ = try await CKContainer(identifier: CloudFavoriteFields.containerIdentifier).privateCloudDatabase.save(rec)
    }
    
    public static func searchRecord(roomId: String) async throws -> [LiveModel] {
        let container = CKContainer(identifier: CloudFavoriteFields.containerIdentifier)
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: " \(CloudFavoriteFields.roomId) = '\(roomId)' ")
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        // 使用新的 API
        let recordArray = try await database.records(matching: query)
        var temp: Array<LiveModel> = []
        for record in recordArray.matchResults.compactMap({ try? $0.1.get() }) {
            guard let liveType = LiveType(rawValue: record.value(forKey: CloudFavoriteFields.liveType) as? String ?? "") else {
                continue
            }
            temp.append(LiveModel(userName: record.value(forKey: CloudFavoriteFields.userName) as? String ?? "",
                                  roomTitle: record.value(forKey: CloudFavoriteFields.roomTitle) as? String ?? "",
                                  roomCover: record.value(forKey: CloudFavoriteFields.roomCover) as? String ?? "",
                                  userHeadImg: record.value(forKey: CloudFavoriteFields.userHeadImage) as? String ?? "",
                                  liveType: liveType,
                                  liveState: nil,
                                  userId: record.value(forKey: CloudFavoriteFields.userId) as? String ?? "",
                                  roomId: record.value(forKey: CloudFavoriteFields.roomId) as? String ?? "",
                                  liveWatchedCount: nil))
        }
        return temp
    }
    
    public static func searchRecord() async throws -> [LiveModel] {
        let container = CKContainer(identifier: CloudFavoriteFields.containerIdentifier)
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "favorite_streamers", predicate: NSPredicate(value: true))
        // 使用新的 API
        let recordArray = try await database.records(matching: query, resultsLimit: 99999)
        var temp: Array<LiveModel> = []
        var seenKeys: Set<String> = []  // 用于去重
        for record in recordArray.matchResults.compactMap({ try? $0.1.get() }) {
            let roomId = record.value(forKey: CloudFavoriteFields.roomId) as? String ?? ""
            guard let liveType = LiveType(rawValue: record.value(forKey: CloudFavoriteFields.liveType) as? String ?? "") else {
                continue
            }
            let userId = record.value(forKey: CloudFavoriteFields.userId) as? String ?? ""
            let model = LiveModel(userName: record.value(forKey: CloudFavoriteFields.userName) as? String ?? "",
                                  roomTitle: record.value(forKey: CloudFavoriteFields.roomTitle) as? String ?? "",
                                  roomCover: record.value(forKey: CloudFavoriteFields.roomCover) as? String ?? "",
                                  userHeadImg: record.value(forKey: CloudFavoriteFields.userHeadImage) as? String ?? "",
                                  liveType: liveType,
                                  liveState: nil,
                                  userId: userId,
                                  roomId: roomId,
                                  liveWatchedCount: nil)
            // 统一用 AppFavoriteModel.favoriteUniqueKey(roomId 主键、视 "0"/空为无效),
            // 避免 userId="0" 的记录挤进 `4_u_0` 碰撞桶被丢。
            let uniqueKey = AppFavoriteModel.favoriteUniqueKey(for: model)
            guard !seenKeys.contains(uniqueKey) else { continue }
            seenKeys.insert(uniqueKey)
            temp.append(model)
        }
        return temp
    }
    
    public static func deleteRecord(liveModel: LiveModel) async throws {
        try await deleteLegacyRecords(identity: LegacyFavoriteIdentity(room: liveModel)) { true }
    }

    /// 删除旧默认 Zone 中与 typed identity 精确匹配的全部记录。
    /// 分页和逐条错误都必须完整处理；调用方可在每页和每条删除前撤销旧 revision。
    public static func deleteLegacyRecords(
        identity: LegacyFavoriteIdentity,
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws {
        guard !identity.namespace.isEmpty, !identity.value.isEmpty else { return }
        let database = CKContainer(identifier: CloudFavoriteFields.containerIdentifier).privateCloudDatabase
        let identityField = identity.field == .userID ? CloudFavoriteFields.userId : CloudFavoriteFields.roomId
        let predicate = NSPredicate(
            format: "%K = %@ AND %K = %@",
            identityField, identity.value,
            CloudFavoriteFields.liveType, identity.namespace
        )
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        let defaultZoneID = CKRecordZone.default().zoneID
        var cursor: CKQueryOperation.Cursor?

        repeat {
            guard await shouldContinue() else { throw CancellationError() }
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(
                    matching: query,
                    inZoneWith: defaultZoneID,
                    resultsLimit: CKQueryOperation.maximumResults
                )
            }
            for result in page.matchResults {
                guard await shouldContinue() else { throw CancellationError() }
                let record = try result.1.get()
                do {
                    try await database.deleteRecord(withID: record.recordID)
                } catch let error as CKError where error.code == .unknownItem {
                    continue
                }
            }
            cursor = page.queryCursor
        } while cursor != nil
    }
    
    public static func getCloudState() async -> String {
        // 1. 检查 CloudKit 容器标识符
        guard !CloudFavoriteFields.containerIdentifier.isEmpty else {
            return "CloudKit 配置错误：容器标识符为空"
        }
        
        // 2. 检查 CloudKit 可用性
        guard CKContainer.default().containerIdentifier != nil else {
            return "CloudKit 服务不可用"
        }
        
        do {
            // 3. 使用更安全的容器初始化方式
            let container: CKContainer
            if CloudFavoriteFields.containerIdentifier == CKContainer.default().containerIdentifier {
                container = CKContainer.default()
            } else {
                container = CKContainer(identifier: CloudFavoriteFields.containerIdentifier)
            }
            
            // 4. 添加超时保护
            let status = try await withTimeout(seconds: 10) {
                try await container.accountStatus()
            }
            
            switch status {
                case .available:
                    return "正常"
                case .couldNotDetermine:
                    return "无法确定状态,请检查iCloud服务/网络连接是否正常"
                case .restricted:
                    return "iCloud用户受限"
                case .noAccount:
                    return "未登录iCloud，请进入 系统设置-用户和账户 登录Apple ID"
                case .temporarilyUnavailable:
                    return "iCloud服务不可用，请进入 系统设置-用户和账户 更新用户状态"
                @unknown default:
                    return "未知的iCloud状态"
            }
        } catch let error as CKError {
            return formatErrorCode(error: error)
        } catch is CancellationError {
            return "操作超时，请检查网络连接"
        } catch {
            // 5. 处理其他未预期的错误
            return "获取iCloud状态失败：\(error.localizedDescription)"
        }
    }
    
    // 添加超时保护的辅助方法
    private static func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @Sendable in
                try await operation()
            }

            group.addTask { @Sendable in
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }

            group.cancelAll()
            return result
        }
    }
    
    /// 将任意错误转成可展示文案(人话 + 建议 + 错误码)。
    ///
    /// 实现已迁移到统一的 `SyncError`:
    /// 三端所有 `formatErrorCode` 调用点因此自动升级为「原因 + 建议 + 错误码」。
    /// 保留此静态方法签名以兼容现有调用点;新代码建议直接用 `SyncError.from(_:)`。
    public static func formatErrorCode(error: Error) -> String {
        SyncError.from(error).displayText
    }

    /// 结构化错误,供需要 code / kind / advice 的调用点使用。
    public static func syncError(for error: Error) -> SyncError {
        SyncError.from(error)
    }
}
