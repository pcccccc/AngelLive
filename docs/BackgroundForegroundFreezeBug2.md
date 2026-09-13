# Bug2 修复文档:iOS 直播播放中「后台→前台」概率卡死

> 2026-09-13 依赖核对更正：当前锁定的 KSPlayer 5.0.0（`93e942ae1f9dbdf8c2a4220ef2437073fdb575de`）没有实现本页历史 F5 所称的同步停止解码后再关闭上下文。Bugsnag 的 7 个 tvOS 事件同时命中旧解码器重建与读线程重连，当前依赖仍存在旧上下文提前释放风险；见 [本次崩溃研究](BugsnagCrashResearch20260913.md)。这与本页已采证的 iOS 渲染冻结不是同一结论，不能将一项的修复状态用于另一项。

> 2026-09-07 宿主接入核对：iOS FullUI 已将业务状态、结束事件接入 `KSCorePlayerView` 的统一回调，取消 `onAppear` 对同一 Coordinator 回调的覆盖。相同 URL 的 KSPlayer 重连改为显式替换媒体项并重新准备播放，不再通过 URL 临时置空等待 SwiftUI 拆建视图；保留活跃画中画控制器的 delegate。不同内核类型仍走 KSPlayer 的 `set(url:options:)`。这些是宿主接入修复，**不是后台冻结根因或修复成功的证据**；下述历史诊断需按当前 KSPlayer 版本和新安装包重新验证。
> 验证：最后源码编辑后，Xcode MCP workspace `BuildProject` 成功，确认重新编译修改文件，Navigator error 为 0。iPhone 17 Pro Max 模拟器 / iOS 27.0（24A5423a）重新执行 `DeviceInteractionInstallAndRun` 成功；从已有收藏进入播放、暂停/恢复、手动重载、退出后重新进入播放均通过。同地址分支未独立证明，真机快速前后台与画中画未验证。`AngelLive` scheme 当前没有自动测试，未运行单元测试；macOS、tvOS 未验证。
>
> 状态:埋点已就位,待真机采证 · 2026-06-21
> 平台:iOS(iPhone,KSPlayer 内核,Metal 渲染)
> 现象:横屏/竖屏播放中按 Home 进后台,再返回前台,**有概率**画面定格;此时点「重新加载」新画面仍卡,只有**退出直播间重进**才能恢复。
> 2026-07-14 更新:F5 已在 KSPlayer Phase 3 修复，Room 会话恢复真实 `isLive`；其余后台/前台与 Metal 假设仍需真机验证。
> 2026-07-31 更新:
> - **A 类已由 2026-06 真机日志确诊**(playhead 推进 / buffered 满 / displayFPS 恒 0),B、C 已排除。详见 §3.1。
> - **触发条件修正为「快速连续进出后台」**,非长时间挂后台。旧复现步骤可能复现不出来,§3.1 已重写。
> - **`pause()→0.12s→play()` 轻踢已真机证伪并丢弃**,排掉「display link 仅被暂停」这一整类假设。详见 §4.3。
> - 采证埋点已落地(AngelLive 侧 `5409059`;KSPlayer `codex/foreground-diagnostics` 分支**改动未提交,且全部在 `#if DEBUG` 内,零行为变更**)。
> - 除已丢弃的轻踢外,**尚无任何修复代码**。`grep hardReload` 全工程零命中。
> - 新增两条代码事实 F10 / F11:上游针对「回前台黑屏」的补丁**只覆盖了两条渲染路径中的 displayView 一条,metal 路径漏填**。
> - §4.3 由「hardReload 边界」改写为**六档恢复阶梯**;hardReload 降为末档且不作为自动策略,**推荐起点为档 1.5(重建 CADisplayLink)**。

---

## 0. 重要前提:先抓现场,别靠读代码定论

参考 Axiom `axiom-graphics` 技能结论:**Metal 渲染层卡死类问题必须用运行时证据定位(GPU Frame Capture / `currentDrawable` 是否为 nil),靠读代码猜「猜要 1–4 小时,抓现场 5–10 分钟」。**

本文已确认的部分是「代码事实」(带 `file:line`),候选根因是「待证据区分的假设」。**动手修之前必须先用 §3 的观察矩阵把方向锁死**,否则可能修错层。

---

