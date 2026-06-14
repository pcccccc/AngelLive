//
//  Logger.swift
//  AngelLiveCore
//
//  统一的日志系统，替代散落的 print 语句。
//
//  用法:
//      Logger.debug("[StateProbe] ...", category: .player)
//      Logger.error(err, message: "拉取失败", category: .network)
//
//  按分类过滤(运行时可改,不必重编译):
//      Logger.setLevel(.warning, for: .player)   // player 只留 warning/error,杀掉 1Hz 探针
//      Logger.mute(.ui)                          // 彻底静音 ui
//      Logger.unmute(.ui)
//      Logger.muteAll(except: [.network])        // 只看网络
//      Logger.resetAllLevels()                   // 回到全局 minimumLevel
//

import Foundation
import os.log

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
#endif
}

/// 日志级别
public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

/// 日志分类。每条日志都归属一个分类,可按分类独立调级别或静音。
public enum LogCategory: String, CaseIterable, Sendable {
    case player = "Player"        // 播放内核/状态/探针: KSPlayer / PlayerFlow / StateProbe
    case danmu = "Danmu"          // 弹幕
    case network = "Network"      // 网络请求: ApiManager 等
    case favorite = "Favorite"    // 收藏: FavoriteSync / FavoriteDedup
    case cloudKit = "CloudKit"    // iCloud / CloudKit
    case sync = "Sync"            // 跨设备/插件同步: PluginSync / RemoteInput / SyncSocket
    case plugin = "Plugin"        // JS 插件: JSRuntime / PluginManager / LiveParse
    case ui = "UI"                // 视图/动画/HUD: Pow / VolumeHUD
    case app = "App"              // App 生命周期/入口 / TopShelf
    case general = "General"      // 未分类
}

/// 统一的日志工具
public enum Logger {

    /// 全局最低日志级别,某分类未单独设级别时回退到这里。
    #if DEBUG
    nonisolated(unsafe) public static var minimumLevel: LogLevel = .debug
    #else
    nonisolated(unsafe) public static var minimumLevel: LogLevel = .warning
    #endif

    /// 总开关,关掉后所有分类都不输出。
    nonisolated(unsafe) public static var isEnabled: Bool = true

    // MARK: - 按分类过滤配置

    /// 各分类单独覆盖的最低级别;未配置的分类用 `minimumLevel`。
    nonisolated(unsafe) private static var categoryLevels: [LogCategory: LogLevel] = [:]
    /// 被静音的分类(硬关,连 error 也不输出)。
    nonisolated(unsafe) private static var mutedCategories: Set<LogCategory> = []
    /// 保护上面两个集合的并发读写(配置一般只在启动时改,日志路径只读)。
    private static let configLock = NSLock()

    /// 给某分类设最低级别(覆盖全局)。例: `setLevel(.warning, for: .player)`。
    public static func setLevel(_ level: LogLevel, for category: LogCategory) {
        configLock.withLock { categoryLevels[category] = level }
    }

    /// 批量给多个分类设最低级别。
    public static func setLevel(_ level: LogLevel, for categories: [LogCategory]) {
        configLock.withLock { for c in categories { categoryLevels[c] = level } }
    }

    /// 取消某分类的级别覆盖,回退到全局 `minimumLevel`。
    public static func resetLevel(for category: LogCategory) {
        configLock.withLock { categoryLevels[category] = nil }
    }

    /// 清空所有分类的级别覆盖与静音,全部回到全局 `minimumLevel`。
    public static func resetAllLevels() {
        configLock.withLock { categoryLevels.removeAll(); mutedCategories.removeAll() }
    }

    /// 静音某分类(硬关,任何级别都不输出)。
    public static func mute(_ category: LogCategory) {
        configLock.withLock { _ = mutedCategories.insert(category) }
    }

    /// 解除某分类静音。
    public static func unmute(_ category: LogCategory) {
        configLock.withLock { _ = mutedCategories.remove(category) }
    }

    /// 静音除指定分类外的所有分类。例: 排查网络时 `muteAll(except: [.network])`。
    public static func muteAll(except keep: [LogCategory] = []) {
        let keepSet = Set(keep)
        configLock.withLock { mutedCategories = Set(LogCategory.allCases).subtracting(keepSet) }
    }

    // MARK: - 便捷方法

    /// 调试日志
    public static func debug(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, line: line)
    }

    /// 信息日志
    public static func info(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(message, level: .info, category: category, file: file, line: line)
    }

    /// 警告日志
    public static func warning(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, line: line)
    }

    /// 错误日志
    public static func error(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(message, level: .error, category: category, file: file, line: line)
    }

    /// 错误日志（带 Error 对象）
    public static func error(_ error: Error, message: String? = nil, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        let errorMessage = message.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        log(errorMessage, level: .error, category: category, file: file, line: line)
    }

    // MARK: - 核心日志方法

    private static func log(_ message: String, level: LogLevel, category: LogCategory, file: String, line: Int) {
        guard isEnabled else { return }

        // 取该分类的有效阈值 + 静音判定(加锁读,避免与配置写并发崩溃)。
        let (muted, threshold): (Bool, LogLevel) = configLock.withLock {
            (mutedCategories.contains(category), categoryLevels[category] ?? minimumLevel)
        }
        guard !muted, level >= threshold else { return }

        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.emoji) [\(category.rawValue)] \(message)"

        #if DEBUG
        // Debug 模式下输出到控制台，包含文件和行号
        print("\(logMessage) (\(fileName):\(line))")
        #else
        // Release 模式下使用 os_log
        let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.angellive", category: category.rawValue)
        os_log("%{public}@", log: osLog, type: level.osLogType, message)
        #endif
    }
}
