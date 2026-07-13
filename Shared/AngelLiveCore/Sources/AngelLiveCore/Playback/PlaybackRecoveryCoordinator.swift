import Foundation
import Observation

// MARK: - 抽象类型(不依赖 KSPlayer,由应用层映射)

/// 播放引擎状态的抽象,映射自 KSPlayerState(8 case)或 VLC 状态。
///
/// AngelLiveCore 不依赖 KSPlayer/VLCKit,所以协调器用本枚举而非 `KSPlayerState`,
/// 应用层在 delegate 回调里做一次映射。这样协调器可单测、可三端共享、并能同时容纳两套内核。
public enum PlaybackEngineState: Sendable {
    case initialized
    case preparing
    case readyToPlay
    case buffering
    case bufferFinished
    case paused
    case ended          // 映射 KSPlayerState.playedToTheEnd
    case error
}

/// 一次采样的判活信号。应用层每个心跳从 playerLayer 读取后提供。
public struct PlaybackSample: Sendable {
    public var bytesRead: Int64
    public var playhead: TimeInterval
    public var buffered: TimeInterval
    public var isPlaying: Bool

    public init(bytesRead: Int64, playhead: TimeInterval, buffered: TimeInterval, isPlaying: Bool) {
        self.bytesRead = bytesRead
        self.playhead = playhead
        self.buffered = buffered
        self.isPlaying = isPlaying
    }
}

/// 升级阶梯的动作类型。
public enum RecoveryActionKind: Sendable, Equatable, CustomStringConvertible {
    case kickPipeline      // play-pause-play hack(可选首档)
    case refreshSameURL    // 同源重连
    case switchCDN         // 切到下一条 CDN(VM 内部 nextCdnIndex();无可切则回退 refresh)
    case reloadPlayArgs    // 重新拉取播放参数(= 现 refreshPlayback)

    public var description: String {
        switch self {
        case .kickPipeline: "kickPipeline"
        case .refreshSameURL: "refreshSameURL"
        case .switchCDN: "switchCDN"
        case .reloadPlayArgs: "reloadPlayArgs"
        }
    }
}

/// 协调器对外暴露的阶段,供 UI 渲染文字反馈。
public enum RecoveryPhase: Sendable, Equatable {
    case idle
    case healthy
    case suspect                                            // 疑似卡顿,尚未发动作
    case recovering(action: RecoveryActionKind, attempt: Int, max: Int)
    case failed(reason: String)
}

/// 协调器要执行的动作,由 VM 注入(协调器不直接依赖 VM / 播放引擎)。
/// 含 MainActor 闭包,仅在 @MainActor 协调器内部调用,故不标 Sendable。
public struct RecoveryActions {
    public var kickPipeline: () -> Void
    public var refreshSameURL: () -> Void
    public var switchCDN: () -> Void
    public var reloadPlayArgs: () -> Void
    public var reportFailed: (_ reason: String) -> Void

    public init(
        kickPipeline: @escaping () -> Void = {},
        refreshSameURL: @escaping () -> Void,
        switchCDN: @escaping () -> Void,
        reloadPlayArgs: @escaping () -> Void,
        reportFailed: @escaping (_ reason: String) -> Void
    ) {
        self.kickPipeline = kickPipeline
        self.refreshSameURL = refreshSameURL
        self.switchCDN = switchCDN
        self.reloadPlayArgs = reloadPlayArgs
        self.reportFailed = reportFailed
    }
}

// MARK: - 协调器

/// 统一播放恢复协调器:把散在三端 6 处的「卡顿检测 + 自动恢复」收成一个可单测的状态机。
///
/// 核心是纯同步状态机 `advance(_:)`;内部 1Hz `Task` 只负责把「时间 tick + 采样」转成事件喂进去。
/// 单测直接喂合成事件序列,不依赖真实时间、不依赖 KSPlayer。
///
/// 修两个确定性 bug:
/// - **Bug A**:熔断计数挂在 `streamKey`(逻辑会话)上,token 滚动产生的新 URL 属同一会话、不重置;
///   起播超时也收编进协调器按会话记次,不再用 View `@State` 按 URL 身份复位。
/// - **Bug B**:熔断预算只在「连续健康 N 秒 playhead 单调推进」后清零;短暂 readyToPlay 不再清零。
@MainActor
@Observable
public final class PlaybackRecoveryCoordinator {

    // 仅 phase 需要被 UI 观察;其余内部状态忽略观察,避免无谓视图失效。
    public private(set) var phase: RecoveryPhase = .idle

    @ObservationIgnored private let config: RecoveryConfig
    @ObservationIgnored private let actions: RecoveryActions
    @ObservationIgnored private let sampleProvider: () -> PlaybackSample?
    @ObservationIgnored private let ladder: [RecoveryActionKind]

