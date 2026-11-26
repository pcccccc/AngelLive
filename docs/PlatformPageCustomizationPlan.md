# 配置页（平台网格）个性化与 iCloud 跨端同步方案

## 1. 背景与目标

当前三端（iOS / iPadOS、macOS、tvOS）FullUI 下的「配置」页（平台入口网格）存在以下体验短板：

1. **无字标插件回退简陋**：当运行时插件未提供宽幅字标大图（`tv_<pluginId>_big`）时，iOS 卡片退化为无标题的固定符号 `play.tv`，多个无字标插件无法区分；tvOS 非播放列表卡片甚至仅剩空白底图；iPad 侧边栏与 macOS 侧边栏分别落回固定 `play.tv` 与 `puzzlepiece.extension`。
2. **背景单一**：三端卡片背景写死 `Image("platform-bg")`，不支持按插件图标主色提取柔和氛围底、系统材质底、内置克制渐变或用户自定义背景图。
3. **尺寸与版式固定**：iOS 写死 2/3 列与 `itemWidth * 0.6` 高度，tvOS 写死 4 列 `380×230`，macOS FullUI 侧边栏缺少「全部配置」网格总览页；用户无法调节卡片密度、比例、圆角、常用平台双列跨度（`spansTwoColumns`）及平台排列顺序。
4. **缺少跨端同步**：用户在任一端整理的平台顺序、自定义图标/徽章/图片与背景风格无法自动同步到其他设备。

本方案以已定稿的三端交互原型 [platform-config-customization.html](prototypes/platform-config-customization.html) 为交互与视觉基线，在 `AngelLiveCore` 构建统一的平台外观配置与 CloudKit 同步层，并在 iOS / iPadOS、macOS、tvOS 三端 FullUI 原生落地。

---

## 2. 边界与红线约束

1. **仅限 FullUI**：所有入口、网格定制、侧边栏图标同步与设置项仅在 `pluginAvailability.hasAvailablePlugins == true` 分支生效；**严禁修改任何 ShellUI 页面或组件**（`ShellConfigView`、`MacShellConfigView`、`TVShellConfigView`、`ShellFavoriteView`、`MacShellFavoriteView` 等）。
2. **原生内聚交互**：严禁在界面中添加任何调试侧栏或开发开关条；全部定制能力均通过各端原生导航栏工具按钮、卡片上下文菜单（长按 / 右键 / 遥控器菜单）、Sheet / Popover / 半屏抽屉及「设置」「数据同步」二级页承载。
3. **几何与视觉铁律**：
   - **同心圆公式**：所有嵌套圆角容器严格遵循 $R_{\text{outer}} = R_{\text{inner}} + P$（`innerRadius = max(6, outerRadius - innerPadding)`），统一使用 `.continuous` 圆角曲线。
   - **内间距与基线对齐**：同一行内字标卡、图标+标题回退卡、自定义徽章卡与双列宽卡（`spansTwoColumns`）必须严格共享外框高度、上下边距与标题基线；双列卡宽度严格等于 `itemWidth * 2 + gridSpacing`，与上下行两张单列卡左右边缘严丝合缝对齐。
   - **设置行视觉复用**：iOS `SettingView`、macOS `SettingView` / `MacSyncManagementView`、tvOS `SettingView` / `SyncManagementView` 新增入口必须 100% 复用同页既有行结构、图标槽宽度（如 iOS 32pt 图标列、`PanelNavigationRow`、tvOS 半屏列表行）与字号色阶，不另起特殊行高或无依据偏移。
4. **平台中立与凭证安全**：源码、注释、测试、fixture 与文档仅使用 `fixture.alpha`、`fixture.beta`、`playlist:<UUID>` 等中性标识；复用现有 `iCloud.icloud.dev.igod.simplelive` 私有 CloudKit 容器，不修改任何 `.entitlements` 或签名配置。

---

## 3. 共享层设计（`Shared/AngelLiveCore`）

在 `Shared/AngelLiveCore/Sources/AngelLiveCore/PlatformAppearance/` 下新增以下模块，遵循 Swift 6 严格并发隔离，不反向依赖宿主或 `AngelLiveDependencies`：

