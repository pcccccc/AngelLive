# 弹幕引擎评估与改造路线图

> 状态:字号过渡与错落感已上线；描边比例与透明度已统一（见 §10）；SC 付费置顶尚未实施 · 更新于 2026-09-16
> 范围:弹幕渲染后端选型(是否换 Metal)+ 三个现网痛点根因 + SC 付费留言改版方向
> 结论先行:**不建议为这几个痛点重写 Metal 引擎。SC、错落感、切字号 bug 三件事都能在现有 Swift 引擎里低成本解决。**

---

## 0. 背景:被评估的提案

外部有人用 **C++ + Metal** 实现了一个「直接渲染弹幕引擎」,主打:高帧率 GPU 渲染、纯硬件加速、实时切弹幕尺寸/字体,场景是**下载好的点播视频 + 点播弹幕文件**直接播放。

本文回答三个问题:实现难度大吗?能替换现有框架吗?性能提升多大?并把讨论中暴露的真实痛点沉淀成可执行的改造计划。

---

## 1. 现状:已确认的代码事实(非推测)

| # | 事实 | 位置 |
|---|------|------|
| F1 | 弹幕运动用 `CABasicAnimation` 改 `position.x`,由 Render Server 在 **GPU 合成**,主线程每帧基本不参与运动 | `DanmakuKit/Core/DanmakuTrack.swift:236-252` |
| F2 | 每条弹幕文字**只光栅化一次**,画进 `CGContext` 生成 `CGImage` 缓存到 `layer.contents`,分摊在 16 条后台队列 | `DanmakuKit/Core/DanmakuAsyncLayer.swift`(`drawDanmakuQueueCount = 16`) |
| F3 | 选轨走 `DanmakuView.FloatingTrackPolicy` 策略；默认 `.topPriority` 从顶部复用第一条安全轨道，`.scattered` 仅保留为旧版兼容选项 | `DanmakuKit/Core/DanmakuView.swift`(`findSuitableTrack`) |
| F4 | 同一 runloop tick 内 shoot 的所有弹幕,起点 x **完全相同**(右边缘) | `DanmakuTrack.swift:103` |
| F5 | 速度只由 `displayTime` 决定,无任何时间/速度抖动 | `DanmakuTrack.swift:240-243` |
| F6 | 切字号已可用:`trackHeight = fontSize * 1.35` 触发 `recalculateTracks()` | `iOS/.../Player/DanmuView.swift:49`、`DanmakuView.swift:86-91` |
| F7 | `updateUIView` **每次 SwiftUI 刷新都无条件**重算轨道,且第 53 行手动再调一次(与 didSet 重复) | `iOS/.../Player/DanmuView.swift:41-54` |
| F8 | `positionY` didSet 会把**正在飞的 cell 的 y 直接挪走**;字号变大→轨道数变少→对超出轨道 `.stop()` 清掉在飞弹幕 | `DanmakuTrack.swift:70-79`、`DanmakuView.swift:462-469` |
| F9 | SC/醒目留言靠 **字符串嗅探** `text.contains("醒目留言") || text.contains("SC")` 判定,命中后只把背景刷成橙色 | `iOS/.../Player/DanmuView.swift:72`、tvOS `DanmuView.swift` 同款 |
| F10 | 弹幕数据来源主要是**直播 WebSocket 批量下发**;弹幕层是独立 UIView,ZStack 叠在播放器层之上 | `LiveParse` + 各端 `DanmuView` |

**由 F1+F2 可知:现有实现已经是 GPU 合成 + 一次性光栅化缓存,不是「CPU 逐帧软渲染」。** 提案里「用 Metal 才能 GPU 加速」的前提对本项目不成立。

---

## 2. Metal 引擎到底快在哪 / 不快在哪

| 维度 | 现状(CALayer 树) | Metal 字形图集 | 对本项目是否有意义 |
|---|---|---|---|
| 每条弹幕对象成本 | UIView + CALayer + 位图 | instanced quad,无对象 | 直播几十~百条,差异感知不到 |
| 海量并发(上千条同屏) | 对象数爆炸 | 单 draw call 搞定 | **仅点播密集弹幕需要**,直播用不上 |
| 实时切字号/字体 | 整批重绘 | 改 quad 缩放,近乎免费 | 见 §4,现架构已能做且符合正确交互 |
| 描边/彩色/背景卡片 | CGContext 直接画 | 需自己写 shader | 现架构更省事 |

