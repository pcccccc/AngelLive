# SimpleLiveTVOS 修复变更说明（ops4.7 审查版）

日期：2026-05-16

## 审查范围

本次修改围绕 3 个用户可见问题：

- Twitch / Kick Cookie 登录无法稳定保存或无法出现在登录入口。
- CHZZK 默认播放清晰度被降到 Auto / 低清晰度。
- SOOP Cookie 登录后部分直播间没有预览图。
- SOOP 19x 直播间返回灰色年龄占位图，登录后仍缺少真实实时封面。
- SOOP 需要列表筛选能力：全部 / 只显示 19x / 只显示非 19x。
- iOS 真机 SOOP 19x 播放页左键点击不弹控制层、画面闪烁或卡死。
- iOS 真机个人开发签名缺少 iCloud entitlement 时启动闪退。
- 官方订阅密钥 `444222000` 未解析，误走普通视频收藏。

同时修复代码审查发现的问题：

- macOS 平台详情页登录入口把 `liveType` 当作 `pluginId` 传入，导致 SOOP 等平台登录页无法定位。
- 初始清晰度选择可能选中空 URL 的“原画 / Best”占位项，导致播放器没有可播放地址。
- ops4.7 复审后补修：音频轨不参与默认清晰度竞争、macOS Cookie 保存失败时登录状态置假、manifest 显式 `auth.required=false` 优先于宿主兜底、session Cookie 去重优先级、SOOP 兜底日志、tvOS 清晰度展示标题与 iOS/macOS 对齐。
- 真机回归后补修：所有 CloudKit 入口在初始化 `CKContainer(identifier:)` 前先判断签名是否包含目标 iCloud 容器，避免个人开发证书无 iCloud 能力时启动或同步入口崩溃；订阅密钥服务补齐官方 `keys.json` 地址和 `444222000` 内置兜底。
- SOOP 19x 复测后补修：只对 19x 占位封面做一次实时截图缓存，非 19x 房间不再 force refresh；首次进入 SOOP 拉取前三页并预热 19x 截图，滚动时继续按窗口预加载未处理过的 19x 房间。
- SOOP 19x 筛选补修：iOS SOOP 分类页新增“全部 / 19x / 非19x”三段筛选；筛选结果基于同一套 19x 占位图检测状态，不改插件协议和持久化模型。

## 核心改动

### 1. 平台登录兼容修复

新增 `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformLoginCompatibility.swift`：

- 为旧版 manifest 缺少 `loginFlow` 的平台提供宿主侧兼容声明。
- 覆盖平台：`twitch`、`kick`、`soop`。
- Twitch 登录 URL：`https://www.twitch.tv/login`。
- Kick 登录 URL：`https://kick.com/login`。
- SOOP 登录 URL：`https://login.sooplive.com/afreeca/login.php`。
- SOOP Cookie 域覆盖 `sooplive.co.kr`、`sooplive.com`、`afreecatv.com`。

修改 `LiveParsePluginManifest.requiresLogin`：

- 由原先只看 manifest 原始字段，改为走 `PlatformLoginCompatibility.requiresLogin`。
- 旧插件即使没有声明登录字段，也可以进入账号管理和登录流程。

修改 `PlatformLoginRegistry`：

- 使用兼容层返回的 `loginFlow` 和 `auth`。
- 登录入口列表可包含 Twitch / Kick / SOOP 旧 manifest。

修复 `macOS/AngelLiveMacOS/Views/PlatformDetailView.swift`：

- 平台详情页登录弹窗改为传 `viewModel.platform.pluginId`。
- 避免 `soop` 平台被错误传成 `8` 后查不到登录入口。

### 2. Cookie 收集与 Web 登录修复

新增 `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformCookieCollector.swift`：

- 统一 iOS / macOS 的 Cookie 过滤、去重、签名和 UID 提取逻辑。
- 支持同站兄弟域匹配，例如 `.twitch.tv` / `www.twitch.tv`、`kick.com` / `www.kick.com`。
- Cookie header 去重时优先非空、当前 session、域名和 path 更具体的 Cookie，再比较长有效期。

修改 iOS 登录面板 `PlatformLoginWebSheet.swift`：

