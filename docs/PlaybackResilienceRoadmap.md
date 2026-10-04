# 播放链路韧性改进路线图

> 状态:2026-10-04 已补充恢复反馈、CDN 偏好与 Playback Timeline；iOS/macOS 开发者控制台按 FullUI/ShellUI 模式分流，tvOS 在开发者模式下提供时间轴入口。代码实现和三端构建通过，实际交互及无障碍覆盖见 [本轮验收记录](TODOProgress20261004.md)。下方 2026-07-31 表格与方案是历史记录，当前契约见本节。

## 2026-10-04 当前实现

- `PlaybackDiagnosticsSession` 观察已有恢复协调器，不增加恢复预算或第二套计时器。取参、连接、缓冲文字来自真实调用/采样；恢复动作带序号与上限，三端顶部提示 2 秒。
- 起播完成须观察到在播且 playhead 推进；`readyToPlay` 不代表已显示首帧。记录名为 `startupCompleted`，精度受既有 1 Hz 采样限制，不宣称渲染器首帧时间。暂停、后台、离开和手动切换不把中断计为失败。
- `PlaybackEventLog` 保存最多 500 条结构化内存事件；只在开发者模式启用时记录。事件只有会话 UUID、时间、标准状态、索引和采样数值，不含原始播放 URL、房间身份、凭据或原始错误正文。iOS/macOS 可主动导出 JSON；tvOS 通用设置提供开发者模式开关和只读时间轴入口，不显示不可用的导出按钮。
- 每个房间 VM 有独立会话。自动 token 刷新保留会话和恢复预算，用户换房创建新会话。
- iOS 时间轴的控件、图表和事件共用一个滚动列表。辅助功能字号改用自然高度的事件概览，事件行及详情纵向排列，避免固定图表挤掉列表；普通字号保留图表。macOS/tvOS 保持各自原有布局。
- `CDNPreferenceStore` 以插件和稳定 `cdn` 标识的摘要保存成功率及采样起播耗时，7 天失效。当前候选全部至少 3 个样本后才选择初始 index；不重排插件数组，不覆盖用户手动选择，不改变后续重新取参的索引语义。
- 分数为 `0.7 × successRate + 0.3 × 500 / max(meanStartupMilliseconds, 500)`，全失败线路的速度项为 0，并列保持原顺序。无稳定标识时不学习。
- 2026-10-04 最后源码的 Core 默认并行全量 440 项／59 组通过（24.391 秒），包含播放诊断、CDN 偏好、恢复协调器及旧播放器进度不能提前完成新会话的回归。Dependencies native 后端全量 20 项／4 组通过；需要外部资源的 opt-in 保持默认未启用。三端新包交互结果另行记录，不能用单测替代。

尚未获得的证据：真实弱网下的长期线路学习效果、12 秒 stall 阈值的数据评估、精确渲染首帧与 30 秒离开率指标。旧方案中的直接记录 URL/KSPlayer 类型、readyToPlay 算首帧、重排数组及 `1/ms` 评分均未采用。

---

## 2026-07-31 历史方案
>
> 落地对照(2026-07-31 核对代码):
>
> | 项 | 状态 | 说明 |
> |---|---|---|
> | §2 `PlaybackTuning` 命名空间 | ✅ 已上线 | `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/PlaybackTuning.swift`,并额外提供 `RecoveryConfig`(按端注入起播超时等差异) |
> | ① stall 退避 | ⚠️ **方案已变更** | 未采用退避数组,改为**固定抬高阈值**。详见 §1 ① |
> | ② `PlaybackPhase` + 恢复文案 | 🟠 部分 | 已有 `PlaybackStatusMachine`(idle/loading/buffering/paused/playing/ended/failed),但**缺细分态**(`fetchingPlayArgs`/`connecting`/`bufferingFirstFrame`)与 `PlaybackRecoveryEvent` toast,用户仍看不到「正在切换线路」 |
> | ⑤ `CDNPreferenceStore` | ❌ 未开始 | 无该文件 |
> | ⑨ `PlaybackEventLog` + Timeline | ❌ 未开始 | 无该文件 |
> 范围:三端(iOS / macOS / tvOS)直播播放链路
> 目标:把"弱网误判 stall / 用户无感知 / CDN 起播没记忆 / 调参没工具"四类痛点收一收

---

## 0. 现状盘点

### 0.1 已落地

