# 弹幕改版 §6.1 + §6.2 实施方案（切字号过渡 + 错落感）

> 状态:方案已评审通过 · 待实施 · 2026-06-25
> 上游依据:`docs/DanmakuRenderingRoadmap.md` §6.1、§6.2(结论:不上 Metal,现有 Swift 引擎低成本解决)
> 范围:本轮只做 §6.1(切字号 bug)、§6.2(错落感),均为 App-only、三端同步;**不含 §6.3 SC 付费置顶**(跨仓库 + 待设计,另案)

---

## 0. 背景与目标

- **§6.1 切字号过渡 bug**:当前每次 SwiftUI 刷新都无条件 `recalculateTracks()`,且重算会迁移 / `.stop()` 正在飞的弹幕 → 切字号时在飞弹幕跳行 / 消失 / 闪,连无关刷新(play/pause/seek)也无故抖动。
  **目标**:在飞弹幕保持原尺寸飞完,只有**新弹幕**用新字号;无关刷新不再扰动。
- **§6.2 错落感**:「从上往下第一个能放下就放」+ 同 tick 起点 x 相同 + 无速度抖动 + WebSocket 批量下发 → 一批弹幕成一道竖墙。
  **目标**:轨道随机化 + 去突发分发 + 速度微抖动。

---

## 1. 实施前已核实的关键架构事实(文档未提,影响方案)

| # | 事实 | 影响 |
|---|------|------|
| K1 | **双引擎**:iOS+macOS 用 `Shared/AngelLiveCore/.../DanmakuKit/Core/`;**tvOS 自带独立副本** `TV/AngelLiveTVOS/Third/DanmakuKit/Classes/Core/`(同名文件、行号不同、`displayTime` 默认 **5 vs 10**) | **所有引擎级改动必须改两份** |
| K2 | tvOS 目标**已广泛 `import AngelLiveCore`**(含其 `RoomInfoViewModel.swift`) | 去突发调度器放 AngelLiveCore,三端共用,**无需复制** |
| K3 | tvOS 的 `webSocketDidReceiveMessage` 回调**未**包 `Task { @MainActor }`(iOS/macOS 包了) | 接 `@MainActor` 调度器时 tvOS 需补包 |
| K4 | `trackHeight.didSet` 已 `guard oldValue != trackHeight`;真正冗余的是各 wrapper 里**显式**的 `recalculateTracks()` | §6.1 删冗余调用即可,不必动 didSet |
| K5 | tvOS 的 `findSuitableTrack` / `shoot` 与 shared 结构一致(无额外同步逻辑);`findSuitableSyncTrack` 是点播同步用,**不能**随机化 | §6.2 随机化只改 floating 的 `findSuitableTrack` |
| K6 | 三端 `trackHeight` 公式不同:iOS/tvOS `fontSize*1.35`,macOS `fontSize*1.2+12` | 改动需保各端公式不变 |

---

## 2. §6.1 切字号过渡 bug

### A. 引擎:重算不再扰动在飞弹幕(两份副本都改)

文件:`DanmakuView.swift` 的 `recalculateFloatingTracks`(shared 449-479 / tvOS 对应函数);top/bottom 同样处理保持一致。

- **缩轨道分支**(shared 462-469):**不再** `.stop()` 被裁掉的轨道;`removeLast` 只移除**空轨道**(`danmakuCount == 0`),非空轨道留到自然飞完后于后续重算淘汰。
- **positionY 重排循环**(shared 470-478):`positionY` **仅对空轨道**赋值 —— `if track.danmakuCount == 0 { track.positionY = ... }`;`index` / `stopClosure` 照常无条件设置(不移动 cell)。

原理:会迁移在飞 cell 的 `positionY.didSet`(`DanmakuTrack.swift` 70-79)只对空轨道触发 → **在飞弹幕零扰动**,新弹幕拿到新几何 Y。

**风险(已接受)**:缩轨道且旧非空轨道 Y 与新轨道重合时,旧批弹幕飞完前可能短暂重叠(自愈)。采用此低风险方案,拒绝更重的 defer-until-drain。

### B. 三端 wrapper:去掉冗余重算,frame 变化才重算

模式(各端公式不变):
```swift
if uiView.frame != newFrame { uiView.frame = newFrame; uiView.recalculateTracks() }
uiView.trackHeight = fontSize * <平台公式>   // didSet 仅在真变化时重算
```
- **iOS** `DanmuView.updateUIView`(41-54):frame 加门,删第 53 行裸 `recalculateTracks()`。
- **macOS** `DanmuView`:`updateNSView`(36-50,删 49 行裸调用)**和** `applyConfiguration`(99-111,删 106 行裸调用,保留 `play()`)。
- **tvOS** `DanmuView.updateUIView`(24-31):frame 加门,删 30 行裸调用;`paddingTop` / `displayArea` 各自 didSet 不动。

---

## 3. §6.2 错落感

### C. 轨道随机化(两份引擎,仅 floating 分支)

`findSuitableTrack` 的 `.floating` case(shared 562-568 / tvOS 556-562)。**不动** top/bottom,**不动** `findSuitableSyncTrack`。改为「最少弹幕 + 随机打破平局」:
```swift
let candidates = floatingTracks.filter { $0.canShoot(danmaku: danmaku) }
guard !candidates.isEmpty else { return nil }
let minCount = candidates.map(\.danmakuCount).min()!
return candidates.filter { $0.danmakuCount == minCount }.randomElement()
```
仍由 `canShoot` 把关,碰撞不变式不破。

