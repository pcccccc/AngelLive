//
//  PlatformCredentialSyncService.swift
//  AngelLiveCore
//
//  通用凭证同步服务：iCloud (CloudKit) + Bonjour 局域网同步。
//  全部平台统一走 PlatformSessionManager。
//

import Foundation
import Network
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - CloudKit 配置

private enum CloudCookieFields {
    static let containerIdentifier = "iCloud.icloud.dev.igod.simplelive"
    static let recordType = "cookie_sessions"
    static let cookieDataField = "cookie_data"
    static let platformIdField = "platform_id"
    static let updatedAtField = "updated_at"

    /// 通用 recordName 前缀
    static func sessionRecordName(for pluginId: String) -> String {
        "angellive_session_sync_\(pluginId)"
    }
}

// MARK: - Cookie 同步数据模型

/// Cookie 同步来源
public enum CookieSyncSource: String, Codable, Sendable {
    case local = "local"
    case iCloud = "icloud"
    case bonjour = "bonjour"
    case manual = "manual"
}

/// 同步的 Cookie 数据
public struct SyncedCookieData: Codable, Sendable {
    public let cookie: String
    public let uid: String?
    public let timestamp: Date
    public let source: CookieSyncSource
    public let deviceName: String?
    public let platformId: String?

    public init(cookie: String, uid: String?, timestamp: Date = Date(), source: CookieSyncSource, deviceName: String? = nil, platformId: String? = nil) {
        self.cookie = cookie
        self.uid = uid
        self.timestamp = timestamp
        self.source = source
        self.deviceName = deviceName
        self.platformId = platformId
    }
}

/// 多平台同步载荷
public struct MultiPlatformSyncPayload: Codable, Sendable {
    public let sessions: [SyncedCookieData]
    public let deviceName: String?
    public let timestamp: Date

    public init(sessions: [SyncedCookieData], deviceName: String? = nil) {
        self.sessions = sessions
        self.deviceName = deviceName
        self.timestamp = Date()
    }
}

// MARK: - 凭证同步服务

@MainActor
public final class PlatformCredentialSyncService: ObservableObject {
    public static let shared = PlatformCredentialSyncService()

    // MARK: - Published Properties

