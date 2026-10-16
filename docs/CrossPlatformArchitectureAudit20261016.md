# 三端架构与页面联动审查

审查日期：2026-10-16。范围为 iOS、macOS、tvOS 的 FullUI 及其共享模块，依据当时包含既有未提交修改的工作树。本文记录静态代码审查结果与后续处理顺序，不代表构建、设备交互或视觉验收通过。

结论：共享业务层已有较完整基础，共用 UI 已提取一部分，但三端页面联动尚未全部完成。主要缺口是宿主页面绕过共享模型修改状态，以及已有共享实现未在三端统一接入。

代码位置均相对仓库根目录，行号对应本次审查快照；后续修改后应通过符号定位。

## 1. 架构现状

| 层级 | 已承担的职责 | 判断 |
| --- | --- | --- |
| 三端宿主 | 导航、窗口、焦点、遥控器、UIKit/AppKit 桥接、播放器呈现 | 平台差异应继续保留 |
| AngelLiveCore | 插件运行时、会话、收藏同步、首页、搜索、播放规则、弹幕与翻译，以及部分共享 UI | 核心业务已有共享基础，但不是完全纯领域包 |
| AngelLiveDependencies | 播放器适配、恢复适配、媒体转换、投屏、图片及其他第三方依赖、字幕 UI | 已承担跨端适配职责 |
| SharedAssets | 资源访问、部分颜色、加载指示器与样式 | 尚不是完整的共享设计系统 |

Package manifest 与源码 import 检查未发现 Core 反向依赖 Dependencies 或宿主。Dependencies 依赖 Core；Core 当前对 SharedAssets 的 target 依赖限定为 iOS/tvOS。

已抽取的主要业务模块：

- 插件与认证：`LiveParsePluginManager`、`LiveService`、`PlatformSessionManager`、`PluginAvailabilityService`。
- 浏览与数据：`PluginHomeFeedModel`、`SearchRequestModel`、`CategoryRoomListModel`、`AppFavoriteModel`、`HistoryModel`。
- 同步：`FavoriteLocalStore`、`FavoriteSyncEngine`、`PersistentSyncRetryCoordinator`。
- 播放：`RoomPlaybackResolver`、`RoomPlaybackPreparer`、`PlaybackRecoveryCoordinator`、`PlaybackDiagnosticsSession`、`CDNPreferenceStore`、`LiveStatusPollingSession`、`RoomSwitchCandidates`。
- 引擎适配：Dependencies 中的 `PlaybackRecoveryFactory` 与 `KSPlayerPlaybackSession`。

## 2. 优先修复的代码问题

### A01 tvOS 收藏重复修改共享数组

`TV/AngelLiveTVOS/Source/List/LiveCardView.swift:328` 调用 `addFavorite()` 后，第 330 行再次向 `roomList` 添加房间。共享服务已经完成插入、分组、版本更新与持久化，因此会形成重复内存成员，并使列表、分组和持久化快照不一致。

取消收藏在同文件第 305 行调用服务后，第 306 行又仅按 `roomId` 删除，可误删另一插件同编号的内存成员。

共享实现依据：`Shared/AngelLiveCore/Sources/AngelLiveCore/Models/AppFavoriteModel.swift:753`，其中第 782–788 行插入，第 828–829 行更新版本并保存。

处理方向：收藏增删只通过共享服务，宿主保留提示及导航。验证添加一次仅有一个成员、分组与列表一致，以及跨来源同编号收藏互不影响。

### A02 tvOS 历史入口绕过持久化

以下入口直接修改 `historyViewModel.watchList`，没有调用 `addHistory/removeHistory`：

- 普通卡片：`TV/AngelLiveTVOS/Source/List/LiveCardView.swift:452`。
- 首页：`TV/AngelLiveTVOS/Source/Home/TVHomeView.swift:1355`。
- 深链：`TV/AngelLiveTVOS/Source/DetailPlayer/DeepLinkPlayerView.swift:103`、`:124`。
- 删除：`TV/AngelLiveTVOS/Source/List/LiveViewModel.swift:385`。

