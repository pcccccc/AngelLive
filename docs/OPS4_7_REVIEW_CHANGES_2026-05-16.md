# SimpleLiveTVOS 修复变更说明（ops4.7 审查版）

日期：2026-05-16

## 本次重点

本 PR 主要修复三类线上可见问题：

- Twitch / Kick / SOOP 的 Cookie 登录与宿主登录入口兼容。
- CHZZK 默认进入低清晰度或 Auto 的问题。
- SOOP 登录后部分直播间，尤其 19x 直播间，预览图、播放控制和筛选体验异常。

真机回归过程中额外修复：

- Twitch 1.0.31 分类列表加载失败，报 `missing clientId or accessToken in token server response`。
- 个人开发签名不包含 iCloud entitlement 时 App 启动或同步入口崩溃。
- 官方订阅密钥 `444222000` 未稳定解析。

## 关键修复

### 1. 平台登录和 Cookie

- 新增宿主侧登录兼容层，旧 manifest 未声明 `loginFlow` 时，Twitch / Kick / SOOP 仍能进入账号管理和 Web 登录。
- iOS / macOS 登录面板统一使用 `PlatformCookieCollector` 收集、过滤、去重 Cookie。
- Web 登录页清理站点数据后再重新登录，避免旧 Cookie 干扰。
- iOS 登录 WebView 改为移动 Safari 风格 UA，避免 Twitch 提示“不支持您的浏览器”。
- iOS / macOS 都接管 `target=_blank` / `window.open`，SOOP 的 Apple / Google 登录按钮可以在当前 WebView 内跳转。
- manifest 显式声明 `auth.required=false` 时优先于宿主 fallback，避免以后插件作者显式开放匿名模式时被宿主覆盖。

### 2. Twitch 1.0.31 列表加载

- `twitch@1.0.31` 发布说明是 website GQL，但导出的 `getCategories` / `getRooms` 仍走 Helix token server。
- 当 token server 返回缺少 `clientId/accessToken` 时，平台页会直接加载失败。
- 新增 `LiveParsePluginCompatibilityPatch`，只对 `twitch@1.0.31` 注入兼容脚本。
- 兼容脚本复用插件内已有的 `_tw_fetchTopGames`、`_tw_fetchAllStreamsPage`、`_tw_fetchCategoryStreamsPage`，把分类和直播间列表切回 `https://gql.twitch.tv/gql`。
- 兼容 Twitch 分类 URL 的 slug，例如 `just-chatting` 会解析回游戏 ID `509658`，并按房间 `biz` 再做一次分类过滤。
- 补丁按精确版本命中，后续上游插件升级到 1.0.32 或其它版本时自动停止注入。

### 3. CHZZK 默认清晰度

- 新增 `RoomPlaybackResolver.preferredInitialSelection(in:)`。
- 默认播放不再盲选插件返回的第一项，而是按可播放性和清晰度评分选择初始项。
- 明确分辨率优先于 Auto / 自适应。
- Source / Best / 原画优先级最高，但空 URL 占位项不会抢默认播放。
- audio-only 音频轨不参与默认视频清晰度竞争。
- iOS / tvOS / macOS 三端接入同一选择逻辑，tvOS 展示标题也与 iOS / macOS 对齐。

### 4. SOOP 预览图和 19x

- 新增 `LiveImageURLResolver`，统一标准化封面和头像 URL。
- SOOP 空封面且 `roomId` 为数字时兜底到 `https://liveimg.sooplive.com/m/{roomId}?320`。
- SOOP 旧图床域名和 http 链接统一 canonicalize，减少 Kingfisher / ATS 加载失败。
- 19x 灰色年龄占位图通过封面 CDN 内容长度识别。
- 只有识别为 19x 占位图的房间才解析播放地址并截取首帧；非 19x 不做实时刷新。
- 19x 实时封面只写入 Kingfisher 内存缓存，key 保持稳定，不污染收藏、历史或 CloudKit 持久化字段。
- 首次进入 SOOP 会预取前三页并预热 19x 封面；向下滚动时继续预加载新出现的 19x 房间。
- 已检测或已加载过的房间不会因为下拉刷新、点击刷新或切换筛选重复拉流截图。
- iOS SOOP 分类页新增筛选：`全部 / 19x / 非19x`。

### 5. SOOP 19x 播放控制

- 移除 VLC drawable 上的 SwiftUI `onTapGesture`，避免 19x 流播放时点击事件和 VLCKit drawable 抢占。
- 控制层改用全屏透明 tap catcher：隐藏时点击显示，显示时点击空白处隐藏。
- VLC 同一 media fingerprint 下不再从 `.paused` 强行恢复播放，只处理 `.stopped` / `.error` 恢复。
- stop / media 释放移到后台队列，降低主线程卡顿和闪退风险。

### 6. 真机签名和订阅源