- 使用 `PlatformCookieCollector.filteredCookies` 收集相关域名 Cookie。
- 使用 `PlatformCookieCollector.cookieHeader` 生成最终 Cookie 字符串。
- 使用 `PlatformCookieCollector.containsAuthenticatedCookie` 判断是否已登录。
- 重新登录 / 退出登录时清理相关域名的 Cookie 和 WebKit 站点数据。
- 登录 WebView 默认使用移动 Safari 风格 UA，不再让旧 Twitch/Kick/SOOP 兜底流强制注入桌面 Chromium UA，避免 Twitch 把 WKWebView 判定成“不支持的浏览器”。
- 开启 `javaScriptCanOpenWindowsAutomatically`，并用 `WKUIDelegate` 接管 `target=_blank` / `window.open`，让 SOOP 的 Apple / Google 第三方登录按钮在当前 WebView 内继续跳转。

修改 macOS 登录面板 `MacPlatformLoginWebSheet.swift`：

- 同步 iOS 的统一 Cookie 收集逻辑。
- 打开登录页时立即轮询一次 Cookie，避免登录完成后等待下一轮定时器。
- “重新登录”和“退出登录”会清理相关平台网页登录缓存，避免旧账号 Cookie 干扰。
- Cookie 保存返回过期、无效或网络错误时显式把 `isLoggedIn` 置为 `false`，避免 UI 留在“账号信息”页。
- 登录 WebView 默认使用桌面 Safari 风格 UA，并同步处理第三方登录新窗口，保持 iOS / macOS 登录行为一致。

### 3. JSRuntime Cookie 注入修复

修改 `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/JSRuntime.swift`：

- 修复 `cookieInject` 写入 body 后又被 `envelope.body` 覆盖的问题。
- 现在 body 注入结果会保留到最终请求。
- 影响场景：插件需要把 Cookie 中的字段注入请求 body 时，之前会丢失。

### 4. SOOP 直播间预览图修复

新增 `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/LiveImageURLResolver.swift`：

- 统一标准化直播间封面和头像 URL。
- 支持：
  - 去掉 JSON 转义中的 `\/`。
  - `//host/path` 补 `https:`。
  - `host/path` 补 `https://`。
  - SOOP 旧图床域 `liveimg.sooplive.co.kr` 统一到 `liveimg.sooplive.com`。
  - SOOP 图床 `http` 自动升级为 `https`。
- 当 SOOP 房间 `roomCover` 为空且 `roomId` 是数字时，兜底生成：
  - `https://liveimg.sooplive.com/m/{roomId}?320`
- 命中 SOOP 兜底时输出 `[ImageResolver][SOOP] fallback=...` 调试日志，便于真机回归判断是否命中。

修改 `LiveParseJSPlatformManager.PluginRoomDTO.toLiveModel`：

- 插件返回的 `roomCover` 和 `userHeadImg` 在进入 `LiveModel` 前先做标准化。

新增 `LiveModel` 展示扩展：

- `displayRoomCover`
- `displayUserHeadImg`

所有 UI 图片加载改用展示扩展，避免旧缓存或未标准化 URL 继续导致图片失败。

iOS SOOP 19x 实时封面补充：

- `PlatformDetailViewModel` 首次进入 SOOP 分类时预取前三页房间列表，避免 19x 房间只在滚动后才进入候选池。
- SOOP `liveimg.sooplive.com/m/{roomId}` URL 统一稳定为 `?320`，不再给所有房间追加 `_al_preview` 时间戳。
- 非 19x 房间只走普通 Kingfisher 缓存，不做实时截图、不做强制刷新。
- 19x 判定通过封面 CDN 的 `HEAD/GET` 内容长度识别灰色年龄占位图；只有命中占位图的房间才会解析播放地址并截取首帧。
- 生成的实时封面只写入 Kingfisher 内存缓存，key 为稳定的 `https://liveimg.sooplive.com/m/{roomId}?320`，不改写收藏和 CloudKit 持久化字段。
- ViewModel 记录已检测和正在处理的 `roomId`，下拉刷新、点击刷新或重复进入同一列表不会对已处理房间二次拉流截图。
- `RoomListViewController.willDisplay` 在滚动时把后续窗口交给 ViewModel，继续预加载新出现的 19x 房间。
- 真机日志已确认 19x 写入稳定 key，例如 `https://liveimg.sooplive.com/m/294067533?320`、`https://liveimg.sooplive.com/m/294050349?320`。

iOS SOOP 19x 筛选补充：

