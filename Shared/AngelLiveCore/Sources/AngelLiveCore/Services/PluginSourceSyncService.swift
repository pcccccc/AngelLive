//
//  PluginSourceSyncService.swift
//  AngelLiveCore
//
//  插件源 URL 的 CloudKit 同步服务。
//  当用户在任一平台添加插件订阅源后，自动同步到 iCloud；
//  其他平台首次启动且无本地插件时，检测云端是否有已保存的源 URL 并提示一键安装。
//

import Foundation
import CloudKit
import Observation

// MARK: - CloudKit 配置

private enum CloudPluginSourceFields {
    static let containerIdentifier = "iCloud.icloud.dev.igod.simplelive"
    static let recordType = "plugin_sources"
    static let urlsField = "urls"
    static let updatedAtField = "updated_at"
    /// 固定 recordName，确保全局只有一条记录
    static let fixedRecordName = "user_plugin_sources"
}

// MARK: - PluginSourceSyncService

@Observable
public final class PluginSourceSyncService {

    /// 是否在云端发现了插件源
    public private(set) var hasSyncedSources: Bool = false

    /// 云端的源 URL 列表
    public private(set) var syncedSourceURLs: [String] = []

    /// 是否正在一键安装中
    public private(set) var isInstalling: Bool = false

    /// 安装进度消息
    public private(set) var installStatusMessage: String?

    /// 用户是否已关闭提示（仅内存标记，重启后重置）
    @ObservationIgnored
    private var userDismissedPrompt: Bool = false

    public init() {}

    // MARK: - 写入 CloudKit（静态方法，供 PluginSourceManager 调用）

    /// 将插件源 URL 列表同步到 CloudKit。
    /// 返回结构化结果(错误带码 + 建议),便于调用方/后续 UI 展示;失败不再被静默吞掉。
    @discardableResult
    public static func syncToCloudStatic(sourceURLs: [String]) async -> OperationOutcome {
        let container = CKContainer(identifier: CloudPluginSourceFields.containerIdentifier)
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: CloudPluginSourceFields.fixedRecordName)

        if sourceURLs.isEmpty {
            // 无源时删除云端记录
            do {
                try await database.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                // 记录本就不存在，忽略
            } catch {
                let syncError = SyncError.from(error)
                Logger.warning("删除云端插件源记录失败: \(syncError.displayText)", category: .plugin)
                return .failure(syncError)
            }
            return .success
        }

        // 尝试先获取已有记录（避免冲突），失败则新建
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            record = CKRecord(recordType: CloudPluginSourceFields.recordType, recordID: recordID)
        }

        record[CloudPluginSourceFields.urlsField] = sourceURLs as NSArray
        record[CloudPluginSourceFields.updatedAtField] = Date() as NSDate

        do {
            _ = try await database.save(record)
            Logger.info("已同步 \(sourceURLs.count) 个插件源 URL 到 CloudKit", category: .plugin)
            return .success
        } catch {
            let syncError = SyncError.from(error)
            Logger.warning("同步插件源到 CloudKit 失败: \(syncError.displayText)", category: .plugin)
            return .failure(syncError)
        }
    }

    // MARK: - 从 CloudKit 检查（冷启动时，无本地插件时调用）

    /// 检查 CloudKit 中是否有已保存的插件源 URL
    @MainActor
    public func checkCloudForSources() async {
        guard !userDismissedPrompt else {
            hasSyncedSources = false
            return
        }

        let container = CKContainer(identifier: CloudPluginSourceFields.containerIdentifier)
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: CloudPluginSourceFields.fixedRecordName)

        do {
            let record = try await database.record(for: recordID)
            guard let urls = record[CloudPluginSourceFields.urlsField] as? [String],
                  !urls.isEmpty else {
                hasSyncedSources = false
                syncedSourceURLs = []
                return
            }

            syncedSourceURLs = urls
            hasSyncedSources = true
            Logger.info("从 CloudKit 发现 \(urls.count) 个插件源 URL", category: .plugin)
        } catch {
            hasSyncedSources = false
            syncedSourceURLs = []
        }
    }

    // MARK: - 一键安装

    /// 一键安装：添加源 → 拉取索引 → 安装全部插件
    /// - Parameter consentRequester: 仅 `pluginSourceManager` / `installAll` 内部 consent 使用,
    ///   外层"检测到云端插件 - 一键安装"alert 已是用户主动触发,这里不再叠加额外 consent;
    ///   登录类插件的凭证泄露风险由 installAll Phase 1 的批量 alert 列具体平台后一次性确认。
    @MainActor
    public func performOneClickInstall(
        pluginSourceManager: PluginSourceManager,
        pluginAvailability: PluginAvailabilityService,
        consentRequester: (any PluginInstallConsentRequesting)? = nil
    ) async {
        _ = consentRequester  // 保留参数签名以兼容调用方,实际由 PluginSourceManager 自身注入的 requester 处理

        isInstalling = true
        installStatusMessage = "正在获取插件列表..."
        defer {
            isInstalling = false
            installStatusMessage = nil
        }

        // 1. 添加所有云端源到本地
        for url in syncedSourceURLs {
            pluginSourceManager.addSource(url)
        }

        // 2. 拉取所有源的索引（合并去重）
        installStatusMessage = "正在拉取插件索引..."
        await pluginSourceManager.fetchAllSourceIndexes()

        // 3. 安装所有插件
        installStatusMessage = "正在安装插件..."
        let count = await pluginSourceManager.installAll()

        if count > 0 {
            installStatusMessage = "正在刷新..."
            await pluginAvailability.refresh()
        }

        // 4. 完成
        hasSyncedSources = false
        Logger.info("一键安装完成: \(count) 个插件已安装", category: .plugin)
    }

    // MARK: - 关闭提示

    @MainActor
    public func dismissPrompt() {
        hasSyncedSources = false
        userDismissedPrompt = true
    }
}