**Metal 唯一真实硬优势是「实时切字号丝滑 + 上千条并发」,而这两点都指向点播密集弹幕场景——也就是提案作者的场景,不是本项目(直播三端聚合)的形态。**

### 为什么提案 demo「看起来自然」
关键在**数据**不在引擎:点播弹幕文件每条带真实视频时间戳,天然散布在时间轴上,永不出现「一批同时来」。那种错落感是数据白送的。把同一引擎喂直播 WebSocket 的批量流,**一样是墙**——除非另写去突发调度。**即:错落感 = 调度算法,与渲染后端无关。**

---

## 3. 实现难度与替换风险评估

- **语言选型**:若真要做,应 **Swift + Metal**;C++ 在此场景是纯负担(桥接/双构建/unsafe 指针),对性能无实质帮助。提案用 C++ 更像炫技。
- **功能对等成本**(语言无关的硬骨头,Metal 一样要啃):CJK 字形图集动态换出、点击命中检测(无 UIView 树需自己反推坐标)、GIF 弹幕帧动画、暂停/seek 动画时间同步、三端 + 叠播放器层验证。
- **工期估算**:Swift+Metal 达到现有功能对等约 **2–4 周**,磨平 GIF/点击/三端边角更久。
- **风险**:拿一个能跑、功能完整、三端适配好的系统,去换一个在直播负载下用户基本感知不到的性能提升,同时背上重写点击/GIF/三端的全部风险。**ROI 不划算,典型「重写 working code」陷阱。**

> 参考 Axiom `axiom-graphics` / `axiom-metal-migration`:Metal 渲染类决策应以**运行时证据**(GPU Frame Capture、实测掉帧)而非代码直觉驱动。上 Metal 之前应先用 Instruments 量化直播场景是否真的掉帧。

---

## 4. 三个真实痛点:根因与改造方向(本次只规划,不改码)

### 痛点 A:弹幕「一股脑出来、同一起跑线、没有错落感」
- **根因**:F3(从上往下第一个能放下就放)+ F4(同 tick 起点 x 相同)+ F5(无速度抖动)+ F10(WebSocket 批量下发)。一批 20 条同帧 shoot → 一道竖墙从顶部往下码。
- **方向(全在现有 Swift,约 1–3 天)**:
  1. **轨道随机化**:`findSuitableTrack` 由 `first(where:)` 改为「收集所有 `canShoot` 通过的轨道,随机/偏向最久未用挑一条」(`DanmakuView.swift:560`)。
  2. **去突发分发**:在喂弹幕那层加缓冲队列,一批不要同帧发,摊到 1–2 秒内带随机抖动逐条发出(新增小调度器,不碰引擎核心)。
  3. **速度微抖动**:建模型时给 `displayTime` 加 ±10~15% 随机,同时起跑的弹幕会自然拉开。

### 痛点 B:切字号有「小 bug」
- **现状**:能力本就存在(F6),bug 是**过渡不平滑**,不是做不到。
- **根因**:F7(每次刷新无条件重算 + 重复调用)+ F8(重算扰动在飞 cell:跳行 / 突然消失 / 新旧字号混排)。
- **正确交互参照**:成熟弹幕产品切字号都**只对新弹幕生效**,已在飞的那批保持原样飞完——恰好是现架构最省力的做法。
- **方向(约 1 天)**:
  1. 去掉 `DanmuView.swift:53` 的重复 `recalculateTracks()`;
  2. 加「字号真变了才更新 `trackHeight`」的判断,避免父视图任意刷新都抖;
  3. 让字号变化只影响**新发弹幕**的 `trackHeight`,不触发对在飞 cell 的破坏性重排(评估:重算时跳过/冻结已有 cell 的 positionY 迁移与 stop)。

### 痛点 C:SC 橙底改版 → 见 §5

---

## 5. SC 付费留言改版:付费置顶留言卡片(设计方向)