- `SubCategoryViewController` 仅在 SOOP 平台显示三段筛选控件：`全部`、`19x`、`非19x`。
- `PlatformDetailViewModel` 保留原始全量 `roomListCache`，新增按分类读取的 `filteredRoomList(...)`，避免筛选破坏分页和缓存。
- 19x / 非19x 状态来自 `liveimg.sooplive.com/m/{roomId}?320` 的占位图检测；未知状态不会被放进 19x 或非19x筛选结果，检测完成后通过通知刷新列表。
- 切换筛选时会立即触发当前分类首屏窗口的 19x 状态检测；滚动到列表后续位置时继续检测附近窗口。
- 已检测过的 `roomId` 不会因为切换筛选、下拉刷新或点击刷新重复进入检测和拉流截图流程。

iOS SOOP 19x 播放控制补充：

- `UnifiedPlayerControlOverlay` 增加全屏透明 tap catcher，控制层隐藏时点击显示，显示时点击空白处隐藏。
- `PlayerContainerView` 移除 VLC drawable 上的 SwiftUI `onTapGesture`，避免 VLCKit drawable 与 SwiftUI 同时争抢 19x 流点击事件。
- `VLCVideoPlayerView` 在同一 media fingerprint 下不再从 `.paused` 强行恢复播放，只处理 `.stopped` / `.error` 恢复；销毁和 stop 时把 VLCKit stop/media 释放放到后台队列，减少主线程卡顿和闪退风险。

### 5. CHZZK 默认清晰度修复

修改 `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/RoomPlaybackResolver.swift`：

- 新增 `preferredInitialSelection(in:)`。
- 默认播放不再盲目使用插件返回的第一个清晰度。
- 清晰度评分规则：
  - `audio` / `音频` 最低。
  - `auto` / `自适应` 低于明确分辨率。
  - `source` / `best` / `原画` 最高。
  - `1080p`、`720p` 等按解析出的高度排序。
  - 没有高度时回退 `qn`。
- 只在可直接播放或声明 `refreshOnSelect` 的清晰度中比较。
- 避免空 URL 的“原画 / Best”占位项抢占默认播放。
- 音频轨不会参与初始默认清晰度竞争；如果没有任何视频候选，仍保持旧逻辑的首项兜底。

修改 iOS / tvOS / macOS 的 `RoomInfoViewModel`：

- 初次拿到 `playArgs` 后使用 `preferredInitialSelection`。
- 手动切换清晰度仍保留原有路径。
- tvOS 展示当前清晰度时改用 `qualityDisplayTitle(in:selection:)`，同名不同流类型时和 iOS / macOS 一样追加 HLS / FLV 区分。

### 6. VLC fallback 构建兼容

当前默认 KSPlayer 依赖链会解析 `https://github.com/TracyPlayer/FFmpegKit`，该远端在本次验证时不可用。为了能在 Xcode 26.5 上完成本地编译验证，使用仓库已有的 `USE_VLC=1` fallback 路径。

补齐 fallback 与真实 KSPlayer 的最小接口差异：

- `Shared/AngelLiveDependencies/Sources/KSPlayerFallback.swift`
  - `KSOptions.playerTypes`
  - `KSOptions.videoFilters`
  - `KSOptions.audioFilters`
  - `KSPlayerLayerBase.reset()`
- `Shared/AngelLiveDependencies/Sources/PlayerOptions.swift`
  - `init()` 显式标记 `override`，兼容 fallback 下 `KSOptions` 的公开初始化器。
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerUI/KSVideoPlayerModelFallback.swift`
  - 增加 `isLocked` 状态，和真实播放器模型对齐。

### 7. 真机签名兼容与订阅密钥修复

新增 `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/CloudKitContainerAccess.swift`：

- 在访问命名 CloudKit 容器前统一判断签名能力。
- iOS / tvOS Debug 或 AdHoc 包通过 `embedded.mobileprovision` 读取 `com.apple.developer.icloud-container-identifiers`。
- 如果当前签名没有 `iCloud.icloud.dev.igod.simplelive`，直接跳过对应 CloudKit 操作并输出日志。
- App Store 包通常没有 `embedded.mobileprovision`，该路径仍信任正式签名 entitlement。

接入该 guard 的 CloudKit 入口：

- `FavoriteService`
- `StreamBookmarkService`
- `PluginSourceSyncService`
- `PlatformCredentialSyncService`

修复效果：

- 个人开发团队不支持 iCloud / Push 的本地真机包可以正常启动。
- 缺少 iCloud entitlement 时不再在 `CKContainer(identifier:)` 处触发 `EXC_BREAKPOINT / SIGTRAP`。
- 本地收藏、插件安装、Cookie 登录仍可继续使用；仅跳过 iCloud 同步。

修改 `PluginSourceKeyService`：

- 补齐远程 `keys.json` 地址：
  - `https://ghfast.top/https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/keys.json`
  - `https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/keys.json`
