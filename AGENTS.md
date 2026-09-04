# AngelLive 项目级 Agent 指南

本文件约束整个仓库，不针对某一台电脑、某一个页面或某一次修复。所有路径均以仓库根目录为基准；先执行 `git rev-parse --show-toplevel` 确认根目录，不要写死个人用户名、绝对路径、Xcode PID、模拟器 UDID 或 DerivedData 路径。

## 1. 产品与工程原则

- AngelLive 是 iOS、macOS、tvOS 多端直播聚合应用，插件提供平台能力，宿主提供一致的浏览、播放、弹幕、收藏、登录、同步和设置体验。
- 产品取向是“原生、克制、沉浸”：内容优先、稳定优先、行为可预测、跨端能力一致但交互遵循各平台习惯。
- 修复应优先落在正确的共享层，不能只让当前截图或单一平台看起来正常。
- 保留用户及其他代理的未提交修改；脏工作树不是覆盖、回滚或重写文件的理由。
- 先理解调用链和状态所有权，再修改。不要用 UI 补丁掩盖插件协议、缓存、并发或播放状态问题。

开始工作前阅读根目录 `PRODUCT.md`；再按任务读取 `docs/` 下的对应设计、协议或问题记录。文档与实现冲突时，以当前代码、Package manifest、Xcode scheme 和测试为准，并指出过期文档。

## 2. 仓库结构与职责边界

### 平台宿主

- `iOS/AngelLive/`：iPhone/iPad 宿主；SwiftUI 为主，同时包含 UIKit 列表与控制器桥接。
- `macOS/AngelLiveMacOS/`：macOS 宿主、窗口和菜单行为。
- `TV/AngelLiveTVOS/`：tvOS 宿主、焦点系统、遥控器交互和 Top Shelf 扩展。

### 共享 Package

- `Shared/AngelLiveCore/`：跨端领域核心。包含插件运行时与管理、平台能力、模型、播放恢复、弹幕、投屏模型、收藏、同步、首页数据和开发者控制台。
- `Shared/AngelLiveDependencies/`：播放器和第三方依赖适配层，依赖 `AngelLiveCore`；包含 KSPlayer/VLCKit 选择、DLNA、Bugsnag 等。
- `Shared/SharedAssets/`：跨端颜色、图片和资源访问器。

依赖方向必须保持：平台宿主 → `AngelLiveDependencies` / `AngelLiveCore` / `SharedAssets`，`AngelLiveDependencies` → `AngelLiveCore`。不要让 `AngelLiveCore` 反向依赖平台宿主或 `AngelLiveDependencies`。

可跨端复用的协议、解析、缓存、状态机和业务规则放入 `AngelLiveCore`；播放器第三方库适配放入 `AngelLiveDependencies`；平台导航、窗口、焦点、UIKit/AppKit 桥接留在各自宿主。

### ShellUI 修改边界

- 用户未明确指定 `ShellUI` 时，所有改动默认仅作用于 `FullUI`，禁止修改 `ShellUI` 目录下的代码。
- 共享入口、共享组件或共享状态的改动如果会间接影响 `ShellUI`，必须在 `FullUI` 分支内隔离；不得以跨模式一致为由自动扩大修改范围。
- 只有用户明确点名 `ShellUI` 时，才能修改或调整 `ShellUI` 行为；如无法确定共享修改是否会影响 `ShellUI`，先检查调用链并进行隔离，不能默认授权。

## 3. 插件系统是核心架构，不等同于首页

插件通过 JavaScriptCore 运行，统一入口为 `LiveParsePlugins.shared`。不要在每次调用时新建 `LiveParsePluginManager`，否则会丢失已加载插件和 JSContext 缓存。

当前平台能力定义在 `PlatformFeature`，包括：

- `categories`：分类列表
- `rooms`：房间列表
- `playback`：播放地址
- `search`：搜索
- `roomDetail`：房间/主播详情
- `liveState`：直播状态
- `shareResolve`：分享文本或链接解析
- `danmaku`：弹幕
- `homeFeed`：首页内容

插件 manifest 还可以声明平台元数据、认证、登录流程、分享匹配、原生流 provider、宿主行为、session 迁移、预加载脚本及最低宿主版本。修改 manifest 或插件调用协议时，不能只验证首页；必须检查受影响能力、安装/升级、登录凭证、版本选择、缓存失效和三端入口。

关键约束：