### 3.1 数据模型（`PlatformAppearanceModels.swift`）

```swift
public enum PlatformDeviceIdiom: String, Codable, Sendable, CaseIterable, Hashable {
    case phone
    case pad
    case mac
    case tv
}

public enum PlatformGridDensity: String, Codable, Sendable, CaseIterable, Hashable {
    case comfortable // 舒展
    case standard    // 标准（默认）
    case compact     // 紧凑
}

public enum PlatformCardAspectPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case wide    // 16:9 (height / width = 0.5625)
    case classic // 5:3  (height / width = 0.60，与现有默认一致)
    case compact // 2:1  (height / width = 0.50)
    case square  // 1:1  (height / width = 1.00)
}

public enum PlatformBackgroundPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case graphite
    case ocean
    case dusk
    case forest
    case ember
}

public enum PlatformBackgroundStyle: Codable, Equatable, Sendable, Hashable {
    case defaultAsset                                  // 默认 platform-bg 资源
    case dominantIconAura                              // 插件方形图标饱和主色柔和渐变（无主色回退柔和中性底）
    case systemSurface                                 // 原生分组表面材质
    case preset(PlatformBackgroundPreset)              // 内置克制渐变
    case customImage(assetID: String, focalY: Double)  // SHA-256 寻址自定义背景图，focalY 范围 0...1（默认 0.5）
}

public enum PlatformLogoMode: Codable, Equatable, Sendable, Hashable {
    case auto                                          // 字标大图 -> 方形图标+标题 -> 首字徽章+标题
    case symbol(name: String, tintHex: String?)        // SF Symbol + 可选十六进制强调色
    case monogramBadge(text: String, tintHex: String?) // 1~3 字符自定义徽章 + 可选十六进制底色/强调色
    case customImage(assetID: String)                  // SHA-256 寻址自定义透明 PNG / 图标
}

public enum PlatformTitleVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    case auto   // 展示插件字标大图时不额外叠标题；方形图标/徽章/符号模式显示单行标题
    case always // 始终在卡片底部安全区内显示单行标题
    case hidden // 视觉隐藏标题（保留 accessibilityLabel）
}

public struct PlatformIdiomCustomMetrics: Codable, Equatable, Sendable, Hashable {
    public var useCustomMetrics: Bool
    public var columns: Int
    public var cardHeight: Double
    public var cornerRadius: Double
    // 提供 clamped(for idiom: PlatformDeviceIdiom) 保证各端数值处于安全区间：
    // phone: 1...3 列, 高 84...180pt, 圆角 12...28pt
    // pad:   2...5 列, 高 96...220pt, 圆角 12...28pt
    // mac:   2...6 列, 高 100...240pt, 圆角 10...24pt
    // tv:    3...5 列, 高 180...300pt, 圆角 16...32pt
}

public struct PlatformCardAppearanceOverride: Codable, Equatable, Sendable, Hashable {
    public var pluginId: String
    public var logoMode: PlatformLogoMode
    public var titleVisibility: PlatformTitleVisibility
    public var backgroundOverride: PlatformBackgroundStyle? // nil 表示跟随全局背景
    public var spansTwoColumns: Bool
    public var updatedAt: Date
}

public struct PlatformAppearanceSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var globalBackground: PlatformBackgroundStyle
    public var backgroundBlurRadius: Double // 0...20
    public var contrastScrimEnabled: Bool
    public var gridDensity: PlatformGridDensity
    public var cardAspect: PlatformCardAspectPreset
    public var globalUpdatedAt: Date
    public var idiomMetrics: [PlatformDeviceIdiom: PlatformIdiomCustomMetrics]
    public var idiomUpdatedAt: [PlatformDeviceIdiom: Date]
    public var orderedPluginIds: [String]
    public var orderUpdatedAt: Date
    public var cardOverrides: [String: PlatformCardAppearanceOverride]
    public var resetTombstones: [String: Date]
}
```

