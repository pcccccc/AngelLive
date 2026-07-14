# KSPlayer 三端播放架构重构计划

> 状态：实施中
> 进度：Phase 1–3 已完成（状态真源、插件优先路由、每会话 KSOptions、KSPlayer 安全重连、真实 live 语义）
> 日期：2026-07-14
> 范围：iOS / macOS / tvOS 的 KSPlayer 播放会话、状态、路由、恢复与控制层接线
> 上游基线：KSPlayer `lgpl@2f7db860`，FFmpegKit `lgpl@c2b9966e`

## 1. 目标与约束

本次重构以 KSPlayer 自身的 `KSOptions -> KSPlayerLayer -> MediaPlayerProtocol` 模型为边界，不另造一套 AVPlayer 架构。

必须满足：

1. `loading / buffering / paused / playing / failed` 状态准确，`readyToPlay` 只表示“已经具备播放条件”，绝不等同于“正在播放”。
2. 保留 iOS 画中画、后台音频、音频会话、Now Playing 和远程控制。
3. 三端控制层保持独立，现有手势、键鼠、窗口、Focus Engine、Siri Remote、全屏、弹幕、清晰度、线路、统计等能力不得回退。
4. 为未来 APTV 风格的多画面、画中画叠加和主辅画面切换预留会话/画面槽位，不把全局单例状态写死到播放器核心。
5. HLS、LL-HLS、FLV 直播必须通过同一套可测试路由进入正确的 KSPlayer 内核顺序。
6. 路由以插件显式提示为第一优先级；只有插件没有提供或提示不可用时，宿主才按 URL/扩展名推断。

## 2. 不做什么

- 不合并 iOS、macOS、tvOS 的播放器控制 View。
- 不删除或重写 KSPlayer 的 PiP、字幕、远程控制、Now Playing、播放器 fallback 机制。
- 不在本轮引入新的播放器内核。
- 不把插件协议绑定到 `AVPlayer` 类名；插件描述流语义与 KSPlayer 内核偏好，宿主负责映射具体类型。
- 不允许在旧 decode operation 退出前关闭其 `AVFormatContext`；live reconnect 必须先通过生命周期测试与真实断流压力验证。

## 3. 已确认的现有缺陷

| 编号 | 缺陷 | 影响 |
|---|---|---|
| S1 | 三端 Room VM 把 `KSPlayerLayer.delegate` 从 `KSVideoPlayer.Coordinator` 抢走 | Coordinator 状态冻结在 `.initialized`，视图只能拼接多份不一致状态 |
| S2 | iOS/tvOS 直链播放器把 `.readyToPlay` 当 `.playing` | 播放按钮、loading 和缓冲 UI 提前切换 |
| S3 | 直链播放器先创建 `KSOptions`，再修改 `KSOptions.firstPlayerType/secondPlayerType` | 实例已复制旧 `playerTypes`，实际内核顺序与 UI 代码意图不一致 |
| S4 | 非重试错误仅记录后被抑制 | 用户看不到失败态，也没有确定的终局 |
| S5 | tvOS 直链播放器用 `@State` 持有 `ObservableObject` Coordinator | Coordinator 发布的状态不保证驱动外层 View 更新 |
| S6 | tvOS 直链“刷新”调用 `seek(0)` | 对不可 seek 的直播流无效 |
| S7 | macOS 多窗口播放器共享 `MPRemoteCommandCenter`，单窗口 stop 可能移除其他窗口 target | 多窗口远程控制互相干扰 |
| R1 | LL-HLS 只用 URL 中 `llhls.m3u8` 推断 | 插件明知流语义时仍无法显式控制 |
| R2 | `LivePlaybackHints` 没有显式 KSPlayer 内核顺序 | 插件优先策略不能完整落地 |

## 4. 分层设计

```text
AngelLiveCore
  PlaybackStatusMachine       准确的展示状态与状态转移
  RoomPlaybackResolver        插件提示优先的播放计划
  PlaybackRecoveryCoordinator 逻辑会话级恢复与熔断
  PlaybackSession/SurfaceSlot 多画面扩展模型（后续阶段）

AngelLiveDependencies
  KSPlayerPlaybackAdapter     KSPlayer 状态/选项/采样映射
  KSVideoPlayer.Coordinator   KSPlayer 的唯一 layer delegate

Platform apps
  iOS controller              触控、方向、PiP、后台播放
  macOS controller            键鼠、窗口、全屏、多窗口 owner
  tvOS controller             Focus Engine、Siri Remote、系统音量 UI
```

共享的是状态语义、播放计划、恢复算法和命令协议；不共享平台控制层。

### 4.1 Delegate 所有权

