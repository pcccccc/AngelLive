import Foundation

public enum PlaybackStartupStage: Sendable, Equatable {
    case fetchingSource, connecting, buffering

    public var title: String {
        switch self {
        case .fetchingSource: "获取播放地址"
        case .connecting: "正在连接"
        case .buffering: "正在缓冲"
        }
    }
}

public struct PlaybackRecoveryNotice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let action: RecoveryActionKind
    public let attempt: Int
    public let limit: Int

    public init(id: UUID = UUID(), action: RecoveryActionKind, attempt: Int, limit: Int) {
        self.id = id
        self.action = action
        self.attempt = attempt
        self.limit = limit
    }

    public var title: String {
        let actionTitle: String
        switch action {
        case .reloadPlayArgs: actionTitle = "正在重新获取播放地址"
        case .switchCDN: actionTitle = "正在切换线路"
        case .refreshSameURL: actionTitle = "正在重新连接"
        case .kickPipeline: actionTitle = "正在恢复播放"
        }
        return "\(actionTitle)（\(attempt)/\(limit)）"
    }
}

/// A sanitized observer of the existing recovery state machine, not a second driver.
public enum PlaybackRecoveryObservation: Sendable {
    case sample(PlaybackSample)
    case recovering(action: RecoveryActionKind, attempt: Int, limit: Int,
                    startupFailure: PlaybackStartupFailureCode?)
    case exhausted(startupFailure: PlaybackStartupFailureCode?)
}