    // —— 会话状态 ——
    @ObservationIgnored private var streamKey: String?
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var attempts = 0                 // 当前会话已发起的恢复次数(熔断计数)
    @ObservationIgnored private var startedPlaying = false       // 是否已起播成功过
    @ObservationIgnored private var enginePlaying = false         // 引擎当前是否在播(供无字节采样内核判健康)
    @ObservationIgnored private var startupElapsed: TimeInterval = 0
    @ObservationIgnored private var startupBaselineBytes: Int64 = -1
    @ObservationIgnored private var stallAccum: TimeInterval = 0
    @ObservationIgnored private var healthyAccum: TimeInterval = 0
    @ObservationIgnored private var lastPlayhead: TimeInterval = -1

    @ObservationIgnored private var driver: Task<Void, Never>?

    public init(
        config: RecoveryConfig,
        actions: RecoveryActions,
        sample: @escaping () -> PlaybackSample?
    ) {
        self.config = config
        self.actions = actions
        self.sampleProvider = sample
        // 优先重新拉取播放参数:短时效签名 URL 同源重连几乎必失败;
        // 再切线路;最后同源重连兜底。单 CDN 时 switchCDN 由 VM 回退 refresh。
        var l: [RecoveryActionKind] = []
        if config.hasKickPipeline { l.append(.kickPipeline) }
        l.append(.reloadPlayArgs)
        l.append(.switchCDN)
        l.append(.refreshSameURL)
        self.ladder = l
    }

    // MARK: - 公开事件入口

    /// 进直播间 / 手动切源 / 手动切 CDN —— 即「新逻辑会话」。token 滚动不要调这个。
    public func episodeChanged(streamKey: String) { advance(.episode(streamKey)) }

    /// 实际播放 URL 变化(可能只是 token 刷新)。★ 不重置熔断、不重置起播计时(修 Bug A)。
    public func urlChanged(_ url: URL) { advance(.url(url)) }

    /// 引擎状态变化(应用层把 KSPlayerState/VLC 状态映射过来)。
    public func stateChanged(_ state: PlaybackEngineState) { advance(.state(state)) }

    /// 播放结束/错误。error 非 nil 视为可恢复(VM 已过滤不可重试错误);nil 为正常结束。
    public func finished(error: Error?) { advance(.finished(error)) }