- 优先使用 manifest 的 `capabilities`；旧插件才回退到入口函数扫描。插件 reload 后必须同步失效能力缓存。
- 插件函数调用统一经过 manager/runtime，不要绕过宿主提供的 HTTP、WebSocket、Crypto、Session 或 Native Stream bridge。
- 凭证通过平台 session/vault 和既有登录服务管理；不得写入日志、测试快照、仓库文件或普通明文配置。
- 保持 pinned version、last-good version、sandbox/built-in candidate 的选择和回退语义；不要为了修单个平台直接删除版本或缓存。
- 安装、远程源、更新和需要登录的插件必须保留用户同意与错误反馈流程。
- 运行时安装的插件、Cookie、Keychain、CloudKit 和 Application Support 数据不属于 Git 工作区。换电脑或新模拟器时不能假设这些状态存在，测试应显式准备前置条件。
- 插件返回的数组不可擅自用 UI 常量截断；只有协议或产品规则明确限制时才能裁剪。空值、缺字段、重复业务 ID、超量数据和部分能力插件都要有确定行为。

首页只是 `homeFeed` 的一个宿主消费面。首页协议和布局任务再读取 `docs/PluginDrivenHomePagePlan.md`，不要把首页的展示规则扩散成整个插件协议的默认规则。

### 平台中立性（强制门禁）

- 宿主源码、共享 Package、测试、fixture、注释、日志结构和 `docs/` 文档必须保持具体内容平台中立；具体平台差异只能由运行时插件及其私有配置承载。
- 禁止写入或引用任何具体内容平台的品牌名、项目名、域名、接口路径、专用 Cookie 名、专用响应字段、专用状态码或真实平台映射编号。不得用真实编号代替名称来规避这条约束。
- 测试数据统一使用中性占位，例如 `fixture.plugin`、`source-a`、`source-b`、`login.example.invalid`、`anonymous_device`；测试名称只描述协议、状态和行为，不写“某平台风格”或引用具体第三方实现。
- 通用诊断只能记录协议级状态，例如 Cookie header 是否存在、请求是否成功、标准化错误类型；不得为单个平台硬编码字段探测、日志摘要或特殊分支。
- 交付前必须对**整个仓库**执行具体平台标识扫描，并检查测试中的 `liveType` / `siteId` 是否偷用了真实映射值；禁止只扫描本次 diff、单个目录或新增文件后声称“没有平台名”。发现命中必须继续清理并重新扫描，直到全仓无命中。

## 4. Swift、并发与状态管理

- Shared Package 使用 Swift tools 6.2，Xcode targets 使用 Swift 6 模式。新增 async、actor、回调或跨隔离域代码时必须遵循 Swift 6 并发检查。
- 不要用新的 `@unchecked Sendable`、锁或 `DispatchQueue` 逃避编译器，除非已经证明所有可变状态的隔离方式，并在代码旁说明不变量。
- JavaScriptCore 对象必须留在其串行运行队列；不要把 `JSContext`/`JSValue` 直接跨 actor 或线程传递。
- UI 状态由主 actor/可观察模型拥有；网络、插件和播放回调回到 UI 前要明确隔离边界。
- 列表、Banner、section 和房间模型的 identity 必须稳定并包含必要命名空间，避免跨插件 ID 冲突和 SwiftUI 错误复用。
- 修复切换、刷新、后台恢复或轮播问题时，同时检查 task 取消、timer 生命周期、旧请求回写和缓存 stale-while-revalidate 行为。

## 5. 播放、弹幕、投屏与同步

- 默认播放器内核是 KSPlayer。仅在明确要求时通过 `USE_VLC=1` 解析为 VLCKit；两者不能同时引入，否则内嵌 FFmpeg 符号会冲突。
- 播放问题先区分插件解析、播放地址、播放器 session、恢复状态机、前后台生命周期和 UI 控制层，不能把所有失败归因于播放器。
- 弹幕协议/渲染修改先读 `docs/DanmakuMixedContentProtocol.md` 与 `docs/DanmakuRenderingRoadmap.md`。
- 播放恢复修改先读 `docs/PlaybackResilienceRoadmap.md` 和相关后台冻结记录。
- DLNA 修改先读 `docs/iOSDLNACastingResearch.md`，并运行 `AngelLiveDependencies` 中相关测试。
- 同步、凭证或 CloudKit 修改先读 `docs/SyncReliabilityRoadmap.md`，验证合并、迁移、删除和离线/失败路径。

## 6. 新电脑或全新环境启动

