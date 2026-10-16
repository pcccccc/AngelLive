# 弹幕引擎现状与后续

文档整理：2026-10-16。字号过渡、轨道复用、描边透明度与文字垂直定位已有实现；结构化付费置顶尚未实施。下方历史验收仅证明对应包和场景，真实电视观感矩阵仍保留。

## 共享引擎与展示模型

- 三端复用 Core 的 DanmakuKit，宿主分别提供 UIKit/AppKit 桥接。当前保留 CALayer 架构，没有证据支持为现有直播业务重写 Metal 后端。
- 默认从顶部复用第一条安全轨道；`.scattered` 作为兼容选项，不将旧随机选轨提案当成默认实现。
- 轨道重算只响应实际配置变化，字号变化不重排仍有在飞弹幕的轨道。已修复前的 F7/F8 描述不再属于当前故障清单。
- 消息支持文字、图片和有序图文片段，WebSocket 与 HTTP polling 共用展示转换，并经过翻译管线。
- 当前付费高亮仍由共享 `DanmakuDisplayModelFactory` 中的正文判断产生，不是三端各自判断，也不是结构化付费消息接口。

## 结构化付费留言

唯一的后续字段、兼容、生命周期及验收方案见[结构化付费留言宿主接口方案](StructuredPaidMessages.md)。旧三字段描述、外部插件字段丢失推断、强制金额字段、固定电视坐标及旧实施清单已被该方案替代。

尚需确认视觉与交互参数、协调外部协议、实现两个传输的解码与翻译透传、去重到期和三端 FullUI overlay。不得把旧正文高亮兼容要求扩展为永久保留嗅探，也不得改变 ShellUI 行为。

## 6. 已完成的引擎调整

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

## 7. 引擎单一化(2026-08-01 完成)

tvOS 原先在 `TV/AngelLiveTVOS/Third/DanmakuKit/` 维护一份与 `AngelLiveCore` 并存的 DanmakuKit(11 个文件),两份已实质分叉。`023e462` 删除副本,统一到共享引擎。

核对结论:tvOS 独有符号只有 5 个,其中 3 个是方法内局部变量。共享版本质是 tvOS 版的超集 —— 跨平台 shim、`@MainActor`、`MAX_FLOAT_X` 由 `infinity/2` 改为有限值、切字号时不再破坏在飞弹幕；选轨现已三端统一为顶部首个安全轨道。

一处此前的认知错误:曾以为「tvOS 没有 `DanmakuShootScheduler`(错落感去突发)」,因为副本目录里没有该文件。实际上 tvOS 的 `RoomInfoViewModel` 早就 `import AngelLiveCore` 在用它。**合并不会给 tvOS 引入去突发行为,它本来就有。**

合并后的行为变化仅限于共享版相对旧副本的那些改进,需真机确认观感(见 §9)。

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
