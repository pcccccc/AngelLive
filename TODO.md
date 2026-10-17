# AngelLive TODO

> 文档整理：2026-10-16；历史实施基线：2026-10-04。
>
> 当前维护未完成事项；来源文档与历史验收通过[文档索引](docs/README.md)查阅。
>
> 已完成清单留在来源及归档，不在此重复；未完成、未验证和需产品确认的事项继续留空。归档不等于关闭问题。
>
> 2026-10-04 的实现、测试与设备证据见 [2026-10-04 实施与验收](docs/archive/TODOProgress20261004.md)。

## P0：影响数据或核心播放稳定性

### 三端共享状态与页面联动

依据[2026-10-16 架构审查](docs/CrossPlatformArchitectureAudit20261016.md)，以下为静态确认问题及待动态验证项：

- [ ] tvOS 卡片与播放器收藏增删回归：添加一次只有一个成员、分组与列表一致、取消收藏不影响其他来源的同编号房间；重复数组写入已移除，设备验收待完成。
- [ ] 统一历史的来源身份与保存入口，修复 tvOS 直接改数组绕过持久化。
- [ ] 为 iOS/tvOS 播放错误状态查询补齐迟到结果归属门禁。
- [ ] 统一分类分页，修复 tvOS 加载失败后可能跳页的问题。
- [ ] 验证设置跨实例刷新、插件同 ID 升级后的平台页更新。

### 收藏同步：消除旧默认 Zone 的“删除后复活”风险

- [ ] 用真实 iCloud 账号验收迁移设备、未迁移旧设备、离线删除和 CloudKit 临时失败。

代码已覆盖两条删除路径；真实账号、多设备及进程重启验收仍待完成。来源：[同步可靠性现状与后续](docs/SyncReliabilityRoadmap.md)、`FavoriteSyncEngine.enqueueDelete`。

### iOS 后台/前台快速切换导致 Metal 画面冻结

- [ ] 核验旧 KSPlayer Debug 诊断补丁的保存位置与适用 revision，确保当前问题能通过可复现分支或补丁采证。
- [ ] 真机按“快速连续进出后台”步骤复现，采集 `[PlayerFlow]`、`[ForegroundTrace]` 与 GPU Frame Capture。
- [ ] 先确认 `enterForeground` 后是否仍有 draw 回调，以及 `nextDrawable` 是 acquired 还是 unavailable。
- [ ] 按证据从恢复阶梯实施：优先验证 Metal 路径对称重绘（档 1）和重建 `CADisplayLink`（档 1.5），再评估 drawable pool、display-layer 或 `MetalView` 重建。
- [ ] 保证用户主动暂停不会被自动续播；`hardReloadPlayer()` 只保留给用户明确重载或前四档均失败的情况。
- [ ] 完成横竖屏、快速切后台、长后台、HLS、Metal/display-layer 双路径及 reload 回归。

来源：[后台/前台冻结 Bug2](docs/BackgroundForegroundFreezeBug2.md)。

## P1：实现与验收中的功能

### 播放链路可观测性与恢复反馈

时间轴、恢复文案与 CDN 学习已经实现，剩余工作为验收与度量：

- [ ] 完成三端交互与无障碍矩阵；2026-10-04 记录已有 iOS/tvOS 当时新包交互证据，macOS 当轮受锁屏阻塞，不能据此推断当前设备状态。
- [ ] 增加 `time_to_first_frame_ms`、watchdog 次数、failover 成功率、首选 CDN 命中率和 30 秒未起播退出率度量。
- [ ] 用时间轴数据复核当前固定 12 秒 stall 阈值是否合理。

来源：[播放链路韧性路线图](docs/PlaybackResilienceRoadmap.md)。

### 结构化付费留言

接口方案已完成，外部协议及宿主渲染尚未实施。字段、兼容、生命周期和验收以[结构化付费留言方案](docs/StructuredPaidMessages.md)为准，不再使用旧路线图的三字段及重复实施清单。

