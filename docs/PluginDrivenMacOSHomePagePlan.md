# 插件驱动 macOS 首页实施规划

> 状态：首期实现完成，宿主构建验证受本机 FFmpegKit checkout 阻塞 · 2026-08-29
>
> 范围：macOS FullUI 首页与必要的共享层抽取；不修改 `MacShell*`、iOS ShellUI 或 tvOS
>
> 基线：页面结构直接参考当前 iPad 的 `iPadTabView` + `HomeView(usesPersistedPlatformSelection: false)`，而不是机械照搬 iPhone 交互或旧规划中尚未实现的模块
>
> 结论：macOS 应沿用 iPad 的独立“首页 / 收藏”侧边栏和 `Banner → 收藏摘要 → 各内容源推荐分区` 页面骨架，复用现有 `homeFeed` 协议、校验和缓存；只在工具栏、窗口、键鼠和播放器呈现上做 Mac 适配。

---

## 0. 产品与范围边界

本方案继承 `docs/PluginDrivenHomePagePlan.md` 的产品边界：

- AngelLive 仍然只是播放器宿主，不提供、维护或分发插件。
- Banner、推荐分区、房间和推荐理由全部来自用户已安装插件。
- 插件只返回结构化数据，不能控制 SwiftUI 布局、窗口、颜色、字体或动效。
- 跨内容源聚合时保留 `pluginId` 和插件显示名；只有插件明确返回 `personalized = true` 时才能展示“为你推荐”。
- 首页请求继续只包含 `schemaVersion`、`locale` 和可选 `region`，不发送收藏、历史、Token、Cookie 或其他插件信息。
- 文档示例不使用真实平台名称；这不限制产品展示插件返回的名称、Logo 和来源信息。

### 0.1 本期包含

首期与当前 iPad 已实现范围对齐：

1. 焦点 Banner。
2. “我的收藏”摘要和进入完整收藏页的入口。
3. 每个支持 `homeFeed` 的内容源最多一个主推荐分区。
4. 默认展示多内容源聚合推荐；与 iPad 一样，首期不在页面内增加内容源筛选器。
5. 房间播放、分类“查看全部”、缓存先行、手动刷新和局部失败降级。
6. 插件安装、更新、卸载及能力变化后的原地刷新。

### 0.2 本期不包含

- 不增加“继续观看”和“我的平台”首页模块。当前 iOS 首页尚未落地这两项，macOS 已有独立“历史记录”和平台侧边栏入口，首期重复展示反而会增加噪音。
- 不把 iOS 的沉浸式窄屏高度、下拉拉伸、触觉反馈或全屏转场直接移植到 Mac。
- 不新增插件协议字段，不提升全局 `apiVersion`，不修改首页 `schemaVersion`。
- 不调整播放器窗口策略、收藏同步规则、平台详情页或搜索页。
- 不修改 `MacShellFavoriteView`、`MacShellConfigView` 等 ShellUI 代码。
- 不在本期同时实现 tvOS；共享抽取需为 tvOS 后续接入保留复用能力，但不能提前加入 tvOS UI 假设。

---

## 1. 当前代码基线

### 1.1 已经可以直接复用的共享能力

| 能力 | 当前实现 | macOS 处理 |
|---|---|---|
| `homeFeed` 能力判定 | `PlatformCapability.supports(.homeFeed, for:)` | 直接复用 |
| 插件调用 | `PluginHomeFeedService` | 直接复用 `LiveParsePlugins.shared`，不得新建 manager |
| 容错解码与宿主校验 | `PluginHomeFeed.swift` | 直接复用 |
| 首页磁盘快照 | `PluginHomeFeedCacheStore.shared` | 直接复用 macOS App 自己的 Caches 容器 |
| 插件目录变更信号 | `PluginAvailabilityService.installedPluginIds` + `catalogRevision` | 同时监听，原地升级不能只看 ID 数组 |
| 收藏快照与刷新 | `AppFavoriteModel` | 复用环境中的全局实例 |
| 房间卡片 | macOS `LiveRoomCard` | 复用视觉与右键收藏能力 |
| 播放入口 | `FullscreenPlayerManager.openRoom(_:openWindow:)` | 保持当前独立窗口/全屏策略 |

### 1.2 实施前缺口（本次已处理）