#### 预设列数映射（未开启单端 `useCustomMetrics` 时）

| 设备形态 (`PlatformDeviceIdiom`) | `comfortable`（舒展） | `standard`（标准，默认） | `compact`（紧凑） |
| --- | --- | --- | --- |
| `phone`（竖屏紧凑） | 1 列 | 2 列 | 3 列 |
| `pad`（常规宽度） | 2 列 | 3 列 | 4 列 |
| `mac`（自适应窗口宽度） | 2~3 列（最小宽 280pt） | 3~4 列（最小宽 220pt） | 4~5 列（最小宽 176pt） |
| `tv`（1920pt 画布） | 3 列 | 4 列 | 5 列 |

### 3.2 图标主色提取（`PlatformIconDominantColor.swift`）

- 将 `TVPlatformIconProvider` 中的 32×32 `CGContext` 像素分桶 + 低透明度/低饱和度过滤（`alpha >= 40`、`saturation >= 0.18`）抽取为 `AngelLiveCore` 公共纯 `CoreGraphics` 工具 `PlatformIconDominantColor.extract(from cgImage: CGImage, cacheKey: String?) -> PlatformRGBAColor?`。
- 内置线程安全内存缓存，供三端 `.dominantIconAura` 卡片背景及 tvOS 插件管理架共同复用。

### 3.3 本地图片资产缓存（`PlatformAppearanceAssetCache.swift`）

- 使用 `ImageIO` + `CoreGraphics` 对用户导入的图片进行格式校验与下采样：
  - 自定义 Logo：最大边长 `512px`，保留 Alpha 通道输出 PNG；
  - 自定义背景：最大边长 `1600px`，无透明通道时编码为高质量 JPEG（`0.82`），有透明通道时编码为 PNG；最终字节数控制在 `<= 1.5 MB`。
- 以编码后字节流的 `SHA256` 前 32 位十六进制字符串作为不可变 `assetID`。
- 存储路径：
  - iOS / macOS：`Application Support/AngelLive/PlatformAppearanceAssets/<assetID>`
  - tvOS：`Caches/AngelLive/PlatformAppearanceAssets/<assetID>`（系统回收缓存后可由 `PlatformAppearanceSyncService` 自动从 CloudKit 重新拉取恢复）。
- 界面渲染层只同步/异步读取本地已落地文件，绝不在视图 `body` 中发起网络请求。

### 3.4 本地状态仓库（`PlatformAppearanceStore.swift`）

- 提供 `@MainActor @Observable public final class PlatformAppearanceStore`（单例 `.shared` + 可注入独立目录用于单元测试），同时提供线程安全的快照读写桥接供 `PlatformAppearanceSyncService` 调用（参照 `PlaylistInstanceStore` 模式）。
- 本地快照文件：`platform-appearance-v1.json`（iOS/macOS 位于 `Application Support/AngelLive/`，tvOS 位于 `Caches/AngelLive/` 并辅以 `UserDefaults` 轻量备份以防缓存清理丢失纯文本配置）。
- 核心方法：
  - `orderedPlatforms(_ platforms: [Platformdescription]) -> [Platformdescription]`：按 `orderedPluginIds` 排列已安装平台；未出现在 `orderedPluginIds` 中的新平台保持原有相对顺序追加在末尾，绝不截断或丢弃任何已安装平台。
  - 更新全局背景、密度/比例、指定 `PlatformDeviceIdiom` 的自定义宽高圆角、平台顺序（前移/后移/拖拽移动）、单平台 `PlatformCardAppearanceOverride`、单平台重置（写入 `resetTombstones[pluginId] = now` 并移除 `cardOverrides[pluginId]`）与全局恢复默认。
  - 每次变更发出 `Notification.Name.platformAppearanceDidChange`（附带变更来源 `local` / `sync` 以避免同步自触发死循环）。

### 3.5 iCloud 跨端合并与同步服务（`PlatformAppearanceSyncService.swift`）

参照 `PlaylistSyncService` 与 `SyncReliabilityRoadmap.md` 设计：

