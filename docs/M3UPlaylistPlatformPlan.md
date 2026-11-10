# m3u 播放列表（IPTV）方案（v1：一个 m3u = 一个平台）

> 状态：方案草案（2026-11-10），未实现。
> 本方案取代插件仓库 `docs/research/diy-playlist-source-plan-2026-11-09.md` 的插件解析路线：m3u 是通用标准格式，由宿主 Core 原生解析，作为宿主自带的 IPTV 能力，不经过 JS 插件。该插件规划降级为解析细节参考（真实样本观察、边界清单仍然有效）。

## 1. 结论

- m3u 解析、分组、线路合并、master m3u8 展开全部在 `AngelLiveCore` 用 Swift 实现，开箱即用，不依赖任何插件的安装、选择或版本。
- 用户在**插件管理 › 添加订阅源**的同一个输入框里粘贴 m3u 地址；宿主按内容嗅探出播放列表后，表单原地展开，要求填写**平台名称（必填）**和**图标地址（可选）**。
- 每个 m3u 保存为一个「播放列表实例」，在平台网格中表现为一个独立平台；浏览、播放、收藏、历史、搜索复用现有链路，上层页面不感知数据来自插件还是宿主。
- 频道卡片复用 m3u 中的台标（`tvg-logo`），播放列表平台的房间统一使用「台标卡片」样式。
- 宿主不内置、不推荐任何播放列表或频道，内容完全由用户提供。

### 为什么宿主解析而不是插件

| 维度 | 插件解析 | 宿主解析（本方案） |
| --- | --- | --- |
| 来源 | 需用户先从订阅源找到并安装解析插件，或宿主首次内置插件 | 随 App 提供，粘贴即用 |
| 平台中立 | — | m3u 是通用格式而非具体平台，不涉及平台接口、字段或映射 |
| 编码 | JavaScriptCore 无 `TextDecoder`，GBK 需要新增宿主能力 | Swift 原生支持 GBK/GB18030，v1 即可支持 |
| 复杂度 | 需插件发现、选择、实例参数注入、插件间隔离 | 无上述概念 |
| 代价 | 格式扩展可不发版 | 格式扩展需发宿主版本；m3u 格式稳定，可接受 |

## 2. 范围

v1 做：

- 一个 m3u 地址 = 一个平台；名称、图标、地址可编辑；可刷新、删除。
- m3u / m3u8 播放列表；编码 UTF-8，嗅探失败时回退 GB18030。
- 扩展属性：`tvg-logo`、`group-title`、`tvg-name`、`#EXTVLCOPT:http-user-agent` / `http-referrer`、`#KODIPROP` 中的请求头类属性。
- iOS / macOS 可添加与管理；tvOS 通过同步获得实例，只读 + 刷新。
- 台标卡片、不可用状态、跨设备同步、平台内搜索与全局搜索。

v1 不做：

- 一个平台合并多个 m3u；本地 `.m3u` 文件导入；整段文本粘贴；DIYP txt。
- EPG（`x-tvg-url`）、频道测活。
- 播放页内「频道列表」侧边面板、上一台/下一台换台（含 tvOS 遥控器上下键）。换台需先修订 `PRODUCT.md` 的反面参照，并作为覆盖所有来源的宿主「播放上下文」单独立项，不在本方案内实现。

## 3. 用户流程与界面

### 3.1 添加（复用 `PluginSourceAddView`）

```
┌ 取消        添加订阅源              ┐
│ [ https://…/playlist.m3u        ]  │
│ [ ⊕ 添加 ]                          │
│ 订阅源地址、兑换码或 m3u 播放列表地址。  │
└─────────────────────────────────────┘
        │ 点击添加 → 拉取 → 嗅探
        ├─ 插件索引 JSON  → 现有流程
        ├─ 兑换码         → 现有流程
        └─ 正文以 #EXTM3U 开头 → 原地展开 ↓

┌ 取消        添加播放列表          添加 ┐
│ 地址   https://…/playlist.m3u      ✓  │
│ ───────────────────────────────────── │
│ 平台名称                               │
│ [ 例如：我的电视                    ]  │
│ 图标地址（可选）                        │
│ [ https://…/logo.png              ]  │
│ 预览  [图]  我的电视                    │
│            343 个频道 · 9 个分组        │
│ 内容由你添加的播放列表提供。              │
└───────────────────────────────────────┘
```

规则：