- 首页聚合和分类分页状态已抽到 `AngelLiveCore`，iOS 继续通过兼容别名消费共享模型。
- iOS `HomeView` 保留 UIKit、安全区、下拉回弹和播放转场；macOS 使用独立原生布局。
- macOS `ContentView` 已加入独立 `.home` 入口，无 `homeFeed` 能力时回退收藏并隐藏首页。
- `⌘R` 已通过 `FocusedValues` 路由到当前焦点窗口的首页，不广播重置其他窗口状态。

### 1.3 规划采用的复用边界

```text
AngelLiveCore
├─ PluginHomeFeedService / CacheStore       已存在
├─ PluginHomeFeedModel                      从 iOS 抽取的跨端展示状态
└─ PluginHomeCategoryModel                  跨端分类分页与错误状态

iOS FullUI
└─ HomeView                                 保留现有 iOS 布局和交互

macOS FullUI
├─ MacHomeView                              Mac 页面组合
├─ MacHomeHeroView                          Banner、箭头、键盘和悬停
├─ MacHomeRoomSection                       横向房间分区
└─ MacHomeCategoryView                      Mac adaptive grid
```

共享层只拥有数据、聚合、刷新、分页和稳定身份；卡片尺寸、工具栏、Hover、焦点、窗口和播放呈现留在平台宿主。

---

## 2. 入口与导航决策

### 2.1 侧边栏结构

macOS 直接参考当前 iPad `iPadTabView` 的结构：`首页` 与 `收藏` 是两个独立一级入口，平台仍位于独立 `TabSection`，搜索和设置继续保留。Mac 只额外保留现有“历史记录”入口。

| 当前 iPad | macOS 规划 | 说明 |
|---|---|---|
| `Tab("首页") { HomeView(usesPersistedPlatformSelection: false) }` | `Tab("首页") { MacHomeView() }` | 都是聚合推荐首页，不复用 iPhone 的首页/收藏偏好切换 |
| 独立“收藏”Tab | 独立“收藏”Tab | 首页“查看全部收藏”切换到该入口 |
| `TabSection` 中展示全部配置和各平台 | 保留当前 Mac 平台 `TabSection` | 不把平台入口重复放进首页 |
| 搜索、设置 | 搜索、历史记录、设置 | “历史记录”是 Mac 已有入口，继续保留 |

支持推荐首页时，macOS FullUI 的最终侧边栏顺序为：

```text
首页
收藏
平台
  ├─ 内容源 A
  └─ 内容源 B
搜索
历史记录
设置
```

- `TabSelection` 新增 `.home`。
- “首页”使用 `house.fill`，放在“收藏”之前。
- `MacHomeView` 与 iPad 一样固定展示聚合推荐，不接入 iPhone 长按首页 Tab 的平台筛选偏好。
- “收藏”保留独立入口，不把完整收藏页塞进首页导航栈。
- 首页“查看全部收藏”通过回调切换 `selectedTab = .favorite`，而不是再创建一份 `FavoriteView`。
- 分类 Banner 和分区“查看全部”使用外层 `NavigationStack` 的 typed route；`MacHomeView` 内不嵌套第二个 `NavigationStack`。
- 房间目标不 Push 到主内容列，继续调用 `FullscreenPlayerManager`，遵循用户当前的播放器窗口设置。

### 2.2 FullUI 与 ShellUI 隔离

首页入口只在以下状态出现：

```text
插件检测尚未完成
或
至少一个已安装插件明确支持 homeFeed
```

检测完成且没有任何 `homeFeed` 能力时：

- 若当前选择为 `.home`，先回退到 `.favorite`，再移除首页 Tab，避免 `sidebarAdaptable` 出现无效 selection 崩溃。
- 保持当前收藏入口：有可用插件时显示 `FavoriteView`，无插件时显示 `MacShellFavoriteView`。
- 不修改任何 `MacShell*` 文件，也不改变 ShellUI 的配置和收藏行为。

若插件原地更新后新增 `homeFeed` 能力，首页入口可以原地出现，但不强制把用户从当前页面切走；下次新窗口默认进入首页。

### 2.3 默认入口与窗口状态

- 新窗口在推荐能力未确认时可先选择 `.home` 并恢复缓存；能力确认不可用后按上一节有序回退。
- `selectedTab`、当前分类导航和首页滚动位置属于单个窗口，不放进全局单例。
- 首页与 iPad 一样固定使用聚合推荐，因此不新增 Mac 内容源筛选偏好，也不复用 iOS 专属 `HomePagePreference` 键。

---

## 3. macOS 页面设计

### 3.1 页面骨架