> 目标:把现在「内联橙色弹幕」升级为**付费置顶高亮卡片**,有金额分级、配色分层、置顶时长。

### 5.1 前置架构债:数据链路三层都丢了金额(已查证)

> 已核实:`LiveParse` 现在已经全部插件化,代码在独立仓库 `LiveParsePlugins`。下表是 SC 数据从插件到屏幕的完整链路证据。

| # | 事实 | 位置 |
|---|------|------|
| S1 | 弹幕协议契约只定义三字段 `DanmakuMessage { text, nickname, color? }`,**没有金额/头像/币种/时长的位置** | `LiveParsePlugins/docs/runtime/DanmakuDriverAPI.md`(通用模型 `DanmakuMessage`) |
| S2 | 已查证多个插件:弹幕脚本**确实解析了付费留言事件**,源数据里金额、头像、背景色等字段都拿得到,**但当前只吐出 `{nickname, text, color}` 三字段,金额/头像/币种/时长全部丢弃**;SC 仅靠给文本加前缀(如 `醒目留言: `)幸存 | `LiveParsePlugins/plugins/*/*/*_danmaku.js`(各弹幕脚本) |
| S3 | App 解码模型忠实镜像三字段 | `LiveParse/Danmu/LiveParseDanmakuPlan.swift:188`(`LiveParseDanmakuMessage { text, nickname, color? }`) |
| S4 | App 消费:`(text, nickname, color)` 中 nickname 只用于底部聊天气泡;飞屏 `shoot` 只传 `text, color` | `iOS/.../RoomInfoViewModel.swift:773-789` |
| S5 | 最终 SC 唯一幸存信号 = 文本前缀(如 `醒目留言: `),再靠 F9 字符串嗅探刷橙色 | `iOS/.../Player/DanmuView.swift:72` |

**结论:SC 的金额/头像/币种/置顶时长在「插件层就被丢掉了」,协议层根本没有承载它们的字段。** 要做付费置顶卡片 UI,必须三层联动补字段:

1. **插件层**(各平台 `*_danmaku.js`):SC 事件额外提取 `price / currency / avatar / durationSec`。这天然是平台相关代码,落在插件里符合「平台差异只进插件」的架构约定。
2. **协议层**(`DanmakuDriverAPI.md` 的 `DanmakuMessage`):新增**可选**结构化 SC 块。**`superChat` 块存在即代表「这条是 SC」——是不是 SC 完全由插件判定,App 不做任何识别。** 字段应是**展示就绪**的,App 不解释币种、不做平台判断:
   ```ts
   interface DanmakuMessage {
     text: string
     nickname: string
     color?: number
     superChat?: {            // 存在 = 这是 SC;普通弹幕不带此块
       priceText: string      // 插件已格式化好的展示金额,如 "¥30" / "$5.00";App 原样显示
       tier?: number          // 插件归一化的档位(如 0–6),App 据此查配色表
       avatar?: string        // 头像 URL
       durationSec?: number   // 置顶时长(可空,App 可有默认)
     }
   }
   ```
   协议本就是「可选字段、渐进启用」,加可选块**向后兼容**:老插件不发 `superChat`,宿主按普通弹幕处理。
3. **App 层**:`LiveParseDanmakuMessage` 加可选 `superChat`;delegate 分支只判断「有没有 `superChat` 块」,有就**路由到置顶 overlay**,没有就照旧飞屏。**App 端彻底删掉 `醒目留言:` 前缀嗅探(F9),不再关心来源平台,也不处理礼物**(礼物在插件层已丢弃,App 永远收不到)。

### 5.2 付费置顶留言机制(行业成熟做法参照)
- 金额决定三样东西:**配色分层**(低→高一档档递进,如 蓝→浅蓝→绿→黄→橙→品红→红 这类 7 档梯度)、**置顶时长**(金额越高顶得越久)、**最大留言长度**。
- 视觉:圆角卡片,顶部彩色条(头像 + 昵称 + 金额),下方同色系浅色区显示留言文本。
- 顶部有 **ticker**:横向滚动的金额药丸,点开展开完整卡片;高档位停留更久。