`Shared/AngelLiveCore/Sources/AngelLiveCore/Models/HistoryModel.swift:22` 的数组没有自动保存观察器；私有保存函数仅由 `addHistory/removeHistory/clearAll` 调用。上述路径缺少保存步骤，重启后新增记录可能丢失、删除记录可能恢复，也绕过了最近观看排序和条数上限。

处理方向：统一历史写入口，并检查批量导入等其他直接数组写入。验证观看、再次观看、删除、上限及重启恢复。

### A03 共享历史身份缺少来源

`HistoryModel.swift:38` 的添加及第 53 行的删除只比较 `roomId`。先后观看 `source-a/123` 和 `source-b/123` 会互相覆盖，删除也可能跨来源生效。

处理方向：复用或定义包含来源的稳定房间身份，统一添加、删除和导入去重。此项应与 A02 一起修复，避免宿主接入后继续继承错误身份规则。

### A04 播放错误检查存在跨端行为分歧

三端 `checkLiveStatusOnError` 都在播放恢复结束后异步查询直播状态并更新错误页面，但只有 macOS 捕获并核对失败房间、请求代次和会话结束状态：

- iOS：`iOS/AngelLive/AngelLive/FullUI/ViewModels/RoomInfoViewModel.swift:1306`。
- macOS：`macOS/AngelLiveMacOS/ViewModels/RoomInfoViewModel.swift:1180`。
- tvOS：`TV/AngelLiveTVOS/Source/DetailPlayer/RoomInfoViewModel.swift:1086`。

iOS/tvOS 缺少对应检查，旧查询迟到时可能覆盖换房或重新请求后的状态。代码风险已确认，具体交互复现尚未运行。

处理方向：先统一异步结果归属与取消契约，再考虑共享失败判定会话；无需合并整个播放器 ViewModel。验证换房、重试、退出时成功与失败响应均不会回写旧状态。

### A05 分类分页未统一且 tvOS 失败页可能被跳过

macOS 已使用 `CategoryRoomListModel`；iOS/tvOS 仍分别维护页码、缓存、加载和错误状态。

- 共享模型：`Shared/AngelLiveCore/Sources/AngelLiveCore/Models/CategoryRoomListModel.swift:21`，仅成功后推进页码。
- macOS 接入：`macOS/AngelLiveMacOS/ViewModels/PlatformDetailViewModel.swift:155`。
- iOS 独立实现：`iOS/AngelLive/AngelLive/FullUI/ViewModels/PlatformDetailViewModel.swift:175`。
- tvOS 独立实现：`TV/AngelLiveTVOS/Source/List/LiveViewModel.swift:230`。
- tvOS 触底递增：`TV/AngelLiveTVOS/Source/List/LiveCardView.swift:390`。

tvOS 失败分支没有回退页码，下一次触底继续递增，存在跳过失败页的风险。处理方向为复用既有分页模型，保留各端分类选择与焦点逻辑，并验证失败重试仍请求原页。

## 3. 页面联动覆盖与待验证项

| 链路 | 静态审查结论 | 依据或剩余工作 |
| --- | --- | --- |
| 首页与插件、登录变化 | 三端已接线 | 首页监听目录修订、网页登录会话和 API 凭证变化，共享刷新上下文包含版本与凭证修订 |
| 插件安装和更新 | 已有共享刷新入口 | `PluginAvailabilityService.swift:104` 执行 runtime reload、能力缓存失效、目录重查和持久会话同步 |
| 收藏与页面展示 | 共享状态机制已有，部分调用方不符合契约 | 先修 A01 |
| 观看与历史页 | 模型已共享，但身份和 tvOS 写入有缺口 | 先修 A02、A03 |
| 设置与已打开播放器 | 跨实例即时刷新尚不完整 | macOS 设置页与播放器分别持有弹幕设置模型，无统一跨实例通知；需动态确认即时效果 |
| 插件原地升级与 tvOS 平台页 | 缺少主动刷新接线 | 平台页仅监听安装 ID，不监听目录修订；同 ID 更新后的标题、描述可能继续使用旧值 |
| 网页登录恢复与搜索结果 | 已按设计保留手动重试 | 登录浮层关闭不视为成功，返回原错误页后由用户重试；不是自动重试缺陷。真实认证完成仍需单独验收 |
| 跨设备同步 | 机制已有，真实账号验收仍待完成 | 不能把共享代码与本地测试等同于多设备同步通过 |

