# AngelLive Agent 指南

## 0. 执行顺序

1. 先运行 `git rev-parse --show-toplevel`、`git status --short`，记录既有修改，读取 `PRODUCT.md`。路径均相对仓库根目录，不写死用户名、机器路径、PID、UDID 或 DerivedData。
2. 识别任务类型，**修改或操作前读完第 7 节所有匹配文档/Skill**；跨领域任务须读取多份，不能只选一项。被触发的 `docs/agents/` 流程与本文件同等效力，红线常驻根文件；局部指南不得降低要求。
3. 分派子代理前，把相关约束原文、适用流程和必要上下文传过去，不假设子代理已继承。必读文档/Skill 缺失或不可读即为门禁阻塞，先获取/恢复，不能跳过；仍可继续不依赖它的工作。
4. 文档与实现冲突时核验当前代码、manifest、scheme 和测试并指出过期内容，不用旧说明掩盖实际失败。约束冲突或需更改规则时交回用户决定。

## 1. 红线

- **保护工作区**：保留他人未提交修改；未经任务明确授权及目标确认，不做破坏性 Git、依赖升级、锁文件/缓存/DerivedData/插件数据清理、证书修改。
- **ShellUI**：未明确点名时只改 FullUI，禁止修改 ShellUI；共享入口、组件或状态须在 FullUI 分支内隔离。影响不明先查调用链，不默认扩大授权。
- **平台中立**：源码、共享包、测试、fixture、注释、日志、文档及提交说明不含具体内容平台的品牌/项目名、域名、接口、专用 Cookie/字段/状态码或真实映射编号；差异仅由运行时插件及私有配置承载。交付前全仓扫描至无命中，并查测试 `liveType`/`siteId`，不能只扫 diff 或用编号规避。
- **凭证与数据**：插件凭证由既有 session/vault/登录服务管理，不写普通明文配置；其他密钥按既有钥匙串或专项受限配置管理。真实凭证、用户数据、插件私有包和设备容器不进入日志、测试快照、fixture、截图说明或提交，凭证不发送给测试模型；不复制私密设备容器。新设备经正常安装/登录/同步准备，Bugsnag 本地配置见环境流程。
- **视觉对齐**：优先复用各平台已有组件，逐项对齐实际行高、控件/图标尺寸、内外间距、文字基线、标题/副标题层级、字体颜色、分隔线、交互控件及跨区块对齐线；考虑图标光学偏差，不另加外层布局、独立说明行、特殊高度或无依据偏移。
- **视觉门槛**：三端分别对照同平台既有页面，使用自适应布局，不改变产品方向/窗口策略或固定屏幕尺寸迁就截图。最后编辑后新包的原尺寸截图和交互须由 root 逐项复核，编译/自动化通过不替代视觉通过；无证据或仍不对齐不得完成，不交由用户反复发现问题或留待以后美化。
- **布局模型**：至少 `gpt-6.1-sol / high`，也可由 `gpt-6-astra / high` 或更高推理强度直接实现，小改动不豁免。确认视觉破坏/样式不一致即由 `gpt-6-astra / high` 接管并实际重写，不能只给建议或交回原实现者自评；接管不因暂停、重启、压缩或恢复而重置。
- **模型可用性**：指定组合不可用就报告阻塞，不自动映射或降级；换模型须用户明确修改规则，不假称使用了指定模型。
- **Xcode**：默认使用本机已安装最高版本，逐个用完整路径的 `xcodebuild -version` 核验版本及 build；用户当次指定优先，历史固定版本不再适用。命令级 `DEVELOPER_DIR`、MCP、UI 和模拟器均用同一核验路径，不凭应用名/共享 bundle ID/旧会话启动旧版，未经要求不改全局 `xcode-select`；版本输出完整捕获，不管道给 `head`。
- **Device Hub**：iOS/tvOS 常规 UI 交互和回归必须使用 Device Hub，先读 `device-interaction`；由子代理独占 session，同一文件修改范围和设备 session 各有唯一负责人，设备操作权不等于布局修改权。
- **模拟器限制**：只使用已有且保留 Xcode 标准名称的模拟器；启动前核对系统版本、设备清单和 Booted 状态，优先复用目标版本的已运行设备。同时最多一台 iOS、一台 tvOS，换设备先结束旧 session、关闭同平台旧设备。使用明确 UDID，不用模糊 `booted`；不自行创建、克隆、重命名、清空或删除设备及其 App/插件/账号数据，用户指定型号不等于授权新建。用户正在操作的设备须先协调，结束后关闭本轮 session 并恢复改动过的运行目标。
- **设备停止与新包**：用户要求暂停/停止或表示已测试时立即停止设备及恢复操作。源码变化后旧包/旧截图失效；iOS/tvOS 以最后修改后的 `DeviceInteractionInstallAndRun` 成功为门禁，macOS 按原生运行流程核验实际产物。缺构建/安装/交互证据不得宣称完成，用户反馈不冒充本轮验证。
- **测试诚信**：不通过删除/禁用/过滤失败测试、放宽断言、吞退出码、`continue-on-error` 或无依据延长超时让 CI 变绿；需求变更须同步契约、说明依据并复核。
- **发布授权**：实际发布先查线上/本地版本，未指定时让用户选具体主/次/补丁版本，确认前不改版本或构建上传；已指定不重复询问。仅上传不等于分发/提审/上架，不覆盖同名已发布附件，结果不确定先查再决定重试；维护规则或查询版本不启动发布。
- **Skill**：所需 Apple 官方 Skill 缺失先从选定 Xcode 导出并读取，升级后核对同步；不虚构已安装/已读取。原生 UI 禁用 `impeccable`，除非用户明确重新启用。