| 改动 | 文件 | 解决 |
|---|---|---|
| HLS 默认走 KSAVPlayer,KSMEPlayer 兜底 | `RoomPlaybackResolver.swift` | 部分 m3u8 直播流 KSME/FFmpeg 解析卡第一帧 |
| Startup watchdog 加 bytes 进度门 + 12s | `RoomPlayerView` / `PlayerContainerView` / `DetailPlayerView` | 弱网下"还在缓冲就被 refresh kill"的死循环 |
| URLCache 清缓存后强制刷计数 | `CacheMaintenanceService.swift` | 设置页第一次点清缓存大小不变 |
| 远程输入事件 id 化 + `.config` 合并 | `RemoteInputService.swift` 等 4 处 | 标题+URL 一起提交丢 URL / 同 URL 重复提交不触发 |

### 0.2 当前韧性栈

```
┌──────────────────────────────────────────┐
│  View 层:Startup Watchdog                │  ← 起播 12s 超时 + bytes 进度门 (三端 View 各一份)
├──────────────────────────────────────────┤
│  ViewModel 层:Stall Watchdog             │  ← 1Hz 采样 bytes+playhead,8s 触发 CDN failover/refresh
├──────────────────────────────────────────┤
│  FFmpeg 层:KSOptions.rw_timeout (9s)     │  ← I/O 级握手超时,走 .failed 错误路径
└──────────────────────────────────────────┘
+ Managed retry: maxPlaybackRetries=3 / 60s 窗口共享预算
+ Bugsnag + PluginConsoleService:已记 stall/managed retry 事件
```

三端 ViewModel(iOS 1084 / macOS 1063 / tvOS 1062 行)各自维护这些 watchdog,字段名一致但代码独立;View 层的 startup watchdog 同理。

---

## 1. 计划改动

本轮**只做 4 项**,理由见 §3。

### ① Stall watchdog 加指数退避 — ⚠️ 已改为固定抬高阈值

> **2026-07-31 实际落地与本节设计不同。** 最终没有采用退避数组,而是把零吞吐阈值从 8s **固定抬到 12s**:
>
> ```swift
> // PlaybackTuning.swift
> /// 零吞吐 stall 判定阈值。抬高于旧的 8s —— 8s < 单个 HLS 分片时长会把正常大分片流误判。
> public static let stallThresholdSeconds: TimeInterval = 12
> ```
>
> **改用固定阈值的理由**:退避方案要解决的是「重试越多越宽容」,但实测主要误判源是**单个 HLS 分片时长本身就可能超过 8s**——这与重试次数无关,退避解决不了首次误判。抬高下限直接命中该场景。
>
> 同时引入 `PlaybackTuning.healthyConfirmSeconds = 20`:只有**连续健康 20s 且 playhead 单调推进**才清零熔断预算,替代了原「短暂 readyToPlay 即清零」——抖动流因此会消耗预算,恢复循环有终点。
>
> 自适应阈值(按观测到的实际分片间隔动态调整)保留为后续可选项,`PlaybackTuning` 注释中已标注。
>
> 以下为原设计,保留作决策记录。

**问题**
`stallThresholdSeconds = 8s` 触发 → CDN failover。弱网下 8s 零吞吐其实很常见:
- TCP RTT 高时 FFmpeg av_read_frame 自然空窗
- KSPlayer 缓冲打满(`loadedTime > maxBufferDuration`)→ `MEPlayerItem.send(.pause)` → bytesRead 不动(已被 `stallPlayheadProgressTolerance` 覆盖)
- 服务端 keep-alive 心跳期

→ 容易把"慢但正常"误判成 stall,浪费 CDN 切换预算。

**改动**
```swift
// 退避序列与 maxPlaybackRetries=3 对齐
public static let stallBackoffSeconds: [Int] = [8, 16, 32]

let threshold = stallBackoffSeconds[
    min(playbackRetryAttempts, stallBackoffSeconds.count - 1)
]
if stallNoChangeTicks >= threshold { ... }
```

**已知行为(写入文档,不算 bug)**
- `playbackRetryWindowStart` 在 60s 窗口外被清零(`RoomInfoViewModel.swift:978-982`)。**这意味着退避也会被重置回 8s**。
- 直播持续 1 小时,经历 6 次零散卡顿(每次相隔 > 60s)时,每次都从 8s 起,而不是退到 32s 不动。
- 这是想要的:避免持久退避把"偶发卡顿"也搞慢。