### 5.3 落到本项目的设计方向(待评审)
- **承载位置**:SC 卡片**脱离 DanmakuKit 轨道系统**,作为播放器之上的独立置顶 overlay 区(顶部 ticker + 展开卡片),不再当弹幕飞过。
- **分级映射**:不绑定任何单一来源的金额档位;各来源金额单位不一,**由插件归一成 `tier`**,App 只按 `tier` 查配色表。**(详见 §5.5 Q2)**
- **置顶时长**:金额越高停留越久,设上下限。
- **并发堆叠**:同时多条 SC 走列表/队列,新的在上,旧的下滑/淡出。
- **三端差异**:
  - iOS:竖屏可放视频下方信息区或顶部 ticker;横屏走 overlay。
  - tvOS:Focus 引擎下为**非交互**置顶 overlay,注意 1920×1080 坐标与安全区。
  - macOS:可常驻侧栏或顶部 ticker。
- **降级**:取不到金额/头像时,回退到「带彩色边框的高亮卡片」,不退回橙底裸弹幕。

### 5.4 设计边界(已定)
- **是不是 SC,由插件判定。** 插件返回 `superChat` 块即为 SC,App 照着渲染,不做任何来源识别。
- **App 永不接触平台语义、永不处理礼物。** 礼物在插件层已丢弃,App 收不到;App 端删除 `醒目留言:` 前缀嗅探(F9)。
- 因此「哪些平台有真 SC / 哪些只有礼物」**App 不需要知道**(原 Q3 作废)。

### 5.5 SC 改版待确认项
- **Q1 已答**:`LiveParse` 现在不提供金额/币种/头像——金额在插件层就被丢弃,协议无承载字段。需按 §5.1 三层补字段,工作量主要在「插件层逐脚本提取 + 协议加可选块」。
- **Q2 档位归一在哪做?** 推荐:**插件输出 `tier`(归一档位)+ `priceText`(展示金额)**,App 只拿 `tier` 查一张固定配色表,不碰币种。需确认:(a) 档位数量与各来源金额→档位的阈值由谁定(产品/设计);(b) App 那张 `tier → 配色` 表的视觉由设计给。
- **Q3** 卡片承载位置:顶部 ticker / 视频内 overlay / 侧栏,三端分别选哪种?
- **Q4** 是否需要点击展开、是否保留历史 SC 列表?置顶时长插件不给时 App 的默认值?
- **Q5** 需要新设计稿(卡片视觉、`tier` 配色表、动效)。

---

## 6. 决策与下一步

**总判断:不上 Metal。** 本项目所有已提诉求都能在现有引擎低成本解决,且风险低、可立即验证:

| 诉求 | 性质 | 估算 | 是否需要 Metal |
|---|---|---|---|
| SC 橙底改付费置顶卡片 | 数据模型 + 新 UI(跨仓库) | 见 §6.3(较大,需设计) | 否 |
| 错落感 / 起跑线 | 调度算法 | 1–3 天 | 否 |
| 切字号小 bug | 过渡重算 bug | ~1 天 | 否 |
| 高并发不掉帧 | 直播量级用不上 | — | 否(仅点播密集才需) |

**实施状态**:
1. 切字号过渡 bug 已完成(`2802a97`)。见 §6.1。
2. 错落感调度已完成(`2802a97`，tvOS 选轨策略后续按大屏体验调整)。见 §6.2。
3. SC 付费置顶改版尚未实施，需先答 §5.5 待确认项并完成设计稿。见 §6.3。

> 若未来产品形态扩展到「点播 + 上千条密集弹幕文件」,届时可**只在点播场景**引入 Swift+Metal 引擎,与现有直播引擎并存,而非替换。那才是 Metal 真正值得的场景。

### 6.1 切字号过渡 bug 实施清单（已完成）
- [x] 去掉 `iOS/.../Player/DanmuView.swift:53` 重复的 `recalculateTracks()`(`trackHeight` didSet 已会触发)。
- [x] 加「字号真变了才更新 `trackHeight`」判断,避免父视图任意刷新都重算。
- [x] 字号变化只影响**新发弹幕**,重算时不迁移、不 stop 在飞 cell。
- [x] 三端同步(iOS/tvOS/macOS 三个 `DanmuView` 同款修)。