- [ ] 确认档位与颜色、承载位置、展开交互、时长及并发设计。
- [ ] 协调外部协议与插件输出，接入 WebSocket/HTTP polling 解码及翻译透传。
- [ ] 实现去重、到期和三端 FullUI 展示，保持 ShellUI 边界；移除新 FullUI 路径的正文嗅探。
- [ ] 完成兼容、取消、跨房间及三端视觉和交互验收。

### CloudKit 静默推送与通用持久重试

- [ ] 核验 `CKSyncEngine` 自身订阅与真实设备通知到达行为，再判断是否需要宿主补充通知接线。
- [ ] 实测 App 存活、后台及终止后重启的收藏变化到达情况。
- [ ] 用真实账号完成限流、离线、账号切换与多设备端到端验收。

说明：收藏自定义 Zone 已由 `CKSyncEngine` 管理增量与退避；缺少手写 subscription 不能证明系统未订阅。凭证/订阅源持久重试已实现，最终构建与实际账号验证分开记录。来源：[同步可靠性现状与后续](docs/SyncReliabilityRoadmap.md)。

### 插件首页收尾

首页协议、缓存、Banner、收藏摘要、插件推荐分区和三端 FullUI 首页已经落地；代码收尾及三端构建已完成，设备覆盖分别记录：

- [ ] 完成三端首页交互矩阵；历史记录中 iOS 已观察到非空首页，macOS 当轮原生界面受锁屏阻塞，不将构建通过视为界面通过。
- [ ] 真机验证首屏时间、滚动稳定性、图片内存、弱网、Dynamic Type、VoiceOver、减弱动态效果、深浅色和 iPad 分屏。
- [ ] 验证首页“推荐 / 收藏 / 平台”胶囊互通、收藏大标题上拉折叠及 iOS 26+ 不出现双层玻璃。

来源：[插件驱动个性首页规划](docs/PluginDrivenHomePagePlan.md)。当前实现入口：`HomeView.swift`、`HomeViewModel.swift`、`PluginHomeFeed.swift`、`PluginHomeFeedCacheStore.swift`。

## P2：实现已完成，但仍缺设备验收

### 实时语音字幕

- [ ] 完成最后 macOS 新包的菜单、历史删除、浅色界面和中文字幕画面验证。
- [ ] 检查日语模型在 App 重启后的就绪状态。
- [ ] 在可用真机上验证真实直播的原文、译文、持续更新、切房、前后台和退出清理。
- [ ] 按实际设备与已安装资源验证语言、引擎及布局组合，未运行的组合继续标记未验证。

来源：[实时语音字幕](docs/LiveSpeechSubtitles.md)。历史 macOS 合成视频证据不替代最后包与 iOS/tvOS 真机结果。

### 历史故障的未决回归

- [ ] 重新核对旧回归中的边缘返回、收藏标题晚回写及 iOS App on Mac 历史实际起播、长时播放场景。
- [ ] 符号动画同系统 A/B 与真实 Apple TV 解码生命周期需独立采证；旧 KSPlayer revision 的结论不能直接应用到当前依赖。

范围与证据入口见[历史索引](docs/archive/README.md)。本次归档不关闭线上分组，也不将未验证项标为完成。

### iOS DLNA 真实设备矩阵

- [ ] 在 Apple Developer App ID 和实际 provisioning profile 中确认 multicast capability；仓库 `.entitlements` 已配置。
- [ ] 至少使用两类真实电视验证公开 HLS/MP4；FLV 按设备单独记录，不把入口可见等同于可播放。
- [ ] 验证带 Header 的 HLS 子清单、分片、密钥、初始化片段与 Range 转发。
- [ ] 覆盖 Wi-Fi 切换、设备离线、切换输入源、重复发现、SOAP 超时、短时效 URL、手机后台挂起和代理令牌释放。
- [ ] 记录三星、LG、索尼、海信、小米等设备的 MIME、HLS、暂停和 seek 兼容情况。
- [ ] 核对错误态不会显示假成功，日志不会泄露 Cookie、完整 token 或私有播放地址。

来源：[iOS DLNA 投屏调研](docs/iOSDLNACastingResearch.md)。