- 增加官方密钥 `444222000` 的内置兜底映射。
- 远程 keys 拉取失败时，`444222000` 仍会解析到官方插件索引，不会误当成普通视频地址。

## 涉及文件

### 新增文件

- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/LiveImageURLResolver.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformCookieCollector.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformLoginCompatibility.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/CloudKitContainerAccess.swift`
- `docs/OPS4_7_REVIEW_CHANGES_2026-05-16.md`

### Shared / Core 修改

- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/LiveParseJSPlatformManager.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/JSRuntime.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/LiveParsePluginManifest.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/RoomPlaybackResolver.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformLoginRegistry.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/FavoriteService.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformCredentialSyncService.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PluginSourceKeyService.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PluginSourceSyncService.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/StreamBookmarkService.swift`
- `Shared/AngelLiveCore/Tests/AngelLiveCoreTests/AngelLiveCoreTests.swift`

### Shared / Dependencies 修改

- `Shared/AngelLiveDependencies/Sources/KSPlayerFallback.swift`
- `Shared/AngelLiveDependencies/Sources/PlayerOptions.swift`

### iOS 修改

- `iOS/AngelLive/AngelLive/FullUI/Components/LiveRoomCard.swift`
- `iOS/AngelLive/AngelLive/Common/PlayerCore/VLCVideoPlayerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Managers/NowPlayingManager.swift`
- `iOS/AngelLive/AngelLive/FullUI/ViewModels/PlatformDetailViewModel.swift`
- `iOS/AngelLive/AngelLive/FullUI/ViewModels/RoomInfoViewModel.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/DetailPlayerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerContainerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/UnifiedPlayerControlOverlay.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerUI/KSVideoPlayerModelFallback.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerUI/VerticalLiveControllerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/StreamerInfoSheet.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/StreamerInfoView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Setting/PlatformLoginWebSheet.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/UIKit/ViewControllers/RoomListViewController.swift`

### tvOS 修改

- `TV/AngelLiveTVOS/Source/DetailPlayer/DetailPlayerView.swift`
- `TV/AngelLiveTVOS/Source/DetailPlayer/PlayerControlCardView.swift`
- `TV/AngelLiveTVOS/Source/DetailPlayer/RoomInfoViewModel.swift`
- `TV/AngelLiveTVOS/Source/List/LiveCardView.swift`
- `TV/TopShelfExtension/ContentProvider.swift`

### macOS 修改

- `macOS/AngelLiveMacOS/ViewModels/RoomInfoViewModel.swift`
- `macOS/AngelLiveMacOS/Views/MacPlatformLoginWebSheet.swift`
- `macOS/AngelLiveMacOS/Views/PlatformDetailView.swift`
- `macOS/AngelLiveMacOS/Views/PlayerControlView.swift`

## 新增测试覆盖

修改 `Shared/AngelLiveCore/Tests/AngelLiveCoreTests/AngelLiveCoreTests.swift`：

- `PlatformLoginCompatibilityTests`
  - 旧 Twitch / Kick / SOOP manifest 能获得宿主登录兜底。
  - manifest 自带 `loginFlow` 时优先使用 manifest，不被兜底覆盖。
- `PluginSourceKeyTests`
  - 官方短密钥 `444222000` 不依赖远程 keys 索引也能解析到官方插件索引。
- `PlatformCookieCollectorTests`
  - 兄弟域 Cookie 能正确过滤。
  - 登录信号 Cookie 能被识别。
  - Cookie header 能正确生成。
  - 同名 Cookie 去重时 session Cookie 优先于旧 persistent Cookie。
- `LiveImageURLResolverTests`
  - SOOP 空封面生成预览 CDN URL。
  - SOOP 旧图床域名 canonicalize。
  - 非 SOOP 空封面保持为空。
- `PlaybackInitialSelectionTests`
  - CHZZK 类 Auto / 720p / 1080p 列表默认选 1080p。
  - 空 URL 的“原画”占位项不会被默认选中。
  - 有视频候选时跳过 audio-only 音频轨。
  - `refreshOnSelect` 的高画质项即使 URL 为空，仍允许作为初始候选。
- `PlatformLoginCompatibilityTests`
  - manifest 显式声明 `auth.required=false` 时优先于宿主 fallback。

## 兼容性说明