1. **纯函数冲突合并（`PlatformAppearanceSyncMerge.merge(local:remote:)`）**：
   - 全局外观字段（`globalBackground`、`backgroundBlurRadius`、`contrastScrimEnabled`、`gridDensity`、`cardAspect`）：比较 `globalUpdatedAt`，取较新一方。
   - 平台顺序（`orderedPluginIds`）：以 `orderUpdatedAt` 较新一方为主序，将另一方存在但主序未包含的 `pluginId` 按原顺序追加在尾部，去重保序。
   - 各端独立尺寸（`idiomMetrics`）：按每个 `PlatformDeviceIdiom` 各自的 `idiomUpdatedAt[idiom]` 独立取新，确保 iPhone 自定义列高绝不覆盖 iPad / Mac / Apple TV 的尺寸配置。
   - 单卡覆盖与重置墓碑（`cardOverrides` + `resetTombstones`）：对每个 `pluginId` 比较 `override.updatedAt` 与 `tombstoneDate`，取时间戳最新者；时间戳完全相同时墓碑（恢复默认）优先，避免其他设备旧缓存把已重置配置复活。
2. **CloudKit 协议与资产同步**：
   - 容器：`iCloud.icloud.dev.igod.simplelive` 的 `privateCloudDatabase`。
   - 元数据记录：`recordType = "platform_appearance"`，`recordName = "user_platform_appearance"`，含 `payload`（JSON `Data`）与 `updated_at`（`Date`）；使用默认 change-tag 条件保存，捕获 `CKError.serverRecordChanged` 自动重新拉取合并重试（最多 3 次）。
   - 图片资产记录：`recordType = "platform_appearance_asset"`，`recordName = "asset_<assetID>"`，含 `asset`（`CKAsset`）与 `sha256`（`String`）。
   - 上传前先收集快照中实际引用的所有 `assetID`（全局自定义背景 + 单卡自定义背景 + 单卡自定义 Logo），仅上传云端尚不存在的本地资产文件；拉取远端快照后，对本地缓存缺失的 `assetID` 按需下载 `CKAsset` 校验写入 `PlatformAppearanceAssetCache`，落盘后通知 UI 刷新。
3. **开关与未签名测试环境守卫**：
   - 新增开关 `PlatformAppearanceSyncService.syncEnabled`（`UserDefaults` 键 `SimpleLive.Setting.PlatformAppearanceICloudSyncEnabled`，默认 `true`，且受总开关 `PlatformCredentialSyncService.iCloudSyncSettingEnabled` 约束；并在「数据同步」页展示状态、独立开关与「立即同步外观」操作）。
   - **SwiftPM 测试安全守卫**：抽象 `PlatformAppearanceCloudStoring` 协议供单测注入内存云端假实现；默认 `CloudKitPlatformAppearanceStore` 在 macOS 构造/调用 `CKContainer` 前先通过 `SecTaskCopyValueForEntitlement`（或 Bundle 可执行路径检查）确认当前进程具备 CloudKit 容器 entitlement，未签名的 `swift test` 进程安全返回不可用而不触发 `CKContainer` 崩溃。
   - 在 `AngelLiveApp.swift`、`AngelLiveMacOSApp.swift`、`SimpleLiveTVOSApp.swift` 启动时调用 `Task { await PlatformAppearanceSyncService.shared.start() }`，并监听前后台激活通知自动拉取。

---

## 4. 三端 FullUI 界面与交互规范

### 4.1 卡片内容智能解析优先级（三端统一）

对于任意 `Platformdescription`：

1. **Logo 呈现（`logoMode`）**：
   - `.customImage(assetID)`：若本地 `PlatformAppearanceAssetCache` 命中图片则居中/等比缩放展示；未下载完成前优雅回退到 `.auto`。
   - `.symbol(name, tintHex)`：在连续圆角徽章槽（圆角 = `slotSide * 0.25`）内居中渲染指定 SF Symbol 与强调色。
   - `.monogramBadge(text, tintHex)`：在连续圆角徽章槽内以光学居中渲染 1~3 字符缩写（复用 `CoreText` 墨迹边界居中或等宽字重排版）。
   - `.auto`（默认智能三级回退）：
     1. 若非播放列表且插件提供字标大图（`tv_<pluginId>_big` / 暗色变体），渲染字标大图；
     2. 否则若插件或播放列表提供方形图标（`pad_live_card_` / `live_card_` / `PlaylistIconCache`），渲染圆角方形图标 + 单行平台标题；
     3. 否则渲染确定性首字徽章 `PluginManagementMonogram` + 单行平台标题。