具体证据：

- 首页：iOS `FullUI/Views/Home/HomeView.swift:37`；macOS `Views/MacHomeView.swift:137`；tvOS `Source/Home/TVHomeView.swift:149`。
- 独立弹幕设置实例：`macOS/AngelLiveMacOS/Views/SettingView.swift:966` 与 `ViewModels/RoomInfoViewModel.swift:151`。共享 `DanmuSettingModel` 的变更通知属于当前实例，部分配置虽会在后续读取时生效，但没有保证其他实例对应视图立即刷新。
- tvOS 平台页：`TV/AngelLiveTVOS/Source/Platform/PlatformView.swift:34`；根 `Other/ContentView.swift:240` 的目录修订处理更新收藏和首页，没有刷新平台页私有模型。切换 Tab 是否触发重新进入需要设备确认。
- 登录恢复的明确契约见[认证恢复说明](AuthenticationRecovery20261004.md)：关闭浮层后由用户手动重试。此依据在文档清理时补充，替代本轮早先的产品预期待确认判断。
- 搜索：iOS `FullUI/Views/SearchView.swift:133`；macOS `Views/SearchView.swift:65`；tvOS `Source/Search/SearchRoomView.swift:98`。
- 真实 iCloud 场景与剩余条件见 [同步可靠性记录](SyncReliabilityRoadmap.md)。

## 4. 尚未收敛的共享业务

| 对象 | 当前重复 | 建议 |
| --- | --- | --- |
| 短剧播放模型 | iOS `FullUI/Views/ShortDrama/ShortDramaPlaybackModel.swift:13` 与 Core `Playback/ShortDramaPlaybackModel.swift:14` 的加载、切集、取消、EOF 和自动连播逻辑基本一致；macOS/tvOS 已使用 Core | 后续将 iOS 接入 Core，保留手势与播放器呈现；当前短剧计划曾明确保留 iOS，不将此债务解释为本轮必须扩大修改范围 |
| 搜索执行封装 | iOS `SearchView.swift:338`、macOS `SearchView.swift:194`、tvOS `LiveViewModel.swift:303` 重复诊断、关键字/分享分流、空结果兼容及分享记录 | 在现有 `SearchRequestModel` 上统一 executor，保留输入和导航 |
| 弹幕连接编排 | 三端 `RoomInfoViewModel.getDanmuInfo` 重复能力检查、plan 加载、transport 选择、delegate 和 connect/disconnect | 明确连接会话契约后共享；沿用现有底层恢复算法，不另造重试系统 |
| 平台目录元数据 | tvOS `Source/Platform/PlatformViewModel.swift:29` 与 Core `Models/PlatformViewModel.swift:27` 重复筛选、去重、标题及描述 fallback | 共用纯描述数据构造，平台图标加载与展示继续留宿主 |

分类分页和播放错误检查的收敛同时具有功能修复价值，见 A04、A05。

## 5. 共用 UI 现状

已确认有宿主实际调用的共享组件：

| 位置 | 组件 | 实际覆盖 |
| --- | --- | --- |
| SharedAssets | `ArcSpinner`、`ArcProgressViewStyle`、`fullUIArcLoadingStyle` | 三端 |
| Core Translation | `TranslatedRoomTitle` | 三端房间卡片及首页 |
| Core PluginUI | `RequiresLoginTag`、`PlatformAPIAccountView`、`PlatformDeviceLoginView`、`PluginSourceErrorCard` | 三端 |
| Core Diagnostics | `SupportDiagnosticsView` | 三端设置及错误页 |
| Core PluginUI | `PluginManagementPluginRow` | iOS/macOS，未发现 tvOS 调用 |
| Core PluginUI | `PluginUpdateOverview` | 本次仅发现 macOS 调用 |
| Core Services | `FavoriteImportResultView` | iOS/macOS |
| Core DevConsole | 开发者和插件控制台、播放时间线 | iOS/macOS 使用控制台，tvOS 使用播放时间线 |
| Dependencies | 字幕设置 section 与字幕 overlay | 三端；快捷控件为 iOS/macOS |