- 兼容层是 data-only，后续插件 manifest 正式声明 `loginFlow` 后，会自动优先使用 manifest 字段。
- SOOP 预览图兜底只在 `liveType` 为 `8` 或 `soop`，且 `roomId` 为纯数字时启用。
- SOOP 19x 实时截图只在 iOS 列表层启用；非 19x 房间不会进入播放地址解析或截图流程。
- SOOP 19x 筛选只在 iOS SOOP 分类页展示；其它平台和 tvOS/macOS 不显示该控件。
- SOOP 19x 截图只作为 Kingfisher 内存缓存存在，App 重启后会重新按当前直播状态检测，不污染收藏、历史或 iCloud 数据。
- UI 层保留原 `LiveModel.roomCover` / `userHeadImg` 字段，只新增展示用扩展，避免影响持久化模型结构。
- 清晰度选择只改变初始默认项，用户手动切换清晰度流程未重写。

## 验证结果

已执行：

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Shared/AngelLiveCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer USE_VLC=1 xcodebuild build -workspace AngelLive.xcworkspace -scheme AngelLive -configuration Debug -destination 'platform=iOS,id=00008130-000204881E6A001C' -allowProvisioningUpdates -skipPackagePluginValidation
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 6F726895-0F44-53B8-9291-C68C6C5B11A2 /Users/bing/Library/Developer/Xcode/DerivedData/AngelLive-gcijnxzpyclukqgalnuqneqbaqcp/Build/Products/Debug-iphoneos/AngelLive.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device process launch --device 6F726895-0F44-53B8-9291-C68C6C5B11A2 --terminate-existing --console com.anlonely.AngelLiveTest
```

结果：

- `git diff --check` 通过。
- Xcode 工具链直接运行 Core 测试通过：`30 tests passed`。
- iOS 26.1 真机 Debug 构建通过：`** BUILD SUCCEEDED **`。
- iOS 26.1 真机安装和 console 启动通过。

真机状态：

- Xcode 26.5 能识别已连接 iPhone 15 Pro，设备系统为 iOS 26.1，开发者模式已启用。
- 使用本地测试 bundle id `com.anlonely.AngelLiveTest` 和个人开发团队完成真机安装。
- 个人开发团队不支持 iCloud / Push，本地 Debug 包改用空 entitlement 验证；修复前启动在 `CKContainer(identifier:)` 崩溃，修复后可稳定进入 App。
- iPhone Mirroring 实时验证：欢迎页、收藏页、配置页、设置页可打开。
- 输入订阅密钥 `444222000` 后弹出订阅内容列表，并成功安装 14 个官方插件。
- 设备容器确认已安装插件包含 `chzzk`、`kick`、`soop`、`twitch`，订阅源持久化为 `https://ghfast.top/https://raw.githubusercontent.com/pcccccc/LiveParse/main/Dist/PluginRelease/plugins.json`。
- SOOP 首次进入分类时真机日志确认只拉取第 1、2、3 页房间列表，然后开始处理 19x 候选。
- SOOP 19x 实时封面真机日志确认写入稳定 Kingfisher key：`https://liveimg.sooplive.com/m/{roomId}?320`，未再出现 `_al_preview` 时间戳缓存 key。
- SOOP 播放控制真机复测：点击画面可弹出控制层，不再出现左键点击导致的持续闪烁和卡死。
- SOOP 19x 筛选代码通过 iOS 26.1 真机 Debug 构建、安装和启动；本轮 iPhone Mirroring 被手机前台使用中断，未做最终截图确认。

## 审查建议

- 重点审查 `RoomPlaybackResolver.preferredInitialSelection` 是否符合 CHZZK 插件实际返回的 `playArgs` 结构。
- 重点审查 `PlatformLoginCompatibility` 中 Twitch / Kick / SOOP 的 Cookie 名称和域名是否覆盖当前线上行为。
- 重点审查 SOOP 兜底预览地址 `https://liveimg.sooplive.com/m/{roomId}` 在目标地区和网络环境下是否可访问。
- 重点审查 iOS SOOP 19x 实时截图策略是否接受：只在内存缓存中替换稳定 `?320` key，App 重启后重新检测。
- 重点审查 iOS SOOP 19x 筛选的产品语义：未知状态在检测完成前不进入 19x / 非19x结果，避免误显示。
- 真机连接后建议验证 iOS 26.1 设备上的 WebKit 登录保存、播放器默认清晰度、SOOP 列表预览图和 SOOP 19x 播放控制四条主链路。
