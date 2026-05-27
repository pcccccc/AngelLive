import Foundation
import Bugsnag

public enum BugsnagPlatform: String, Sendable {
    case iOS = "iOS"
    case macOS = "macOS"
    case tvOS = "tvOS"
}

/// 三端共用的 Bugsnag 启动 / 元数据写入入口。
///
/// - DEBUG 构建完全跳过启动,本地崩溃不上报。
/// - Release 构建按 App Store / TestFlight / 自签 (Developer ID 或 Ad-hoc) 自动设置 releaseStage。
/// - API key 走同模块内的 `BugsnagSecrets.swift`(已 gitignore),按平台分发。
public enum BugsnagBootstrap {

    private static let liveSectionKey = "live"
    private static let playbackSectionKey = "playback"

    public static func start(platform: BugsnagPlatform) {
#if DEBUG
        _ = platform
#else
        guard let apiKey = BugsnagSecrets.apiKey(for: platform),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // 没配 key 时静默跳过,避免污染 dashboard
            return
        }

        let config = BugsnagConfiguration(apiKey)
        config.releaseStage = currentReleaseStage()
        config.addMetadata(platform.rawValue, key: "platform", section: "app")
        Bugsnag.start(with: config)
#endif
    }

    /// 进入某直播房间时调用。roomID 已脱敏:这里只是把上游传进来的字符串写进 metadata,
    /// 调用方负责确保不含真实用户标识。
    public static func setLiveContext(platform: String?, roomID: String?) {
#if !DEBUG
        Bugsnag.addMetadata(platform as Any, key: "platform", section: liveSectionKey)
        Bugsnag.addMetadata(roomID as Any, key: "roomID", section: liveSectionKey)
#endif
    }

    /// 当前播放内核:KSPlayer / KSMEPlayer / AVPlayer / VLC 等。
    public static func setPlayerKernel(_ kernel: String?) {
#if !DEBUG
        Bugsnag.addMetadata(kernel as Any, key: "kernel", section: playbackSectionKey)
#endif
    }

    /// 离开播放页 / 换房间时清掉,避免错误的上下文跟随后续崩溃。
    public static func clearLiveContext() {
#if !DEBUG
        Bugsnag.clearMetadata(section: liveSectionKey)
        Bugsnag.clearMetadata(section: playbackSectionKey)
#endif
    }

    // MARK: - Private

    private static func currentReleaseStage() -> String {
        guard let url = Bundle.main.appStoreReceiptURL else {
            // macOS Developer ID / Ad-hoc 等非商店分发
            return "production"
        }
        switch url.lastPathComponent {
        case "sandboxReceipt": return "testflight"
        case "receipt":        return "production"
        default:               return "production"
        }
    }
}