### D. 去突发调度器(AngelLiveCore 共用,三端接入)

新增 `Shared/AngelLiveCore/Sources/AngelLiveCore/.../DanmakuShootScheduler.swift`:
```swift
@MainActor public final class DanmakuShootScheduler {
    public struct Config {
        public var window: TimeInterval = 1.2   // 一批摊开的时间窗
        public var jitter: TimeInterval = 0.25  // 每条释放的随机抖动
        public var maxBuffer: Int = 200         // 缓冲上限,超出丢最旧
    }
    public var config: Config                   // 运行时可调,便于真机调感
    public init(config: Config = .init())
    public func enqueue(_ shoot: @escaping () -> Void)  // FIFO,按 window/bufferCount 令牌桶节流释放,带 ±jitter
    public func reset()                                 // 切房清空
}
```

接入(**仅 ViewModel 层,不碰引擎**;底部聊天气泡 `addDanmuMessage` 保持即时、不进队列):
- **iOS** `RoomInfoViewModel`(773-789):`Task{@MainActor}` 内把直接 `shoot` 改为 `danmuShootScheduler.enqueue { [danmuCoordinator] in danmuCoordinator.shoot(...) }`;属性区加 `let danmuShootScheduler = DanmakuShootScheduler()`。
- **macOS** `RoomInfoViewModel`(706-722):同上。
- **tvOS** `RoomInfoViewModel`(640-642):**补包** `Task{@MainActor in danmuShootScheduler.enqueue { ... } }`。
- 切房处统一调用 `danmuShootScheduler.reset()`。

### E. 速度微抖动(三端 coordinator 建模型时,非引擎)

各 `Coordinator.shoot` 创建 `DanmakuTextCellModel` 后:
```swift
let base = model.displayTime                 // 自动取各端默认(shared 10 / tvOS 5)
model.displayTime = base * Double.random(in: 0.85...1.15)   // ±15%
```
- iOS(69 行后)、macOS(64 行后)、tvOS(45 行后)。
- 放建模型处而非引擎 `addAnimation`,避免 play/pause/update 重放时反复抖动。

---

## 4. 采用的默认(实施时可微调)

| 项 | 取值 | 备注 |
|---|---|---|
| §6.1 重排策略 | 空轨道才重排、缩轨道不停在飞弹幕 | 接受短暂自愈重叠,低风险 |
| §6.2.1 选轨 | 最少弹幕 + 随机平局 | 仍受 `canShoot` 约束 |
| §6.2.2 window / jitter / maxBuffer | 1.2s / ±0.25s / 200 | 运行时可调 |
| §6.2.3 速度抖动 | ±15% | `0.85...1.15` |
| tvOS 调度器 | 共用 AngelLiveCore | 已确认 tvOS 可 import |

---

## 5. 改动文件清单

- **引擎(×2)**:`Shared/AngelLiveCore/.../DanmakuKit/Core/DanmakuView.swift`、`TV/AngelLiveTVOS/Third/DanmakuKit/Classes/Core/DanmakuView.swift`(A 重排 + C 随机化)。
- **Wrapper(×3)**:`iOS/.../Player/DanmuView.swift`、`macOS/.../Views/DanmuView.swift`、`TV/.../DetailPlayer/DanmuView.swift`(B frame 门 + E 抖动)。
- **ViewModel(×3)**:iOS / macOS / tvOS `RoomInfoViewModel.swift`(D 调度器接入 + reset)。
- **新增**:`Shared/AngelLiveCore/.../DanmakuShootScheduler.swift`。

---

## 6. 实施顺序

1. §6.1 引擎重排(两份)→ 各端 build。
2. §6.1 三端 wrapper frame 门。
3. 真机验 §6.1。
4. §6.2.1 随机化(两份)。
5. §6.2.3 抖动(三端 coordinator)。
6. §6.2.2 新增调度器 + 三端 ViewModel 接入 + 切房 reset。
7. 真机验 §6.2。

---

## 7. 验证(每端:iOS 竖+横 / macOS 改窗口 / tvOS 1080p)

- **§6.1**:密集流下连续切字号 → 在飞弹幕保持原尺寸飞完、不跳行 / 不消失 / 不闪,新弹幕用新尺寸;play/pause/seek 等无关刷新弹幕不抖。
- **§6.2.1**:一批弹幕选轨明显散开,非严格从上往下。
- **§6.2.2**:已知突发摊到约 `window` 秒释放,非一帧;底部聊天气泡仍即时更新。
- **§6.2.3**:同 tick 两条弹幕速度可见差异、自然拉开;play/pause 前后速度不变。
- **回归**:同轨不重叠 / 不追尾;pause/play/clear/切房干净(切房 `reset()`)。

---

## 8. 构建命令

```bash
cd Shared/AngelLiveCore && swift build        # 引擎 + 调度器
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLive -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLiveMacOS -destination 'platform=macOS' build
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLiveTVOS -destination 'platform=tvOS Simulator,name=Apple TV' build
```