## 2. 模型分工

| 角色 / 模型 | 职责与验收重点 |
| --- | --- |
| root（主代理角色） | 明确业务目标、约束、接口与验收标准，负责规划、拆分、架构决策、跨模块协调和最终验收；独立复核子代理的 diff 与证据。root 是角色，不等同于指定模型。 |
| `gpt-6-astra` | 处理极其复杂的 Bug、架构、抽象概念、接口语义及签名设计；负责 UI/UX 验收标准和视觉参考。新增内容出现视觉破坏或样式不一致时，必须使用 `high`，直接接管并重写相关布局。 |
| `gpt-6.1-sol` | 中等及较复杂功能实现、常规模块、跨文件修改与测试补齐、跨模块业务逻辑、复杂运维与 Bug 排查。页面布局实现至少使用本模型和 `high`，严格按已确认的视觉参考落地；架构或接口含义不清时交回 root/Astra。校验、兜底、重试和兼容分支必须有真实契约或故障证据支持。 |
| `gpt-6.1-terra`，推理强度 `high` | 独立测试设计、回归用例补齐、覆盖缺口分析和测试结果复核；依据业务契约与故障证据检查实现。可承担范围明确的测试及 CI 排查，不替代 sol 的页面布局实现或 Astra 的视觉问题接管，最终验收仍由 root 独立复核。 |
| `gpt-6-luna`，推理强度 `max` | 简单且边界清晰的非布局代码任务、日志监控、简单运维、任务状态与时间跟踪。不得承担页面布局实现或视觉整改；复杂异常交给 root/Astra 或 sol。 |

这些是项目分工约定，不是模型固有能力判断；root 是角色。默认 root/Astra 定义目标、架构与接口，GPT-6 子代理实现，Terra 按风险独立测试，root 复核；简单不可拆分的非布局任务不为使用代理硬拆。Astra 作为 root 可直接设计；可用性遵守红线，不增设模型替代兜底。分派、交接、Terra 文件权限与指南维护见 [协作流程](docs/agents/collaboration.md)。

## 3. 产品、架构与目录

AngelLive 是 iOS/macOS/tvOS 直播聚合应用，插件提供平台能力，宿主提供浏览、播放、弹幕、收藏、登录、同步和设置；遵循“原生、克制、沉浸”，内容、稳定和可预测行为优先，跨端能力一致但交互遵循平台习惯。先理解调用链和状态所有权，修复应优先落在正确的共享层，不能只让当前截图或单一平台看起来正常，不用 UI 补丁掩盖底层问题。

| 目录 | 职责 |
| --- | --- |
| `iOS/AngelLive/` | iPhone/iPad 宿主，SwiftUI 及 UIKit 列表/控制器桥接 |
| `macOS/AngelLiveMacOS/` | macOS 宿主、窗口和菜单 |
| `TV/AngelLiveTVOS/` | tvOS 宿主、焦点、遥控器、Top Shelf |
| `Shared/AngelLiveCore/` | 插件运行时/管理、能力、模型、缓存/状态/业务规则、播放恢复、弹幕、投屏模型、收藏、同步、首页数据、开发者控制台 |
| `Shared/AngelLiveDependencies/` | 播放器及第三方适配：KSPlayer/VLCKit、DLNA、Bugsnag 等 |
| `Shared/SharedAssets/` | 跨端颜色、图片和资源访问 |

依赖只允许宿主 → Dependencies/Core/Assets，Dependencies → Core；Core 不反向依赖宿主或 Dependencies。可复用协议/解析/缓存/状态机/业务放 Core，第三方播放器适配放 Dependencies，导航/窗口/焦点/UIKit/AppKit 桥接留宿主。默认 KSPlayer，只有明确要求时在首次解析前用 `USE_VLC=1` 切到 VLCKit，两者互斥。

