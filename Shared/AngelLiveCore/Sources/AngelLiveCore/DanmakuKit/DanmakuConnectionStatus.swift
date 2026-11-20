import Foundation

public enum DanmakuConnectionStatus: Sendable, Equatable {
    case connecting
    case connected
    case reconnecting
    case failed

    public var title: String {
        switch self {
        case .connecting: String(localized: "正在连接弹幕")
        case .connected: String(localized: "弹幕已连接")
        case .reconnecting: String(localized: "正在重新连接")
        case .failed: String(localized: "弹幕连接失败")
        }
    }

    public var visibleDuration: Duration? {
        switch self {
        case .connecting: nil
        case .connected: .milliseconds(1500)
        case .reconnecting, .failed: .seconds(4)
        }
    }
}