1. **按内容嗅探，不看扩展名**。真实样本中大量地址无扩展名或为动态脚本。判定：去掉 BOM 与前导空白后以 `#EXTM3U` 开头。
2. **嗅探必须在乐观持久化之前**。`PluginSourceManager.validateAndLoadSource` 在所有候选拉取失败时会把主候选存为「异常插件源」；m3u 分支须在 JSON 解码失败后、持久化前判定，否则 m3u 会变成一条永久报错的插件源。兑换码解析出的地址同样走嗅探。
3. **解析成功才能保存**：Core 解析器至少解析出 1 个频道才启用「添加」；解析结果（频道数、分组数）用于预览行，并作为首份缓存写入，避免保存后再拉一次。
4. **平台名称必填**：去首尾空白后非空；与已有平台（含其他实例）重名提示「名称已存在」；长度上限按平台卡片可完整显示的宽度定（视觉验收确定，初值 12 个字符）。可用 m3u 头部标题作为占位建议，不自动代填保存。
5. **图标可选**：
   - 留空 → 首字图标（名称首字符 + 中性底色），尺寸/圆角与现有平台卡片图标一致。
   - 填写 → 下载并校验为图片，缓存到本地，卡片只读本地缓存；失败提示「图标无法加载，将使用默认图标」，**不阻止保存**。
6. **错误文案具体化**：无法访问（复用 `friendlySourceErrorDescription`）、不是 m3u、未识别到频道、无法识别文本编码。不使用笼统的「添加失败」。

页脚文案同步更新为覆盖三种输入。

### 3.2 平台网格

实例平台卡片与其他平台**完全同构**（名称 + 图标），不加徽标或特殊尺寸。点击进入 `PlatformDetailView`：一级导航为 m3u 分组，首位为「全部」；缺省分组归「未分组」；宿主不截断分组或频道。

### 3.3 管理

插件管理页新增「播放列表」分区，与「订阅源」分区并列，行结构对齐既有订阅源行：

```
播放列表
┌────────────────────────────────┐
│ [图] 我的电视        343 频道  › │
│      更新于 8 分钟前             │
└────────────────────────────────┘
```

详情页：编辑名称 / 图标 / 地址（改地址需重新解析通过）、立即刷新、删除。删除确认说明「相关收藏和观看历史将无法播放」。刷新失败保留上次成功的数据并在行内标注，不把平台页变成整页错误。

### 3.4 不可用状态

| 情况 | 表现 |
| --- | --- |
| 首次拉取失败且无缓存 | 平台页显示现有 `ErrorView` + 重试，标题不出现「请登录」 |
| 刷新失败但有缓存 | 正常显示缓存，管理行标注「正在使用 N 分钟前的数据」 |
| 实例在本设备不存在（他端已删除） | 收藏/历史条目显示「播放列表不可用」，不崩溃、不静默删除 |
| 频道在新版列表中已消失 | 播放时提示「该频道已不在播放列表中」 |

### 3.5 三端差异

| | iOS / iPadOS | macOS | tvOS |
| --- | --- | --- | --- |
| 添加 | 同一输入框 + 展开表单 | 同一输入框 + 展开表单 | 不提供输入；经同步获得 |
| 管理 | 插件管理「播放列表」分区 | 同左（macOS 设置样式） | 只读列表 + 刷新 |
| 卡片 | 台标卡片 | 台标卡片 | 台标卡片（焦点放大） |

各端控件、行高、间距分别对齐本端既有插件管理页，不共用一套样式。

## 4. 频道台标

解析器映射：

| m3u | LiveModel | 说明 |
| --- | --- | --- |
| `tvg-logo` | `roomCover`、`userHeadImg` | http 尝试升级 https；无效置空 |
| 频道名（EXTINF 属性区之后第一个逗号后的文本） | `roomTitle`、`userName` | 标题可含 `#` 与全角标点，不按 `#` 或任意逗号切分 |
| `group-title` | 分类 | 缺省「未分组」 |
| — | `liveWatchedCount` = nil，`liveState` = 在播 | 不测活 |

宿主展示：现有房间卡片把 `roomCover` 当 16:9 直播截图铺满裁切，台标（多为透明底、近方形）直接套用会被裁切。播放列表平台的房间使用**台标卡片**：

```
┌────────┐┌────────┐┌────────┐
│  logo  ││  logo  ││   频   │  台标 aspectFit 居中，内边距留白，
│        ││        ││        │  底色为系统中性材质；
├────────┤├────────┤├────────┤  台标为空/加载失败 → 频道名首字
│频道 A   ││频道 B   ││频道 C   │
│ 2 条线路││        ││ 2 条线路│  副标题：线路数或分组名
└────────┘└────────┘└────────┘
```