页面内容顺序以当前 iPad `HomeView` 为直接参照，macOS 不重新排列模块：

```text
窗口工具栏：标题“首页” | 刷新

ScrollView
└─ LazyVStack
   ├─ 焦点 Banner
   ├─ 我的收藏（有本地收藏时）
   ├─ 内容源 A 主推荐
   ├─ 内容源 B 主推荐
   └─ 局部错误或空状态
```

- 使用系统背景和现有 `AppConstants` 语义色，不为首页创造独立主题。
- iPad 的纵向 `ScrollView` + `LazyVStack`、全宽 Hero 和横向房间分区作为结构基线；Mac 组件可独立实现，但相同数据应落在相同模块位置。
- 主内容保持合理最大宽度并居中；窗口变宽时增加两侧留白，不无限拉高 Banner 或卡片。
- 所有尺寸由内容区宽度驱动，不依赖固定 Mac 型号、屏幕分辨率或窗口 PID。
- 最小窗口仍遵守 App 当前 `800 × 450` 下限，侧边栏展开、收起和拖动宽度时不重建首页模型。

### 3.2 工具栏

macOS 首期保持与 iPad 一样的聚合首页，不额外增加内容源筛选。工具栏只承载 Mac 平台需要的页面级动作：

- 标题为“首页”。
- 刷新按钮只在刷新期间显示系统进度状态并禁用重复请求，不旋转整页或清空旧内容。
- 接入现有 `⌘R` 菜单命令时使用 focused scene action，只刷新当前焦点窗口；不新增跨窗口广播通知。
- 如果以后确认 Mac 需要单内容源筛选，再作为独立增强评估，不把它混入本次“参考 iPad 结构”的首期实现。

### 3.3 焦点 Banner

- 采用宽幅单卡 Banner，宽高比随容器适配并设置最大高度；不使用 iPhone 约 90% 视口高度。
- 图片优先级与 iOS 一致：房间目标优先 `roomCover`，插件 `imageURL` 作为兜底；使用 Kingfisher 下采样和现有缓存。
- 标题、可选副标题、Badge 放在底部渐变遮罩内，来源在需要时使用次要文本显示。
- 左右箭头在鼠标悬停或键盘焦点进入 Banner 时出现；触控板横滑、左右方向键和按钮均可切换。
- 多 Banner 保持宿主公平轮询顺序；选中页使用稳定 ID，不因某个插件后返回而跳页。
- 前台且窗口活跃时可按 iOS 规则每 6 秒轮播；鼠标悬停、用户刚手动切页、窗口失焦或“减弱动态效果”开启时暂停。
- macOS 不实现 iOS 下拉回弹拉伸、触觉反馈和纵向视差。
- 房间 Banner 直接打开播放器；分类 Banner进入 `MacHomeCategoryView`。

### 3.4 收藏与推荐分区

- 分区使用横向 `LazyHStack`，保持和 iOS 相同的信息顺序，同时为鼠标提供悬停箭头和滚轮/触控板横向滚动。
- 房间卡片复用 macOS `LiveRoomCard`，建议宽度在 200–260 pt 范围随窗口自适应；同一分区等宽等高。
- “我的收藏”最多展示前 10 个稳定快照；为空时隐藏整个分区。
- 收藏状态刷新只在分区副标题显示“状态更新中”，不覆盖每一张卡。
- 收藏卡遵循当前离线拦截语义；插件推荐卡按 iOS `.direct` 语义进入播放器，不因缺失或过期的 `liveState` 被错误拦截。
- 每个内容源只展示一个主推荐分区：优先非空个性化分区，否则取第一个主分区。
- 推荐副标题继续显示插件来源；插件返回理由可以替代卡片次要信息，但不能改变卡片结构。
- 有 `seeAllTarget` 时显示“查看全部”，进入共享分页模型驱动的 Mac adaptive grid。

### 3.5 分类查看全部

- `MacHomeCategoryRoute` 只携带稳定的 `pluginId`、`LiveType` 和分类字段，不保存整份 feed。
- `MacHomeCategoryView` 使用 `LazyVGrid` + `.adaptive(minimum: 180, maximum: 260)`，沿用现有平台详情页和收藏页密度。
- 首次加载、加载更多、下拉/工具栏刷新、空结果和失败分别显示明确状态。
- 触发最后一项加载更多时必须防重入；失败后页码回滚，不能跳页。
- 内容源卸载或 route 失效时显示紧凑错误，并允许返回首页，不尝试用其他内容源替代。