**预算**:`maxPlaybackRetries=3 / 60s` 不变。
**风险**:CDN 真死时第二次切换从 8s → 16s,首次切换不变。
**触点**:三端 `RoomInfoViewModel.swift:77`(常量)、`:965`(判定)。

---

### ② 加载状态文字反馈(PlaybackPhase 状态机)

**问题**
现在 loading overlay = 转圈 + "加载中"一句。watchdog 触发 refresh / CDN 切换时用户无感知 → 体感是"卡了又自动好了",或者"卡了越来越久"(看不到补救动作)。

**改动**
1. ViewModel 暴露 `playbackPhase: PlaybackPhase` 状态机:
   ```swift
   public enum PlaybackPhase: Sendable {
       case idle
       case fetchingPlayArgs     // 拉播放地址中
       case connecting           // URL 已下发,等首字节
       case bufferingFirstFrame  // 收到字节但 player 还没进 readyToPlay
       case playing
       case error(message: String)
   }

   // 一次性事件(toast 用),与 phase 解耦,Observable 双写
   public enum PlaybackRecoveryEvent: Sendable {
       case switchingCDN(from: String, to: String, attempt: Int, max: Int)
       case retrying(attempt: Int, max: Int)
   }
   ```

2. View 层把 `phase` 渲染成具体文字 + 副标题:
   - "连接中 · 服务器响应慢..."
   - "重新加载 · 当前线路无响应"

3. CDN failover / managed retry 触发时,**复用现有 `attemptStallRecovery` / `attemptManagedPlaybackRetry` 里的 `PluginConsoleService.log()` 调用点**(`RoomInfoViewModel.swift:1037` / `:813`)旁边发 `recoveryEvent`,View 用 `.onChange` 弹 toast 1.5s:
   - "网络较慢,正在切换线路 (1/3)"

**过渡策略**
现有字段(`isLoading`/`playError`/`playErrorMessage`/`isFetchingPlayURL`)做成 `phase` 的 computed,先让 View 不用改;视图层后续逐个迁移读 `phase`。

**收益**:用户感觉系统在主动处理,不是"卡死"。客服反馈类问题应该会少。

**触点**:三端 VM 顶部状态字段、`StreamLoadingOverlay` 文案、`attemptStallRecovery`/`attemptManagedPlaybackRetry` 各发一次 event。

---

### ⑤ CDN 偏好学习

**问题**
进直播间永远从 `CDN[0]` 起,平台返回顺序未必反映用户当前的可达性。

**改动**
1. 新建 `CDNPreferenceStore`(`AngelLiveCore/Playback/CDNPreferenceStore.swift`,纯 `UserDefaults` 持久化):
   ```swift
   public struct CDNObservation: Codable, Sendable {
       var startupAttempts: Int
       var startupSuccesses: Int
       var avgFirstFrameMillis: Double
       var lastSuccessAt: Date?
   }

   // key: "\(liveType.rawValue):\(cdnHost)"
   public actor CDNPreferenceStore {
       public static let shared = CDNPreferenceStore()
       public func reorder(_ playArgs: [LiveQualityModel], for liveType: LiveType) -> [LiveQualityModel]
       public func recordSuccess(host: String, liveType: LiveType, firstFrameMs: Double)
       public func recordFailure(host: String, liveType: LiveType)
   }
   ```

2. 切入点:`updateCurrentRoomPlayArgs(_:)` `RoomInfoViewModel.swift:160` —
   ```swift
   self.currentRoomPlayArgs = await CDNPreferenceStore.shared
       .reorder(playArgs, for: currentRoom.liveType)
   ```

3. 评分:
   ```swift
   score = success_rate * 0.7 + (1 / max(avg_first_frame_ms, 500)) * 0.3
   ```
   样本 < 3 时按平台原顺序走,不动。

4. 观测信号(三端 VM 已有的回调里挂):
   - 成功:`KSPlayerLayerDelegate` 收到 `.readyToPlay`,记 first-frame 时长
   - 失败:`attemptStallRecovery` 触发 / `attemptManagedPlaybackRetry` 触发 / `playError` 非 nil

5. 数据有效期:`validityWindow = 7 days`,过期清掉(用户换网络环境历史数据失效)。

**已确认的边界**
- 用户手动 `changePlayUrl(cdnIndex:urlIndex:)` 不影响重排,仍按用户意图走 — 重排只发生在 `updateCurrentRoomPlayArgs` 这一次
- `nextCdnIndex()` 走 `(currentCdnIndex + 1) % args.count`,重排后逻辑仍正确
- UI 上展示的 CDN 标识用 `cdn.displayName` 或 `cdn.cdn`(host),不依赖 index,重排无副作用

