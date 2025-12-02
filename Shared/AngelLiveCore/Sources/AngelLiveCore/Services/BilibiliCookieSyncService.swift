//
//  BilibiliCookieSyncService.swift
//  AngelLiveCore
//
//  Created by pangchong on 2024/11/28.
//

import Foundation
import LiveParse
import Network
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Cookie 同步数据模型

/// Cookie 同步来源
public enum CookieSyncSource: String, Codable {
    case local = "local"           // 本地（扫码登录）
    case iCloud = "icloud"         // iCloud 同步
    case bonjour = "bonjour"       // 局域网同步
    case manual = "manual"         // 手动输入
}

/// 同步的 Cookie 数据
public struct SyncedCookieData: Codable {
    public let cookie: String
    public let uid: String?
    public let timestamp: Date
    public let source: CookieSyncSource
    public let deviceName: String?

    public init(cookie: String, uid: String?, timestamp: Date = Date(), source: CookieSyncSource, deviceName: String? = nil) {
        self.cookie = cookie
        self.uid = uid
        self.timestamp = timestamp
        self.source = source
        self.deviceName = deviceName
    }
}

/// Cookie 验证结果
public enum CookieValidationResult {
    case valid
    case invalid(reason: String)
    case expired
    case networkError(Error)
}

// MARK: - Bilibili Cookie 同步服务

@MainActor
public final class BilibiliCookieSyncService: ObservableObject {
    public static let shared = BilibiliCookieSyncService()

    // MARK: - Published Properties