**验收点**:
- 播放中连续切字号:已在飞的弹幕保持原尺寸飞完,不跳行、不消失、不闪;新弹幕用新尺寸。
- 仅改播放进度/状态等无关刷新时,弹幕不再无故抖动。
- 三端表现一致。

### 6.2 错落感调度实施清单（已完成）
- [x] **顶部安全轨道已落地（2026-08-17）**：共享引擎默认从顶部逐轨碰撞检测，复用第一条安全轨道；上方轨道确实无法容纳时才向下扩展。
- [x] tvOS 继续显式设置 `.topPriority`；iOS/macOS 使用相同默认行为，`.scattered` 仅作为旧版兼容策略保留。
- [x] 去突发:喂弹幕处加缓冲队列,一批不同帧发,摊到 1–2 秒带随机抖动逐条发出。
- [x] 速度微抖动:建模型时 `displayTime` 加 ±10~15% 随机。
- [x] 参数(抖动窗口/速度方差)可调,便于真机调感。

**验收点**:
- 一批弹幕到达时不再是「同起跑线竖墙」,起始时间与纵向轨道明显散开。
- 高弹幕量时纵向铺满、错落自然,无明显从上往下顺序堆叠。
- 不破坏既有碰撞检测(同轨不重叠、不追尾)。

### 6.3 SC 付费置顶改版实施清单(跨仓库三步)

**Step 1 — 插件层(`LiveParsePlugins`,各弹幕脚本)**
- [ ] 付费留言事件额外输出 `superChat { priceText, tier, avatar?, durationSec? }`;`priceText` 展示就绪、`tier` 落在约定档位区间。
- [ ] 普通弹幕不带 `superChat` 块;礼物事件继续丢弃(不产生 message)。
- [ ] 档位归一(金额→`tier`)在插件内完成,宿主不感知来源金额单位。

  **验收点**:付费留言 message 带完整 `superChat`;普通弹幕不带;礼物无 message;旧宿主(不认 `superChat`)收到仍能按普通弹幕显示(text/nickname/color 不缺)→ 向后兼容通过。

**Step 2 — 协议层(`LiveParsePlugins/docs/runtime/DanmakuDriverAPI.md`)**
- [ ] `DanmakuMessage` 增补可选 `superChat` 块定义、字段语义、`tier` 取值范围。
- [ ] 写明「`superChat` 存在即 SC,宿主不做识别」「老插件不发即普通弹幕,行为不变」。
- [ ] 补一个带 `superChat` 的 `onDanmakuFrame` 返回示例。

  **验收点**:文档自洽,字段/范围/兼容性表述明确,示例可直接照抄落地。

**Step 3 — App 层(`AngelLiveCore` + 三端)**
- [ ] `LiveParseDanmakuMessage` 增加可选 `superChat` 解码(`LiveParseDanmakuPlan.swift:188`)。
- [ ] delegate 分支只判断「有无 `superChat`」:有 → 置顶 overlay;无 → 照旧飞屏。
- [ ] 新增置顶 overlay 组件:`tier → 配色`表、头像、昵称、`priceText`、留言、置顶时长(插件不给时用默认)、多条并发堆叠(新在上、超时/超量退出)。
- [ ] **删除 F9 前缀嗅探与橙底特判**(`DanmuView.swift:72`,三端)。
- [ ] 三端接入:tvOS 非交互 + 安全区;iOS 横竖屏;macOS 承载位。

  **验收点**:
  - 带 `superChat` 的消息进 overlay、不再飞屏;不带的仍飞屏。
  - 卡片正确显示头像/昵称/`priceText`/留言,按 `tier` 上色,按时长置顶后退出;并发堆叠正确。
  - `grep "醒目留言" iOS TV macOS` 在 App 侧清零(F9 已删)。
  - App 侧代码 `grep` 无任何来源平台名(符合主工程约定)。

> 依赖关系:Step 1 与 Step 2 可并行(协议先定义、插件按定义实现);Step 3 依赖 Step 2 字段定稿。Step 1 完成后即使 App 未改,旧链路仍正常(向后兼容),可分批上线。

---

## 7. 引擎单一化(2026-08-01 完成)

