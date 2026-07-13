import Foundation
import Testing
@testable import AngelLiveCore

// MARK: - PlaybackRecoveryCoordinator Tests
//
// 纯同步状态机测试:直接喂合成事件(advance(.tick/.state/...)),不依赖真实时间、不依赖 KSPlayer。
// 重点覆盖两个确定性 bug 的修复:
//   Bug A — 熔断预算挂在逻辑会话上,逐级升级到顶才 failed(ladderEscalatesThenFails)。
//   Bug B — 短暂 readyToPlay 不清零预算(briefReadyDoesNotResetBudget);
//           只有连续健康 N 秒才清零(sustainedHealthResetsBudget)。

@MainActor
@Suite("PlaybackRecoveryCoordinator")
struct PlaybackRecoveryCoordinatorTests {

    private struct TestError: Error {}

    /// 记录各恢复动作被调用的次数(plain class,全程在 MainActor 上被调用,无跨隔离传递)。
    private final class ActionRecorder {
        var kick = 0
        var refresh = 0
        var cdn = 0
        var reload = 0
        var failedReasons: [String] = []

        func make() -> RecoveryActions {
            RecoveryActions(
                kickPipeline: { self.kick += 1 },
                refreshSameURL: { self.refresh += 1 },
                switchCDN: { self.cdn += 1 },
                reloadPlayArgs: { self.reload += 1 },
                reportFailed: { self.failedReasons.append($0) }
            )
        }
    }

    private func makeCoordinator(
        config: RecoveryConfig,
        recorder: ActionRecorder
    ) -> PlaybackRecoveryCoordinator {
        PlaybackRecoveryCoordinator(config: config, actions: recorder.make(), sample: { nil })
    }

    // 起播阶段不健康样本:无 playhead 推进、无缓冲、未在播。
    private func startupStall(bytes: Int64 = 0) -> PlaybackSample {
        PlaybackSample(bytesRead: bytes, playhead: 0, buffered: 0, isPlaying: false)
    }

    // 已起播后的零吞吐样本:playhead 不动、无缓冲。
    private func runningStall(playhead: TimeInterval = 5) -> PlaybackSample {
        PlaybackSample(bytesRead: 1, playhead: playhead, buffered: 0, isPlaying: false)
    }

    // 健康样本:有缓冲且在播。
    private func healthy(playhead: TimeInterval) -> PlaybackSample {
        PlaybackSample(bytesRead: 1, playhead: playhead, buffered: 5, isPlaying: true)
    }

    private func tick(_ c: PlaybackRecoveryCoordinator, _ s: PlaybackSample, delta: TimeInterval = 1) {
        c.advance(.tick(sample: s, delta: delta))
    }

    // MARK: 1. 进会话即 healthy

    @Test("episodeChanged 进入 healthy 阶段")
    func episodeStartsHealthy() {
        let r = ActionRecorder()
        let c = makeCoordinator(config: .phone(stallMonitoringEnabled: true), recorder: r)
        #expect(c.phase == .idle)
        c.episodeChanged(streamKey: "k1")
        #expect(c.phase == .healthy)
    }

    // MARK: 2. 起播超时 → 阶梯首档 reloadPlayArgs