    /// 启动 1Hz 采样驱动(进入播放器时调)。
    public func start() {
        monitoring = true
        guard driver == nil else { return }
        let nanos = UInt64(config.tickInterval * 1_000_000_000)
        driver = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                guard let self, !Task.isCancelled else { return }
                self.advance(.tick(sample: self.sampleProvider(), delta: self.config.tickInterval))
            }
        }
    }

    /// 停止采样驱动(离开播放器时调)。
    public func stop() {
        driver?.cancel()
        driver = nil
        monitoring = false
    }

    // MARK: - 状态机(纯同步,可单测)

    enum Event {
        case episode(String)
        case url(URL)
        case state(PlaybackEngineState)
        case finished(Error?)
        case tick(sample: PlaybackSample?, delta: TimeInterval)
    }

    func advance(_ event: Event) {
        switch event {
        case .episode(let key): applyEpisode(key)
        case .url(let url): currentURL = url
        case .state(let state): handleState(state)
        case .finished(let error): handleFinished(error)
        case .tick(let sample, let delta): handleTick(sample: sample, delta: delta)
        }
    }

    private func applyEpisode(_ key: String) {
        guard key != streamKey else { return }   // 同会话(token 滚动等)不重置
        streamKey = key
        attempts = 0
        startedPlaying = false
        enginePlaying = false
        startupElapsed = 0
        startupBaselineBytes = -1
        stallAccum = 0
        healthyAccum = 0
        lastPlayhead = -1
        monitoring = true
        phase = .healthy
    }

    private func handleState(_ state: PlaybackEngineState) {
        guard monitoring else { return }
        switch state {
        case .readyToPlay, .bufferFinished:
            // ★ 修 Bug B:起播成功只标记 startedPlaying,绝不在此清零熔断预算。
            // 预算清零只靠「连续健康 N 秒」(见 handleTick)。
            startedPlaying = true
            enginePlaying = true
            startupElapsed = 0
            stallAccum = 0
            if attempts == 0 { phase = .healthy }
        case .ended:
            // 直播 isLive=false 时 CDN 会话结束常表现为 playedToTheEnd,不能当点播终局。
            enginePlaying = false
            handleStreamEnd()
        case .error, .initialized, .preparing, .buffering, .paused:
            enginePlaying = false
            break   // error 走 finished(error:) 路径,避免重复触发
        }
    }

    private func handleFinished(_ error: Error?) {
        guard monitoring else { return }
        // error == nil: 直播流 endOfStream 常走这条,与 .ended 收口到同一处理。
        guard let error else {
            handleStreamEnd()
            return
        }
        triggerRecovery(reason: error.localizedDescription)
    }

    /// 直播意外结束(endOfStream 的 finished(nil) 与 playedToTheEnd 的 .ended)。
    /// 两者常成对到达:首个事件已进入恢复阶梯(并把 startedPlaying 复位),尾随事件在 .recovering
    /// 下忽略——既避免连烧两档,也避免被误判为「从未起播」而错误地关掉监控。
    private func handleStreamEnd() {
        guard monitoring else { return }
        if startedPlaying {
            triggerRecovery(reason: "stream ended")
        } else if !isRecovering {
            // 从未起播就结束:真终局。
            monitoring = false
            phase = .idle
        }
    }

    private var isRecovering: Bool {
        if case .recovering = phase { return true }
        return false
    }

    private func handleTick(sample: PlaybackSample?, delta: TimeInterval) {
        guard monitoring else { return }
        guard let sample else {
            // 无字节采样内核(HLS/KSAVPlayer):卡顿由 EOF/error 经 finish 反馈,这里不判 stall。
            // 但恢复后仍需「持续在播 N 秒」清零熔断预算,否则反复 EOF(官方房每 ~2 分钟断一次)
            // 会逐档烧满阶梯后永久 failed —— HLS 就再也续不上。
            if attempts > 0 {
                if enginePlaying {
                    healthyAccum += delta
                    if healthyAccum >= config.healthyConfirmSeconds {
                        attempts = 0
                        healthyAccum = 0
                        phase = .healthy
                    }
                } else {
                    healthyAccum = 0
                }
            }
            return
        }

        if isHealthy(sample) {
            stallAccum = 0
            startedPlaying = true
            lastPlayhead = sample.playhead
            if attempts > 0 {
                // 恢复后观察健康:累计,满确认时长才清熔断、回 healthy(修 Bug B 的另一半)。
                healthyAccum += delta
                if healthyAccum >= config.healthyConfirmSeconds {
                    attempts = 0
                    healthyAccum = 0
                    phase = .healthy
                }
            } else {
                healthyAccum = 0
                phase = .healthy
            }
            return
        }

        // 不健康
        healthyAccum = 0
        if !startedPlaying {
            // 起播阶段:计时;超时且无 bytes 进度 → 触发恢复。
            if startupBaselineBytes < 0 { startupBaselineBytes = sample.bytesRead }
            startupElapsed += delta
            if startupElapsed >= config.startupTimeout {
                let progressed = sample.bytesRead > startupBaselineBytes + config.startupBytesProgressThreshold
                if progressed {
                    // 网络在动、只是首帧慢:重置计时再等一轮,不消耗熔断预算。
                    startupElapsed = 0
                    startupBaselineBytes = sample.bytesRead
                    phase = .suspect
                } else {
                    triggerRecovery(reason: "起播超时 \(Int(config.startupTimeout))s 无进度")
                }
            }
        } else if config.stallMonitoringEnabled {
            // 已起播:零吞吐 stall 累计。
            stallAccum += delta
            if stallAccum >= config.stallThresholdSeconds {
                triggerRecovery(reason: "零吞吐 \(Int(config.stallThresholdSeconds))s")
            } else if phase == .healthy {
                phase = .suspect
            }
        }
        lastPlayhead = sample.playhead
    }

    /// 判活:playhead 单调推进 OR (有缓冲 AND 在播)。两者皆死才算 stall。
    /// 大分片正常流在分片边界 bytesRead 不动,但 playhead 仍推进 → 不会误判。
    private func isHealthy(_ s: PlaybackSample) -> Bool {
        let advanced = lastPlayhead >= 0 && (s.playhead - lastPlayhead) > config.playheadProgressTolerance
        let buffering = s.buffered > 0 && s.isPlaying
        return advanced || buffering
    }

    private func triggerRecovery(reason: String) {
        guard monitoring else { return }
        guard attempts < ladder.count else {
            phase = .failed(reason: reason)
            monitoring = false
            log(action: nil, attempt: attempts, reason: "熔断预算用尽 · \(reason)")
            actions.reportFailed(reason)
            return
        }
        let action = ladder[attempts]
        attempts += 1
        phase = .recovering(action: action, attempt: attempts, max: ladder.count)

        // 给恢复动作时间:重置检测累计与起播计时;attempts 已累加,熔断不被复位。
        stallAccum = 0
        healthyAccum = 0
        startupElapsed = 0
        startupBaselineBytes = -1
        startedPlaying = false
        enginePlaying = false
        lastPlayhead = -1

        log(action: action, attempt: attempts, reason: reason)
        perform(action)
    }

    private func perform(_ action: RecoveryActionKind) {
        switch action {
        case .kickPipeline: actions.kickPipeline()
        case .refreshSameURL: actions.refreshSameURL()
        case .switchCDN: actions.switchCDN()
        case .reloadPlayArgs: actions.reloadPlayArgs()
        }
    }

    private func log(action: RecoveryActionKind?, attempt: Int, reason: String) {
        let method = action.map { "\($0)#\(attempt)/\(ladder.count)" } ?? "failed"
        let id = PluginConsoleService.shared.log(tag: "Recovery", method: method, status: .loading)
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: action == nil ? .error : .success,
            responseBody: "streamKey=\(streamKey ?? "-")\nurl=\(currentURL?.absoluteString ?? "-")\nreason=\(reason)",
            errorMessage: action == nil ? reason : nil
        )
    }
}