2. **标题显示策略（`titleVisibility`）**：
   - `.auto`：步骤 1 命中宽幅字标大图时不叠加标题（避免与字标文字重复）；其余模式均在图标下方展示单行平台标题。
   - `.always`：即使使用字标大图，也在底部内嵌安全区内展示清晰单行标题（字标最大高度自动收敛，保证上下内边距与同心圆安全区不被挤压）。
   - `.hidden`：隐藏卡片可见文字标题，外层交互控件保留 `.accessibilityLabel(platform.title)`。
3. **卡片背景解析（`card.backgroundOverride ?? snapshot.globalBackground`）**：
   - `.defaultAsset`：现有 `Image("platform-bg")` 铺满裁剪。
   - `.dominantIconAura`：基于插件方形图标提取主色（无主色时回退基于 `PluginManagementMonogramStyle` 调色板的克制渐变），配合微光径向/线性过渡，适配浅色/深色模式。
   - `.systemSurface`：各端原生次级卡片表面 + 1px 内描边（`.strokeBorder(.primary.opacity(0.08), lineWidth: 1)`），保证浅色与深色背景下的边界清晰度。
   - `.preset(_)`：5 款克制低噪点双色渐变，保证前景可读性。
   - `.customImage(assetID, focalY)`：按 `focalY` 垂直焦点裁切铺满，叠加用户可调模糊半径（`backgroundBlurRadius`）与可选对比度保护暗角（`contrastScrimEnabled`）。
4. **双列跨度网格布局（`spansTwoColumns`）**：
   - 提供共享网格排布计算器 `PlatformGridLayoutPlanner`：给定容器总宽 `containerWidth`、列数 `columnsCount`、间距 `spacing`、水平边距 `horizontalPadding` 与有序平台列表：
     - 单列槽宽 `unitWidth = (containerWidth - horizontalPadding * 2 - spacing * CGFloat(columnsCount - 1)) / CGFloat(columnsCount)`；
     - 当平台设置 `spansTwoColumns == true` 且 `columnsCount >= 2` 时：若当前行剩余列数 `>= 2` 则直接占 2 列（宽度 `unitWidth * 2 + spacing`）；若当前行仅剩 1 列，为避免右侧悬空缺口或溢出，可将该双列卡换至下一行起始位置（或将紧随其后的单列卡补位填满当前行，保持视觉紧凑且相对顺序最小扰动，单元行高恒定一致）。

### 4.2 iOS / iPadOS（`iOS/AngelLive/`）

- **作用范围**：`AdaptivePlatformView.swift`（仅 `pluginAvailability.hasAvailablePlugins` 分支）、`FullUI/Views/PlatformView.swift`、`ContentView.swift`（iPad `TabSection` 平台图标）、`Common/Utils/PlatformIconProvider.swift`、`FullUI/Views/Setting/SettingView.swift`、`FullUI/Views/Setting/SyncView.swift`。
- **交互入口**：
  1. `AdaptivePlatformView` 与 `PlatformView` 顶部导航栏右侧提供「外观」按钮（`Image(systemName: "slider.horizontal.3")`，与原有 `+` 按钮共享原生 ToolbarItemGroup 间距）。
  2. 平台卡片支持 `.contextMenu`：「自定义卡片外观…」「跨两列展示 / 恢复单列展示」「前移一位」「后移一位」「恢复默认外观」。
  3. `SettingView`（`hasAvailablePlugins` 条件内）在「设置」分组新增「配置页外观」入口（图标槽 `.frame(width: 32)`，与「通用设置」「弹幕设置」完全对齐）。
  4. `SyncView` 新增「配置页外观同步」卡片/开关与手动立即同步入口，复用页面既有卡片圆角、内边距与状态文案样式。
