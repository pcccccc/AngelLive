# 弹幕引擎评估与改造路线图

> 状态:评估完成 · 仅文档 · 暂不改码 · 2026-06-24
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
| F3 | 轨道选择是「从上往下,第一个能放下就放」 | `DanmakuView.swift:560-584`(`floatingTracks.first(where:)`) |
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

**建议执行顺序**(后续单独开工,本文不含代码改动):
1. 切字号过渡 bug(最小改动、最快验证)→ 真机看手感。见 §6.1。
2. 错落感调度(轨道随机化 + 去突发 + 速度微抖动)。见 §6.2。
3. SC 付费置顶改版(跨仓库三步,需先答 §5.5 待确认项 + 设计稿)。见 §6.3。

> 若未来产品形态扩展到「点播 + 上千条密集弹幕文件」,届时可**只在点播场景**引入 Swift+Metal 引擎,与现有直播引擎并存,而非替换。那才是 Metal 真正值得的场景。

### 6.1 切字号过渡 bug 实施清单
- [ ] 去掉 `iOS/.../Player/DanmuView.swift:53` 重复的 `recalculateTracks()`(`trackHeight` didSet 已会触发)。
- [ ] 加「字号真变了才更新 `trackHeight`」判断,避免父视图任意刷新都重算。
- [ ] 字号变化只影响**新发弹幕**,重算时不迁移、不 stop 在飞 cell。
- [ ] 三端同步(iOS/tvOS/macOS 三个 `DanmuView` 同款修)。

**验收点**:
- 播放中连续切字号:已在飞的弹幕保持原尺寸飞完,不跳行、不消失、不闪;新弹幕用新尺寸。
- 仅改播放进度/状态等无关刷新时,弹幕不再无故抖动。
- 三端表现一致。

### 6.2 错落感调度实施清单
- [ ] 轨道随机化:`DanmakuView.swift:560` `findSuitableTrack` 由 `first(where:)` 改为「收集所有 `canShoot` 通过的轨道随机/偏向最久未用挑一条」。
- [ ] 去突发:喂弹幕处加缓冲队列,一批不同帧发,摊到 1–2 秒带随机抖动逐条发出。
- [ ] 速度微抖动:建模型时 `displayTime` 加 ±10~15% 随机。
- [ ] 参数(抖动窗口/速度方差)可调,便于真机调感。

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