    @Test("起播超时无进度触发首档 reloadPlayArgs")
    func startupTimeoutTriggersFirstRung() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(startupTimeout: 2, stallMonitoringEnabled: false)
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        tick(c, startupStall())   // baseline=0, elapsed=1
        tick(c, startupStall())   // elapsed=2 → 触发
        #expect(r.reload == 1)
        #expect(r.refresh == 0 && r.cdn == 0)
        #expect(c.phase == .recovering(action: .reloadPlayArgs, attempt: 1, max: 3))
    }

    // MARK: 3. 起播期网络在动 → suspect,不消耗熔断预算

    @Test("起播超时但 bytes 在涨 → suspect 不发动作")
    func startupProgressYieldsSuspectNoAction() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(startupTimeout: 2, stallMonitoringEnabled: false)
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        tick(c, startupStall(bytes: 0))        // baseline=0, elapsed=1
        tick(c, startupStall(bytes: 100_000))  // elapsed=2,bytes 远超门槛 → suspect
        #expect(c.phase == .suspect)
        #expect(r.refresh == 0 && r.cdn == 0 && r.reload == 0)
    }

    // MARK: 4. 已起播后零吞吐 stall → 触发恢复

    @Test("已起播零吞吐 stall 触发恢复")
    func stallTriggersRecovery() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(startupTimeout: 99, stallThresholdSeconds: 2, stallMonitoringEnabled: true)
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)           // startedPlaying=true
        tick(c, runningStall())                // stallAccum=1, suspect
        tick(c, runningStall())                // stallAccum=2 → 触发
        #expect(r.reload == 1)
        #expect(c.phase == .recovering(action: .reloadPlayArgs, attempt: 1, max: 3))
    }

    // MARK: 5. Bug A — 阶梯逐级升级,到顶 failed,预算按会话累计

    @Test("阶梯逐级升级后熔断 failed(Bug A)")
    func ladderEscalatesThenFails() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(startupTimeout: 2, stallMonitoringEnabled: false)
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        // 每 2 个起播 tick 触发一次;触发后 startedPlaying 复位,继续走起播路径。
        // 阶梯: reloadPlayArgs → switchCDN → refreshSameURL
        for _ in 0..<8 { tick(c, startupStall()) }
        #expect(r.reload == 1)
        #expect(r.cdn == 1)
        #expect(r.refresh == 1)
        #expect(r.failedReasons.count == 1)
        if case .failed = c.phase {} else {
            Issue.record("phase 应为 .failed,实际 \(c.phase)")
        }
    }

    // MARK: 6. Bug B — 短暂 readyToPlay 不清零熔断预算

    @Test("短暂 readyToPlay 不重置熔断预算(Bug B)")
    func briefReadyDoesNotResetBudget() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(startupTimeout: 99, stallThresholdSeconds: 2, stallMonitoringEnabled: true)
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)
        tick(c, runningStall()); tick(c, runningStall())   // 触发 rung0 → reloadPlayArgs, attempts=1
        #expect(r.reload == 1)

        c.stateChanged(.readyToPlay)                       // 短暂 ready —— 不应清零 attempts
        tick(c, runningStall()); tick(c, runningStall())   // 再触发 → 应是 rung1 = switchCDN
        #expect(r.cdn == 1)
        #expect(r.reload == 1)   // 若预算被错误清零,这里会变成 2
    }

    // MARK: 7. Bug B 另一半 — 连续健康 N 秒才清零预算

    @Test("连续健康 N 秒后清零预算并回 healthy(Bug B)")
    func sustainedHealthResetsBudget() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(
            startupTimeout: 99,
            stallThresholdSeconds: 2,
            healthyConfirmSeconds: 3,
            stallMonitoringEnabled: true
        )
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)
        tick(c, runningStall()); tick(c, runningStall())   // rung0 → reloadPlayArgs, attempts=1
        #expect(r.reload == 1)

        // 连续 3 秒健康(playhead 单调推进)→ 清零预算,回 healthy。健康阶段结束于 playhead=20。
        tick(c, healthy(playhead: 10))
        tick(c, healthy(playhead: 15))
        tick(c, healthy(playhead: 20))
        #expect(c.phase == .healthy)

        // 预算已清零:再次 stall 应从 rung0 重新开始。
        // ★ stall 样本 playhead 必须 ≤ 上一帧(=20),否则会被 isHealthy 判活而非 stall。
        tick(c, runningStall(playhead: 20)); tick(c, runningStall(playhead: 20))
        #expect(r.reload == 2)
        #expect(r.cdn == 0)
        #expect(r.refresh == 0)
    }

    // MARK: 8. finished/ended 终止语义

    @Test("finished(nil)/ended 回 idle;finished(error) 触发恢复")
    func finishedAndEndedGoIdle() {
        // ended → idle
        let r1 = ActionRecorder()
        let c1 = makeCoordinator(config: .phone(stallMonitoringEnabled: true), recorder: r1)
        c1.episodeChanged(streamKey: "k1")
        c1.stateChanged(.ended)
        #expect(c1.phase == .idle)

        // finished(nil) → idle,无动作
        let r2 = ActionRecorder()
        let c2 = makeCoordinator(config: .phone(stallMonitoringEnabled: true), recorder: r2)
        c2.episodeChanged(streamKey: "k1")
        c2.finished(error: nil)
        #expect(c2.phase == .idle)
        #expect(r2.refresh == 0)

        // finished(error) → 触发恢复(首档 reloadPlayArgs)
        let r3 = ActionRecorder()
        let c3 = makeCoordinator(config: .phone(stallMonitoringEnabled: true), recorder: r3)
        c3.episodeChanged(streamKey: "k1")
        c3.finished(error: TestError())
        #expect(r3.reload == 1)
        #expect(c3.phase == .recovering(action: .reloadPlayArgs, attempt: 1, max: 3))
    }

    // MARK: 9. 索引夹取

    @Test("clampedSelection 保持偏好索引并夹到可用范围")
    func clampedSelectionKeepsPreference() {
        let liveType = LiveType(rawValue: "test") ?? .placeholder
        let q0 = LiveQualityDetail(
            roomId: "r", title: "原画", qn: 0, url: "https://a/0.flv",
            liveCodeType: .flv, liveType: liveType
        )
        let q1 = LiveQualityDetail(
            roomId: "r", title: "高清", qn: 1, url: "https://a/1.flv",
            liveCodeType: .flv, liveType: liveType
        )
        let playArgs = [
            LiveQualityModel(cdn: "A", qualitys: [q0, q1]),
            LiveQualityModel(cdn: "B", qualitys: [q0])
        ]
        let keep = RoomPlaybackResolver.clampedSelection(
            in: playArgs, preferredCdnIndex: 1, preferredQualityIndex: 0
        )
        #expect(keep.cdnIndex == 1 && keep.qualityIndex == 0)

        let clampQ = RoomPlaybackResolver.clampedSelection(
            in: playArgs, preferredCdnIndex: 1, preferredQualityIndex: 9
        )
        #expect(clampQ.cdnIndex == 1 && clampQ.qualityIndex == 0)

        let clampCdn = RoomPlaybackResolver.clampedSelection(
            in: playArgs, preferredCdnIndex: 99, preferredQualityIndex: 1
        )
        #expect(clampCdn.cdnIndex == 1 && clampCdn.qualityIndex == 0)
    }

    // MARK: 10. 已起播后意外结束 → 恢复(直播 EOF 误报点播终局)

    @Test("已起播后 finished(nil) 触发恢复(首档 reloadPlayArgs)")
    func streamEndAfterStartedRecovers() {
        let r = ActionRecorder()
        let c = makeCoordinator(config: .phone(stallMonitoringEnabled: false), recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)          // 已起播
        c.finished(error: nil)                // 直播 CDN 会话结束走 endOfStream → finish(nil)
        #expect(r.reload == 1)
        #expect(c.phase == .recovering(action: .reloadPlayArgs, attempt: 1, max: 3))
    }

    // MARK: 11. endOfStream + playedToTheEnd 成对到达只烧一档,不误关监控

    @Test("成对流结束事件只触发一次恢复,尾随事件不关监控")
    func pairedStreamEndTriggersOnce() {
        let r = ActionRecorder()
        let c = makeCoordinator(config: .phone(stallMonitoringEnabled: false), recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)
        // 日志顺序:endOfStream 的 finished(nil) 先到,playedToTheEnd 的 .ended 尾随。
        c.finished(error: nil)                // 首档 reloadPlayArgs,triggerRecovery 复位 startedPlaying
        c.stateChanged(.ended)                // 尾随:.recovering 中应被忽略,不能落 idle
        #expect(r.reload == 1)
        #expect(r.cdn == 0 && r.refresh == 0)
        if case .recovering = c.phase {} else {
            Issue.record("应仍在 recovering(监控未被误关),实际 \(c.phase)")
        }
    }

    // MARK: 12. HLS 无字节采样:恢复后持续在播清预算,反复 EOF 仍能续

    @Test("HLS 无采样内核:每次续播后清熔断预算,反复 EOF 不熔断")
    func hlsBudgetResetsWithoutSamples() {
        let r = ActionRecorder()
        let cfg = RecoveryConfig(
            startupTimeout: 20,
            healthyConfirmSeconds: 3,
            stallMonitoringEnabled: false      // HLS(KSAVPlayer)不跑 stall 采样
        )
        let c = makeCoordinator(config: cfg, recorder: r)
        c.episodeChanged(streamKey: "k1")
        c.stateChanged(.readyToPlay)

        // 官方房每 ~2 分钟断一次:连烧 4 次 EOF,每次续播后靠「持续在播」清预算。
        for _ in 0..<4 {
            c.finished(error: nil)             // EOF → rung0 reloadPlayArgs
            c.stateChanged(.readyToPlay)       // 续播成功、又在播 → enginePlaying=true
            for _ in 0..<3 {                   // nil-sample tick 累计健康至 healthyConfirmSeconds
                c.advance(.tick(sample: nil, delta: 1))
            }
        }
        // 每次都从 rung0 起 → 全是 reloadPlayArgs,从不升档、从不 failed。
        #expect(r.reload == 4)
        #expect(r.cdn == 0 && r.refresh == 0)
        #expect(r.failedReasons.isEmpty)
        #expect(c.phase == .healthy)
    }
}