- **定制面板**：
  - **配置页外观 Sheet**（`.listStyle(.insetGrouped)`）：顶部展示实时等比缩略预览卡（遵循同心圆内边距），下方依次为「全局卡片背景」（含 `PhotosPicker` 选图、模糊度滑杆、对比度保护开关）、「网格密度与比例」（舒展/标准/紧凑、比例分段器、当前设备自定义列数/卡片高度/圆角开关与步进滑杆）、「平台顺序与单卡管理」（支持 `onMove` 排序及点击进入单卡定制）、「iCloud 外观同步」与底部「恢复全部默认」二次确认按钮。
  - **单平台外观定制 Sheet**：顶部实时渲染该平台真实比例卡片预览，下方提供 Logo 模式分段切换（自动 / 系统符号 / 缩写徽章 / 自定义图片 `PhotosPicker`）、标题显示策略（自动 / 始终显示 / 隐藏）、单卡背景覆盖（跟随全局 / 独立预设 / 独立图片）、双列跨度开关与「恢复此平台默认」。
- **iPad 侧边栏同步**：`ContentView.swift` 的 `iPadTabView` 中 `TabSection` 下的平台图标（`25×25`）优先读取用户为该平台定制的自定义图片 / SF Symbol / 缩写徽章，`.auto` 无图标时使用 `PluginManagementMonogram(size: 25)`，彻底消除盲目的 `play.tv` 占位。

### 4.3 macOS（`macOS/AngelLiveMacOS/`）

- **作用范围**：`ContentView.swift`（仅 `pluginAvailability.hasAvailablePlugins` 分支）、`Views/PlatformView.swift`、`Utils/MacPlatformIconProvider.swift`、`Views/SettingView.swift`、`Views/MacSyncManagementView.swift`。
- **补齐 FullUI「全部配置」总览页**：
  - 在 `macOS/AngelLiveMacOS/ContentView.swift` 的 `TabSection("平台")` 中，当 `pluginAvailability.hasAvailablePlugins == true` 时：
    - 顶部展示 `Tab(value: TabSelection.allPlatforms)`（标题 `"全部配置"`，图标 `square.grid.2x2.fill`），承载重构后的 `PlatformView`；
    - 下方 `ForEach` 按 `PlatformAppearanceStore.shared.orderedPlatforms(platformViewModel.platformInfo)` 顺序渲染各平台侧边栏项，侧边栏图标（`18×18`）同步应用单平台自定义 Logo 或首字徽章回退（消除 `puzzlepiece.extension` 简陋回退）；
    - 点击「全部配置」网格中的任意平台卡片，直接将 `selectedTab` 切换至 `.platform(platform)` 进入该平台分类房间页。
- **桌面端原生交互**：
  - 工具栏右侧提供紧凑密度分段选择与「页面外观」按钮，点击弹出原生 `.popover`（宽度 `360pt`，分组表单排版，支持切换全局背景、Mac 端列数/高度/圆角、背景模糊及平台排序入口）。
  - 卡片支持鼠标悬停微高亮、右键 `.contextMenu`（自定义外观、跨两列展示、前后移动、恢复默认）及居中模态「单平台外观定制」Sheet（复用 `.macSettingsSheetPresentation()` 与 `PanelCloseButton`，通过 `.fileImporter(allowedContentTypes: [.image])` 选择本地 PNG/JPEG 图片）。
  - `SettingView`（在 `hasAvailablePlugins` 分支内，并遵循 `isVodDemo` 禁用约束）增加「配置页外观」入口；`MacSyncManagementView` 增加「配置页外观 iCloud 同步」`PanelNavigationRow` 开关与立即同步操作。

### 4.4 tvOS（`TV/AngelLiveTVOS/`）