- 新增 `CloudKitContainerAccess`，访问命名 CloudKit 容器前先检查当前签名是否包含目标 iCloud 容器。
- 个人开发团队不支持 iCloud / Push 时，本地 Debug 包跳过 CloudKit 同步，不再在 `CKContainer(identifier:)` 崩溃。
- 收藏、书签、插件源同步、平台凭证同步都接入该 guard。
- `PluginSourceKeyService` 补齐官方 `keys.json` 地址，并内置 `444222000` 兜底映射。

## 主要文件

新增：

- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformLoginCompatibility.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformCookieCollector.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/LiveImageURLResolver.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/CloudKitContainerAccess.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/LiveParsePluginCompatibilityPatch.swift`

重点修改：

- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/JSRuntime.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/LiveParseLoadedPlugin.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/LiveParseJSPlatformManager.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/RoomPlaybackResolver.swift`
- `Shared/AngelLiveCore/Sources/AngelLiveCore/Services/PlatformLoginRegistry.swift`
- `iOS/AngelLive/AngelLive/FullUI/ViewModels/PlatformDetailViewModel.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/UIKit/ViewControllers/RoomListViewController.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/UIKit/ViewControllers/SubCategoryViewController.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Setting/PlatformLoginWebSheet.swift`
- `macOS/AngelLiveMacOS/Views/MacPlatformLoginWebSheet.swift`
- `macOS/AngelLiveMacOS/Views/PlatformDetailView.swift`
- 三端 `RoomInfoViewModel`

## 测试覆盖

新增或更新的 Core 测试覆盖：

- Twitch / Kick / SOOP 旧 manifest 登录 fallback。
- manifest 显式 `auth.required=false` 优先于宿主 fallback。
- Cookie 跨域过滤、登录信号识别和 session Cookie 去重优先级。
- 官方订阅密钥 `444222000` 兜底解析。
- SOOP 封面 URL 标准化和空封面兜底。
- CHZZK 类清晰度列表默认选择 1080p，跳过 Auto、空 URL 占位和 audio-only。
- `twitch@1.0.31` 兼容脚本只命中该版本，并可在宿主 JavaScriptCore 中执行。
- Twitch `just-chatting` slug 能解析到 `509658`，且只返回该分类房间。

## 兼容边界

- 登录兼容层只作为旧 manifest 兜底；插件 manifest 明确声明时优先使用插件声明。
- Twitch 列表补丁只作用于 `twitch@1.0.31`。
- SOOP 19x 实时封面只在 iOS 列表层启用。
- 非 19x SOOP 房间不做实时截图、不强制刷新封面。
- SOOP 19x 截图只进内存缓存，不写入收藏、历史、CloudKit。
- CHZZK 清晰度修复只改变初始默认项，不改变用户手动切换流程。
- 缺少 iCloud entitlement 时只跳过 CloudKit 同步，本地功能继续可用。

## 验证结果

已执行：

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Shared/AngelLiveCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer USE_VLC=1 xcodebuild build -workspace AngelLive.xcworkspace -scheme AngelLive -configuration Debug -destination 'platform=iOS,id=00008130-000204881E6A001C' -allowProvisioningUpdates -skipPackagePluginValidation -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 6F726895-0F44-53B8-9291-C68C6C5B11A2 /Users/bing/Library/Developer/Xcode/DerivedData/AngelLive-gcijnxzpyclukqgalnuqneqbaqcp/Build/Products/Debug-iphoneos/AngelLive.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device process launch --device 6F726895-0F44-53B8-9291-C68C6C5B11A2 --terminate-existing --console com.anlonely.AngelLiveTest
```

结果：

- Core 测试通过：`34 tests passed`。
- iOS 26.1 真机 Debug 构建、安装、启动通过。
- 个人开发签名无 iCloud entitlement 时可正常进入 App。
- 输入订阅密钥 `444222000` 后可安装官方插件。
- SOOP 19x 播放控制真机复测：点击画面可弹出控制层，不再持续闪烁或卡死。
- SOOP 19x 实时封面真机日志确认写入稳定 key：`https://liveimg.sooplive.com/m/{roomId}?320`。
- Twitch 1.0.31 真机日志确认 `getCategories` / `getRooms` 均请求 `https://gql.twitch.tv/gql`，HTTP 200，分类和直播间列表成功返回。

## 建议重点审查

- `LiveParsePluginCompatibilityPatch` 的 Twitch 版本边界是否足够保守。
- `RoomPlaybackResolver.preferredInitialSelection` 是否符合 CHZZK 当前插件返回结构。
- `PlatformCookieCollector` 的 Cookie 域匹配和 session Cookie 优先级。
- SOOP 19x 筛选中“未知状态不进入 19x / 非19x结果”的产品语义。
- SOOP 19x 实时封面只写内存缓存、不污染持久化字段的策略是否符合发布预期。