## 1. 代码层已确认的事实(非推测)

| # | 事实 | 位置 |
|---|------|------|
| F1 | 进后台且 `canBackgroundPlay=false`(默认)时,KSPlayer 内核必定 `pause()` | `KSPlayer/AVPlayer/KSPlayerLayer.swift:921-939` |
| F2 | 回前台(非画中画)只调 `player.enterForeground()`,**只恢复 Metal 渲染定时器,不调用 `play()`** | `KSPlayerLayer.swift:941-967` / `MEPlayer/MetalPlayView.swift:257` |
| F3 | App 自己的 `didBecomeActive` 处理**只关画中画**,不重连/不踢播放 | `PlayerContainerView.swift:150-164` |
| F4 | `MetalPlayView.enterBackground` 在 `!isPaused` 时会按 fps 在后台继续 `draw`;但 F1 的 `pause()` 已把 `isPaused` 置真,故正常不会在后台跑 GPU | `MetalPlayView.swift:248-255` |
| F5 | **当前锁定依赖未解决（2026-09-13 更正）:** 三端 Room 使用真实 `isLive`，但重连先关闭旧 context，异步轨道 shutdown 也未等待 decode operation 退出，仍有借用指针失效风险 | `KSPlayer/MEPlayerItem.swift` / `MEPlayerItemTrack.swift` |
| F6 | 恢复协调器采样对 **KSAVPlayer(HLS 流)直接返回 nil** → 这类流**没有零吞吐 stall 检测** | `PlaybackRecoveryAdapter.swift:98-112` |
| F7 | 手动 reload / 恢复动作都走 `changePlayUrl`,复用全局 `@StateObject playerCoordinator`(`.id("stable_player")` 永不重建);URL 变化时 `KSPlayerLayer.set(url:)` 只 `player.replace(url:)`,**复用同一个 player 实例**;只有退房间才会重建 coordinator | `DetailPlayerView.swift:22` / `KSPlayerLayer.swift:199-224` |
| F8 | `assignCurrentPlayURL`:URL 相同走 `nil→url` 真重建;URL 变化只换地址,**跳过重建** | `RoomInfoViewModel.swift:342-362` |
| F9 | 手动 reload 调 `episodeChanged(streamKey: roomId)`,同房间 early-return,**不会重新武装已熔断的监控** | `PlaybackRecoveryCoordinator.swift:196-208` |
| F10 | **回前台补帧只覆盖 displayView 一条路径。** `MetalPlayView.enterForeground()` 里那句带注释「解决从后台一会儿在进入到前台的时候，displayView黑屏的问题」的补帧,条件是 `if metalView.isHidden`(即**仅** AVSampleBufferDisplayLayer 路径)。走 CAMetalLayer 时**不补帧、不强制重绘** | `KSPlayer/MEPlayer/MetalPlayView.swift`(`enterForeground()`) |
| F11 | `enterForeground()` 只置 `isBackground = false`,**从不碰 `isPaused`**;而 `displayLink.isPaused` 由 `isPaused` 的 didSet 驱动。故 F1 在后台置的暂停态回前台后不会自动解除,**display link 保持停止** | `MetalPlayView.swift`(`enterForeground()` / `isPaused` didSet) |

由 F1+F2+F3 可知:回前台后内核停在「暂停 + 仅恢复渲染」状态,App 这层没有任何主动恢复动作。这是后续所有候选根因的共同土壤。

**F10 的意义:上游作者撞过同一个 bug 并已修复,但只修了两条渲染路径中的一条。** 本 bug 的 A 类现象恰好发生在没修的那条上——这把 A 类从「需要重写 Metal 生命周期」降级为「补一个上游已验证过的对称补丁」。仍需运行时证据确认(见 §3 / §4.4),但着手成本远低于原估计。

---

## 2. 候选根因(待证据区分)

### A. 渲染/Drawable 失效(Metal 层)
后台→前台过程中 `CAMetalLayer` 的 drawable 失效或渲染管线被打断,回前台 `nextDrawable` 拿不到/管线未恢复 → **声音在播,画面定格在最后一帧**。属图形层,需 GPU Frame Capture 确认。