`KSVideoPlayer.Coordinator` 保持 `KSPlayerLayer.delegate` 的唯一所有者。业务层通过 KSPlayer 已提供的回调接收事件：

- `onStateChanged`
- `onFinish`
- `onPlay`
- `onBufferChanged`
- `onURLChanged`

不再执行 `playerLayer.delegate = viewModel`。这样既符合 KSPlayer 风格，也让 Coordinator 的 `@Published state`、时间模型、遮罩状态和业务恢复逻辑同时工作。

若将来一个回调需要多个业务订阅者，再在 `AngelLiveDependencies` 增加 token 化 observer hub；不把多播逻辑塞回平台 View。

## 5. 准确播放状态机

### 5.1 展示状态

```swift
enum PlaybackStatus {
    case idle
    case loading
    case buffering
    case paused
    case playing
    case ended
    case failed(message: String?)
}
```

`RecoveryPhase` 继续描述“健康/疑似卡顿/恢复第几步/熔断”；它不能代替用户可见播放状态。两者是正交维度。

### 5.2 KSPlayer 映射表

| 输入 | 附加事实 | 展示状态 | 说明 |
|---|---|---|---|
| 加载请求已发出 | - | `loading` | 覆盖拉地址和创建 layer 阶段 |
| `.initialized` | 当前会话有效 | `loading` | reset/replace 后等待 prepare |
| `.preparing` | - | `loading` | 正在打开输入与探测流 |
| `.readyToPlay` | 任意 | `loading` | 只表示 ready；自动播放尚未必产生播放态/首帧 |
| `.buffering` | 任意 | `buffering` | 不用 `KSPlayerState.isPlaying` 把它伪装成 playing |
| `.bufferFinished` | `layer.player.isPlaying == true` | `playing` | 唯一正常进入 playing 的 KSPlayer 状态 |
| `.bufferFinished` | `layer.player.isPlaying == false` | `paused` | 处理事件时序和主动暂停竞态 |
| `.paused` | - | `paused` | 用户暂停、系统中断都一致 |
| `.playedToTheEnd` | - | `ended` | 直播恢复协调器可随后触发新一轮 `loading` |
| `.error` / finish 非重试错误 | 错误文本 | `failed` | 必须有可见终局 |
| 会话停止/页面退出 | - | `idle` | 清除上一个资源的粘性状态 |

状态机只消费 KSPlayer 事实，不从“按钮上次被点击”猜测最终状态。按钮命令发出后等待 KSPlayer 回调确认。

### 5.3 状态与 UI 的单一口径

- loading overlay：`loading` 或 `buffering`。
- 播放按钮：仅 `playing` 显示 pause 图标。
- 主动暂停：`paused` 不显示 loading。
- 错误页：`failed`；恢复协调器正在恢复时可保持 loading 并显示恢复文案。
- `isLoading` 仅表示插件网络请求，不能再兼任播放器状态。

## 6. 插件优先的 HLS / LL-HLS / FLV 路由

### 6.1 向后兼容的提示模型

在现有 `LivePlaybackHints` 上增加可选字段：

```swift
enum LivePlaybackLatencyMode: String, Codable, Sendable {
    case standard
    case lowLatency
}

enum LivePlaybackEngine: String, Codable, Sendable {
    case mePlayer
    case avPlayer
}

struct LivePlaybackHints {
    var streamFormat: LivePlaybackStreamFormat?
    var latencyMode: LivePlaybackLatencyMode?
    var preferredEngines: [LivePlaybackEngine]?
    var isLive: Bool?
    var requiresCustomSegmentLoader: Bool?
    var selectionBehavior: LivePlaybackSelectionBehavior?
    var startPositionSeconds: Double?
}
```

所有新增字段可选，旧插件 JSON 无需修改即可继续解码。`preferredEngines` 使用 KSPlayer 语义，宿主映射为 `KSMEPlayer.self / KSAVPlayer.self`。

插件返回示例：

```json
{
  "streamFormat": "hlsLive",
  "latencyMode": "lowLatency",
  "preferredEngines": ["avPlayer", "mePlayer"],
  "isLive": true
}
```

标准 HLS 可省略 `preferredEngines`，宿主默认使用 `mePlayer -> avPlayer`；FLV 即使误填
`avPlayer` 也会过滤不兼容项并回落 `mePlayer`，不会把 FLV 交给系统播放器。

### 6.2 决策优先级

```text
插件 preferredEngines（过滤宿主不可用内核并去重）
  -> 插件 streamFormat + latencyMode + requiresCustomSegmentLoader
  -> 插件 streamFormat
  -> liveCodeType
  -> URL/扩展名推断（最后托底）
```

只有显式顺序为空、包含未知值或过滤后没有可用内核时，才进入下一层。

### 6.3 默认路由

