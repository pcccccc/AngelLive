//
//  SyncError.swift
//  AngelLiveCore
//
//  统一的同步错误模型:人话标题 + 错误码 + 可操作建议。
//  三个同步域(收藏 / 登录凭证 / 订阅源)共享,三端只读不各写文案。
//
//  设计要点:
//  - 必须带「错误码」:CKError 用 CKError.Code.rawValue(如 quotaExceeded=25),
//    账号状态等非 CKError 用负数合成码并在展示时隐藏数字。
//  - title 为人话,advice 为可操作建议(尤其针对分流/代理网络场景)。
//

import Foundation
import CloudKit

/// 同步过程中可展示给用户的结构化错误。
public struct SyncError: Error, Codable, Sendable, Equatable {
    /// 错误码。CKError 为其 `code.rawValue`(正数);账号状态/超时等为合成负数码。
    public let code: Int
    /// 错误大类,供调用方做重试判定 / 分支处理。
    public let kind: Kind
    /// 人话标题,如「iCloud 空间已满」。
    public let title: String
    /// 可操作建议,如「请放行 *.icloud.com 后重试」。可为 nil。
    public let advice: String?
    /// 原始错误描述,折叠展示 / 上报用。
    public let rawDescription: String
    /// CloudKit 建议的最短重试间隔。独立存储，避免聚合或错误分类时丢失。
    public let serverRetryAfter: TimeInterval?

    public init(
        code: Int,
        kind: Kind,
        title: String,
        advice: String?,
        rawDescription: String,
        serverRetryAfter: TimeInterval? = nil
    ) {
        self.code = code
        self.kind = kind
        self.title = title
        self.advice = advice
        self.rawDescription = rawDescription
        self.serverRetryAfter = serverRetryAfter
    }

    public enum Kind: Codable, Sendable, Equatable {
        case notSignedIn          // 未登录 iCloud
        case iCloudRestricted     // 受家长控制 / 设备管理限制
        case accountUnavailable   // 账号暂时不可用 / 状态无法确定
        case networkBlocked       // 网络不可用 / 被代理分流拦截 / 超时
        case rateLimited(retryAfter: TimeInterval?)  // 限流
        case quotaExceeded        // iCloud 空间满
        case serverChanged        // 服务端记录已变更(冲突)
        case notFound             // 记录 / 区域不存在
        case permission           // 权限 / entitlement 异常
        case configuration        // 容器 / 数据库配置错误
        case partialFailure(failed: Int, total: Int)  // 批量部分失败
        case unknown
    }

    /// 是否值得自动重试(瞬时错误)。
    public var isRetryable: Bool {
        switch kind {
        case .networkBlocked, .rateLimited, .accountUnavailable, .serverChanged:
            return true
        case .notSignedIn, .iCloudRestricted, .quotaExceeded, .permission,
             .configuration, .notFound, .partialFailure, .unknown:
            return false
        }
    }

    /// 限流场景下服务端建议的重试间隔(秒)。
    public var retryAfter: TimeInterval? {
        serverRetryAfter ?? {
            if case let .rateLimited(seconds) = kind { return seconds }
            return nil
        }()
    }

    /// 页面展示文案:标题 + 建议 +(正数)错误码。
    public var displayText: String {
        var text = title
        if let advice, !advice.isEmpty {
            text += " " + advice
        }
        if code > 0 {
            text += "(错误码 \(code))"
        }
        return text
    }
}

// MARK: - 映射工厂

public extension SyncError {

    /// 任意 Error → SyncError。识别 CKError / CancellationError,其余兜底。
    static func from(_ error: Error) -> SyncError {
        if let ckError = error as? CKError {
            return from(ckError)
        }
        if error is CancellationError {
            return SyncError(
                code: -100,
                kind: .networkBlocked,
                title: "操作超时",
                advice: "请检查网络连接后重试。",
                rawDescription: "CancellationError"
            )
        }
        let nsError = error as NSError
        return SyncError(
            code: nsError.code,
            kind: .unknown,
            title: "同步失败",
            advice: nil,
            rawDescription: nsError.localizedDescription
        )
    }