tvOS 原先在 `TV/AngelLiveTVOS/Third/DanmakuKit/` 维护一份与 `AngelLiveCore` 并存的 DanmakuKit(11 个文件),两份已实质分叉。`023e462` 删除副本,统一到共享引擎。

核对结论:tvOS 独有符号只有 5 个,其中 3 个是方法内局部变量。共享版本质是 tvOS 版的超集 —— 跨平台 shim、`@MainActor`、`MAX_FLOAT_X` 由 `infinity/2` 改为有限值、切字号时不再破坏在飞弹幕；选轨现已三端统一为顶部首个安全轨道。

一处此前的认知错误:曾以为「tvOS 没有 `DanmakuShootScheduler`(错落感去突发)」,因为副本目录里没有该文件。实际上 tvOS 的 `RoomInfoViewModel` 早就 `import AngelLiveCore` 在用它。**合并不会给 tvOS 引入去突发行为,它本来就有。**

合并后的行为变化仅限于共享版相对旧副本的那些改进,需真机确认观感(见 §8)。

---

## 8. 已解决:`DanmakuGraphicsContextStack` 并发 bug(以删除死代码收场)

> 状态:**已解决(2026-08-03)** · 发现于 2026-08-01 的 Swift 6 迁移过程中

原始判断:全局共享 push/current/pop 栈模拟 `UIGraphicsBeginImageContextWithOptions`
语义,而绘制分摊在 16 条并发队列,`NSLock` 只防崩不防语义,线程 A 的 `current()`
可能拿到线程 B 刚 push 的 context → 偶发串图。竞态分析成立。

**但复核发现影响面判断有误**:该 shim 位于 `#if os(macOS)` 分支,而调用方
`DanmakuAsyncLayer` 的 UIGraphics 调用全部在 `#if os(iOS) || os(tvOS)` 分支
(走 UIKit 原生实现,UIKit 的上下文栈本来就是线程本地的);macOS 分支自移植起
(`9a3e3e7`)就走 `NSImage.lockFocus` 路线。**shim 全仓库零调用,是死代码,
竞态从未实际触发**。原文"影响面扩大到三端"不成立。

处置:整体删除(struct + 栈类 + 全局实例 + 4 个 UIGraphics* 函数),原位留注释
说明历史与"未来如需重建必须线程本地实现"。顺带减少一处 `@unchecked Sendable`
(27 → 26)。教训:分析并发 bug 前先确认代码可达性。

## 9. 待真机验收:引擎单一化后的 tvOS 观感

1. 选轨:三端低密度时都从顶部起排；第一轨通过碰撞检测后应立即复用，不应跳到底部空轨。
2. 高密度时纵向铺满,不重叠、不追尾。
3. 切字号:在飞弹幕保持原尺寸飞完,不跳行不消失。**共享版与旧副本此处行为不同** —— 旧副本会破坏在飞 cell,用户能看出差异。
4. `MAX_FLOAT_X` 由 `infinity/2` 改为 `100000`:确认无异常位移或闪烁。
5. SC / 醒目留言橙底仍正常(F9 嗅探逻辑未动)。
6. GIF 弹幕正常。

若观感不对,优先怀疑 `floatingTrackPolicy` 未生效或 `visibleFloatingTrackCount` 计算差异。

## 10. 文字描边与透明度（2026-09-16）

iPhone 与 iPad 使用同一套 FullUI 和共享文字绘制函数，默认均为 15pt 系统常规字重。此前的固定 3 个物理像素描边，在 2× 屏幕上换算为 1.5pt，在 3× 屏幕上为 1pt；相同字号下的逻辑宽度相差 50%，容易出现黑边压过字芯的观感。

现在描边完整线宽固定为字号的 5%，通过负的 `NSAttributedString.Key.strokeWidth` 同时绘制底色与描边，再覆盖正文。15pt 字号对应 0.75pt：2× 光栅化为 1.5px，3× 为 2.25px，不对物理像素取整。字号、字重、布局与运动方式保持原行为；纯文本和混排文本共用这套绘制。接近黑色的正文仍使用白色描边。