| 流语义 | 默认 `playerTypes` | `isLive` 目标语义 | 说明 |
|---|---|---|---|
| LL-HLS live | `[KSAVPlayer, KSMEPlayer]` | `true` | AV 原生支持 PART/PRELOAD-HINT，ME 兜底 |
| 标准 HLS live | `[KSMEPlayer, KSAVPlayer]` | `true` | ME 提供可控 IO/统计，AV 兜底 |
| FLV live | `[KSMEPlayer]` | `true` | AV 不支持 FLV |
| DASH live | `[KSMEPlayer]` | `true` | AV 不作为默认解码器 |
| HLS VOD | 按插件提示；缺省 `[KSMEPlayer]` | `false` | 支持 seek/ended 语义 |
| unknown | `[KSMEPlayer]` | 由插件/房间语义确定 | 不根据未知 URL 强行走 AV |

三端直播 Room VM 现已使用插件/resolver 得出的真实 `isLive`。KSMEPlayer 负责同一地址的轻量重连，只有其内部重连最终失败或遇到不可内部恢复的 EOF 时，`PlaybackRecoveryCoordinator` 才重取地址并重建整个会话。

### 6.4 每会话 KSOptions

每次选择流后构造独立 options 快照，禁止先创建实例再修改 `KSOptions` 静态默认值：

```text
RoomPlaybackPlan
  -> playerTypes
  -> isLive
  -> userAgent
  -> headers
  -> startPosition
  -> PiP/background/remote-control policy（平台注入）
  -> KSOptions instance
```

静态 `KSOptions.*` 只保留真正的进程级默认值。流路由必须写入本次会话的 `option.playerTypes`。

## 7. 三端能力保留矩阵

| 能力 | iOS | macOS | tvOS |
|---|---:|---:|---:|
| 播放/暂停/刷新 | 保留 | 保留 | 保留 |
| 清晰度/CDN | 保留 | 保留 | 保留 |
| 弹幕与设置 | 保留 | 保留 | 保留 |
| 播放统计 | 保留 | 保留 | 保留 |
| PiP | 保留 KSComplexPlayerLayer 流程 | 保留现状 | 不新增自定义行为 |
| 后台音频/Now Playing/远控 | 保留并回归测试 | 多窗口 owner 化 | 保留系统行为 |
| 手势/方向锁/亮度音量 | 独立保留 | 不适用 | 不套用 iOS 手势 |
| 键鼠/窗口/置顶/全屏 | 不适用 | 独立保留 | 不适用 |
| Focus/Siri Remote/Menu | 不适用 | 不适用 | 独立保留并真机测试 |

macOS 的 Remote Command 需要引入“活动播放会话 owner”：只有前台/最后交互窗口注册或响应全局命令，关闭其他窗口不能 `removeTarget(nil)` 清掉 owner 的 target。

## 8. 多画面扩展扣子

先定义模型边界，不在本轮实现多路同步解码：

```swift
struct PlaybackSurfaceID: Hashable, Sendable { ... }

enum PlaybackSurfaceRole: Sendable {
    case primary
    case secondary
    case overlay
    case preview
}

struct PlaybackSessionDescriptor: Sendable {
    let surfaceID: PlaybackSurfaceID
    let role: PlaybackSurfaceRole
    let plan: RoomPlaybackPlan
}
```

约束：

- 状态、恢复预算、URL、options、统计都按 `surfaceID` 隔离。
- PiP、Now Playing、Remote Command、音频焦点是有 owner 的全局能力，由 primary/active session 仲裁。
- 平台控制层通过 `activeSurfaceID` 发命令，不直接依赖全局唯一 player。
- 多画面容器可以换布局，不需要修改插件路由或单会话状态机。

## 9. 实施阶段

### Phase 1：状态真源与事件接线

- 新增纯 Swift `PlaybackStatusMachine` 与状态转移测试。
- 使用 `KSVideoPlayer.Coordinator.onStateChanged/onFinish`，移除三端 Room VM 的 delegate 抢占。
- iOS/tvOS 直链播放器停止把 `.readyToPlay` 映射为 playing。
- 非重试错误进入 `failed`，不再只打日志。
- 结果：三端 Coordinator 状态恢复更新，loading/pause/play/buffer/error 有统一语义。

### Phase 2：插件优先播放计划与实例 options

- [x] 扩展 `LivePlaybackHints`，补解码与 resolver 测试。
- [x] 建立 `KSOptions` per-session configurator。
- [x] 三端 Room 播放统一通过 configurator；直链无插件时使用实例级原生推断托底。
- [x] 验证 HLS、LL-HLS、FLV 的内核顺序、冲突过滤和 fallback。