播放故障先区分插件解析、播放地址、播放器 session、恢复状态机、前后台生命周期和 UI 控制层，不把所有失败归因于播放器。

## 4. 插件与状态约束

- JavaScriptCore 插件统一用 `LiveParsePlugins.shared`，不每次新建 `LiveParsePluginManager`；调用经过 manager/runtime，不绕过 HTTP/WebSocket/Crypto/Session/Native Stream bridge。
- `PlatformFeature`：`categories` 分类、`rooms` 列表、`playback` 播放地址、`search` 搜索、`roomDetail` 详情、`liveState` 状态、`shareResolve` 分享解析、`danmaku` 弹幕、`homeFeed` 首页。
- manifest 可声明元数据、认证/登录、分享匹配、原生流 provider、宿主行为、session 迁移、预加载脚本和最低宿主版本；修改协议/manifest 必须查受影响能力、安装升级、凭证、版本选择、缓存失效及三端入口，不能只测首页。
- 优先 manifest `capabilities`，旧插件才扫描入口函数；reload 同步失效能力缓存。保持 pinned、last-good、sandbox/built-in candidate 选择及回退语义，不为单个平台删版本或缓存。
- 安装、远程源、更新及登录插件保留用户同意和错误反馈；运行时插件、Cookie、Keychain、CloudKit、Application Support 不属于 Git 工作区，新环境须明确准备前置状态。
- 插件数组不以 UI 常量截断，只有协议/产品明确限制才裁剪；空值、缺字段、重复业务 ID、超量数据和部分能力均有确定行为。`homeFeed` 只是一个消费面，不把首页规则扩成整个插件协议。
- fixture 用 `fixture.plugin`、`source-a`、`source-b`、`login.example.invalid`、`anonymous_device` 等中性值，测试名只描述协议/状态/行为，不写具体平台风格；诊断只记 Cookie header 是否存在、请求结果、标准错误等协议状态，不硬编码平台字段探测或摘要。
- 外部输入校验、租户隔离、写入结果不确定时的处理和幂等恢复必须保留；增删防御逻辑须有真实代码、协议或故障证据，不虚构异常或扩展架构。

## 5. Swift 并发与生命周期

- Shared Package 使用 Swift tools 6.2，Xcode targets 使用 Swift 6 模式。新增 async、actor、回调或跨隔离域代码时必须遵循 Swift 6 并发检查。
- 不要用新的 `@unchecked Sendable`、锁或 `DispatchQueue` 逃避编译器，除非已经证明所有可变状态的隔离方式，并在代码旁说明不变量。
- JavaScriptCore 对象必须留在其串行运行队列；不要把 `JSContext`/`JSValue` 直接跨 actor 或线程传递。
- UI 状态由主 actor/可观察模型拥有；网络、插件和播放回调回到 UI 前要明确隔离边界。
- 列表、Banner、section 和房间模型的 identity 必须稳定并包含必要命名空间，避免跨插件 ID 冲突和 SwiftUI 错误复用。
- 修复切换、刷新、后台恢复或轮播问题时，同时检查 task 取消、timer 生命周期、旧请求回写和缓存 stale-while-revalidate 行为。

## 6. 验证矩阵

打开根 `AngelLive.xcworkspace`，按已提交锁文件解析。scheme：iOS `AngelLive`；macOS `AngelLiveMacOS`、`AngelLiveMacOS-AppStore`；tvOS `AngelLiveTVOS`、`AngelLiveTVOS-SimpleLive`。

| 改动 | 必须验证 |
| --- | --- |
| Core | 相关 `AngelLiveCoreTests`；公共 API/跨端行为改变再构建受影响宿主 |
| Dependencies | 相关 Package 测试及使用该依赖/内核的平台构建 |
| SharedAssets | 所有引用它的受影响平台构建及 bundle `.module` 访问 |
| 平台宿主 | 对应 scheme；UI 改动另做设备验收 |
| 插件 manifest/runtime/安装更新/session/capability | 相关 Core 测试及三端插件管理/消费入口 |
| 公共播放/收藏/同步/弹幕 | 按调用链覆盖受影响平台，不只验 iOS |
| 纯文档/注释且不影响运行 | 不启动 Xcode、构建或设备；检查差异、引用及规则一致性 |

Package 测试、宿主构建、UI/设备验收三层分别报告，不能相互替代或从 macOS Package 测试推断其他平台通过。低影响显示改动不为形式新增单测，但仍须视觉/设备验收；逻辑或状态回归优先用针对性用例重现。先最小检查，再按影响扩大，详细入口和前置条件见 [测试与 CI](docs/agents/ci.md)。

## 7. 强制读取路由