### 3.6 键鼠、辅助功能与动效

- Banner 箭头、卡片、刷新和“查看全部”都可通过键盘访问，并提供明确辅助功能标签。
- 房间卡右键菜单继续复用现有收藏/取消收藏能力。
- 文本使用系统语义字体；来源、状态和 Badge 不能只靠颜色表达。
- Hover 只提供轻量描边、阴影或缩放反馈，开启“减弱动态效果”时取消缩放和自动轮播。
- 深浅色、增加对比度、减少透明度下均保持可读；插件颜色只允许作为受限点缀。
- 不做逐卡片长队列入场、自动视频、持续呼吸或粒子动效。

---

## 4. 共享状态与数据流

### 4.1 `PluginHomeFeedModel`

把当前 iOS `HomeViewModel` 的无平台依赖部分移动到 `AngelLiveCore/Home`，形成可被 iOS、macOS 和后续 tvOS 复用的 `@MainActor @Observable` 模型：

```swift
@MainActor
@Observable
public final class PluginHomeFeedModel {
    public private(set) var bannerEntries: [HomeBannerEntry]
    public private(set) var sectionEntries: [HomeSectionEntry]
    public private(set) var platformOptions: [HomePlatformOption]
    public private(set) var failedPluginNames: [String]
    public private(set) var selectedPluginId: String?
    public private(set) var isRefreshing: Bool
    public private(set) var hasLoaded: Bool
    public private(set) var hasRestoredCache: Bool

    public func refresh(installedPluginIds: [String], availabilityConfirmed: Bool) async
    public func selectPlatform(pluginId: String?)
}
```

抽取必须保持当前 iOS 行为不变：

- 插件检测未确认时只恢复缓存，不错误清空快照。
- 同时响应 `installedPluginIds` 与 `catalogRevision`。
- 多内容源并发加载，一个失败不阻塞其他来源。
- 分区顺序沿用上次稳定顺序，不按网络返回速度重排。
- Banner 按来源轮询聚合且不擅自截断插件数组。
- 选择失效插件时回到聚合推荐。
- 保存缓存时只保留当前仍有效的内容源。

iOS target 可保留轻量 `typealias HomeViewModel = PluginHomeFeedModel` 作为迁移桥，避免同时进行无关 UI 重构。

### 4.2 分类分页模型

把 iOS 私有 `HomeCategoryViewModel` 中与 SwiftUI 尺寸无关的部分抽为 `PluginHomeCategoryModel`：

- 共享：route、页码、`rooms`、`isLoading`、`hasMore`、`errorMessage`、刷新和加载更多。
- 平台宿主保留：`CGFloat` 卡片宽度、Grid 列数、导航呈现和播放动作。
- 插件调用继续通过 `LiveParseJSPlatformManager` 统一入口，不跨线程传递 `JSContext` / `JSValue`。
- 模型保持 `@MainActor`；插件运行时自行维护其串行队列，结果回到主 actor 后更新 UI 状态。

### 4.3 首页进入与刷新流程

```text
MacHomeView 出现
  ├─ 固定选择聚合推荐（与 iPad usesPersistedPlatformSelection: false 一致）
  ├─ 并行执行
  │   ├─ PluginHomeFeedModel：恢复缓存 -> 后台请求各内容源
  │   └─ AppFavoriteModel：按 shouldSync() 刷新收藏
  └─ 每个结果按稳定 ID 原地更新

手动刷新 / ⌘R
  ├─ 保留当前 Banner、分区和滚动位置
  ├─ 刷新全部 homeFeed 内容源
  └─ 强制刷新收藏状态
```

- `.task(id:)` 的触发键包含 `installedPluginIds`、`hasCheckedAvailability` 和 `catalogRevision`。
- 新触发开始时取消旧任务，防止旧插件请求在升级或卸载后回写。
- 重复点击刷新不创建并行刷新任务。
- App 进入后台或窗口关闭时取消 Banner 计时器和当前页面拥有的任务。

### 4.4 稳定身份

- Banner 和分区继续使用共享校验后的 namespaced ID。
- 房间身份保持 `liveType + roomId` 口径，不能只按 `roomId` 去重。
- 页面 route 保存标量字段和 ID，不保存会过期的完整 feed 快照。
- 插件显示名、Logo 或元数据变化不能让仍然有效的房间卡获得错误身份。

---

## 5. 状态与降级矩阵