- 不显示观看人数与「直播中」角标。
- 样式**按平台类型判定**：房间 `liveType` 属于播放列表实例 → 台标卡片。收藏、历史、搜索结果中的同一频道自动一致，`LiveModel` 不新增持久化字段。
- 图片沿用现有加载与缓存组件；卡片比例与列数在视觉验收时按各端既有网格确定。

## 5. Core 设计

### 5.1 解析器 `M3UPlaylistParser`

纯函数、值类型输入输出，无 I/O，便于 fixture 测试：

- 识别 `#EXTM3U`、`#EXTINF`、`#EXTVLCOPT`、`#KODIPROP`；其余 `#` 行（含非标准扩展指令）静默忽略。
- `#EXTVLCOPT` / `#KODIPROP` 绑定到下一条 URL 行，映射为该线路的 `userAgent` / 请求头。
- 同一 `(分组, 频道名)` 的多条 URL 合并为一个频道的多条线路，保持原顺序。
- 编码：先按 UTF-8 严格解码，失败回退 GB18030；仍失败报「无法识别文本编码」，不做静默乱码解析。
- 大小上限与行数上限按真实样本量级设置保护阈值（防止误把超大文件读入内存），超限给出明确错误。

### 5.2 实例模型与存储

```swift
public struct PlaylistInstance: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var iconURL: String?
    public var sourceURL: String      // 可能含 token，按凭据级保存
    public var createdAt: Date
    public var updatedAt: Date
}
```

- `sourceURL` 视为敏感，实例走既有 vault/钥匙串通道，不进普通明文配置、日志、诊断导出；日志只记实例 ID 与请求结果。
- 同步复用 `PlatformCredentialSyncService` 通道，**保持 UUID 不变**；冲突以 `updatedAt` 较新者为准，删除需传播（墓碑），按 `SyncReliabilityRoadmap.md` 的合并/删除/离线规则落地。
- 解析结果缓存（频道索引）存 Application Support 的缓存目录，按实例 ID 分文件，不同步；TTL 初值 600s，过期后 stale-while-revalidate：先展示旧数据，后台刷新成功再替换。
- 图标本地缓存不同步，各设备按 `iconURL` 自行拉取。

### 5.3 平台身份

- 实例 `LiveType` = `"playlist:<小写UUID>"`。`playlist:` 前缀为宿主保留命名空间，需在插件 manifest 校验中拒绝以该前缀声明的 `liveTypes`，避免冲突。
- `LiveModel.id` 为 `"\(liveType)-\(roomId)"`，实例间天然隔离。
- `roomId` = `(分组 + "|" + 频道名)` 的稳定哈希前 16 位，不含 URL：线路变化、列表刷新后收藏不失效；同名多行合并为一个房间。

### 5.4 接入现有数据链路

现状：平台由 `SandboxPluginCatalog.platform(for:)` / `availablePlatforms()` 提供；分类、房间、搜索经 `LiveService` → `ApiManager` → `LiveParseJSPlatformManager`；播放地址在三端 `RoomInfoViewModel` 与 `ShortDramaPlaybackModel` 中直接调用 `LiveParseJSPlatformManager.getPlayArgs`；状态经 `getLiveLastestInfo`（含 `FavoriteRefreshPolicy`）。

方案：在 Core 引入平台数据提供者协议，按 `LiveType` 分发，**分发点放在 `LiveParseJSPlatformManager` 与 `ApiManager` 的入口函数内部**，三端调用点不改：

```swift
protocol LivePlatformDataProvider: Sendable {
    func categories() async throws -> [LiveMainListModel]
    func rooms(category: LiveCategoryModel, page: Int) async throws -> [LiveModel]
    func search(keyword: String, page: Int) async throws -> [LiveModel]
    func playArgs(roomId: String) async throws -> [LiveQualityModel]
    func liveState(roomId: String) async throws -> LiveState
}
```

- JS 插件路径保持现状；`playlist:` 前缀的 `LiveType` 分发到 `PlaylistPlatformProvider`。
- 平台目录需合并实例平台，供平台网格、全局搜索、收藏刷新使用；实例增删改触发平台列表与相关缓存失效。
- `LiveService.fetchCategoryList` 现有磁盘缓存键基于插件版本，播放列表平台走自己的缓存，不进入该分支。
- 能力：播放列表平台声明分类、房间、搜索、播放、状态可用；弹幕、分享解析、首页不可用，宿主按现有能力机制隐藏对应入口。
- 并发：Provider 为 actor 或无状态值类型 + actor 缓存，遵循 Swift 6 严格并发；不新增 `@unchecked Sendable`。

