# AngelLive TODO

> 汇总日期：2026-08-26
>
> 范围：仓库内全部 Markdown 文档，以及文档中点名的当前代码入口。
>
> 规则：只收录仍未完成、未验证或需要产品确认的事项；已完成、已证伪、明确放弃和“首期不做”的方案不重新进入待办。

## P0：影响数据或核心播放稳定性

### 收藏同步：消除旧默认 Zone 的“删除后复活”风险

- [ ] 删除收藏时，同时删除旧默认 Zone 中对应的 `favorite_streamers` 记录。
- [ ] 默认 Zone 删除失败后进入持久重试，跨启动继续执行。
- [ ] 增加迁移设备、未迁移旧设备、离线删除和 CloudKit 临时失败的回归测试。

当前代码只向自定义 `FavoritesZone` 入队删除；默认 Zone 迁移记录仍保留。来源：[同步可靠性后续](docs/SyncReliabilityRoadmap.md)、`FavoriteSyncEngine.enqueueDelete`。

### iOS 后台/前台快速切换导致 Metal 画面冻结

- [ ] 将 KSPlayer Debug 诊断改动提交到可复现的分支或补丁，避免只存在于某台机器的未提交工作区。
- [ ] 真机按“快速连续进出后台”步骤复现，采集 `[PlayerFlow]`、`[ForegroundTrace]` 与 GPU Frame Capture。
- [ ] 先确认 `enterForeground` 后是否仍有 draw 回调，以及 `nextDrawable` 是 acquired 还是 unavailable。
- [ ] 按证据从恢复阶梯实施：优先验证 Metal 路径对称重绘（档 1）和重建 `CADisplayLink`（档 1.5），再评估 drawable pool、display-layer 或 `MetalView` 重建。
- [ ] 保证用户主动暂停不会被自动续播；`hardReloadPlayer()` 只保留给用户明确重载或前四档均失败的情况。
- [ ] 完成横竖屏、快速切后台、长后台、HLS、Metal/display-layer 双路径及 reload 回归。

来源：[后台/前台冻结 Bug2](docs/BackgroundForegroundFreezeBug2.md)。

## P1：已规划但尚未实现的功能

### 播放链路可观测性与恢复反馈

实施顺序保持为“时间轴 → 恢复文案 → CDN 学习”：

- [ ] 新增 `PlaybackEventLog` 与开发者控制台 Playback Timeline，事件环形上限 500，并支持 JSON 快照导出。
- [ ] 记录 URL 变化、播放器状态、watchdog 采样、stall、CDN 切换、managed retry、错误和预算耗尽。
- [ ] 在现有 `PlaybackStatusMachine` 上补齐 `fetchingPlayArgs`、`connecting`、`bufferingFirstFrame` 等细分状态。
- [ ] 增加一次性的 `PlaybackRecoveryEvent`，三端展示“正在切换线路 / 正在重试”及尝试次数。
- [ ] 新增 `CDNPreferenceStore`，按平台与 CDN host 学习成功率和首帧耗时；样本不足时保持插件原顺序，数据 7 天失效。
- [ ] 增加 `time_to_first_frame_ms`、watchdog 次数、failover 成功率、首选 CDN 命中率和 30 秒未起播退出率度量。
- [ ] 用时间轴数据复核当前固定 12 秒 stall 阈值是否合理。

来源：[播放链路韧性路线图](docs/PlaybackResilienceRoadmap.md)。

### SC / 付费置顶留言（三仓库链路）

开始编码前先完成产品与设计确认：

- [ ] 确认 `tier` 档位数量、各来源金额到档位的阈值责任方，以及 App 端 `tier → 配色`设计。
- [ ] 确认 iOS、tvOS、macOS 的承载位置，是否允许点击展开、是否保留历史，以及缺省置顶时长。
- [ ] 完成卡片、ticker、并发堆叠与退出动效设计稿。

协议与实现：

- [ ] `LiveParsePlugins` 的付费留言事件输出 `superChat { priceText, tier, avatar?, durationSec? }`；普通弹幕不带该块，礼物仍不产生消息。
- [ ] 更新 `DanmakuDriverAPI.md`，定义字段、档位范围、兼容规则和完整示例。
- [ ] `AngelLiveCore` 解码可选 `superChat`，App 只按该块是否存在进行路由，不识别平台或币种。
- [ ] 三端新增置顶 overlay，处理头像、昵称、金额、留言、档位配色、超时及多条并发。
- [ ] 删除当前 `醒目留言` / `SC` 字符串嗅探和橙底特判。
- [ ] 补协议兼容、普通弹幕、SC 路由、并发队列与三端 UI 验收。

来源：[弹幕引擎评估与改造路线图](docs/DanmakuRenderingRoadmap.md)。

### CloudKit 静默推送与通用持久重试

- [ ] 为收藏自定义 Zone 创建并维护 `CKRecordZoneSubscription`。
- [ ] App 存活时收到静默通知后触发 `CKSyncEngine` 拉取；终止状态继续由下次启动兜底。
- [ ] 为凭证与插件订阅源的手动同步统一处理 `CKErrorRetryAfterKey`。
- [ ] 将可重试操作持久化，跨启动继续；不可重试错误继续映射为具体 `SyncError`。
- [ ] 覆盖限流、离线、账号切换、重复通知与幂等重放测试。

说明：收藏自定义 Zone 已由 `CKSyncEngine` 管理增量与退避；本项针对尚未接入的静默推送，以及凭证/订阅源的手动同步路径。来源：[同步可靠性后续](docs/SyncReliabilityRoadmap.md)。

### 插件首页收尾