| 场景 | macOS 行为 |
|---|---|
| 插件检测中 | 可先显示兼容缓存和本地收藏；不清空旧内容 |
| 没有安装插件 | 不显示 FullUI 首页入口，保持当前 ShellUI 收藏/配置流程 |
| 有插件但均无 `homeFeed` | 不显示首页入口，默认收藏；分类、搜索、播放不受影响 |
| 有 `homeFeed`、无缓存 | 显示匹配 Banner 和卡片尺寸的骨架，不用全页转圈 |
| 有缓存、网络刷新中 | 立即显示缓存，只在工具栏和分区标题提示刷新 |
| 一个内容源失败 | 保留其旧缓存；无缓存时只显示紧凑来源错误 |
| 全部内容源失败 | 收藏仍可用；有旧缓存继续显示，无缓存显示局部空态 |
| 插件返回空 feed | 不伪造推荐；其他内容源和收藏继续显示 |
| 插件原地升级 | `catalogRevision` 触发能力和 feed 重载 |
| 当前分类对应插件被卸载 | 首页重新聚合剩余来源；分类 route 显示来源不可用 |
| 收藏刷新慢或失败 | 不阻塞 Banner/推荐；保留本地收藏快照 |
| 窗口变窄/变宽 | 保持模型、选中 Banner 和滚动位置，只调整布局 |

---

## 6. 分阶段实施

### 阶段 0：冻结现状与静态原型

- 记录当前 iOS 首页真实实现范围和 macOS 现有导航/播放行为。
- 用中性 fixture 创建 Mac Preview：聚合、多来源、无收藏、部分失败、无缓存。
- 验证最小窗口、默认窗口和宽窗口下的 Banner 高度、卡片宽度及工具栏密度。

完成标准：确认首期只有“Banner + 收藏摘要 + 每来源一个推荐分区 + 分类查看全部”。

### 阶段 1：抽取共享展示状态

- 新增 `PluginHomeFeedModel` 和共享 Entry/Option 类型。
- 抽取 `PluginHomeCategoryModel` 的分页业务。
- iOS 改用共享模型，但不改变现有 iOS 视图和产品行为。
- 为聚合顺序、iPhone 既有筛选归一、缓存恢复、部分失败和分类分页补充 Core 测试。

完成标准：`AngelLiveCoreTests` 通过；iOS 首页展示与抽取前一致。

### 阶段 2：接入 macOS 入口和页面

- `TabSelection` 增加 `.home`，实现能力确认、出现和有序回退。
- 新增 `MacHomeView`、Hero、分区、加载态和局部错误组件。
- “查看全部收藏”切换 sidebar；房间复用 Mac 播放入口。
- 首页结构、模块顺序和聚合展示与 iPad 对齐，不增加首期内容源筛选状态。

完成标准：缓存内容可以首屏显示；收藏刷新和单一插件失败不阻塞首页。

### 阶段 3：分类、键鼠与刷新命令

- 接入 `MacHomeCategoryView` 和分页。
- 完成 Banner Hover 箭头、触控板/键盘切页、自动轮播暂停条件。
- 将 `⌘R` 路由到当前焦点窗口的首页刷新动作。
- 验证右键收藏、VoiceOver、减弱动态效果、深浅色和窗口缩放。

完成标准：所有首页动作可由鼠标和键盘完成，且不影响其他窗口。

### 阶段 4：回归与稳定性

- 验证插件安装、原地升级、卸载、登录态变化和 capability 变化。
- 验证多窗口各自的 Banner 页码、刷新和导航状态。
- 检查 Kingfisher 下采样、长列表懒加载、滚动稳定性和任务取消。
- 根据实际测量调整 Banner 最大高度和卡片宽度，不修改协议限额。

完成标准：macOS 首页达到本文件验收标准，iOS 首页和三端插件能力无回归。

---

## 7. 预计文件边界

建议新增：

```text
Shared/AngelLiveCore/Sources/AngelLiveCore/Home/PluginHomeFeedModel.swift
Shared/AngelLiveCore/Sources/AngelLiveCore/Home/PluginHomeCategoryModel.swift
macOS/AngelLiveMacOS/Views/Home/MacHomeView.swift
macOS/AngelLiveMacOS/Views/Home/MacHomeHeroView.swift
macOS/AngelLiveMacOS/Views/Home/MacHomeRoomSection.swift
macOS/AngelLiveMacOS/Views/Home/MacHomeCategoryView.swift
```

预计修改：