1. 克隆仓库并进入根目录。
2. 安装项目要求的 Xcode 27 版本。Xcode 应用名称和安装位置可以不同；动态查找候选并用 `<XCODE_APP>/Contents/Developer/usr/bin/xcodebuild -version` 确认主版本为 27。
3. 为当前命令设置 `DEVELOPER_DIR=<XCODE_APP>/Contents/Developer`；不要永久修改用户的全局 `xcode-select`，除非用户明确要求。
4. 打开根目录 `AngelLive.xcworkspace`，不要只打开某个 `.xcodeproj`。workspace 同时包含三个宿主工程和三个本地 Package。
5. 让 Xcode 从已提交的 `Package.resolved` 解析依赖。不要随意删除 resolved 文件、Package cache 或 DerivedData；依赖变更必须是任务本身的一部分。
6. 默认使用 KSPlayer。只有需要 VLC 变体时，才在首次解析相关 Package 前设置 `USE_VLC=1`。
7. Bugsnag 真正的 API key 使用 gitignored 的 `Shared/AngelLiveDependencies/Sources/Resources/BugsnagSecrets.local.plist`；仓库中的占位配置允许无密钥构建。不要提交本地密钥。
8. 模拟器构建不应要求更换签名。真机运行需要本机证书与 provisioning；不要为了通过构建擅自修改 development team、bundle identifier 或 entitlements。
9. 全新设备没有已安装插件和账号状态。需要这些数据的手工测试，应通过应用支持的安装/登录/同步流程准备，不能复制或提交其他机器的私密容器数据。

## 7. Scheme、构建与测试范围

主要 workspace：`AngelLive.xcworkspace`。

共享 scheme：

- iOS：`AngelLive`
- macOS：`AngelLiveMacOS`、`AngelLiveMacOS-AppStore`
- tvOS：`AngelLiveTVOS`、`AngelLiveTVOS-SimpleLive`

验证范围按改动决定：

- 只改 `AngelLiveCore`：运行相关 `AngelLiveCoreTests`；若公共 API 或跨端行为变化，再构建所有受影响宿主。
- 改 `AngelLiveDependencies`：运行对应 Package 测试，并构建使用该依赖/播放器内核的平台。
- 改 `SharedAssets`：至少构建所有引用该资源的受影响平台，并检查 bundle `.module` 访问。
- 改某个平台宿主：构建对应 scheme；UI 改动还要在对应设备上验证。
- 改插件 manifest、runtime、安装/更新、session 或 capability：运行相关 Core 测试，并检查 iOS、macOS、tvOS 的插件管理/消费入口。
- 改公共播放、收藏、同步或弹幕逻辑：不能只以 iOS 编译通过作为跨端通过。

Package 级测试入口：

```sh
swift test --package-path Shared/AngelLiveCore
swift test --package-path Shared/AngelLiveDependencies
```

通过 Xcode MCP 测试时，先 `GetTestList`，迭代阶段使用 `RunSomeTests`，最终再按风险运行 `RunAllTests`。只报告实际运行过的 targets、测试数量和结果；未运行的平台明确写“未验证”。

## 8. Xcode 27 MCP

任何 Xcode MCP 操作都先使用 `axiom-xcode-mcp` Skill，并读取对应 setup/tools/reference。

### 连接

1. Xcode 27 已启动且打开 `AngelLive.xcworkspace`。
2. Xcode Settings > Intelligence 中启用 Model Context Protocol 和 Xcode Tools。
3. 首次连接批准 Xcode 的 PID 级权限弹窗；MCP 客户端重启后 PID 改变，可能需要再次批准。
4. 优先使用客户端已注册的 Xcode MCP server。新电脑可按 Skill 的客户端配置方式注册 `xcrun mcpbridge`。
5. 多个 Xcode 同时运行时，动态取得目标 Xcode 27 的 PID，并为 bridge 设置 `MCP_XCODE_PID=<PID>`。同时设置 `DEVELOPER_DIR=<XCODE_APP>/Contents/Developer`，不要写死旧机器的 PID 或 Xcode Beta 小版本路径。

原始 stdio 方式仅作回退：

```sh
MCP_XCODE_PID=<xcode-27-pid> \
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun mcpbridge
```

若直接处理 JSON-RPC，使用 MCP 协议 `2025-06-18` 完成 `initialize`，发送 `notifications/initialized` 后再调用工具。

### 强制工作流

1. 每次连接先调用 `XcodeListWindows`。
2. 按返回的 `workspacePath` 选择当前仓库的 workspace，并保存当次有效的 `tabIdentifier`。
3. 修改后调用 `BuildProject`。
4. 失败时使用 `GetBuildLog` 和 `XcodeListNavigatorIssues`，以 Issue Navigator 的结构化诊断为准。
5. 修复后重新 build；旧 build 不能证明新代码。
6. 成功后再次检查 error severity 的 navigator issues。

不要默默用独立 `xcodebuild` 结果冒充 MCP workspace build。本仓库有本地 Package，单独工程或不同解析上下文可能出现缺失 product/依赖图差异。

若出现 Cocoa 4099/helper connection 不存在：确认 Xcode、workspace、MCP 开关和权限弹窗，激活 Xcode 后重连一次；仍失败就如实报告 MCP 未验证。未经用户同意不要重启 Xcode 或打断其现有窗口。

## 9. Device Hub / 模拟器 / 真机验收

任何设备 UI 验证使用 `device-interaction` Skill。该 Skill 要求主代理把 Device Hub session 委派给子代理，并确保一个 session 只有一个代理操作。