**风险**:冷启动期数据稀疏 → 阈值过滤(样本 < 3 用原顺序)。
**位置**:`Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/CDNPreferenceStore.swift`。

---

### ⑨ DevConsole 加 PlaybackTimeline

**思路**
DevConsole 已经有日志流(`PluginConsoleService.entries`)。补一个时间轴视图:
- 横轴:时间(进入直播间到现在)
- 纵轴:事件类型(URL set / state change / watchdog tick / refresh / CDN switch / Managed retry / Error)
- 点击事件展开详情

**实现选择(已比对)**
不复用 `PluginConsoleEntry`:它的语义是"插件 HTTP 请求",字段(url/method/headers/statusCode/HTTP 子请求)和播放事件不重叠。强塞需要把字段当 stringly-typed 用,后续扩展难看。

→ 新建 `PlaybackEventLog`(`AngelLiveCore/Playback/PlaybackEventLog.swift`):
```swift
public enum PlaybackEvent: Sendable {
    case urlChanged(URL)
    case stateChanged(KSPlayerState)
    case watchdogTick(bytesRead: Int64, playhead: TimeInterval)
    case stallTriggered(threshold: Int, attempt: Int)
    case cdnSwitch(from: Int, to: Int, reason: String)
    case managedRetry(attempt: Int, error: String)
    case errorReported(String)
    case recoveryBudgetExhausted
}

@Observable
public final class PlaybackEventLog {
    public static let shared = PlaybackEventLog()
    public private(set) var events: [(Date, PlaybackEvent)] = []  // 环形,cap=500
    public func record(_ event: PlaybackEvent)
    public func snapshot() -> [(Date, PlaybackEvent)]  // 导出 JSON 用
}
```

**双写策略**:`attemptStallRecovery` / `attemptManagedPlaybackRetry` 现有的 `PluginConsoleService.log()` 调用保留(后端日志可读),旁边加 `PlaybackEventLog.shared.record(...)`。新事件类型(URL set / state change)只往 PlaybackEventLog 写。

**视图**:`Shared/AngelLiveCore/.../DevConsole/PlaybackTimelineView.swift`,DevConsole 主界面加一个 tab。

**收益**
- 调参直接看曲线(stall 触发时 bytes/playhead 历史)
- 用户上报问题一键导出 timeline JSON(`PlaybackEventLog.shared.snapshot()`)
- DogFooding 价值大

**风险**:低,纯加性。

---

## 2. 通用基础 · Playback 命名空间(共享层) — ✅ 已上线

`①②` 都要在三端 VM 各改一份。**不做 ⑥**(actor controller),但抽常量和纯类型,降低漂移。

> **已落地,且比本节设计更进一步。** 实际的 `PlaybackTuning.swift` 除常量外还提供了 `RecoveryConfig` 结构体 + `phone()` / `desktopTV()` 工厂方法,把三端差异(起播超时 iOS 20s、macOS/tvOS 12s;`stallMonitoringEnabled` 按内核区分)**显式注入**而非散落各端。
>
> 常量清单也与下方草案有出入(以代码为准):新增 `healthyConfirmSeconds`、`tickInterval`、`hasKickPipeline`;`stallBackoffSeconds` 数组未采用(见 ①)。

**新建**(草案,实际实现见代码) `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/PlaybackTuning.swift`:
```swift
public enum PlaybackTuning {
    public static let stallBackoffSeconds: [Int] = [8, 16, 32]
    public static let stallPlayheadProgressTolerance: TimeInterval = 0.5
    public static let stallWatchdogTickNanos: UInt64 = 1_000_000_000
    public static let maxPlaybackRetries = 3
    public static let playbackRetryWindow: TimeInterval = 60
    public static let startupWatchdogTimeoutSeconds: TimeInterval = 12
    public static let startupWatchdogBytesProgressThreshold: Int64 = 16 * 1024

    public static func stallThreshold(for attempt: Int) -> Int {
        stallBackoffSeconds[min(attempt, stallBackoffSeconds.count - 1)]
    }
}
```

VM 和 View 各端读这里,三端 VM 内部仍保留各自的 `playbackRetryAttempts`/`stallNoChangeTicks` 状态(状态不抽,只抽配置)。