    /// CKError → SyncError。覆盖 FavoriteService.formatErrorCode 的全部 case 并补码 + 建议。
    static func from(_ error: CKError) -> SyncError {
        let code = error.code.rawValue
        let raw = error.localizedDescription
        let proxyAdvice = "若使用了加速或分流工具,请确认已放行 *.icloud.com,或临时关闭后重试。"

        switch error.code {
        case .networkUnavailable, .networkFailure:
            return SyncError(code: code, kind: .networkBlocked,
                             title: "iCloud 连接失败", advice: proxyAdvice, rawDescription: raw)
        case .serviceUnavailable:
            let retry = (error as NSError).userInfo[CKErrorRetryAfterKey] as? TimeInterval
            return SyncError(code: code, kind: .networkBlocked,
                             title: "iCloud 服务暂不可用", advice: "请稍后再试。" , rawDescription: raw,
                             serverRetryAfter: retry)
        case .requestRateLimited, .zoneBusy, .batchRequestFailed:
            let retry = (error as NSError).userInfo[CKErrorRetryAfterKey] as? TimeInterval
            return SyncError(code: code, kind: .rateLimited(retryAfter: retry),
                             title: "iCloud 繁忙", advice: "操作过于频繁,请稍后再试。", rawDescription: raw,
                             serverRetryAfter: retry)
        case .quotaExceeded:
            return SyncError(code: code, kind: .quotaExceeded,
                             title: "iCloud 空间已满", advice: "请在 系统设置 > Apple 账户 > iCloud 清理空间后重试。", rawDescription: raw)
        case .notAuthenticated:
            return SyncError(code: code, kind: .notSignedIn,
                             title: "未登录 iCloud", advice: "请前往 系统设置 > Apple 账户 登录后重试。", rawDescription: raw)
        case .managedAccountRestricted:
            return SyncError(code: code, kind: .iCloudRestricted,
                             title: "iCloud 账户受限", advice: "当前账户受管理限制,请联系管理员。", rawDescription: raw)
        case .accountTemporarilyUnavailable:
            return SyncError(code: code, kind: .accountUnavailable,
                             title: "iCloud 账户暂时不可用", advice: "请尝试在 系统设置 中重新登录默认账户后再试。", rawDescription: raw)
        case .permissionFailure, .missingEntitlement:
            return SyncError(code: code, kind: .permission,
                             title: "iCloud 权限异常", advice: "请检查 iCloud 账户状态。", rawDescription: raw)
        case .badContainer, .badDatabase, .incompatibleVersion:
            return SyncError(code: code, kind: .configuration,
                             title: "iCloud 配置错误", advice: "请更新 App 或联系开发者。", rawDescription: raw)
        case .serverRecordChanged:
            return SyncError(code: code, kind: .serverChanged,
                             title: "云端数据已更新", advice: "请刷新后重试。", rawDescription: raw)
        case .unknownItem, .zoneNotFound, .userDeletedZone, .assetFileNotFound:
            return SyncError(code: code, kind: .notFound,
                             title: "记录不存在", advice: "请刷新收藏列表。", rawDescription: raw)
        case .partialFailure:
            return SyncError(code: code, kind: .partialFailure(failed: 0, total: 0),
                             title: "部分数据同步失败", advice: "请重试。", rawDescription: raw)
        case .changeTokenExpired:
            return SyncError(code: code, kind: .serverChanged,
                             title: "同步令牌过期", advice: "请刷新后重试。", rawDescription: raw)
        case .operationCancelled:
            return SyncError(code: code, kind: .networkBlocked,
                             title: "操作已取消", advice: "请重试。", rawDescription: raw)
        case .constraintViolation:
            return SyncError(code: code, kind: .serverChanged,
                             title: "数据冲突", advice: "请刷新后重试。", rawDescription: raw)
        case .limitExceeded:
            return SyncError(code: code, kind: .configuration,
                             title: "单次请求过大", advice: "请联系开发者。", rawDescription: raw)
        case .internalError:
            return SyncError(code: code, kind: .unknown,
                             title: "iCloud 内部错误", advice: "请稍后再试。", rawDescription: raw)
        default:
            return SyncError(code: code, kind: .unknown,
                             title: "同步失败", advice: nil, rawDescription: raw)
        }
    }

    /// CKAccountStatus → SyncError。`.available` 返回 nil(无错误)。
    static func from(accountStatus: CKAccountStatus) -> SyncError? {
        switch accountStatus {
        case .available:
            return nil
        case .noAccount:
            return SyncError(code: -1, kind: .notSignedIn,
                             title: "未登录 iCloud", advice: "请前往 系统设置 > Apple 账户 登录后重试。",
                             rawDescription: "accountStatus=noAccount")
        case .restricted:
            return SyncError(code: -2, kind: .iCloudRestricted,
                             title: "iCloud 账户受限", advice: "iCloud 受家长控制或设备管理限制。",
                             rawDescription: "accountStatus=restricted")
        case .couldNotDetermine:
            return SyncError(code: -3, kind: .accountUnavailable,
                             title: "无法确定 iCloud 状态", advice: "请检查网络/iCloud 服务后重试。",
                             rawDescription: "accountStatus=couldNotDetermine")
        case .temporarilyUnavailable:
            return SyncError(code: -4, kind: .accountUnavailable,
                             title: "iCloud 暂时不可用", advice: "请在 系统设置 中更新账户状态后重试。",
                             rawDescription: "accountStatus=temporarilyUnavailable")
        @unknown default:
            return SyncError(code: -99, kind: .unknown,
                             title: "未知 iCloud 状态", advice: nil,
                             rawDescription: "accountStatus=unknown")
        }
    }
}