半透明文字先以不透明描边和正文完成组合，再整体应用原有透明度，避免黑色底层透入字芯。仅在 alpha 小于 1 时建立 CGContext 透明层，默认不透明弹幕不增加该缓冲；绘制后恢复上下文状态，避免影响混排中的后续图片。

验证证据：

- `swift test --package-path Shared/AngelLiveCore --filter DanmakuText`：5 项通过，其中 3 项 macOS 位图测试检查半透明字的 alpha 上限、浅灰背景下白字字芯亮度，以及后续绘制的上下文状态恢复。
- `swift test --package-path Shared/AngelLiveCore`：40 个 suite、302 项全部通过。
- 通过 Xcode 在 UIKit 中执行当前共享绘制函数，生成相同 15pt 文案、深浅背景和 60% 不透明度的 2×/3× 前后对照；新描边逻辑宽度一致，半透明字芯不再混入黑底。对照产物为 `before-after.png`、`iphone-3x-after.png`、`ipad-2x-after.png`，保存在本轮临时验证产物中；这些是离屏渲染证据。
- Xcode 27.0 RC（27A266a）的 workspace MCP `BuildProject`：`AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` 均通过，各次构建后的 Issue Navigator error 均为 0。主代理复核的日志为 `BuildProject-Log-20260916-103932.txt`、`BuildProject-Log-20260916-104131.txt`、`BuildProject-Log-20260916-104320.txt`。
- iPad mini（A17 Pro）/ iOS 27.0 模拟器：最后一次源码修改后，`DeviceInteractionInstallAndRun` 返回 `Application installed and running`。经首页进入直播页，10:50:41 与 10:51:16 的新包截图显示视频和消息继续更新；顶部紫色飞屏与聊天消息内容对应，未见描边裁切或重影。主代理复核了原尺寸截图 `Verify Danmaku Outline iPad-10_50_41_696-screenshot.png`、`Verify Danmaku Outline iPad-10_51_16_411-screenshot.png`；视频内嵌字幕不作为描边证据。
- iPhone 18 Pro / iOS 27.0 模拟器：最后一次源码修改后，新 session 的 `DeviceInteractionInstallAndRun` 返回 `Application installed and running`。经用户明确授权，通过配置页添加订阅并安装单个插件，再进入首页直播间。11:01:38 与 11:02:22 的新包截图显示视频、聊天和实际飞屏持续更新；飞屏文本可逐句对应下方聊天，细描边和字芯正常，未见裁切或重影。主代理复核了原尺寸截图 `Verify Danmaku Outline iPhone Authorized-11_01_38_731-screenshot.png`、`Verify Danmaku Outline iPhone Authorized-11_02_22_114-screenshot.png`。
- 两端 Device Hub session 均已结束；Xcode 恢复 `AngelLive` / `iPad mini (A17 Pro) (27.0)`。构建和设备响应索引分别保存在本轮临时产物 `angellive-outline-build-evidence.json`、`angellive-outline-device-evidence.json`。

上述描边验收阶段，macOS、tvOS 仅验证了构建；后续 tvOS 播放器验证见 §11。模拟器与离屏渲染不能替代真机屏幕观感验收。

## 11. 顶部区域的纯文字垂直定位（2026-09-16）

tvOS「顶部 1/4」使用 270pt 高的弹幕视图。纯文字模型在 UIKit 上额外分配 `fontSize * 0.5 + 12` 的竖向空间，但原绘制位置固定为局部 `y = 5`，使大部分留白落在文字下方。文字因此偏离轨道中心；65pt 字号时向上偏移 17.25pt。透明 cell 的矩形相交本身不代表文字互相遮挡，不能仅据 cell 高度大于轨距就认定字形重叠。

实际 UIKit 测量中，65pt、顶部 1/4、顶部留白 5pt、轨距 87.75pt 时仍有 3 条轨道，首轨中心 52.25pt。文字模型高度 122.068pt，cell 顶部为 -8.784pt；尽管文字排版框越过顶部，带描边的实测字形仍从屏幕内约 5.216pt 开始，模拟器没有复现字形像素被截断。实机照片中的遮挡原因尚不能仅凭该计算确定，但文字明显上偏可以独立复现。