首页协议、缓存、Banner、收藏摘要、插件推荐分区和 iOS 首页已经落地；剩余缺口：

- [ ] 决定并实现“继续观看”和“我的平台”模块，或更新规划文档明确从首期删除。
- [ ] 让 `ttlSeconds` 真正参与刷新决策；当前仅校验并保存，进入首页仍会直接刷新。
- [ ] 接入插件升级、禁用、卸载和登录态变化时的定向缓存失效。
- [ ] 将插件刷新并发限制为 3，并明确重复请求的合并/取消语义。
- [ ] 把聚合的失败名单细化为每个来源独立的 cached/loading/refreshing/stale/failed 状态。
- [ ] 补充首页 ViewModel/聚合规则测试：稳定顺序、平台过滤、部分失败、缓存恢复和选择持久化。
- [ ] 真机验证首屏时间、滚动稳定性、图片内存、弱网、Dynamic Type、VoiceOver、减弱动态效果、深浅色和 iPad 分屏。
- [ ] 验证首页“推荐 / 收藏 / 平台”胶囊互通、收藏大标题上拉折叠及 iOS 26+ 不出现双层玻璃。

来源：[插件驱动个性首页规划](docs/PluginDrivenHomePagePlan.md)。当前实现入口：`HomeView.swift`、`HomeViewModel.swift`、`PluginHomeFeed.swift`、`PluginHomeFeedCacheStore.swift`。

## P2：实现已完成，但仍缺设备验收

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
- [ ] 现有 SC 橙底在结构化 SC 上线前不回归。
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

### 文档维护

- [ ] 更新根 `README.md`：workspace 名称应为 `AngelLive.xcworkspace`；Bugsnag 本地密钥路径应为 `Shared/AngelLiveDependencies/Sources/Resources/BugsnagSecrets.local.plist`。
- [ ] 为当前为空的 `TV/README.md` 和 `TV/ARCHITECTURE.md` 补充有效内容，或删除空占位文件。
- [ ] 更新 [插件驱动个性首页规划](docs/PluginDrivenHomePagePlan.md) 的状态与已落地清单；同步“推荐使用 SF Symbol”“首页可选推荐/收藏”等当前产品决策。
- [ ] 将 [Swift 6 / Sendable 适配现状](docs/Swift6SendableAudit.md) 中已被顶部完成结论取代的旧基线明确标为历史记录，避免读者误认为 P0 尚未执行。
- [ ] 将 [iOS DLNA 投屏调研](docs/iOSDLNACastingResearch.md) 的阶段描述与当前“协议、UI、Header 代理均已实现，仅待真机矩阵”状态统一。

## 可选项（不阻塞当前发布）

- [ ] DLNA 自有设备选择器稳定后，再评估 `AVCustomRoutingController` 统一 AirPlay/DLNA 路由 UI。
- [ ] 只有产品未来增加“点播 + 上千条密集弹幕文件”场景，并且 Instruments 证明现有引擎不足时，才评估独立 Swift + Metal 弹幕后端。

## 明确不纳入 TODO

- Stall 指数退避：已改为固定 12 秒阈值，不再实施旧数组方案。
- 播放失败前静默降清晰度、内核偏好白名单、统一 watchdog controller、网络 HEAD 探针和 playArgs 预热：路线图已明确放弃。
- 用 Metal 重写当前直播弹幕引擎：现有 CALayer 架构已是 GPU 合成，当前没有足够收益证据。
- 插件自定义布局、HTML/WebView 首页、远程 SwiftUI/JSON UI DSL、宿主跨插件画像和内置推荐算法：属于首页首期明确边界。

## 文档审计覆盖

| 文档 | 结论 |
|---|---|
| `PRODUCT.md` | 产品原则，无未完成实施项 |
| `AGENTS.md` | 工程执行规范，不作为产品待办来源 |
| `README.md` | 有两处环境配置说明过期，已列入“文档维护” |
| `Shared/SharedAssets/README.md` | 使用说明与当前 Package 配置一致，无待办 |
| `TV/README.md` | 空文件，待补写或删除 |
| `TV/ARCHITECTURE.md` | 空文件，待补写或删除 |
| `docs/BackgroundForegroundFreezeBug2.md` | 有 P0 采证、修复和回归事项 |
| `docs/DanmakuMixedContentProtocol.md` | 当前协议说明，无未完成项 |
| `docs/DanmakuRenderingRoadmap.md` | SC 三层实现及 tvOS 真机验收未完成 |
| `docs/PlaybackResilienceRoadmap.md` | Timeline、恢复反馈、CDN 学习未完成 |
| `docs/PluginDrivenHomePagePlan.md` | 核心已实现，缓存策略、模块取舍和体验验收未收尾 |
| `docs/Swift6SendableAudit.md` | 代码迁移完成，仅剩五组真机验收与历史段落整理 |
| `docs/SwiftUISpecialistAudit.md` | 两项低优先级机会性整理未完成 |
| `docs/SyncReliabilityRoadmap.md` | 三组同步可靠性事项待实施 |
| `docs/iOSDLNACastingResearch.md` | 实现已落地，真实设备、签名能力与兼容矩阵待验证 |
| `iOS/.../Player/PlayerUI/README.md` | 来源与 fork 说明，无未完成项 |

## 维护规则

- 完成事项时，先更新来源文档的状态，再勾选本文件对应条目。
- 方案发生变化时，在来源文档保留决策理由，本文件只保留当前执行方案。
- 需要真机证据的事项不得用模拟器、旧安装包或静态代码检查标记完成。
- 跨端共享层改动按受影响范围构建 iOS、macOS、tvOS；只记录实际运行过的测试和设备。