### 新包门禁

源码在上次安装后有变化时，当前可见 App 一律视为旧包，不能作为证据。必须执行：

1. `DeviceInteractionStartWorkspaceSession`，绑定当前 workspace 和明确的目标设备。
2. 必要时终止目标设备上旧的 App 进程。
3. 在最后一次代码修改之后调用 `DeviceInteractionInstallAndRun`，完成 build、install、launch。
4. 确认操作成功且 App 已重新启动，随后才能截图和判断。

禁止仅因为 Simulator 或 Device Hub 已显示 AngelLive 就声称“已测试”。禁止复用最后一次成功 `InstallAndRun` 之前的截图。多个模拟器运行时必须使用明确 UDID，不能模糊使用 `booted`。

### 交互证据

- 新启动后先用空 interaction 的 `DeviceEventSynthesize` 获取截图和 hierarchy；仍在启动/加载则再次捕获。
- 优先使用 hierarchy 的 `hitPoint`；只有 hitPoint 尝试失败并重新捕获后，才使用截图估算坐标。
- 每次点击、滑动、切换、旋转或状态变化后重新捕获并核对可见状态与 hierarchy。
- 视觉问题检查原尺寸截图，覆盖颜色、对齐、裁切、重叠、圆角、安全区和深浅色。
- 交互问题必须验证结果状态；“发出了点击”不等于通过。
- 完成后记录设备/OS、交互路径、观察结果和安装后的截图路径，并调用 `DeviceInteractionEndSession`。

有效通过报告必须说明最后编辑后完成了新的 `DeviceInteractionInstallAndRun`。构建或安装没有完成时只能写“未运行/被阻塞”，不能从源码、旧进程、旧 build 或旧截图推断成功。用户说已经测试或要求停止时，立即停止，不再启动 Device Hub。

## 10. Skill 路由

### 新电脑上恢复 Skill

如果第三方 Agent 环境（如 Codex、Claude Code 或 Cursor）找不到 Xcode 27 内置的 Apple 原生 Agent Skills，使用当前选定的 Xcode 27 toolchain 导出：

```sh
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun agent skills export --output-dir ~/Downloads/xcode-skills
```

上述命令适合先导出到临时目录检查内容。确认目标 Agent 使用 `~/.agents/skills` 且不会覆盖需要保留的同名 Skill 后，也可直接导出：

```sh
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun agent skills export ~/.agents/skills
```

导出后重新启动或刷新 Agent 会话，并通过当前环境的 Skill 列表确认所需 `SKILL.md` 已被发现。不要假设 Xcode 的安装路径或 Skill 目录在新电脑上与旧电脑一致。

如果任务需要 Axiom Skill，但当前的 Skill 列表和已导出的 Xcode Skills 中都找不到，从 [Axiom](https://charleswiltgen.github.io/Axiom/) 查找对应 Skill 的安装与使用方法。不要伪造未安装的 Skill 名称或假装已经读取其 `SKILL.md`。

- Xcode MCP：`axiom-xcode-mcp`
- Xcode/依赖/模拟器环境故障：先 `axiom-build`
- SwiftUI：先 `axiom-design` 决定语义与 HIG，再 `axiom-swiftui` 实现
- UIKit 或 SwiftUI/UIKit 桥接：`axiom-uikit`
- macOS UI/窗口/菜单：`axiom-macos`
- Swift 6 async/actor/Sendable：`axiom-concurrency`
- 网络和插件 HTTP/WebSocket：`axiom-networking`
- 持久化、缓存、CloudKit、序列化：`axiom-data`
- 播放、音频、Now Playing：`axiom-media`
- 性能/卡顿/内存：先领域 Skill，再 `axiom-performance`
- 无障碍/对比度/触控目标：`axiom-accessibility`
- 单元测试/UI 测试：`axiom-testing`
- 设备交互：`device-interaction`

不要在本仓库使用 `impeccable` 前端设计 Skill，除非用户以后明确要求重新启用。使用 Skill 前按 Skill 规则完整读取必要文件，并在 Skill 导致行动或暂停时简短告知用户。

## 11. 修改与交付纪律

- 使用 `rg`/`rg --files` 定位代码；编辑现有文件使用 `apply_patch`。
- 不执行破坏性 git、缓存清理、证书修改、插件数据删除或依赖升级，除非任务明确要求并已确认目标。
- 不把真实 Cookie、Token、API key、用户数据、插件私有包或设备容器内容写入日志、测试 fixture、截图说明或仓库。
- 先运行最小相关测试，再按共享影响扩大范围。不要为了显得完整而宣称未执行的验证。
- 最终交付说明：改了什么、为何在该层修改、实际运行了哪些 build/test/device 验证、哪些平台未验证、是否存在环境阻塞。
