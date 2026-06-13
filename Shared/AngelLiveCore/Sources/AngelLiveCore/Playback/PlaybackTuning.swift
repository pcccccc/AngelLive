import Foundation

/// 播放恢复(watchdog)相关的调参常量,三端共享一份,避免散落漂移。
///
/// 旧实现把这些常量在三端 ViewModel/View 各写一份(stall=8s、起播=20/12s 等),
/// 这里统一收口。具体每端的差异(如起播超时 iOS 20s、桌面/TV 12s)通过
/// `RecoveryConfig` 工厂方法注入,而非散在各端。
public enum PlaybackTuning {
    /// 采样心跳间隔(1Hz)。
    public static let tickInterval: TimeInterval = 1.0

    /// playhead 推进容差:一个 tick 内推进超过该秒数才算"在走"。
    public static let playheadProgressTolerance: TimeInterval = 0.5

    /// 起播阶段 bytes 进度门:起播超时时,若较基线累计读到超过该字节数,视为"网络在动",不误杀。
    public static let startupBytesProgressThreshold: Int64 = 16 * 1024

    /// 零吞吐 stall 判定阈值。抬高于旧的 8s —— 8s < 单个 HLS 分片时长会把正常大分片流误判。
    /// 这里取一个远大于 8s 的下限;真正的自适应(按观测分片间隔)可后续接入。
    public static let stallThresholdSeconds: TimeInterval = 12

    /// ★ 修 Bug B 的关键:只有"连续健康 N 秒 playhead 单调推进"才清零熔断预算。
    /// 短暂 readyToPlay 不再清零,抖动流会消耗预算 → 循环有终点。
    public static let healthyConfirmSeconds: TimeInterval = 20

    /// 起播超时(首帧):iOS 现状 20s。
    public static let startupTimeoutPhone: TimeInterval = 20

    /// 起播超时(首帧):macOS / tvOS 现状 12s。
    public static let startupTimeoutDesktopTV: TimeInterval = 12
}

/// 协调器配置。每端构造时按平台/内核注入,保持现有行为(不强行统一三端差异)。
public struct RecoveryConfig: Sendable {
    /// 起播首帧超时秒数。
    public var startupTimeout: TimeInterval
    /// 起播 bytes 进度门。
    public var startupBytesProgressThreshold: Int64
    /// 零吞吐 stall 阈值。
    public var stallThresholdSeconds: TimeInterval
    /// playhead 推进容差。
    public var playheadProgressTolerance: TimeInterval
    /// 连续健康多少秒后清零熔断预算。
    public var healthyConfirmSeconds: TimeInterval
    /// 采样心跳间隔。
    public var tickInterval: TimeInterval
    /// 是否启用零吞吐 stall 监控。KSAVPlayer / VLC 路径有清晰 `.failed` 走 fallback,关掉避免误判。
    public var stallMonitoringEnabled: Bool
    /// 升级阶梯是否包含 kickPipeline(play-pause-play hack)首档。当前内核路径若无此 hack 则置 false。
    public var hasKickPipeline: Bool

    public init(
        startupTimeout: TimeInterval,
        startupBytesProgressThreshold: Int64 = PlaybackTuning.startupBytesProgressThreshold,
        stallThresholdSeconds: TimeInterval = PlaybackTuning.stallThresholdSeconds,
        playheadProgressTolerance: TimeInterval = PlaybackTuning.playheadProgressTolerance,
        healthyConfirmSeconds: TimeInterval = PlaybackTuning.healthyConfirmSeconds,
        tickInterval: TimeInterval = PlaybackTuning.tickInterval,
        stallMonitoringEnabled: Bool,
        hasKickPipeline: Bool = false
    ) {
        self.startupTimeout = startupTimeout
        self.startupBytesProgressThreshold = startupBytesProgressThreshold
        self.stallThresholdSeconds = stallThresholdSeconds
        self.playheadProgressTolerance = playheadProgressTolerance
        self.healthyConfirmSeconds = healthyConfirmSeconds
        self.tickInterval = tickInterval
        self.stallMonitoringEnabled = stallMonitoringEnabled
        self.hasKickPipeline = hasKickPipeline
    }

    /// iOS:起播 20s。`stallMonitoringEnabled` 由内核决定(KSME 主路 true;KSAV/VLC false)。
    public static func phone(stallMonitoringEnabled: Bool, hasKickPipeline: Bool = false) -> RecoveryConfig {
        RecoveryConfig(
            startupTimeout: PlaybackTuning.startupTimeoutPhone,
            stallMonitoringEnabled: stallMonitoringEnabled,
            hasKickPipeline: hasKickPipeline
        )
    }

    /// macOS / tvOS:起播 12s。
    public static func desktopTV(stallMonitoringEnabled: Bool, hasKickPipeline: Bool = false) -> RecoveryConfig {
        RecoveryConfig(
            startupTimeout: PlaybackTuning.startupTimeoutDesktopTV,
            stallMonitoringEnabled: stallMonitoringEnabled,
            hasKickPipeline: hasKickPipeline
        )
    }
}