修复采用与测量同源的竖向 padding，将 UIKit 文字绘制原点设为该 padding 的一半。65pt 时局部绘点变为 22.25pt；保留原 cell 尺寸、轨距、轨道数量及滚动行为。AppKit 继续使用现有的绘制坐标约定。

用户进一步确认实机现象是首行被屏幕顶边截掉。tvOS FullUI 播放器的入口使用全屏忽略安全区，原弹幕视图也随之贴边；仅修正文案居中不能保证避开电视 overscan 区域。宿主因此增加本地 `TVDanmakuContainerView`：将所属 `window.safeAreaLayoutGuide.layoutFrame` 转换到容器坐标，与当前弹幕区域求交，inner 引擎只使用交集的纵向范围，横向仍保持完整宽度供文字飞入、飞出。挂载到 window 或安全区变化时重新布局，frame 实变才重算轨道，不硬编码电视边距，不修改共享引擎或 ShellUI。

「顶部 1/4」仍请求 270pt 的外部容器高度；安全区占用的高度会从可用轨道空间中扣除。上面的三轨度量是未扣系统安全区的共享引擎 fixture。当前播放器的实际视图层级中，外部容器在屏幕坐标的 y 为 -16pt、高 270pt，系统安全区从 60pt 开始，因此实际交集为 60...254pt、高 194pt；65pt 字号可容纳两轨，底边仍在屏幕顶部四分之一区域内。安全区语义依据 [Apple UIKit 文档](https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area)，实际边距以所属 window 和容器的位置为准。

验证证据：

- `swift test --disable-sandbox --package-path Shared/AngelLiveCore`：40 个 suite、302 项通过，日志 `angellive-quarter-core-tests.log`。新增的 `DanmakuTextVerticalAlignmentTests` 仅在 UIKit 平台启用，不计入这次 macOS Package 运行结果。
- Xcode UIKit snippet 实际调用 `DanmakuView.shoot` 和正式 `DanmakuTextCell.displaying`，复核 50/60/64/65/70pt 五组字号：绘点 Y 为 18.5/21/22/22.25/23.5pt，轨数仍为 3/3/3/3/2。65pt 正式 renderer 的实测首轨字形上沿为约 22.216pt，所有受测首轨字形都在 270pt 视口内。该检查验证了实际绘制接线，不是仅在临时脚本中手动改绘点。
- Apple TV 4K（第 3 代）/ tvOS 27.0 模拟器：最后一次源码修改后，`DeviceInteractionInstallAndRun` 返回 `Application installed and running`（响应 `angellive-quarter-tv-final-install-response.json`，id 43）。设置截图 `Verify Final tvOS Quarter Danmaku-11_39_15_544-screenshot.png` 确认为 65pt 与「顶部 1/4」。11:45:11、11:45:47 的播放截图及 hierarchy 确认弹幕引擎位于屏幕 y=60、高 194pt，首轨 cell 的 y=57.1pt，文字在 cell 内居中后留在安全区内；第二轨 cell 的 y=144.8pt。主代理复核了原图和层级。关闭应用弹幕后仍存在的直播源内嵌文字不作为此次布局证据。
- iPhone 18 Pro / iOS 27.0 模拟器：最后一次源码修改后的 `DeviceInteractionInstallAndRun` 明确成功（响应 `angellive-quarter-iphone-install-response.json`，id 113）。主代理复核 `Verify Final iPhone Danmaku Alignment-11_58_59_386-screenshot.png`，实际飞屏与下方聊天对应，首行字形完整。此前两次安装调用未返回确认，不作为验收证据。
- 最终源码的三端 workspace MCP `BuildProject` 均成功，构建后 Issue Navigator error 均为 0。主代理复核日志：tvOS `BuildProject-Log-20260916-115135.txt`、macOS `BuildProject-Log-20260916-115334.txt`、iOS `BuildProject-Log-20260916-115508.txt`。
- tvOS 已恢复原来的 50pt、全屏设置；两个 Device Hub session 均已结束，Xcode 恢复 `AngelLive` / `iPad mini (A17 Pro) (27.0)`。证据索引为本轮临时产物 `angellive-quarter-evidence.json`。此次垂直定位修改后未重新进行 iPad 或 macOS 播放器视觉验收，也未在用户反馈的实体电视上验证。