实现说明：`KSPlayerSessionConfigurator` 同时应用 `playerTypes / UA / headers / isLive`。三端 Room
会话使用 `.playerManaged`，将 plan 的真实 live 语义传给 KSPlayer；`.applicationManaged` 仍作为
显式选择保留，但不再是默认规避路径。

### Phase 3：恢复、直播语义与错误终局

- [x] 将 `PlaybackStatusMachine` 与 `PlaybackRecoveryCoordinator` 接成明确的双状态模型。
- [x] 本地 KSPlayer fork 在关闭旧 `AVFormatContext` 前同步停止 track、等待 decode operation 退出并释放 decoder。
- [x] 重连时不再复用已 shutdown 的图片字幕 track。
- [x] 三端 Room 切换为 `.playerManaged`，恢复插件/resolver 的准确 `isLive`。
- [x] 保留应用层恢复协调器，处理 KSPlayer 内部重连失败、地址过期、预算耗尽和主播下播。

验证记录：异步 track 启停/幂等 shutdown 循环 100 次通过；本机 FLV 限速断流测试在 22 秒内完成
4 次 HTTP 建连，KSMEPlayer 持续为 `playing`，未出现 `avcodec_send_packet`/已释放 context 崩溃。
KSPlayer `swift build`、AngelLiveCore 55 项测试及 iOS/tvOS/macOS Debug 构建均通过。KSPlayer 上游
全量测试仍有一个与本次改动无关的编译基线问题：`FFmpegUtilityTests.conversionAudio` 继续调用已删除的
`mediaType:` 参数；生命周期与断流测试已分别定向执行通过。

### Phase 4：平台能力回归

- iOS：PiP 自动进入/退出、后台音频、来电中断恢复、Now Playing、锁屏/耳机远控。
- macOS：多窗口、活动 owner、关闭非活动窗口、全屏、置顶、键鼠控制。
- tvOS：Focus 路径、Play/Pause、Menu 层级、统计面板、系统音量 HUD；Focus 与性能必须真机验证。

### Phase 5：多画面基础

- 引入 `surfaceID`/role/session registry，不开启产品 UI。
- 把全局媒体能力迁移为 active-session ownership。
- 添加两会话并存的状态与资源释放测试。

## 10. 测试与验收矩阵

| 场景 | iOS | macOS | tvOS | 核心断言 |
|---|---:|---:|---:|---|
| HLS live，ME 首选成功 | 模拟器+真机 | 真机 | 真机 | playerTypes 顺序、首帧、状态 playing |
| HLS live，ME 失败 AV fallback | 真机 | 真机 | 真机 | 一次 fallback，不提前 failed |
| LL-HLS，插件显式 lowLatency | 真机 | 真机 | 真机 | AV 首选，非 URL 猜测 |
| FLV live | 真机 | 真机 | 真机 | 只实例化 ME，持续播放 |
| ready 后首帧前 | 自动测试 | 自动测试 | 自动测试 | 始终 loading，不显示 pause 图标 |
| 播放中断网/恢复 | 真机 | 真机 | 真机 | playing -> buffering/recovering -> playing |
| 用户主动暂停 | 真机 | 真机 | 真机 | paused 不出现 loading，不触发 watchdog |
| 不可重试错误 | 自动+真机 | 自动+真机 | 自动+真机 | failed 可见且不无限重试 |
| CDN/token 刷新 | 自动+真机 | 自动+真机 | 自动+真机 | 同逻辑会话不重置恢复预算 |
| iOS 后台/PiP | 真机 | - | - | 音频、PiP、Now Playing 不回退 |
| macOS 两窗口 | - | 真机 | - | 关闭 B 不破坏 A 的远控 |
| tvOS Remote/Focus | - | - | 真机 | 焦点、Menu、Play/Pause 全路径可达 |

## 11. Phase 1 完成标准

- Core 状态机测试覆盖映射表所有分支，特别覆盖 `readyToPlay != playing`。
- 三端 Room 播放不再覆盖 `playerLayer.delegate`。
- `KSVideoPlayer.Coordinator.state` 在三端可正常更新。
- loading、buffering、pause、playing、failed 仅来自统一状态语义。
- iOS PiP/后台相关代码路径未删除，编译与基础回归通过。
- 记录尚未完成的真机矩阵，不用模拟器结果替代 tvOS Focus、iOS PiP 或后台音频验收。

## 12. 与旧文档的关系

- `PlaybackRecoveryCoordinator.md` 的逻辑会话熔断和恢复阶梯继续有效。
- `PlaybackResilienceRoadmap.md` 中与当前实现冲突的旧 HLS 默认策略，以本文第 6 节为准。
- `BackgroundForegroundFreezeBug2.md` 的诊断保留，后续归入 Phase 4 iOS 回归。