### B. 直播管线陈旧(解复用/网络)
后台期间直播连接被服务器掐断或直播边缘漂移过远;回前台 demuxer 想从旧位置续读但数据已不存在。当前锁定 KSPlayer 的重连仍有 F5 所述生命周期风险，也需要真机确认后台挂起/恢复时是否触发该路径。

### C. 暂停未被恢复(纯生命周期)
F2 表明前台不自动 `play()`。若没有别处补 `play()`,就停在暂停态 → **画面是「暂停的最后一帧」,手动点播放可能能恢复(或恢复后再走 B)**。

> 三者都被 F6/F7/F8/F9 放大成「救不回」:HLS 无 stall 采样(F6)、reload 复用死实例(F7/F8)、熔断后不再武装(F9)。这解释了「reload 无效、只能退房间」。

---

## 3. 观察矩阵:复现时按这几条定方向

| 卡死时观察 | 指向 | 含义 |
|---|---|---|
| 声音继续 + 画面定格 + 左上角网速 HUD 还在跳 | **A** | 管线活着,卡在渲染/drawable |
| 声音停 + 网速归零/不动 | **B** | 管线整体死(网络/解复用) |
| 声音停 + 手动点播放能恢复 | **C** | 仅暂停未恢复 |
| 看日志 `[PlayerFlow] KS state changed ->` 最终停在 `.paused` | 倾向 **C** | 内核停在暂停 |
| 停在 `.buffering` 且不前进 | 倾向 **B** | 在等永远不来的包 |
| 停在 `.bufferFinished`/`.readyToPlay` 但画面不动 | 倾向 **A** | 状态在播但没出帧 |

### 3.1 ⚠️ 复现步骤(2026-07-31 修正)

> **旧步骤「进后台停 30s+ → 回前台」可能复现不出来。** 2026-06 真机日志显示实际触发条件是**快速连续进出后台**——日志里能看到一次只走到 `inactive` 没到 `background`,与完整的 background 事件交错。推测是打乱了 KSPlayer 前后台 / CADisplayLink 的暂停-恢复时序。

真机连 Xcode,Console 过滤 `[PlayerFlow]`(AngelLive 侧)与 `[ForegroundTrace]`(KSPlayer 侧):

1. 进直播间,确认正常出画。
2. **快速连续进出后台数次**(Home 划出立刻划回,重复;夹杂一两次完整的长时间后台),直到画面定格、声音继续。
3. 记录 §3 观察矩阵各项 + 进/出后台与回前台各打印了什么。
4. 再点重新加载,看 state 走到哪。
5. A 类再补一次 GPU Frame Capture。

长时间后台(30s+)仍应各跑一轮作为对照——**若长后台不复现、只有快速进出复现,这本身就是有价值的定位信息**(指向时序竞态而非资源回收)。

> **已确诊结论(2026-06 真机)**:candidate **A**。`playhead` 每秒 +1(音频/解码在跑)、`buffered` 满 7s+(没饿死)、`displayFPS` 恒 0、drop 计数不动 → 视频一帧不出。B/C 已被这组数据排除。
>
> **⚠️ 判读禁区**:FFmpeg 内核的 `dynamicInfo.bytesRead` / `networkSpeed` **恒为 0,健康播放时也是 0**。verdict 不能依赖吞吐,只能看 playhead 推进 + fps + buffered 走势。§3 表格中「网速 HUD 还在跳」一行对 FFmpeg 内核不适用。

---

## 4. 修复方案

### 4.1 先做无副作用现场采集

当前实现已补齐以下 Debug 证据,但**不会自动调用 `play()`、`pause()`、`readNextFrame()` 或重建播放器**:

- AngelLive 在 `willResignActive`、`didEnterBackground`、`willEnterForeground`、`didBecomeActive` 记录 `engineState`、`playerState`、`isPlaying`、进后台前播放意图、playhead、buffer、bytes、network speed、FPS 和播放 surface 状态;
- 回前台 watchdog 在 `+1/+2/+3/+5s` 采样同一组状态,只读判定 A/B/C;
- Debug KSPlayer 分支记录 `KSPlayerLayer` 实际收到的前后台事件、实际执行的 `player.enterBackground()` / `player.enterForeground()` / `play()` / `pause()`;
- `MetalPlayView` 记录 `isPaused`、后台标记、display link 状态、渲染路径和视图/Drawable 几何信息;
- 回前台后第一次真正进入 `CAMetalLayer.nextDrawable()` 时记录成功,或记录 `nextDrawable` 不可用;不会为了探测而额外调用 `nextDrawable()`;
- iOS Debug scheme 已打开 Metal API Validation 和 GPU Frame Capture。真机卡住时使用 Xcode 的 Capture GPU Frame,不能用 FPS 单独推断 Drawable。