实现前需逐一核对上述入口及三端调用点，确认无绕过分发点的直接调用。

### 5.5 播放

- 多条线路 → 多个 `LiveQualityModel`（cdn），命名「线路 1 / 线路 2」，`QualitySelectionPanel` 直接展示。
- 线路 URL 在 `playArgs` 时抓取嗅探：内容为 master m3u8 → 解析 `#EXT-X-STREAM-INF` 展开为「自动」+ 各清晰度（名称取 `NAME` / `RESOLUTION`，否则由 `BANDWIDTH` 生成如「5000kbps」），相对 URI 按播放列表地址补全，嵌套展开上限 2 层；其余按原地址透传。抓取与播放都带上该线路的请求头。
- 起播失败自动切下一条线路：先核对 `PlaybackResilienceRoadmap.md` 现有恢复状态机是否已覆盖跨 cdn 回退；未覆盖则在 Core 通用实现，不做播放列表特例。
- http 流与 http 台标的 ATS 行为需三端实测后定稿（宿主现有 ATS 配置不在本方案内修改）。

## 6. App Store 注意事项

- 不内置、不推荐、不链接任何播放列表或频道源；文案只表述「添加你自己的 m3u 播放列表」。
- 商店截图与描述只使用自制演示播放列表和中性图标，不出现真实电视台台标或节目。
- 审核备注提供一个可合法播放的测试播放列表地址及操作步骤。
- 以上为一般性经验，不构成审核结果保证；提审前按当时的审核指南复核。

## 7. 改动清单（预估）

| 层 | 位置 | 内容 |
| --- | --- | --- |
| Core | 新增 `Playlist/` 模块 | 解析器、实例存储与同步、Provider、缓存 |
| Core | `LiveParseJSPlatformManager`、`ApiManager`、`SandboxPluginCatalog` | 按 `LiveType` 分发、平台目录合并实例平台 |
| Core | 插件 manifest 校验 | 拒绝 `playlist:` 前缀的 `liveTypes` |
| Core | `PluginSourceManager` | 持久化前的 m3u 嗅探分支 |
| iOS | `PluginManagementView` | 输入框文案、展开表单、「播放列表」分区与详情 |
| iOS | 房间卡片 / 平台卡片 | 台标卡片、首字图标 |
| macOS | 插件管理、`LiveRoomCardButton` | 同上 |
| tvOS | 插件管理、`LiveCardView` | 只读实例列表、台标卡片 |

共享入口须在 FullUI 分支内隔离，不修改 ShellUI。

## 8. 验证

| 层 | 内容 |
| --- | --- |
| Core 测试 | 解析器：EXTINF 属性与标题切分（含 `#`、全角标点）、缺省分组、非标准指令忽略、EXTVLCOPT/KODIPROP 绑定、同名多线路合并、UTF-8/GB18030/无法识别、空列表、超限；master 展开：NAME/RESOLUTION/BANDWIDTH 命名、相对 URI、嵌套上限；嗅探先于乐观持久化；实例 CRUD 与同步合并/删除/离线；`LiveType` 前缀保留与 manifest 拒绝；分发路由；`roomId` 稳定性；缓存 TTL 与 stale-while-revalidate |
| fixture | 依据真实样本结构脱敏重写，地址用 `*.example.invalid`，频道/分组用中性名称；不入库任何真实订阅地址或台标 |
| 宿主构建 | `AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` |
| 设备验收 | 添加（成功/各类错误）、名称必填与重名、图标留空/失败/成功、台标卡片在平台页/收藏/历史/搜索、线路切换与自动回退、删除后收藏表现、tvOS 同步可见；按 `ui-visual-gate.md` 三端分别对照既有页面截图 |

## 9. 待定问题

1. 名称长度上限与台标卡片比例/列数：视觉验收时按各端既有网格确定。
2. 同一 m3u 地址重复添加：倾向允许（名称不同即可），提示「该地址已添加为 xx」。
3. 实例平台在首页 `homeFeed` 中的呈现：v1 不提供首页内容。
4. 播放列表大小与行数保护阈值的具体数值：按真实样本量级与设备内存实测确定。