```text
iOS/AngelLive/AngelLive/FullUI/ViewModels/HomeViewModel.swift
iOS/AngelLive/AngelLive/FullUI/Views/Home/HomeView.swift
macOS/AngelLiveMacOS/ContentView.swift
macOS/AngelLiveMacOS/AngelLiveMacOSApp.swift
Shared/AngelLiveCore/Tests/AngelLiveCoreTests/...
```

约束：

- 不修改 `macOS/AngelLiveMacOS/Views/MacShell*`。
- 不修改 `iOS/AngelLive/AngelLive/ShellUI/`。
- 不让 `AngelLiveCore` 依赖 SwiftUI、AppKit、平台宿主或 `AngelLiveDependencies`。
- 如 Xcode 工程不是 folder-synchronized group，新增 macOS Swift 文件时显式加入 macOS targets；先检查工程结构，不能假设自动收录。

---

## 8. 测试与验证计划

### 8.1 Core 自动测试

- 缓存先恢复、插件检测未确认时不清空。
- 多来源 Banner 公平轮询和稳定顺序。
- 每来源只选一个主推荐分区，个性化非空分区优先。
- 共享模型的单内容源筛选及插件卸载归一仍需测试，确保 iPhone 现有行为在抽取后不回归；Mac 首期固定使用聚合模式。
- 一个来源失败时其他来源正常更新，失败来源保留旧缓存。
- `catalogRevision` 对相同 pluginId 的原地升级有效。
- 分类刷新、加载更多、防重入、空页结束和失败页码回滚。

### 8.2 Build

按仓库要求使用 Xcode 27 MCP：

1. `XcodeListWindows` 确认打开的是根目录 `AngelLive.xcworkspace`。
2. 运行相关 `AngelLiveCoreTests`。
3. `BuildProject` 构建 `AngelLiveMacOS`。
4. 因共享模型会影响 iOS，再构建 `AngelLive`。
5. 检查 build log 和 error severity navigator issues；旧 build 不作为新代码证据。

如果同时覆盖 App Store 条件编译，再补 `AngelLiveMacOS-AppStore`；未运行的 scheme 必须明确写“未验证”。

### 8.3 macOS 交互验收

- 默认、最小、宽屏三种窗口尺寸。
- 侧边栏展开/收起和拖动宽度。
- 多来源聚合顺序，以及某一来源安装、升级或卸载后的原地更新。
- Banner 鼠标、触控板、左右方向键、自动轮播与悬停暂停。
- 首页房间、收藏房间和分类房间三条播放路径。
- “查看全部收藏”正确切换侧边栏且不创建重复导航栈。
- `⌘R` 只刷新焦点窗口，另一个窗口状态不被重置。
- 深色、浅色、增加对比度、减少透明度、减弱动态效果和 VoiceOver。
- 插件无能力、空 feed、部分失败、全部失败、缓存离线和收藏慢刷新。

---

## 9. 首期验收标准

1. 支持 `homeFeed` 时，macOS 新窗口默认可进入“首页”，首屏先显示缓存/本地收藏。
2. 没有 `homeFeed` 时保持现有收藏与 ShellUI 行为，不出现空首页或无效 selection。
3. macOS 与 iPad 使用同一聚合规则：同一批 feed 得到相同的 Banner 顺序和每来源主推荐分区；Mac 首期不额外增加内容源筛选器。
4. 首页窗口调整大小时不重建数据模型、不重置滚动位置、不跳回第一张 Banner。
5. 推荐房间遵循 Mac 当前播放器窗口设置；分类目标进入主窗口导航栈。
6. 插件更新、卸载或 capability 变化后，无需重启 App 即可刷新首页入口和内容。
7. 一个来源失败不会阻塞收藏和其他来源；刷新不会先清空旧内容。
8. 未修改任何 ShellUI 文件，iOS 首页行为无变化。
9. Core 测试、macOS workspace build 和受共享抽取影响的 iOS build 均实际通过。

---

## 10. 最终实施顺序

建议严格按以下顺序落地：

```text
共享 HomeFeedModel / CategoryModel
        ↓
iOS 无行为变化迁移并验证
        ↓
macOS 入口与静态页面
        ↓
真实 feed、收藏和播放
        ↓
分类、键鼠、焦点窗口刷新
        ↓
多窗口与异常状态回归
```

这样可以先固定跨端内容语义，再实现 macOS 表现层；后续规划 tvOS 时可以直接复用共享模型，只重新设计焦点和遥控器交互。