各端内部房间卡片也已复用：

- iOS：`FullUI/Components/LiveRoomCard.swift` 被首页、搜索、平台页和 UIKit cell 消费，收藏与历史列表复用该 cell。
- macOS：`Views/PlatformDetailView.swift:392` 定义的 `LiveRoomCard` 被首页、搜索、收藏、历史和播放器换房区使用。可迁入 `Components` 提高可发现性，无需重造。
- tvOS：`Source/List/LiveCardView.swift` 被列表、首页、收藏、搜索和历史页使用。

优先提取机会：

| 对象 | 重复证据 | 合理共享边界 |
| --- | --- | --- |
| 房间骨架 | iOS `FullUI/Components/LiveRoomCardSkeleton.swift:18` 与 macOS `Components/LiveRoomCardSkeleton.swift:17` 的封面、头像和两行占位结构接近 | 共享纯内容，宽度、网格及 shimmer 所有权由宿主控制 |
| 双层封面 | iOS `LiveRoomCard.swift:344`、macOS `PlatformDetailView.swift:519`、tvOS `LiveCardView.swift:78` | 共享无交互展示及图片适配；保留各端降采样、缓存、裁切策略，不给 Core 引入 Kingfisher |
| 头像展示 | iOS 卡片、tvOS 卡片与 macOS `RemoteAvatarView` | 共用容器/占位接口，保留 Mac GIF 解码和 TV 焦点描边 |
| 能力状态徽标 | iOS `PlatformCapabilitySheet.swift:162`、macOS `PlatformCapabilityPopover.swift:66`、tvOS `TVPlatformCapabilitySheet.swift:210` | 共用状态文案和颜色映射，字号、圆点和间距按平台参数化 |
| 主题基础常量 | iOS `Common/Constants.swift` 与 macOS `Constants.swift` | 收敛语义角色及同值常量，保留系统色映射和平台密度；先检查并隔离 ShellUI 影响 |
| 观看人数格式 | iOS/macOS Constants 与 tvOS String 扩展 | 先确认千/万边界的显示契约，再共享纯 formatter；无调用副本优先删除 |

整张房间卡片、错误页、清晰度面板及导航不宜直接合并。iOS 的 UIKit 手势和转场、macOS 的窗口与 hover、tvOS 的焦点与遥控器行为具有真实差异。当前无需为这些提取先重建整套 Package 架构。

## 6. 后续处理清单

- [ ] 修复 A01，收藏数组只由共享模型维护。
- [ ] 联合修复 A02、A03，统一历史身份、写入与持久化。
- [ ] 修复 A04，验证迟到响应不会污染新播放会话。
- [ ] 修复 A05，将分类分页收敛到已有共享模型。
- [ ] 补验设置跨实例刷新、插件同 ID 升级及登录后搜索恢复。
- [ ] 后续将 iOS 短剧和三端搜索执行封装接入共享实现。
- [ ] 定义弹幕连接会话契约，再迁移宿主重复编排。
- [ ] 按低风险顺序提取骨架、能力徽标、封面与主题常量。
- [ ] 使用真实账号完成跨设备同步验收。

每项修复应先明确 FullUI 边界和状态所有者，再运行针对性测试及受影响宿主构建。涉及 UI 结构或样式时，必须按项目规则完成最后编辑后新包的视觉对齐与交互验收。

## 7. 本轮验证边界

本轮完成源码检索、跨端实现比较、共享模型与消费点调用链复核、Package 依赖检查，以及全仓可见文本的常见内容平台标识检索和测试身份字段检查。检索未发现所查标识命中；这不等同于对未知平台标识的穷尽证明。

`git diff --check` 通过。审查未修改业务代码，未运行构建、单元测试或设备操作；上述运行风险与待验证项不标记为动态复现或视觉通过。既有未提交修改保持原样。