- **作用范围**：`Source/Platform/PlatformView.swift`、`Source/Platform/PlatformViewModel.swift`、`Source/Setting/SettingView.swift`、`Source/Setting/SyncManagementView.swift`。
- **10 英尺大屏网格与焦点体验**：
  - 保留 `.buttonStyle(.card)` 系统级焦点抬升阴影与焦点态平台描述浮层（遵循 `generalDisableMaterialBackground` 切换 `sl-background` 或 `.thinMaterial`）。
  - 修复非播放列表无字标插件空白卡片：统一接入 4.1 节智能解析（包括从 iPhone / iPad / Mac 通过 iCloud 同步过来的自定义透明 Logo 与自定义背景图！）。当卡片非宽幅字标图（如首字徽章、符号、方形图标+标题）获得焦点时，前景图标+标题平滑淡出（`opacity: 0`），避免文字模糊后与焦点描述文案重影；宽幅字标图或纯背景图获得焦点时平滑高斯模糊衬托前景描述。
  - 支持预设密度（舒展 3 列 / 标准 4 列 / 紧凑 5 列）、卡片宽高比或 TV 端自定义高度/圆角，以及双列宽卡排布（自动计算精确槽宽与焦点间距 `50pt`，保证焦点缩放不裁切）。
- **遥控器定制交互与焦点契约（遵循 `TVFocusAndRemoteNavigation.md`）**：
  - 平台网格右上角提供克制的「页面外观」胶囊按钮，且每张平台卡片支持遥控器长按 `.contextMenu`（「自定义卡片外观…」「跨两列展示 / 恢复单列」「前移 / 后移」「恢复默认外观」）。
  - 触发定制时在右侧滑出半屏玻璃抽屉（复用 `adaptiveGlassEffect` 材质与半屏宽度），覆盖密度/列数、TV 卡片高度与圆角、全局/单卡内置背景与主色氛围、Logo 符号/缩写徽章、标题策略与排序操作；对于自定义相册图片项，展示清晰说明「在 iPhone、iPad 或 Mac 设置自定义图片后将通过 iCloud 自动同步至 Apple TV」。
  - 抽屉打开时将焦点确定性移入抽屉首项，拦截 `.onExitCommand`（遥控器 Menu / Back 键）关闭抽屉并将焦点精准恢复到触发前的平台卡片或工具按钮，绝不发生焦点丢失或误退回顶层 Tab。
  - `TV/.../SettingView.swift` 在 `hasAvailablePlugins` 半屏菜单中增加「配置页外观」子页，`SyncManagementView.swift` 增加「配置页外观同步」状态与开关详情页。

---

## 5. 验证矩阵与交付门禁

| 层级 | 必验项 | 通过标准 |
| --- | --- | --- |
| `AngelLiveCoreTests` | 新增 `PlatformAppearanceTests.swift` | 覆盖默认编解码、跨端 `idiomMetrics` 独立合并、单平台 `updatedAt` 与 `resetTombstones` 冲突消解、`orderedPluginIds` 保序合并、CloudKit `serverRecordChanged` 重试与缺失 `CKAsset` 按需拉取、主色提取；全部测试 100% 通过，测试数据 100% 使用 `fixture.*` 中性值 |
| 三端宿主构建 | `AngelLive`（iOS）、`AngelLiveMacOS`（macOS）、`AngelLiveTVOS`（tvOS） | 使用本机最高版本 Xcode（`/Applications/Xcode-27.2.0.app`）完成三端 Debug 构建 0 错误 |
| 平台中立与静态检查 | 全仓扫描 + `git diff --check` + `ShellUI` 零改动核查 | 新增/修改文件不含任何具体内容平台品牌、域名或私有字段；`ShellUI` 相关文件零 diff；保留工作区既有未提交改动 |
| 设备与视觉验收 | Terra 串行执行模拟器/原生运行截图，root 逐张原尺寸复核 | 严格遵守单模拟器运行上限（iOS -> 关机 -> tvOS -> 关机 -> macOS 原生运行）；逐张核验浅色/深色模式、无字标回退卡、自定义背景/徽章、双列跨度对齐、同心圆圆角、内间距与设置页行高对齐 |