### Swift 6 迁移真机验收

- [ ] 弹幕连接：WebSocket/轮询、断线重连、快速切房和 `MainActor.assumeIsolated` 前提。
- [ ] 收藏/书签同步：两台设备互相增删、远端变化回调和逐条进度。
- [ ] tvOS 弹幕：顶部优先选轨、切字号、GIF 与 `MAX_FLOAT_X` 行为。
- [ ] 高频弹幕：异步绘制取消、清屏残影、漏回调与 `didDisplay` 语义。
- [ ] tvOS 收口批次：二维码同步、网页输入、控制层计时器、退出播放检测和 TopShelf 刷新。

来源：[Swift 6 / Sendable 适配现状](docs/Swift6SendableAudit.md)。代码侧 Swift 6 迁移已完成，本节只保留真机门禁。

### 弹幕共享引擎 tvOS 观感

- [ ] 低密度顶部安全轨道复用正确，高密度不重叠、不追尾。
- [ ] 切字号时在飞弹幕不跳行、不消失。
- [ ] `MAX_FLOAT_X = 100000` 无异常位移或闪烁。
- [ ] 现有 SC 橙底在结构化方案上线前不回归；新 FullUI 方案上线后改按结构化路由验收，不永久保留正文嗅探。
- [ ] GIF 弹幕正常。

来源：[弹幕引擎评估与改造路线图](docs/DanmakuRenderingRoadmap.md#9-待真机验收引擎单一化后的-tvos-观感)。

## P3：低风险工程整理

### SwiftUI 审计剩余项

- [ ] 触碰相关页面时，将真正的局部状态改为 `@State private`，常量改为 `let/static let`，父级输入改为普通存储属性。
- [ ] 优先清理审计点名的 tvOS 收藏、设置、二维码、播放器控制，以及 iOS `DetailPlayerView` 的状态所有权。
- [ ] 随播放控制层后续改动，逐个把大型 computed `some View` 拆为窄输入子 View，降低无效刷新范围；不做全仓库一次性重写。

来源：[SwiftUI Specialist Audit](docs/SwiftUISpecialistAudit.md)。这两项是机会性维护，不是当前正确性故障。

### 代码内已有的显式 TODO

- [ ] 重新设计后恢复 iOS、macOS、tvOS 房间卡片的平台图标和直播状态；统一三端语义与视觉后再开启。
- [ ] 为 UP 主弹幕增加结构化样式，替代 `"up: "` 文本前缀。

来源：`LiveRoomCard.swift`、macOS `PlatformDetailView.swift`、tvOS `LiveCardView.swift`、`DanmakuTextCellModel.swift` 中的 `TODO` 注释。

## 可选项（不阻塞当前发布）

- [ ] DLNA 自有设备选择器稳定后，再评估 `AVCustomRoutingController` 统一 AirPlay/DLNA 路由 UI。
- [ ] 只有产品未来增加“点播 + 上千条密集弹幕文件”场景，并且 Instruments 证明现有引擎不足时，才评估独立 Swift + Metal 弹幕后端。

## 明确不纳入 TODO

- Stall 指数退避：已改为固定 12 秒阈值，不再实施旧数组方案。
- 播放失败前静默降清晰度、内核偏好白名单、统一 watchdog controller、网络 HEAD 探针和 playArgs 预热：路线图已明确放弃。
- 用 Metal 重写当前直播弹幕引擎：现有 CALayer 架构已是 GPU 合成，当前没有足够收益证据。
- 插件自定义布局、HTML/WebView 首页、远程 SwiftUI/JSON UI DSL、宿主跨插件画像和内置推荐算法：属于首页首期明确边界。

## 维护规则

- 完成事项时先更新来源文档及实际验证范围，再从本文件移除已完成项；未验证部分继续保留。
- 方案发生变化时，在来源文档保留决策理由，本文件只保留当前执行方案。
- 需要真机证据的事项不得用模拟器、旧安装包或静态代码检查标记完成。
- 跨端共享层改动按受影响范围构建 iOS、macOS、tvOS；只记录实际运行过的测试和设备。