**收益**:① 改完后,三端 stall 阈值改动只动一处;startup watchdog 三端 View 同理。
**风险**:零(纯常量重定位)。
**估时**:0.5 天。

不是 ⑥ 那种 actor + protocol 的大手术,**只是把"应该 share 的常量"实际 share 一份**。

---

## 3. 不做的 5 项(放弃理由)

| 项 | 放弃理由 |
|---|---|
| ③ 失败前先降清晰度 | `LiveQualityModel` 缺 quality 排序规范(qn 数值跨平台不一致),前置工作量大;且"流畅 vs 高清"是用户偏好,不该 silent 改 |
| ④ 内核选择记忆 + 平台白名单 | `PlatformCapability` 语义是"插件能力探测",塞内核偏好会污染语义;现 KSAV/KSME fallback 链路已工作良好,ROI 不足 |
| ⑥ 三个 watchdog 合并成 Controller | 三端 VM diff 不只 watchdog(PlayerKernel/UA/弹幕设置等都差),抽 protocol 适配成本大于去重收益;§2 的最小共享层已经覆盖主要痛点 |
| ⑦ 网络质量探针 | 大多数直播 CDN 不允许 HEAD;64KB 探针在弱网下慢,跟实际起播差距小;不如 ⑤ 学历史数据 |
| ⑧ playArgs 预热 | 直播 token 有时效(30-300s 不等),缓存窗口窄;tvOS focus 收益大但仅一端,iOS long-press 与 Context Menu 冲突 |

---

## 4. 落地顺序

| # | 项 | 估时 | 前置 | 状态 |
|---|---|---|---|---|
| 0 | §2 `PlaybackTuning` 命名空间 | 0.5d | - | ✅ 已上线 |
| 1 | ① stall 阈值 | 0.5d | 0 | ✅ 已上线(改为固定 12s,非退避) |
| 2 | ⑨ `PlaybackEventLog` + Timeline View | 1.5d | 0 | ❌ 未开始 ← **剩余项里应优先** |
| 3 | ② `PlaybackPhase` + recoveryEvent | 1.5d | 1, 2 | 🟠 部分(有 `PlaybackStatusMachine`,缺细分态与 toast) |
| 4 | ⑤ `CDNPreferenceStore` + 接入 | 2d | 2(借时间轴验证) | ❌ 未开始 |

**为什么 ⑨ 排前面**:① 和 ⑤ 都需要看数据调参,先把时间轴落了,后面调参不用瞎调。⑤ 上线后用 timeline 验证"重排是否真的命中常用 CDN"也方便。

> ① 已用固定阈值落地,但**「12s 是否合适」本身仍缺数据支撑**——这正是 ⑨ 要提供的。⑨ 的优先级因此不降反升:它既是 ⑤ 的前置,也是回头验证 ① 的唯一手段。

**剩余估时**:约 5 天(⑨ 1.5d + ② 剩余 ~1.5d + ⑤ 2d)。

---

## 5. 度量

| 指标 | 含义 | 期望方向 | 数据源 |
|---|---|---|---|
| `time_to_first_frame_ms` | URL set 到 isPlaying=true 的耗时 | 下降 | PlaybackEventLog |
| `watchdog_refresh_count_per_session` | 单场观看里 startup watchdog 触发 refresh 的次数 | 下降至 0-1 | PlaybackEventLog |
| `stall_recovery_count_per_session` | 单场观看里 stall watchdog 触发 CDN/refresh 的次数 | 下降(随 ①) | PlaybackEventLog |
| `cdn_failover_success_rate` | failover 后 5s 内起播成功的比例 | 上升 | PlaybackEventLog + Bugsnag breadcrumb |
| `cdn_first_choice_hit_rate` | 进直播间用 `CDN[0]`(重排后)5s 内起播的比例 | 上升(随 ⑤) | PlaybackEventLog |
| `playback_abandon_rate` | 进入详情页但 30s 内未起播就退出的比例 | 下降 | 需新埋点(进入/退出回调) |

前 5 个由 ⑨ 完成后自动可查;最后一个需要在 `RoomInfoView.onDisappear` 加一行埋点。

---

## 6. 不在此规划内

- 播放器 UI 重设计(控制栏 / 弹幕 / 设置面板)
- 音频独立模式(audio-only fallback)
- 全屏 / PiP / AirPlay 现有问题
- 弹幕通道稳定性
- 三端 VM 整体合并(见 ⑥ 放弃理由)
