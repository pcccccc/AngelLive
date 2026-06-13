//
//  KSPlayerConsoleBridge.swift
//  AngelLive
//
//  将 KSPlayer 的 KSLog 输出同时打印到 Xcode 控制台(OSLog)和 App 内开发者控制台
//  (PluginConsoleService),方便在 TestFlight 等无线设备上排查播放问题。
//

import Foundation
import AngelLiveCore
import AngelLiveDependencies
import KSPlayer
import os

final class KSPlayerConsoleBridge: LogHandler, @unchecked Sendable {

    private let label: String
    private let osLogger: os.Logger
    private let formatter: DateFormatter

    init(label: String = "KSPlayer") {
        self.label = label
        self.osLogger = os.Logger(subsystem: "com.angellive.player", category: label)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        self.formatter = formatter
    }

    func log(level: KSPlayer.LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        let text = message.description
        let location = "\(file):\(line) \(function)"
        let timestamp = formatter.string(from: Date())

        // 1) 输出到 Xcode 控制台 / OSLog,保持与默认 KSPlayer.OSLog 一致的可见性。
        switch level {
        case .panic, .fatal, .error:
            osLogger.error("\(timestamp, privacy: .public) \(level.description, privacy: .public) \(location, privacy: .public) | \(text, privacy: .public)")
        case .warning:
            osLogger.warning("\(timestamp, privacy: .public) \(level.description, privacy: .public) \(location, privacy: .public) | \(text, privacy: .public)")
        case .info:
            osLogger.info("\(timestamp, privacy: .public) \(level.description, privacy: .public) \(location, privacy: .public) | \(text, privacy: .public)")
        default:
            osLogger.debug("\(timestamp, privacy: .public) \(level.description, privacy: .public) \(location, privacy: .public) | \(text, privacy: .public)")
        }

        // 2) 转发到 App 内开发者控制台。PluginConsoleService 的写入需在 MainActor。
        let status: PluginConsoleEntryStatus
        switch level {
        case .panic, .fatal, .error:
            status = .error
        default:
            status = .success
        }

        let tag = label
        let method = "\(level.description) · \(function)"
        let requestBody = "\(file):\(line)"
        let responseBody = text

        Task { @MainActor in
            let service = PluginConsoleService.shared
            let id = service.log(tag: tag, method: method, status: status)
            service.updateRequest(id: id, body: requestBody)
            service.updateStatus(
                id: id,
                status: status,
                duration: nil,
                responseBody: responseBody,
                errorMessage: status == .error ? text : nil
            )
        }
    }
}
