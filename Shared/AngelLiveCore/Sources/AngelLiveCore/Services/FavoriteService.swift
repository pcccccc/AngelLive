//
//  FavoriteService.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/19.
//

import Foundation
import CloudKit
import LiveParse

private enum CloudFavoriteFields {
    static let roomId = "room_id"
    static let userId = "user_id"
    static let userName = "user_name"
    static let roomTitle = "room_title"
    static let roomCover = "room_cover"
    static let userHeadImage = "user_head_img"
    static let liveType = "live_type"
    static let liveState = "live_state"
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
        rec.setValue(liveModel.liveState ?? "", forKey: CloudFavoriteFields.liveState)
        try await CKContainer(identifier: CloudFavoriteFields.containerIdentifier).privateCloudDatabase.save(rec)
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
            temp.append(LiveModel(userName: record.value(forKey: CloudFavoriteFields.userName) as? String ?? "",
                                  roomTitle: record.value(forKey: CloudFavoriteFields.roomTitle) as? String ?? "",
                                  roomCover: record.value(forKey: CloudFavoriteFields.roomCover) as? String ?? "",
                                  userHeadImg: record.value(forKey: CloudFavoriteFields.userHeadImage) as? String ?? "",
                                  liveType: LiveType(rawValue: record.value(forKey: CloudFavoriteFields.liveType) as? String ?? "") ?? .bilibili,
                                  liveState: record.value(forKey: CloudFavoriteFields.liveState) as? String ?? "",
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
            let liveType = LiveType(rawValue: record.value(forKey: CloudFavoriteFields.liveType) as? String ?? "") ?? .bilibili
            let userId = record.value(forKey: CloudFavoriteFields.userId) as? String ?? ""
            let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
            let uniqueKey: String
            if !normalizedUserId.isEmpty {
                uniqueKey = "\(liveType.rawValue)_u_\(normalizedUserId)"
            } else {
                uniqueKey = "\(liveType.rawValue)_r_\(normalizedRoomId)"
            }
            guard !seenKeys.contains(uniqueKey) else { continue }
            seenKeys.insert(uniqueKey)

            temp.append(LiveModel(userName: record.value(forKey: CloudFavoriteFields.userName) as? String ?? "",
                                  roomTitle: record.value(forKey: CloudFavoriteFields.roomTitle) as? String ?? "",
                                  roomCover: record.value(forKey: CloudFavoriteFields.roomCover) as? String ?? "",
                                  userHeadImg: record.value(forKey: CloudFavoriteFields.userHeadImage) as? String ?? "",
                                  liveType: liveType,
                                  liveState: record.value(forKey: CloudFavoriteFields.liveState) as? String ?? "",
                                  userId: userId,
                                  roomId: roomId,
                                  liveWatchedCount: nil))
        }
        return temp
    }
    
    public static func deleteRecord(liveModel: LiveModel) async throws {
        let container = CKContainer(identifier: CloudFavoriteFields.containerIdentifier)
        let database = container.privateCloudDatabase
        let trimmedUserId = liveModel.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRoomId = liveModel.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate: NSPredicate
        if !trimmedUserId.isEmpty {
            predicate = NSPredicate(
                format: "%K = %@ AND %K = %@",
                CloudFavoriteFields.userId, trimmedUserId,
                CloudFavoriteFields.liveType, liveModel.liveType.rawValue
            )
        } else {
            predicate = NSPredicate(
                format: "%K = %@ AND %K = %@",
                CloudFavoriteFields.roomId, trimmedRoomId,
                CloudFavoriteFields.liveType, liveModel.liveType.rawValue
            )
        }
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        let recordArray = try await database.records(matching: query)
        let recordsToDelete = recordArray.matchResults.compactMap { try? $0.1.get() }
        for record in recordsToDelete {
            try await database.deleteRecord(withID: record.recordID)
        }
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
    
    public static func formatErrorCode(error: Error) -> String {
        guard let theError = error as? CKError else { return "未知错误" }
        switch theError.code {
            case .internalError:
                return "iCloud内部错误，请稍后再试"
            case .partialFailure, .networkUnavailable:
                return "网络不可用，请检查网络问题"
            case .badContainer:
                return "容器错误，请联系开发者"
            case .serviceUnavailable:
                return "CloudKit暂停服务，请稍后再试"
            case .requestRateLimited:
                return "操作频繁，请稍后再试"
            case .missingEntitlement:
                return "操作权限异常，请检查iCloud账户状态"
            case .notAuthenticated:
                return "未登录，请检查iCloud账户状态"
            case .permissionFailure:
                return "权限异常，请检查iCloud账户状态"
            case .unknownItem:
                return "操作记录不存在，请更新收藏列表"
            case .invalidArguments:
                return "错误请求，请更新收藏列表"
            case .serverRecordChanged:
                return "请求结果与iCloud不一致，请更新收藏列表"
            case .serverRejectedRequest:
                return "iCloud服务器拒绝了请求，请更新收藏列表"
            case .assetFileNotFound:
                return "文件未找到"
            case .assetFileModified:
                return "保存文件时文件被修改"
            case .incompatibleVersion:
                return "iCloud版本不兼容"
            case .constraintViolation:
                return "唯一字段冲突"
            case .operationCancelled:
                return "操作取消，请重试"
            case .changeTokenExpired:
                return "token异常，请重新登录Apple ID"
            case .batchRequestFailed:
                return "有其他线程访问，请稍后再试"
            case  .zoneBusy:
                return "iCloud服务器繁忙，请稍后再试"
            case .badDatabase:
                return "iCloud数据库异常"
            case .quotaExceeded:
                return "iCloud存储已满，请清理空间后再试"
            case .zoneNotFound:
                return "iCloud不存在此区域，请联系开发者"
            case .limitExceeded:
                return "对服务器的请求太大，请联系开发者"
            case .userDeletedZone:
                return "区域不存在"
            case .tooManyParticipants:
                return "同时操作用户多过，请稍后再试"
            case .alreadyShared:
                return "无法保存"
            case .referenceViolation:
                return "未找到共享区域"
            case .managedAccountRestricted:
                return "由于管理账户限制，请求被拒绝"
            case .accountTemporarilyUnavailable:
                return "账户暂时不可用，请尝试在系统设置中重新登录默认账户后再试"
            case .networkFailure:
                return "连接到iCloud失败，请检查网络"
            default:
                return "未知错误"
        }
    }
}