KSPlayer 诊断分支位于本机相邻路径 `/Users/pangchong/Desktop/Git/KSPlayer`,分支 `codex/foreground-diagnostics`;远程依赖没有这些埋点时,AngelLive 侧日志仍可用,但缺少内部 `enterForeground`/Drawable 证据。

> **⚠️ KSPlayer 侧埋点尚未提交。** 该分支上 5 个文件(`KSAVPlayer` / `KSPlayerLayer` / `KSMEPlayer` / `MetalPlayView` / `MetalRender`)处于 modified 未提交状态。已核对 diff:**全部包裹在 `#if DEBUG` 内,只有 `KSLog` 与 `ForegroundDrawableProbe`,不含任何 `play()` / `pause()` / 重建动作**。换机器或 clean checkout 会丢失,采证前先确认这些改动在位。

### 4.2 按证据修复,不预设是 KSPlayer

- **C 类:暂停未恢复** — 只有在日志确认「进后台前在播、回前台后 `.paused`、没有实际 `play()`」时,在 AngelLive 生命周期层对原本在播的会话补一次幂等 `play()`。用户原本暂停的会话不能自动播放。
- **A 类:渲染循环/Drawable** — 只有在 playhead 或音频仍推进、FPS 为 0,并且 KSPlayer 日志/GPU Frame Capture 确认 display link 或 `nextDrawable` 异常时,才修改 KSPlayer 的 `MetalPlayView`/Metal 渲染生命周期。
- **B 类:直播管线** — 只有在 playhead 停止、buffer 耗尽并且日志确认取流、demux 或 reconnect 断供时,才修 AngelLive 取流/重连策略或 KSPlayer 管线;不能仅凭“画面卡住”就重建。

### 4.3 恢复阶梯:从最轻到最重,逐档升级

**硬重建播放器的用户体验代价过高(黑屏 + 重缓冲 + 重连),不接受把它当作回前台的常规策略。** 下表是 hardReload 之前的四档,按代价升序;每一档都保留解码器与网络连接存活。

| 档 | 动作 | 触点 | 用户可感知代价 | 状态 |
|---|------|------|---|---|
| ~~**0**~~ | ~~对「进后台前在播」的会话补一次**幂等 `play()`**~~ | AngelLive 生命周期层 | 无 | ❌ **大概率已证伪,见下** |
| **1** | metal 路径补上与 displayView **对称的回前台重绘**——即把 F10 那个补丁的覆盖面补全 | `MetalPlayView.enterForeground()` | 无 | 未试 |
| **1.5** | **重建 CADisplayLink**(`invalidate()` + 重新 `add(to:forMode:)`),而非仅翻 `isPaused` | `MetalPlayView`(`displayLink`) | 无 | 未试 ← **推荐起点** |
| **2** | 抖动 `drawableSize` 强制 `CAMetalLayer` 重建 drawable pool | `MetalPlayView` / `MetalView` | 无 | 未试 |
| **3** | 翻到 display-layer 路径兜底(**双路架构本已存在**,`draw(force:)` 里按 `options.isUseDisplayLayer` 常态切换) | `MetalPlayView.draw(force:)` | 无,解码器完全不动 | 未试 |
| **4** | 只替换 `MetalView`(新建 `CAMetalLayer`),保留 player / 解码器 / 音频 | `MetalPlayView` | 最多闪一帧黑 | 未试 |
| ~~5~~ | ~~`hardReloadPlayer()`~~ | — | ~~黑屏 + 重缓冲 + 重连~~ | **不接受作为自动策略** |

#### ⚠️ 档 0 已被真机证伪(2026-06)

曾在 AngelLive 的 FG-watch 循环里试过 `pause() → 0.12s → play()` 轻踢,意图正是翻转 `displayLink.isPaused` true→false 踢活 CADisplayLink —— **真机验证无效**。该改动**已丢弃,当前工作区不存在**。