    @Published public var isSyncing = false
    /// 最近一次 iCloud 同步的错误(成功后置 nil),供页面展示「原因 + 错误码」。
    @Published public var lastSyncError: SyncError?
    @Published public var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
        }
    }
    @Published public var lastICloudSyncTime: Date?

    /// 按 pluginId 索引的登录状态
    @Published public var loggedInByPluginId: [String: Bool] = [:]

    // MARK: - Bonjour

    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isBonjourListening = false
    @Published public var lastBonjourSyncAt: Date?
    @Published public var lastBonjourSyncedPlatformIds: [String] = []

    // MARK: - Private

    private enum Keys {
        static let iCloudSyncEnabled = "PlatformCredentialSyncService.iCloudSyncEnabled"
        static let lastICloudSyncTime = "PlatformCredentialSyncService.lastICloudSyncTime"
        static let migrationDone = "AngelLive.Migration.pluginIdSessionV2"

    }

    private var bonjourListener: NWListener?
    private var bonjourBrowser: NWBrowser?

    // MARK: - Init

    private init() {
        // 先尝试读 manifest 声明的旧 key 迁移
        if UserDefaults.standard.object(forKey: Keys.iCloudSyncEnabled) == nil,
           let legacyEnabledKey = Self.legacyMigrationKey(\.legacyICloudSyncEnabledKeys),
           UserDefaults.standard.object(forKey: legacyEnabledKey) != nil {
            let oldValue = UserDefaults.standard.bool(forKey: legacyEnabledKey)
            UserDefaults.standard.set(oldValue, forKey: Keys.iCloudSyncEnabled)
        }
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)

        // 恢复 iCloud 同步时间（兼容旧 key）
        if let timeInterval = UserDefaults.standard.object(forKey: Keys.lastICloudSyncTime) as? Double {
            self.lastICloudSyncTime = Date(timeIntervalSince1970: timeInterval)
        } else if let legacyTimeKey = Self.legacyMigrationKey(\.legacyICloudSyncTimeKeys),
                  let oldTime = UserDefaults.standard.object(forKey: legacyTimeKey) as? Double {
            self.lastICloudSyncTime = Date(timeIntervalSince1970: oldTime)
            UserDefaults.standard.set(oldTime, forKey: Keys.lastICloudSyncTime)
        }

        Task {
            await performLegacyMigrationIfNeeded()
            await refreshAllLoginStatus()
        }
    }

    // MARK: - 登录状态查询

    /// 查询指定平台是否已登录
    public func isLoggedIn(pluginId: String) -> Bool {
        loggedInByPluginId[pluginId] ?? false
    }

    /// 刷新单个平台登录状态
    public func refreshLoginStatus(pluginId: String) async {
        if let session = await PlatformSessionManager.shared.getSession(pluginId: pluginId),
           session.state == .authenticated,
           let cookie = session.cookie, !cookie.isEmpty {
            loggedInByPluginId[pluginId] = true
        } else {
            loggedInByPluginId[pluginId] = false
        }
    }

    /// 刷新所有平台登录状态
    public func refreshAllLoginStatus() async {
        let sessions = await PlatformSessionManager.shared.allSessions()
        var status: [String: Bool] = [:]
        for session in sessions {
            let isAuth = session.state == .authenticated
                && session.cookie?.isEmpty == false
            status[session.pluginId] = isAuth
        }
        loggedInByPluginId = status
    }

    // MARK: - iCloud 同步 (CloudKit)

    /// 同步所有已认证平台到 CloudKit。
    /// 返回明确结果(成功 / 部分失败 / 失败),并写入 `lastSyncError` 供页面展示。
    @discardableResult
    public func syncAllToICloud() async -> OperationOutcome {
        isSyncing = true
        defer { isSyncing = false }

        let sessions = await collectAllPlatformSessions()
        let sessionsByPluginId: [String: SyncedCookieData] = sessions.reduce(into: [:]) { result, session in
            guard let pluginId = session.platformId else { return }
            result[pluginId] = session
        }

        let container = CKContainer(identifier: CloudCookieFields.containerIdentifier)
        let database = container.privateCloudDatabase

        // 获取现有所有 cloudRecord 的 pluginId 列表
        let allPluginIds = Set(sessionsByPluginId.keys)
            .union(await knownCloudPluginIds())

        var failures: [SyncError] = []

        for pluginId in allPluginIds {
            let recordName = CloudCookieFields.sessionRecordName(for: pluginId)
            let recordID = CKRecord.ID(recordName: recordName)

            if let session = sessionsByPluginId[pluginId],
               let encoded = try? JSONEncoder().encode(session) {
                let record: CKRecord
                do {
                    record = try await database.record(for: recordID)
                } catch {
                    record = CKRecord(recordType: CloudCookieFields.recordType, recordID: recordID)
                }
                record[CloudCookieFields.cookieDataField] = encoded as NSData
                record[CloudCookieFields.platformIdField] = pluginId as NSString
                record[CloudCookieFields.updatedAtField] = Date() as NSDate
                do {
                    _ = try await database.save(record)
                } catch {
                    let syncError = SyncError.from(error)
                    failures.append(syncError)
                    Logger.warning("同步 \(pluginId) session 到 CloudKit 失败: \(syncError.displayText)", category: .general)
                }
            } else {
                // 无 session，删除云端记录
                do {
                    try await database.deleteRecord(withID: recordID)
                } catch let error as CKError where error.code == .unknownItem {
                    // 不存在则忽略
                } catch {
                    let syncError = SyncError.from(error)
                    failures.append(syncError)
                    Logger.warning("删除 CloudKit session 失败 (\(pluginId)): \(syncError.displayText)", category: .general)
                }
            }
        }

        let outcome = makeOutcome(failures: failures, total: allPluginIds.count, failedTitle: "部分平台登录信息同步失败")
        lastSyncError = outcome.error
        if outcome.isSuccess {
            recordICloudSyncTime()
            Logger.info("已同步 \(sessions.count) 个平台 session 到 CloudKit", category: .general)
        }
        return outcome
    }

    /// 从 CloudKit 同步所有平台。
    /// 返回明确结果并写入 `lastSyncError`。「记录不存在」视为正常跳过,不计入失败;
    /// 网络/权限等错误才计入。
    @discardableResult
    public func syncAllFromICloud() async -> OperationOutcome {
        isSyncing = true
        defer { isSyncing = false }

        let container = CKContainer(identifier: CloudCookieFields.containerIdentifier)
        let database = container.privateCloudDatabase

        await migrateLegacyCloudRecords(database: database)

        // 查询所有 cookie_sessions 记录
        let knownIds = await knownCloudPluginIds()
        var failures: [SyncError] = []

        for pluginId in knownIds {
            let recordName = CloudCookieFields.sessionRecordName(for: pluginId)
            let recordID = CKRecord.ID(recordName: recordName)

            do {
                let record = try await database.record(for: recordID)
                guard let data = record[CloudCookieFields.cookieDataField] as? Data,
                      let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data),
                      !syncedData.cookie.isEmpty else {
                    continue
                }

                // 如果本地更新，跳过
                if let local = await PlatformSessionManager.shared.getSession(pluginId: pluginId),
                   local.state == .authenticated,
                   let localCookie = local.cookie, !localCookie.isEmpty,
                   local.updatedAt >= syncedData.timestamp {
                    continue
                }

                _ = await PlatformSessionManager.shared.loginWithCookie(
                    pluginId: pluginId,
                    cookie: syncedData.cookie,
                    uid: syncedData.uid,
                    source: .iCloud,
                    validateBeforeSave: true
                )
            } catch let error as CKError where error.code == .unknownItem {
                // 该平台无云端记录，正常跳过
            } catch {
                // 网络/权限等错误,计入失败
                failures.append(SyncError.from(error))
            }
        }

        let outcome = makeOutcome(failures: failures, total: knownIds.count, failedTitle: "部分平台登录信息下载失败")
        lastSyncError = outcome.error
        if outcome.isSuccess {
            recordICloudSyncTime()
        }
        await refreshAllLoginStatus()
        return outcome
    }

    /// 把一批失败聚合成 OperationOutcome:无失败→success;全失败→failure;部分→partial。
    private func makeOutcome(failures: [SyncError], total: Int, failedTitle: String) -> OperationOutcome {
        guard let representative = failures.first else { return .success }
        if failures.count >= total {
            return .failure(representative)
        }
        let partial = SyncError(
            code: representative.code,
            kind: .partialFailure(failed: failures.count, total: total),
            title: failedTitle,
            advice: representative.advice ?? "请稍后重试。",
            rawDescription: representative.rawDescription
        )
        return .partial(partial)
    }

    /// 云端同步预览（时间 + 平台列表），不下载 Cookie
    public struct ICloudSyncPreview: Sendable {
        public let latestTime: Date?
        public let platformNames: [String]
    }

    public func fetchCloudSyncPreview() async -> ICloudSyncPreview {
        let container = CKContainer(identifier: CloudCookieFields.containerIdentifier)
        let database = container.privateCloudDatabase

        var latestDate: Date?
        var platformNames: [String] = []

        let knownIds = await knownCloudPluginIds()
        for pluginId in knownIds {
            let recordName = CloudCookieFields.sessionRecordName(for: pluginId)
            let recordID = CKRecord.ID(recordName: recordName)
            if let record = try? await database.record(for: recordID),
               let data = record[CloudCookieFields.cookieDataField] as? Data,
               let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data),
               !syncedData.cookie.isEmpty {
                if let date = record[CloudCookieFields.updatedAtField] as? Date {
                    if latestDate == nil || date > latestDate! {
                        latestDate = date
                    }
                }
                platformNames.append(displayName(for: pluginId))
            }
        }

        return ICloudSyncPreview(latestTime: latestDate, platformNames: platformNames)
    }

    /// 清理 CloudKit 中保存的所有平台登录信息，不影响本地登录态。
    @discardableResult
    public func clearAllICloudSessions() async -> Int {
        isSyncing = true
        defer { isSyncing = false }

        let container = CKContainer(identifier: CloudCookieFields.containerIdentifier)
        let database = container.privateCloudDatabase
        var recordIDsByName: [String: CKRecord.ID] = [:]

        let query = CKQuery(recordType: CloudCookieFields.recordType, predicate: NSPredicate(value: true))
        do {
            let records = try await database.records(matching: query, resultsLimit: 99999)
            for record in records.matchResults.compactMap({ try? $0.1.get() }) {
                recordIDsByName[record.recordID.recordName] = record.recordID
            }
        } catch {
            Logger.warning("查询 CloudKit session 记录失败: \(error.localizedDescription)", category: .general)
        }

        for pluginId in await knownCloudPluginIds() {
            let recordName = CloudCookieFields.sessionRecordName(for: pluginId)
            recordIDsByName[recordName] = CKRecord.ID(recordName: recordName)
        }
        for recordName in legacyCloudRecordNames() {
            recordIDsByName[recordName] = CKRecord.ID(recordName: recordName)
        }

        var deletedCount = 0
        for recordID in recordIDsByName.values {
            do {
                try await database.deleteRecord(withID: recordID)
                deletedCount += 1
            } catch let error as CKError where error.code == .unknownItem {
                // 记录本就不存在，忽略。
            } catch {
                Logger.warning("清理 CloudKit session 失败 (\(recordID.recordName)): \(error.localizedDescription)", category: .general)
            }
        }

        recordICloudSyncTime()
        Logger.info("已清理 \(deletedCount) 个 CloudKit 平台 session", category: .general)
        return deletedCount
    }

    /// 获取本地已登录的平台名称列表
    public func getLocalAuthenticatedPlatformNames() async -> [String] {
        let sessions = await PlatformSessionManager.shared.allSessions()
        return sessions
            .filter { $0.state == .authenticated && $0.cookie?.isEmpty == false }
            .map { displayName(for: $0.pluginId) }
    }

    /// 格式化同步时间
    public static func formatSyncTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 局域网同步 (Bonjour)

    /// 发现的���备
    public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let endpoint: NWEndpoint

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
            lhs.id == rhs.id
        }
    }

    private let bonjourServiceType = "_angellive-cookie._tcp"

    /// 开始监听（tvOS 端）
    public func startBonjourListener() {
        guard bonjourListener == nil else { return }

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: "AngelLive-tvOS-\(getDeviceName())", type: bonjourServiceType)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isBonjourListening = true
                        Logger.info("Bonjour 监听已启动", category: .general)
                    case .failed(let error):
                        Logger.warning("Bonjour 监听失败: \(error)", category: .general)
                        self?.isBonjourListening = false
                    case .cancelled:
                        self?.isBonjourListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }

            listener.start(queue: .main)
            bonjourListener = listener
        } catch {
            Logger.warning("创建 Bonjour 监听失败: \(error)", category: .general)
        }
    }

    /// 停止监听
    public func stopBonjourListener() {
        bonjourListener?.cancel()
        bonjourListener = nil
        isBonjourListening = false
    }

    /// 开始搜索设备（iOS/macOS 端）
    public func startBonjourBrowsing() {
        guard bonjourBrowser == nil else { return }

        let browser = NWBrowser(for: .bonjour(type: bonjourServiceType, domain: nil), using: .tcp)

        browser.stateUpdateHandler = { state in
            Logger.info("Bonjour browser state: \(state)", category: .general)
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discoveredDevices = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return DiscoveredDevice(id: name, name: name, endpoint: result.endpoint)
                    }
                    return nil
                }
            }
        }

        browser.start(queue: .main)
        bonjourBrowser = browser
    }

    /// 停止搜索
    public func stopBonjourBrowsing() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        discoveredDevices = []
    }

    /// 发送所有平台 Cookie 到指定设备（iOS/macOS → tvOS）
    public func sendAllToDevice(_ device: DiscoveredDevice) async -> Bool {
        let sessions = await collectAllPlatformSessions()
        guard !sessions.isEmpty else { return false }

        let payload = MultiPlatformSyncPayload(
            sessions: sessions,
            deviceName: getDeviceName()
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return false }

        let sessionCount = sessions.count
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: device.endpoint, using: .tcp)
            let state = SendState()

            connection.stateUpdateHandler = { [state] connectionState in
                switch connectionState {
                case .ready:
                    connection.send(content: encoded, completion: .contentProcessed { [state] error in
                        guard !state.hasResumed else { return }
                        state.hasResumed = true
                        if let error = error {
                            Logger.warning("多平台发送失败: \(error)", category: .general)
                            continuation.resume(returning: false)
                        } else {
                            Logger.info("多平台发送成功 (\(sessionCount) 个平台)", category: .general)
                            continuation.resume(returning: true)
                        }
                        connection.cancel()
                    })
                case .failed(let error):
                    guard !state.hasResumed else { return }
                    state.hasResumed = true
                    Logger.warning("连接失败: \(error)", category: .general)
                    continuation.resume(returning: false)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: .main)
        }
    }

    /// 处理多平台 Bonjour 接收数据（tvOS 端调用）
    public func handleMultiPlatformSyncData(_ data: Data) async {
        // 先尝试解析为多平台格式
        if let payload = try? JSONDecoder().decode(MultiPlatformSyncPayload.self, from: data) {
            var appliedPlatformIds: [String] = []
            for session in payload.sessions {
                guard let pluginId = session.platformId, !pluginId.isEmpty else { continue }
                let result = await PlatformSessionManager.shared.loginWithCookie(
                    pluginId: pluginId,
                    cookie: session.cookie,
                    uid: session.uid,
                    source: .bonjour,
                    validateBeforeSave: true
                )
                if case .valid = result {
                    appliedPlatformIds.append(pluginId)
                }
            }
            if !appliedPlatformIds.isEmpty {
                lastBonjourSyncedPlatformIds = appliedPlatformIds
                lastBonjourSyncAt = Date()
            }
            await refreshAllLoginStatus()
            Logger.info("多平台局域网同步完成 (\(payload.sessions.count) 个平台)", category: .general)
            return
        }

        // 兼容旧格式：单个 SyncedCookieData
        if let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data) {
            guard let pluginId = syncedData.platformId ?? defaultLegacyPluginId() else { return }
            let result = await PlatformSessionManager.shared.loginWithCookie(
                pluginId: pluginId,
                cookie: syncedData.cookie,
                uid: syncedData.uid,
                source: .bonjour,
                validateBeforeSave: true
            )
            if case .valid = result {
                lastBonjourSyncedPlatformIds = [pluginId]
                lastBonjourSyncAt = Date()
            }
            await refreshAllLoginStatus()
        }
    }

    /// 手动设置 Cookie（tvOS 手动输入场景）
    public func setManualCookie(pluginId: String, cookie: String) async -> PlatformSessionValidationResult {
        // UID 提取：从 manifest loginFlow.uidCookieNames 遍历
        let uid = extractUid(from: cookie, pluginId: pluginId)
        let result = await PlatformSessionManager.shared.loginWithCookie(
            pluginId: pluginId,
            cookie: cookie,
            uid: uid,
            source: .manual,
            validateBeforeSave: true
        )
        await refreshLoginStatus(pluginId: pluginId)
        return result
    }

    /// 清除指定平台登录态
    public func clearSession(pluginId: String, clearICloud: Bool = true) async {
        await PlatformSessionManager.shared.clearSession(pluginId: pluginId)
        loggedInByPluginId[pluginId] = false

        if clearICloud {
            let container = CKContainer(identifier: CloudCookieFields.containerIdentifier)
            let database = container.privateCloudDatabase
            let recordName = CloudCookieFields.sessionRecordName(for: pluginId)
            let recordID = CKRecord.ID(recordName: recordName)
            do {
                try await database.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                // 不存在则忽略
            } catch {
                Logger.warning("清除 CloudKit session 失败 (\(pluginId)): \(error.localizedDescription)", category: .general)
            }
        }
    }

    /// 清除所有平台登录态
    public func clearAllSessions(clearICloud: Bool = true) async {
        let sessions = await PlatformSessionManager.shared.allSessions()
        for session in sessions {
            await clearSession(pluginId: session.pluginId, clearICloud: clearICloud)
        }
    }

    // MARK: - 收集平台 Sessions

    /// 收集所有已认证平台 session 数据（用于 Bonjour/iCloud 同步）
    public func collectAllPlatformSessions() async -> [SyncedCookieData] {
        let sessions = await PlatformSessionManager.shared.allSessions()
        let deviceName = getDeviceName()
        return sessions.compactMap { session in
            guard session.state == .authenticated,
                  let cookie = session.cookie, !cookie.isEmpty else {
                return nil
            }
            return SyncedCookieData(
                cookie: cookie,
                uid: session.uid,
                source: .local,
                deviceName: deviceName,
                platformId: session.pluginId
            )
        }
    }

    // MARK: - Private Helpers

    private func recordICloudSyncTime() {
        let now = Date()
        lastICloudSyncTime = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.lastICloudSyncTime)
    }

    /// 辅助类用于跟踪 Bonjour 发送状态
    private final class SendState: @unchecked Sendable {
        var hasResumed = false
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiveData(from: connection)
                }
            case .failed(let error):
                Logger.warning("Bonjour 连接失败: \(error)", category: .general)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    await self?.handleMultiPlatformSyncData(data)
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    /// 从 cookie 字符串提取 UID（根据 manifest loginFlow.uidCookieNames）
    private func extractUid(from cookie: String, pluginId: String) -> String? {
        // 常见 uid cookie 名作为 fallback
        let fallbackUidNames = ["DedeUserID", "uid", "user_id", "userId"]
        let uidNames = fallbackUidNames

        let pairs = cookie.components(separatedBy: "; ")
        for name in uidNames {
            for pair in pairs {
                let kv = pair.components(separatedBy: "=")
                if kv.count >= 2 && kv[0].trimmingCharacters(in: .whitespaces) == name {
                    return kv.dropFirst().joined(separator: "=")
                }
            }
        }
        return nil
    }

    /// 异步版本：从 manifest 获取 uidCookieNames 后提取 UID
    public func extractUidAsync(from cookie: String, pluginId: String) async -> String? {
        if let entry = await PlatformLoginRegistry.shared.entry(pluginId: pluginId),
           let names = entry.loginFlow.uidCookieNames, !names.isEmpty {
            let pairs = cookie.components(separatedBy: "; ")
            for name in names {
                for pair in pairs {
                    let kv = pair.components(separatedBy: "=")
                    if kv.count >= 2 && kv[0].trimmingCharacters(in: .whitespaces) == name {
                        return kv.dropFirst().joined(separator: "=")
                    }
                }
            }
            return nil
        }
        return extractUid(from: cookie, pluginId: pluginId)
    }

    /// 获取已知的云端 pluginId 列表（基于本地已知 session + 已安装插件）
    private func knownCloudPluginIds() async -> Set<String> {
        var ids = Set<String>()

        // 本地所有 session
        let sessions = await PlatformSessionManager.shared.allSessions()
        for session in sessions {
            ids.insert(session.pluginId)
        }

        // 已安装插件
        let installed = SandboxPluginCatalog.installedPluginIds()
        for id in installed {
            ids.insert(id)
        }

        return ids
    }

    /// 平台显示名（优先走 LiveParseTools，fallback 到 pluginId）
    private func displayName(for pluginId: String) -> String {
        // 尝试通过 liveType 获取平台名称
        if let liveType = LiveType(rawValue: pluginId) {
            return LiveParseTools.getLivePlatformName(liveType)
        }
        if let platform = LiveParseJSPlatformManager.platform(forPluginId: pluginId) {
            return LiveParseTools.getLivePlatformName(platform.liveType)
        }
        return pluginId
    }

    private func getDeviceName() -> String {
        #if os(tvOS)
        return UIDevice.current.name
        #elseif os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }

    // MARK: - 旧数据迁移

    /// 一次性迁移：manifest 声明的旧凭证数据 → 新服务
    private func performLegacyMigrationIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Keys.migrationDone) else { return }

        for platform in LiveParseJSPlatformManager.availablePlatforms {
            guard let migration = platform.sessionMigration,
                  let legacyCookie = firstLegacyString(forKeys: migration.userDefaultsCookieKeys),
                  !legacyCookie.isEmpty else {
                continue
            }
            let legacyUid = firstLegacyString(forKeys: migration.userDefaultsUIDKeys)
            if let existing = await PlatformSessionManager.shared.getSession(pluginId: platform.pluginId),
               existing.state == .authenticated,
               let cookie = existing.cookie, !cookie.isEmpty {
                continue
            }
            _ = await PlatformSessionManager.shared.loginWithCookie(
                pluginId: platform.pluginId,
                cookie: legacyCookie,
                uid: legacyUid,
                source: .legacy,
                validateBeforeSave: false
            )
        }

        for key in legacyCleanupKeys() {
            UserDefaults.standard.removeObject(forKey: key)
        }

        UserDefaults.standard.set(true, forKey: Keys.migrationDone)
        Logger.info("旧凭证数据迁移完成", category: .general)
    }

    private func migrateLegacyCloudRecords(database: CKDatabase) async {
        for platform in LiveParseJSPlatformManager.availablePlatforms {
            guard let recordNames = platform.sessionMigration?.legacyCloudRecordNames else { continue }
            for recordName in recordNames {
                await migrateLegacyCloudRecord(
                    database: database,
                    legacyRecordName: recordName,
                    pluginId: platform.pluginId
                )
            }
        }
    }

    private func migrateLegacyCloudRecord(database: CKDatabase, legacyRecordName: String, pluginId: String) async {
        let legacyRecordID = CKRecord.ID(recordName: legacyRecordName)
        let newRecordName = CloudCookieFields.sessionRecordName(for: pluginId)
        let newRecordID = CKRecord.ID(recordName: newRecordName)

        do {
            let legacyRecord = try await database.record(for: legacyRecordID)
            guard let data = legacyRecord[CloudCookieFields.cookieDataField] as? Data else { return }

            // 如果新 record 已存在且更新，跳过
            if let newRecord = try? await database.record(for: newRecordID),
               let newDate = newRecord[CloudCookieFields.updatedAtField] as? Date,
               let oldDate = legacyRecord[CloudCookieFields.updatedAtField] as? Date,
               newDate >= oldDate {
                // 新记录���新，删除旧记录即可
            } else {
                // 复制到新 record
                let newRecord = CKRecord(recordType: CloudCookieFields.recordType, recordID: newRecordID)
                newRecord[CloudCookieFields.cookieDataField] = data as NSData
                newRecord[CloudCookieFields.platformIdField] = pluginId as NSString
                newRecord[CloudCookieFields.updatedAtField] = legacyRecord[CloudCookieFields.updatedAtField]
                _ = try await database.save(newRecord)
            }

            // 删除旧记录
            try await database.deleteRecord(withID: legacyRecordID)
            Logger.info("已迁移旧 CloudKit 记录到新命名", category: .general)
        } catch let error as CKError where error.code == .unknownItem {
            // 旧记录不存在，无需迁移
        } catch {
            Logger.warning("迁移旧 CloudKit 记录失败: \(error.localizedDescription)", category: .general)
        }
    }

    private static func legacyMigrationKey(_ keyPath: KeyPath<ManifestSessionMigration, [String]?>) -> String? {
        LiveParseJSPlatformManager.availablePlatforms
            .lazy
            .compactMap { $0.sessionMigration?[keyPath: keyPath] }
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func legacyCloudRecordNames() -> [String] {
        LiveParseJSPlatformManager.availablePlatforms
            .compactMap { $0.sessionMigration?.legacyCloudRecordNames }
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func legacyCleanupKeys() -> [String] {
        LiveParseJSPlatformManager.availablePlatforms
            .compactMap { $0.sessionMigration?.cleanupUserDefaultsKeys }
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func firstLegacyString(forKeys keys: [String]?) -> String? {
        keys?
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { UserDefaults.standard.string(forKey: $0) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func defaultLegacyPluginId() -> String? {
        LiveParseJSPlatformManager.availablePlatforms.first { platform in
            platform.sessionMigration?.userDefaultsCookieKeys?.isEmpty == false ||
            platform.sessionMigration?.legacyCloudRecordNames?.isEmpty == false
        }?.pluginId
    }
}
