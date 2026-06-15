//
//  PlaybackRecoveryAdapter.swift
//  AngelLiveDependencies
//
//  把 AngelLiveCore 的纯算法协调器(PlaybackRecoveryCoordinator)接到 KSPlayer 上的「胶水层」。
//
//  分层背景:
//  - AngelLiveCore 的 PlaybackRecoveryCoordinator 是纯状态机,故意不依赖 KSPlayer,可单测、三端共享。
//  - 但「从 KSPlayerLayer 读采样」「KSPlayerState → 抽象状态」「把 VM 动作包成 RecoveryActions」这层
//    与内核绑定,进不了 Core。本文件就是这层,放在三端都 import 的 AngelLiveDependencies 里,
//    于是三端 VM 不再各写一份,只需 conform 一个协议 + 传一份平台 config。
//
//  KSPlayer / VLC 双内核:本包在 USE_VLC=1 时用 KSPlayerFallback 的 shim 类型(无 bytesRead 等),
//  所以凡是读 KSPlayer 私有字段的代码都用 `#if canImport(KSPlayer)` 收口,VLC 模式走降级实现。
//

import Foundation
import AngelLiveCore

// MARK: - Host 协议

/// 播放恢复协调器对宿主 VM 的要求。三端 VM 已有这些成员(签名一致),conform 即可,无需新增适配代码。
///
/// 标 `@MainActor`:协调器的恢复动作都在主线程触发,这里统一隔离,免去各调用点的 hop。
@MainActor
public protocol PlaybackRecoveryHost: AnyObject {
    /// 当前监视的播放层,供 1Hz 采样读取 dynamicInfo / playhead。
    var watchedPlayerLayer: KSPlayerLayer? { get }
    /// 当前线路索引。
    var currentCdnIndex: Int { get }
    /// 当前清晰度索引。
    var currentQualityIndex: Int { get }
    /// 切到指定线路/清晰度(= switchCDN / refreshSameURL 的落地动作)。
    func changePlayUrl(cdnIndex: Int, urlIndex: Int)
    /// 重新拉取播放参数(= reloadPlayArgs)。
    func refreshPlayback()
    /// 下一条可用线路;仅 1 条时返回 nil(由协调器回退 refresh)。
    func nextCdnIndex() -> Int?
    /// 恢复预算用尽:检查直播状态并落地错误页/下播判定。
    func checkLiveStatusOnError(error: Error)
}

// MARK: - 工厂

public enum PlaybackRecoveryFactory {

    /// 用宿主 VM + 平台 config 组装协调器。三端共用此工厂,平台差异只在传入的 config。
    ///
    /// - Parameters:
    ///   - host: 宿主 VM(弱引用捕获,不形成环)。
    ///   - config: 平台调参,iOS 传 `.phone(...)`、macOS/tvOS 传 `.desktopTV(...)`。
    @MainActor
    public static func make(
        host: PlaybackRecoveryHost,
        config: RecoveryConfig
    ) -> PlaybackRecoveryCoordinator {
        let actions = RecoveryActions(
            refreshSameURL: { [weak host] in
                guard let host else { return }
                host.changePlayUrl(cdnIndex: host.currentCdnIndex, urlIndex: host.currentQualityIndex)
            },
            switchCDN: { [weak host] in
                guard let host else { return }
                if let next = host.nextCdnIndex() {
                    host.changePlayUrl(cdnIndex: next, urlIndex: 0)
                } else {
                    host.refreshPlayback()   // 单 CDN 无可切,回退同源刷新
                }
            },
            reloadPlayArgs: { [weak host] in
                host?.refreshPlayback()
            },
            reportFailed: { [weak host] reason in
                guard let host else { return }
                let error = NSError(
                    domain: "AngelLive.Player.Recovery",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )
                host.checkLiveStatusOnError(error: error)
            }
        )
        return PlaybackRecoveryCoordinator(
            config: config,
            actions: actions,
            sample: { [weak host] in host?.currentPlaybackSample() }
        )
    }
}

// MARK: - 采样 / 状态映射(内核绑定,VLC 模式降级)

public extension PlaybackRecoveryHost {

    /// 协调器 1Hz 采样源。
    /// KSAVPlayer 返回 nil(bytesRead 仅 segment 边界跳变会误判,且出错有清晰 .failed 走 fallback),
    /// 与旧 watchdog 的 KSAV 豁免一致。VLC 内核(无 KSPlayer)同样返回 nil。
    func currentPlaybackSample() -> PlaybackSample? {
        #if canImport(KSPlayer)
        guard let player = watchedPlayerLayer?.player else { return nil }
        if player is KSAVPlayer { return nil }
        let playhead = player.currentPlaybackTime
        return PlaybackSample(
            bytesRead: player.dynamicInfo.bytesRead,
            playhead: playhead,
            buffered: max(0, player.playableTime - playhead),
            isPlaying: player.isPlaying
        )
        #else
        return nil
        #endif
    }
}

/// `KSPlayerState`(真实内核 8 case)→ 协调器抽象状态。VLC fallback 的状态集不同,单独映射。
public func mapKSPlayerEngineState(_ state: KSPlayerState) -> PlaybackEngineState {
    #if canImport(KSPlayer)
    switch state {
    case .initialized: return .initialized
    case .preparing: return .preparing
    case .readyToPlay: return .readyToPlay
    case .buffering: return .buffering
    case .bufferFinished: return .bufferFinished
    case .paused: return .paused
    case .playedToTheEnd: return .ended
    case .error: return .error
    @unknown default: return .initialized
    }
    #else
    // KSPlayerFallback.KSPlayerStateBase:initialized/buffering/readyToPlay/paused/playedToTheEnd/error/stopped
    switch state {
    case .initialized: return .initialized
    case .readyToPlay: return .readyToPlay
    case .buffering: return .buffering
    case .paused: return .paused
    case .playedToTheEnd: return .ended
    case .error: return .error
    case .stopped: return .ended
    }
    #endif
}