以下均为“遇到此任务，修改/操作前必须读取”，并应用所有匹配项；每次分派/交接还读协作流程。专项文档缺失不能跳过，迁移对照表仅供审核，不作为运行规则。

| 任务 | 必读文档 / Skill |
| --- | --- |
| 分派、交接、独立测试、监控运维、指南维护 | [collaboration.md](docs/agents/collaboration.md) |
| UI 布局/视觉审查/整改 | [ui-visual-gate.md](docs/agents/ui-visual-gate.md)、`axiom-design`，及下方对应 UI 框架 Skill |
| SwiftUI / UIKit 或桥接 / macOS UI、窗口、菜单 | SwiftUI 先 `axiom-design`、再 `axiom-swiftui`；UIKit/桥接用 `axiom-uikit`；macOS 用 `axiom-macos` |
| 构建、签名、环境准备、Xcode MCP/工具故障 | [xcode-mcp.md](docs/agents/xcode-mcp.md)；MCP 用 `axiom-xcode-mcp`，环境故障先 `axiom-build` |
| 模拟器/真机 UI、安装运行、设备取证/交接 | [device-hub.md](docs/agents/device-hub.md)、[xcode-mcp.md](docs/agents/xcode-mcp.md)、`device-interaction`；macOS 按设备文档的原生流程 |
| 测试设计/编写/运行、CI 排查 | [ci.md](docs/agents/ci.md)、`axiom-testing` |
| 版本查询、发布规则/技能维护、上传/发布 | [release.md](docs/agents/release.md) 和 `$angellive-release`；未发现技能则读个人技能目录的 `angellive-release/SKILL.md` |
| 缺 Apple 官方 Skill、新机器或 Xcode 升级 | [apple-skills-sync.md](docs/agents/apple-skills-sync.md) |
| 首页协议/布局 | `docs/PluginDrivenHomePagePlan.md` |
| 弹幕协议/渲染 | `docs/DanmakuMixedContentProtocol.md`、`docs/DanmakuRenderingRoadmap.md` |
| 播放恢复 | `docs/PlaybackResilienceRoadmap.md` 及相关后台冻结记录 |
| DLNA / 同步、凭证、CloudKit | `docs/iOSDLNACastingResearch.md` / `docs/SyncReliabilityRoadmap.md`；DLNA 运行 Dependencies 相关测试，同步验证合并、迁移、删除及离线/失败 |
| Swift async/actor/Sendable / 网络与插件 HTTP/WebSocket | `axiom-concurrency` / `axiom-networking` |
| 存储/缓存/序列化 / 播放/音频/Now Playing | `axiom-data` / `axiom-media` |
| 性能/卡顿/内存 / 无障碍 | 先领域 Skill，再 `axiom-performance` / `axiom-accessibility` |

使用 Skill 前读 `SKILL.md` 及必要引用并简短告知用户，清单以当前会话和选定 Xcode 为准；Axiom 缺失从 [官方指南](https://charleswiltgen.github.io/Axiom/) 查找。新增单个 UI 组件/流程先用 SwiftUX MCP，用户指定“UX MCP”也指它；按当前工具要求检索、读 conventions 和选定源码再定稿/分派，`weak_match` 按返回指南处理。既有页面审查/微调或非 UI 不强行检索，不用 Figma/Xcode MCP 替代 SwiftUX；所有结果仍须适配三端 HIG 和视觉门禁。

## 8. 交付与维护

- Git 提交用 `<type>(<scope>): <中文摘要>`（scope 可省），标准英文 type；摘要/正文中文，代码标识符和必要术语除外。正文至少两条列表准确说明实际修改及目的，不只写标题或笼统说明，不遗漏独立改动、不虚构或重复凑数。
- 用 `rg`/`rg --files` 定位、`apply_patch` 编辑；完成后检查实际 diff 和 `git diff --check`，只修复本轮引入的问题，区分并保留既有修改。
- 交付列改动、所属层/原因、实际 build/test/device 入口和结果、未验证平台及阻塞；测试列 target、数量及通过/失败/跳过/禁用/取消/未执行的原因，CI 附 SHA/job/证据。计划、旧版本、接入成功或用户反馈不算本轮验证。
- UI 完成须满足视觉、构建和设备门禁并由 root 复核，附实际模型/推理设置及 Astra 接管、视觉基准、状态清单和最终新包截图。未达门槛明确“未完成”，列已完成项、缺失证据、已尝试恢复、阻塞/恢复条件。
- 指南只依据真实证据维护，标明待验证判断并协调文件负责人；Astra 可主动维护且向 root 汇报，不扩大生产/发布/外部消息授权。流程维护规则见协作文档；移出内容必须保持根路由可达，不删门禁或制造循环引用。
