# Bug2 修复文档:iOS 直播播放中「后台→前台」概率卡死

> 状态:待运行时证据确认 · 2026-06-21
> 平台:iOS(iPhone,KSPlayer 内核,Metal 渲染)
> 现象:横屏/竖屏播放中按 Home 进后台,再返回前台,**有概率**画面定格;此时点「重新加载」新画面仍卡,只有**退出直播间重进**才能恢复。

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
| F5 | `option.isLive = false`(为绕开 KSPlayer reconnect 崩溃),IO 异常走 `.failed`/`finish`,**不会重连到直播边缘** | `RoomInfoViewModel.swift:124-128` |
| F6 | 恢复协调器采样对 **KSAVPlayer(HLS 流)直接返回 nil** → 这类流**没有零吞吐 stall 检测** | `PlaybackRecoveryAdapter.swift:98-112` |
| F7 | 手动 reload / 恢复动作都走 `changePlayUrl`,复用全局 `@StateObject playerCoordinator`(`.id("stable_player")` 永不重建);URL 变化时 `KSPlayerLayer.set(url:)` 只 `player.replace(url:)`,**复用同一个 player 实例**;只有退房间才会重建 coordinator | `DetailPlayerView.swift:22` / `KSPlayerLayer.swift:199-224` |
| F8 | `assignCurrentPlayURL`:URL 相同走 `nil→url` 真重建;URL 变化只换地址,**跳过重建** | `RoomInfoViewModel.swift:342-362` |
| F9 | 手动 reload 调 `episodeChanged(streamKey: roomId)`,同房间 early-return,**不会重新武装已熔断的监控** | `PlaybackRecoveryCoordinator.swift:196-208` |

由 F1+F2+F3 可知:回前台后内核停在「暂停 + 仅恢复渲染」状态,App 这层没有任何主动恢复动作。这是后续所有候选根因的共同土壤。

---

## 2. 候选根因(待证据区分)

### A. 渲染/Drawable 失效(Metal 层)
后台→前台过程中 `CAMetalLayer` 的 drawable 失效或渲染管线被打断,回前台 `nextDrawable` 拿不到/管线未恢复 → **声音在播,画面定格在最后一帧**。属图形层,需 GPU Frame Capture 确认。

### B. 直播管线陈旧(解复用/网络)
后台期间直播连接被服务器掐断或直播边缘漂移过远;回前台 demuxer 想从旧位置续读但数据已不存在。叠加 F5(`isLive=false` 不重连)→ **音视频整体死,吞吐归零**。

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

复现步骤:真机连 Xcode,Console 过滤 `[PlayerFlow]`,播放→进后台停 30s+→回前台,记录上表 + 进/出后台与回前台各打印了什么;再点重新加载,看 state 走到哪。A 类再补一次 GPU Frame Capture。

---

## 4. 修复方案

### 4.1 统一「硬重载」(三类根因的共同兜底,优先做)

现状 reload 之所以救不回,是因为复用了 wedged 的 `playerCoordinator`/player 实例(F7/F8)。新增一个**真正销毁重建播放器层**的入口,让「回前台恢复」「手动 reload」「协调器 reloadPlayArgs」统一走它:

- 在 `RoomInfoViewModel` 增加 `hardReloadPlayer()`:
  1. 无条件走 `nil → url` 重建(即 F8 中「URL 相同」那条路径,但对所有情况生效),强制 `compatiblePlayerSurface` 从视图树移除再加入 → KSVideoPlayer onDisappear 触发,player 层真正释放后重建;
  2. 重新拉 `getPlayArgs()`(token/线路可能已变)后再 set URL;
  3. 调 `recoveryCoordinator.start()` 并重置监控状态(配合 4.4)。
- `PlayerControlBridge.refreshPlayback`(`PlayerContainerView.swift:560`)、协调器 `reloadPlayArgs`(`PlaybackRecoveryAdapter.swift:70`)都改调 `hardReloadPlayer()`。

> 仅此一项就能修掉「reload 无效、只能退房间」——因为它把「退房间才会做的重建」搬到了 reload 路径。

### 4.2 回前台主动恢复(补 F2/F3 的缺口)

在 `PlayerContainerView` 的 `didBecomeActive`(`:150-164`,KSPlayer 分支)加入:
- 若回前台后**短时间内未恢复播放**(根据 §3 判定:state 仍 `.paused` 或画面不前进),直接 `viewModel.hardReloadPlayer()`;
- 直播场景**不要尝试「从旧位置续播」**(F5 决定了续不上),宁可硬重载到直播最新位置。

### 4.3 HLS/KSAVPlayer 盲区兜底(补 F6)

KSAVPlayer 没有 stall 采样,静默卡死协调器感知不到。给它加一个**前台后兜底计时**:回前台后 N 秒(如 5s)内若 `playhead` 不推进且未在播 → `hardReloadPlayer()`。可放在 `PlaybackRecoveryAdapter` 的采样层,或 View 层一个轻量 watchdog。

### 4.4 reload 后重新武装监控(修 F9)

`hardReloadPlayer()` 内显式重置协调器会话:要么给协调器加 `rearm()`(把 `monitoring=true`、`attempts=0`、`phase=.healthy` 并重启 driver),要么 reload 时用一个带版本号的 streamKey 让 `applyEpisode` 不再 early-return。避免「卡死熔断后,手动 reload 也唤不醒监控」。

### 4.5 (若 §3 判定为 A)渲染层专项

- 确认后台确无 GPU 提交(F4 路径在 `isPaused=true` 时不调度,验证之);
- 回前台强制重新取 drawable / 重绘一帧(`readNextFrame()` 已存在,`MetalPlayView.swift:244`);
- 若仍 wedged,4.1 的硬重载会重建整个渲染层兜底。

---

## 5. 验证

1. **复现回归**:横屏 + 竖屏各跑「进后台 30s+ → 回前台」×20 次,统计卡死率(修前 vs 修后)。
2. **HLS 专项**:挑确定走 KSAVPlayer 的 m3u8 直播间,重点验 4.3。
3. **reload 路径**:卡死后点重新加载必须能恢复,不允许「只能退房间」。
4. **不回归 Bug1**:横屏回前台仍保留横屏(见 `DetailPlayerView.reassertLandscapeOrientation()`)。
5. **协调器单测**:为 4.4 的 `rearm()` 补 `PlaybackRecoveryCoordinatorTests` 用例。

---

## 6. 关联

- `docs/PlaybackRecoveryCoordinator.md` — 协调器设计
- `docs/PlaybackResilienceRoadmap.md` — 整体韧性栈
- Bug1(横屏回前台变竖屏)修复:`DetailPlayerView.swift` `reassertLandscapeOrientation()` + scenePhase 记录 `wasLandscapeBeforeBackground`