    @Published public var isValidating = false
    @Published public var isSyncing = false
    @Published public var lastValidationResult: CookieValidationResult?
    @Published public var lastSyncedData: SyncedCookieData?
    @Published public var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
        }
    }

    // MARK: - Bonjour 相关

    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isBonjourListening = false

    // MARK: - Private Properties

    private enum Keys {
        static let cookieKey = "SimpleLive.Setting.BilibiliCookie"
        static let uidKey = "LiveParse.Bilibili.uid"
        static let lastSyncedDataKey = "BilibiliCookieSyncService.lastSyncedData"
        static let iCloudSyncEnabled = "BilibiliCookieSyncService.iCloudSyncEnabled"
        static let iCloudCookieKey = "bilibili_cookie_sync"
    }

    private var bonjourListener: NWListener?
    private var bonjourBrowser: NWBrowser?

    // MARK: - Init

    private init() {
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)

        // 加载上次同步数据
        if let data = UserDefaults.standard.data(forKey: Keys.lastSyncedDataKey),
           let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data) {
            self.lastSyncedData = syncedData
        }

        // 监听 iCloud 变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )

        // 启动 iCloud 同步
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Cookie 有效性验证

    /// 验证 Cookie 是否有效（通过调用 Bilibili.getRoomList）
    public func validateCookie(_ cookie: String? = nil) async -> CookieValidationResult {
        isValidating = true
        defer { isValidating = false }

        let cookieToValidate = cookie ?? getCurrentCookie()

        guard !cookieToValidate.isEmpty else {
            let result = CookieValidationResult.invalid(reason: "Cookie 为空")
            lastValidationResult = result
            return result
        }

        // 临时设置 cookie 进行验证
        let originalCookie = getCurrentCookie()
        if cookie != nil {
            setCookie(cookieToValidate, uid: nil, source: .local, save: false)
        }

        do {
            // 使用 getRoomList 验证 - 这是最严格的验证方式
            let rooms = try await Bilibili.getRoomList(id: "0", parentId: "2", page: 1)

            // 恢复原始 cookie（如果是临时验证）
            if cookie != nil && cookie != originalCookie {
                setCookie(originalCookie, uid: nil, source: .local, save: false)
            }

            if rooms.isEmpty {
                let result = CookieValidationResult.invalid(reason: "无法获取房间列表")
                lastValidationResult = result
                return result
            }

            let result = CookieValidationResult.valid
            lastValidationResult = result
            return result
        } catch {
            // 恢复原始 cookie
            if cookie != nil && cookie != originalCookie {
                setCookie(originalCookie, uid: nil, source: .local, save: false)
            }

            let errorMessage = error.localizedDescription.lowercased()

            // 判断是否为过期错误
            if errorMessage.contains("expired") || errorMessage.contains("过期") ||
               errorMessage.contains("invalid") || errorMessage.contains("无效") {
                let result = CookieValidationResult.expired
                lastValidationResult = result
                return result
            }

            let result = CookieValidationResult.networkError(error)
            lastValidationResult = result
            return result
        }
    }

    /// 检查当前 Cookie 状态
    public func checkCurrentCookieStatus() async -> CookieValidationResult {
        return await validateCookie()
    }

    // MARK: - Cookie 管理

    /// 获取当前 Cookie
    public func getCurrentCookie() -> String {
        UserDefaults.standard.string(forKey: Keys.cookieKey) ?? ""
    }

    /// 获取当前 UID
    public func getCurrentUid() -> String? {
        UserDefaults.standard.string(forKey: Keys.uidKey)
    }

    /// 设置 Cookie
    public func setCookie(_ cookie: String, uid: String?, source: CookieSyncSource, save: Bool = true) {
        UserDefaults.standard.set(cookie, forKey: Keys.cookieKey)
        if let uid = uid {
            UserDefaults.standard.set(uid, forKey: Keys.uidKey)
        }

        if save {
            let syncedData = SyncedCookieData(
                cookie: cookie,
                uid: uid,
                source: source,
                deviceName: getDeviceName()
            )
            saveSyncedData(syncedData)

            // 如果启用了 iCloud 同步，同步到 iCloud
            if iCloudSyncEnabled && source != .iCloud {
                syncToICloud(syncedData)
            }
        }
    }

    /// 清除 Cookie
    public func clearCookie() {
        UserDefaults.standard.removeObject(forKey: Keys.cookieKey)
        UserDefaults.standard.removeObject(forKey: Keys.uidKey)
        UserDefaults.standard.removeObject(forKey: Keys.lastSyncedDataKey)
        lastSyncedData = nil
        lastValidationResult = nil
    }

    /// 是否已登录（检查 Cookie 中是否包含 SESSDATA）
    public var isLoggedIn: Bool {
        getCurrentCookie().contains("SESSDATA")
    }

    // MARK: - iCloud 同步

    /// 同步到 iCloud
    public func syncToICloud(_ data: SyncedCookieData? = nil) {
        let syncData = data ?? SyncedCookieData(
            cookie: getCurrentCookie(),
            uid: getCurrentUid(),
            source: .local,
            deviceName: getDeviceName()
        )

        guard !syncData.cookie.isEmpty else { return }

        if let encoded = try? JSONEncoder().encode(syncData) {
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: Keys.iCloudCookieKey)
            NSUbiquitousKeyValueStore.default.synchronize()
            print("[BilibiliCookieSyncService] 已同步到 iCloud")
        }
    }

    /// 从 iCloud 获取 Cookie
    public func fetchFromICloud() async -> SyncedCookieData? {
        NSUbiquitousKeyValueStore.default.synchronize()

        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Keys.iCloudCookieKey),
              let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data) else {
            return nil
        }

        return syncedData
    }

    /// 从 iCloud 同步并验证
    public func syncFromICloud() async -> Bool {
        isSyncing = true
        defer { isSyncing = false }

        guard let syncedData = await fetchFromICloud() else {
            print("[BilibiliCookieSyncService] iCloud 中没有 Cookie")
            return false
        }

        // 验证 Cookie
        let result = await validateCookie(syncedData.cookie)

        switch result {
        case .valid:
            setCookie(syncedData.cookie, uid: syncedData.uid, source: .iCloud)
            print("[BilibiliCookieSyncService] 从 iCloud 同步成功")
            return true
        default:
            print("[BilibiliCookieSyncService] iCloud Cookie 无效")
            return false
        }
    }

    @objc private func iCloudDidChange(_ notification: Notification) {
        guard iCloudSyncEnabled else { return }

        Task { @MainActor in
            _ = await syncFromICloud()
        }
    }

    // MARK: - 局域网同步 (Bonjour)

    /// 发现的设备
    public struct DiscoveredDevice: Identifiable, Hashable {
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

    /// 服务类型
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
                        print("[BilibiliCookieSyncService] Bonjour 监听已启动")
                    case .failed(let error):
                        print("[BilibiliCookieSyncService] Bonjour 监听失败: \(error)")
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
            print("[BilibiliCookieSyncService] 创建 Bonjour 监听失败: \(error)")
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
            print("[BilibiliCookieSyncService] Browser state: \(state)")
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
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

    /// 发送 Cookie 到指定设备（iOS/macOS 端）
    public func sendCookieToDevice(_ device: DiscoveredDevice) async -> Bool {
        // 先在 MainActor 上获取数据
        let cookie = getCurrentCookie()
        let uid = getCurrentUid()
        let deviceName = getDeviceName()

        let syncData = SyncedCookieData(
            cookie: cookie,
            uid: uid,
            source: .bonjour,
            deviceName: deviceName
        )

        guard let encoded = try? JSONEncoder().encode(syncData) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: device.endpoint, using: .tcp)
            let state = SendState()

            connection.stateUpdateHandler = { [state] connectionState in
                switch connectionState {
                case .ready:
                    // 连接成功，发送数据
                    connection.send(content: encoded, completion: .contentProcessed { [state] error in
                        guard !state.hasResumed else { return }
                        state.hasResumed = true
                        if let error = error {
                            print("[BilibiliCookieSyncService] 发送失败: \(error)")
                            continuation.resume(returning: false)
                        } else {
                            print("[BilibiliCookieSyncService] 发送成功")
                            continuation.resume(returning: true)
                        }
                        connection.cancel()
                    })
                case .failed(let error):
                    guard !state.hasResumed else { return }
                    state.hasResumed = true
                    print("[BilibiliCookieSyncService] 连接失败: \(error)")
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

    /// 用于跟踪发送状态的辅助类
    private final class SendState: @unchecked Sendable {
        var hasResumed = false
    }

    /// 处理传入连接（tvOS 端）
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiveData(from: connection)
                }
            case .failed(let error):
                print("[BilibiliCookieSyncService] 连接失败: \(error)")
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    /// 接收数据
    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let syncedData = try? JSONDecoder().decode(SyncedCookieData.self, from: data) {
                    Task { @MainActor in
                        // 验证并保存
                        let result = await self?.validateCookie(syncedData.cookie)
                        if case .valid = result {
                            self?.setCookie(syncedData.cookie, uid: syncedData.uid, source: .bonjour)
                            print("[BilibiliCookieSyncService] 局域网同步成功")
                        }
                    }
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    // MARK: - 手动输入

    /// 手动设置 Cookie
    public func setManualCookie(_ cookie: String) async -> CookieValidationResult {
        let result = await validateCookie(cookie)

        if case .valid = result {
            // 尝试从 cookie 中提取 uid
            let uid = extractUidFromCookie(cookie)
            setCookie(cookie, uid: uid, source: .manual)
        }

        return result
    }

    /// 从 Cookie 字符串中提取 UID
    private func extractUidFromCookie(_ cookie: String) -> String? {
        let pairs = cookie.components(separatedBy: "; ")
        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            if keyValue.count == 2 && keyValue[0] == "DedeUserID" {
                return keyValue[1]
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    private func saveSyncedData(_ data: SyncedCookieData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Keys.lastSyncedDataKey)
        }
        lastSyncedData = data
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
}

// MARK: - 便捷扩展

public extension BilibiliCookieSyncService {
    /// 获取登录状态描述
    var loginStatusDescription: String {
        if !isLoggedIn {
            return "未登录"
        }

        guard let lastSync = lastSyncedData else {
            return "已登录"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let sourceDesc: String
        switch lastSync.source {
        case .local:
            sourceDesc = "扫码登录"
        case .iCloud:
            sourceDesc = "iCloud 同步"
        case .bonjour:
            sourceDesc = "局域网同步"
        case .manual:
            sourceDesc = "手动输入"
        }

        return "\(sourceDesc) · \(formatter.string(from: lastSync.timestamp))"
    }
}