这条负面结果很有价值,它排掉了一整类假设:

- 卡死**不是**「display link 仅被暂停」——`isPaused` 能翻但画面不回来。
- 因此**幂等 `play()`(档 0)走同一条通路,大概率同样无效**,不必再试。
- 剩下两种可能:① display link 已**失效**(需重建,不是 `isPaused` 能救的)→ **档 1.5**;② 卡在更下游的 drawable / render source 层 → 档 2 及以上。

**推荐起点因此是档 1.5,而非档 0/1。** 档 1 仍值得顺手做(F10 的补丁覆盖面本就该补全,3 行,且能独立验证 render source 是否供帧),但单独它未必够。

`hardReloadPlayer()` 仍只允许在以下两种情况使用:

1. 用户明确点击「重新加载」或确认恢复;
2. 有运行时证据证明当前 player 实例不可恢复,且**档 0–4 全部失败**。

即使需要重建,也应记录触发原因、旧实例状态和新实例首帧结果,避免把重建当成根因修复。

### 4.4 日志判读:用已有埋点定档

采证命令:真机连 Xcode,Console 过滤 `[ForegroundTrace]`(KSPlayer 侧)与 `[PlayerFlow]`(AngelLive 侧),播放 → 进后台 30s+ → 回前台。

| 日志特征 | 卡在哪 | 对应档 |
|---|---|---|
| `displayLinkPaused=false` 但 `[ForegroundTrace]` 之后再无 draw 相关输出 | display link **已失效**:标记为运行但回调不来(与轻踢证伪结论一致) | **档 1.5** |
| `displayLinkPaused=true` 且轻踢式操作能翻回 false | 仅被暂停 —— **但此路已被真机排除**,若真出现说明与 2026-06 现场不是同一问题,需重新定向 | 档 0 |
| 有 `nextDrawable acquired` 但画面仍不动 | 拿到 drawable 却没有帧被喂进来(印证 F10) | **档 1** |
| `nextDrawable unavailable afterForeground=true` 反复出现 | 真·drawable 饥饿 | **档 2 → 3** |
| `renderPath=display-layer` 时不复现,仅 `renderPath=metal` 复现 | 反证只有 metal 路径漏补丁 | **档 1** |

以上映射是**代码事实 + 2026-06 真机负面结果**推导出的预期,不是已观测的正面结论;新一轮真机日志与之冲突时以日志为准。

**最省事的一次采证**:按 §3.1 复现后,先只看两件事 —— ① `[ForegroundTrace]` 里 `enterForeground` 之后还有没有 draw 输出;② `nextDrawable` 是 acquired 还是 unavailable。这两个二元答案就能把档位锁到 1 / 1.5 / 2-3 其中之一。

---

## 5. 验证

1. **复现回归**:横屏 + 竖屏各跑「进后台 30s+ → 回前台」×20 次,统计卡死率(修前 vs 修后)。
2. **HLS 专项**:挑确定走 KSAVPlayer 的 m3u8 直播间,验 §4.3 阶梯在该路径下的行为。
3. **双渲染路径都要覆盖**:分别构造 `renderPath=metal` 与 `renderPath=display-layer` 的直播间各跑一轮。F10 预期只有 metal 路径复现——若 display-layer 也复现,说明 F10 不是主因,需回 §3 重新定向。
4. **reload 路径**:卡死后点重新加载必须能恢复,不允许「只能退房间」。
5. **不回归 Bug1**:横屏回前台仍保留横屏(见 `DetailPlayerView.reassertLandscapeOrientation()`)。
6. **不误伤用户暂停**:用户主动暂停后进后台再回前台,**不得**自动续播(档 0 的边界)。
7. **协调器单测**:若最终改动触及 `PlaybackRecoveryCoordinator` 的熔断/重新武装(F9),补 `PlaybackRecoveryCoordinatorTests` 用例。

---

## 6. 关联

- `PlaybackRecoveryCoordinator` — 已上线的统一恢复协调器实现
- `docs/PlaybackResilienceRoadmap.md` — 整体韧性栈
- Bug1(横屏回前台变竖屏)修复:`DetailPlayerView.swift` `reassertLandscapeOrientation()` + scenePhase 记录 `wasLandscapeBeforeBackground`
