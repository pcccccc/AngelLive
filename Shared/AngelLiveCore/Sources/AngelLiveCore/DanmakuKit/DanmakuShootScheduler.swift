//
//  DanmakuShootScheduler.swift
//  AngelLiveCore
//
//  §6.2 错落感 · 弹幕去突发调度器
//

import Foundation

/// 弹幕去突发调度器:把一批同帧到达的弹幕摊到 `window` 秒内、带随机抖动逐条释放,
/// 消除「WebSocket 批量下发 → 同 tick 一股脑发射」造成的竖墙感。
///
/// 只给飞屏弹幕节流;底部聊天气泡不走这里,保持即时。
@MainActor
public final class DanmakuShootScheduler {

    public struct Config: Sendable {
        /// 一批弹幕摊开释放的时间窗
        public var window: TimeInterval
        /// 每条释放时刻的随机抖动(±)
        public var jitter: TimeInterval
        /// 缓冲上限,超出丢最旧,防止突发洪峰无限堆积
        public var maxBuffer: Int

        public init(window: TimeInterval = 1.2, jitter: TimeInterval = 0.25, maxBuffer: Int = 200) {
            self.window = window
            self.jitter = jitter
            self.maxBuffer = maxBuffer
        }
    }

    /// 运行时可调,便于真机调感
    public var config: Config

    private var buffer: [() -> Void] = []
    private var pendingWork: DispatchWorkItem?
    private var isWaiting = false

    /// init 标 nonisolated,以便作为非隔离 ViewModel 的存储属性默认值直接构造
    public nonisolated init(config: Config = .init()) {
        self.config = config
    }

    /// 入队一条弹幕发射闭包。调度器会把当前缓冲摊到 `window` 秒内逐条释放。
    public func enqueue(_ shoot: @escaping () -> Void) {
        if config.maxBuffer > 0, buffer.count >= config.maxBuffer {
            buffer.removeFirst()
        }
        buffer.append(shoot)
        scheduleNext()
    }

    /// 清空待发缓冲并取消定时(切房 / 断流 / 关闭弹幕时调用),避免陈旧弹幕飞进新房间。
    public func reset() {
        buffer.removeAll()
        pendingWork?.cancel()
        pendingWork = nil
        isWaiting = false
    }

    private func scheduleNext() {
        guard !isWaiting, !buffer.isEmpty else { return }
        isWaiting = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushOne() }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + nextInterval(), execute: work)
    }

    private func flushOne() {
        isWaiting = false
        pendingWork = nil
        guard !buffer.isEmpty else { return }
        let shoot = buffer.removeFirst()
        shoot()
        scheduleNext()
    }

    /// 令牌桶:把当前缓冲摊到 `window` 秒,间隔 = window / 剩余条数,叠加 ±jitter。
    /// 缓冲越多间隔越小(快速消化洪峰),缓冲少时间隔大(自然拉开)。
    private func nextInterval() -> TimeInterval {
        let remaining = max(buffer.count, 1)
        let base = config.window / Double(remaining)
        guard config.jitter > 0 else { return max(0, base) }
        return max(0, base + Double.random(in: -config.jitter...config.jitter))
    }
}
