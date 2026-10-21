# AngelLive 项目级 Agent 指南

本文件约束整个仓库，不针对某一台电脑、某一个页面或某一次修复。所有路径均以仓库根目录为基准；先执行 `git rev-parse --show-toplevel` 和 `git status --short`，确认根目录并记录既有修改，不要写死个人用户名、绝对路径、Xcode PID、模拟器 UDID 或 DerivedData 路径。

**视觉对齐（强制）：新增或修改页面布局必须对齐目标平台已有页面的实际行高、控件与图标尺寸、内外间距、文字基线、字体颜色及标题/副标题结构，优先复用原有组件，不得自行另做一套样式。页面布局至少使用 `gpt-6.1-sol / high`；出现视觉破坏或样式不一致，直接使用 `gpt-6-astra / high` 重写相关布局。以最后编辑后的新包截图逐项验收，编译通过不能代替视觉对齐。** 具体分工与验收门禁见下文 UI/UX 一节。

**视觉对齐是不可绕过的完成门槛，不因改动小、工期、工具故障或上下文切换而降低。代理必须主动发现并修复布局问题，未通过不得交付为完成，也不得留给用户反复指出问题或以后再美化。** 同时满足业务正确性、数据安全与无障碍要求；局部指南只能补充，不能降低此门槛。

## 0. 模型分工与子代理协作

以下是项目使用偏好与经验判断，可根据后续证据更新，不代表模型的固定能力边界。能由 GPT-6 系列完成的实现、排查、运维与监控，优先交给对应子代理；DeepSeek 一日试用期间，符合下述范围的任务优先按试用规则分派。root 保留整体判断和最终责任，Astra 集中处理关键设计与极其复杂的问题。简单、不可拆分且没有独立并行工作的任务直接完成，不为使用代理而拆分。

### 角色与模型选择

| 角色 / 模型 | 职责与验收重点 |
| --- | --- |
| root（主代理角色） | 明确业务目标、约束、接口与验收标准，负责规划、拆分、架构决策、跨模块协调和最终验收；独立复核子代理的 diff 与证据。root 是角色，不等同于指定模型。 |
| `gpt-6-astra` | 处理极其复杂的 Bug、架构、抽象概念、接口语义及签名设计；负责 UI/UX 验收标准和视觉参考。新增内容出现视觉破坏或样式不一致时，必须使用 `high`，直接接管并重写相关布局。 |
| `gpt-6.1-sol` | 中等及较复杂功能实现、常规模块、跨文件修改与测试补齐、跨模块业务逻辑、复杂运维与 Bug 排查。页面布局实现至少使用本模型和 `high`，严格按已确认的视觉参考落地；架构或接口含义不清时交回 root/Astra。校验、兜底、重试和兼容分支必须有真实契约或故障证据支持。 |
| `gpt-6-luna`，推理强度 `max` | 简单且边界清晰的非布局代码任务、日志监控、简单运维、任务状态与时间跟踪。不得承担页面布局实现或视觉整改；复杂异常交给 root/Astra 或 sol。 |
| DeepSeek Harness 外部子代理（一日试用） | 优先承接范围明确的只读定位、机械检查和指定日志初筛；实际模型与推理设置以运行时为准。root 每次独立验收、评分并向用户汇报，不预设其速度或质量优于现有子代理。 |

仅使用当前运行时实际可用的模型和推理强度。指定组合不可用时，说明实际限制和采用的可用替代，不能假称使用了指定模型。Astra 已作为 root 时，可直接承担设计职责，无需再启动同模型代理。

### 分派与交付

- 默认流程：root/Astra 定义问题、架构和接口 → GPT-6 子代理实现并验证 → root 独立验收；极其复杂或跨架构的问题再由 Astra 复核。
- 每项任务写清：目标与完成标准、负责文件或服务、依赖与禁止触碰范围、输入输出、已确认的函数或类型签名及语义、错误边界、验证方式。接口尚未确定时，先完成设计再分派依赖它的实现。
- 监控与运维任务另写清操作步骤、时间范围、检查频率、异常判定和停止条件；结果附时间与证据，异常按复杂度升级处理。
- 同一文件修改范围和同一设备 session 均指定唯一负责人，交接前原负责人停止操作。交接时说明最后修改、已运行检查、当前设备与 session、阻塞和剩余工作；接手方核验工具连接与设备状态，不复用失效标识或旧包证据。设备操作者负责运行、交互和取证，不因此取得布局代码修改权；发现问题交给对应代码负责人。设备操作仍遵守第 9 节。
- 实现遵守已确认的契约，不自行扩展架构或虚构异常场景。真实外部输入校验、租户隔离、写入结果不确定时的处理和幂等恢复保障仍须保留；增加或删除防御逻辑都应有代码、协议或故障证据。
- 子代理交付实际 diff、运行过的检查及结果、证据位置和未解决问题。root 不以“子代理说通过”代替代码审查和必要验收，不将构建通过等同于设备或视觉通过。

### DeepSeek 一日试用与逐次评分

- 试用规则及跨任务记录统一放在 [DeepSeekSubagentTrial.md](docs/DeepSeekSubagentTrial.md)。每次准备分派先读该文件；从首次真实派单起计时 24 小时，起止时间只登记一次。到期停止新增试用派单，在下一次活跃任务中汇总，不自动续期，不为凑样本制造任务。
- 先核验可调用的 CLI/ACP/MCP 入口及实际模型；`dsh` 在 PATH 中不等于子代理接入完成。入口未验证时如实报告，使用现有分工，不假称已调用 DeepSeek，也不把其他模型结果计入试用。
- 初期只分派只读检索、调用链定位、规则检查及指定日志初筛。稳定性有实际记录支持后，才由 root 按试用文档决定是否尝试已定方案的小范围非 UI 修改。架构、并发、播放恢复、插件协议、凭证、跨端状态和设备操作继续按原分工执行。
- 每次派单明确文件范围、禁止项、验收清单、输出上限及时间预算；显式传递相关项目规则与必要上下文，不假设外部 Harness 继承当前对话、Skills、工具或权限。不得通过外部代理扩大本任务权限。
- root 按正确性 40、完整性 20、证据 15、范围遵守 15、速度 10 的标准复核；质量门禁优先于总分。每次返回（含追问、失败、超时或取消）都记录并向用户汇报，未能核验的项目标记待核验或 N/A，不编造分数。
- 每次结果复核后立即在当前对话给出简短评分卡；最终回复汇总本轮各次结果。同步追加试用记录，保留首次结果与返工结果，禁止用修正后的成绩覆盖初次失败。记录由当次 root 单独负责，避免多个代理覆盖同一文件。

### UI/UX：模型下限与“视觉对齐”强制门禁

1. Astra 先依据 `PRODUCT.md`、目标平台 HIG 和现有界面，给出可执行的验收标准与视觉参考。明确页面和模式边界、信息层级、布局与间距、字体与颜色、交互及导航；按任务覆盖加载、空态、错误、深浅色、无障碍，以及 tvOS 焦点和遥控器行为。
2. 视觉参考使用明确的现有页面、截图、设计稿或带尺寸说明的布局示意，并标明来源及适用设备；不得仅用“更原生”“更精致”等主观描述代替。已有标准足够的小修改可以复用，不要求每次制作新设计稿。
3. 页面布局实现至少选择 `gpt-6.1-sol`、推理强度 `high`，也可由 `gpt-6-astra`（`high` 或更高）直接实现。将标准、参考、目标文件和接口一并交付；即使只是新增一行设置或小组件，也不得降为 Luna 或较低推理强度。指定组合不可用时说明限制，并选用满足本节下限的可用模型；不得降级到本节要求以下。
4. 新增内容出现视觉破坏、样式不一致，或用户指出与原页面不一致时，直接使用 `gpt-6-astra`、推理强度 `high` 接管并重写相关布局；不能继续交由原实现代理修补后自行宣称通过。代码审查、设备验收或用户反馈一旦确认问题即触发接管，不等最终交付；Astra 必须实际修改代码，不能只给建议。重写范围限定于受影响内容，保留其他已有修改及功能逻辑。交接记录视觉基准、失败证据和接管状态；暂停、工具重启、上下文压缩或恢复任务均不重置该状态，未通过前继续由 Astra 负责。
5. 视觉效果严格执行“视觉对齐”：以目标平台同页或同类的现有组件和截图为基准，优先直接复用其结构。逐项核对实际行高、控件及图标尺寸、内外边距、文字基线、标题/副标题层级、字体、颜色、分隔线和交互控件。不得另加外层布局、独立说明行或特殊高度来使新增内容偏离原有样式；标题或文案修改不能代替行高与布局修复。
   同时检查几何对齐与视觉对齐：跨区块保持一致的对齐线，文字按基线对齐，图标考虑字形、留白及描边造成的光学偏差；约束数值相等或容器居中不能代替实际截图验收，不堆叠无依据的偏移量掩盖布局问题。
6. 三端新增内容必须分别对照各自既有页面检查，保持业务含义一致并遵循各平台原有样式，不把三端强行做成同一套控件。实现后按第 7、9 节完成对应构建和设备验收，提供最后编辑后新包的截图及交互结果；root 对照参考逐项复核实际视觉尺寸，不以源码相似、编译通过或代理自评代替“视觉对齐”。未取得新包证据的项目明确标记未验证，不得宣称视觉通过。
   任一同类行高度不同、控件边缘或文字基线偏移、样式不一致，必须继续修复并重新验收，禁止作为已完成结果交付。工具阻塞时保留未完成状态并说明具体缺失证据，不把视觉检查转交给用户，也不要求用户替代理发现布局问题。
7. 影响信息架构、交互含义或公共接口的变更交回 root/Astra 决策。上述模型分工和视觉门禁不改变 FullUI/ShellUI 边界，也不替代 Skill 要求。
8. 实现前列出受影响页面及适用状态的验收清单，覆盖长文本、动态字体、深浅色、加载/空态/错误，以及产品支持的 iPhone/iPad 尺寸、横屏、分屏、macOS 窗口变化和 tvOS 焦点；不擅自改变产品的方向或窗口策略。逐项记录“通过／不通过／阻塞／不适用”及证据路径，不适用项注明依据。使用自适应布局，不以固定屏幕尺寸换取单张截图正确；按影响范围选择检查项，不无关扩展为所有设备的组合测试。
9. 工具冲突、超时、构建、安装或登录前置条件故障属于验证阻塞，本身不触发布局重写，也不代表视觉通过。先按第 8 节恢复工具并继续验收；确实无法恢复时保留未完成状态，记录缺失证据与恢复条件。已确认的视觉问题及 Astra 接管要求不因同时存在工具阻塞而撤销。

### 指南的持续维护

- Astra 无论作为 root 还是子代理，都可在任务中主动维护根目录及相关目录的 `AGENTS.md`，更新模型特点、分工、任务说明方法和实际踩坑记录，无需为指南维护单独请求确认。子代理修改后向 root 汇报，并与文件负责人协调，避免并发覆盖。
- 更新依据实际代码、故障或验收证据，说明适用场景、问题表现、原因和有效处理方式；待验证的判断明确标注，不把猜测或一次偶发现象写成永久禁令。
- 根文件仅保留可复用的简短结论；模块细则放局部 `AGENTS.md`，较长案例放 `docs/` 并链接。定期合并重复项、删除失效经验。
- 维护指南不扩大生产操作、发布或外部消息授权，也不得覆盖用户已明确的要求。

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
2. 使用用户指定的 Xcode 版本。2026-10-19 用户明确要求只使用 Xcode 27.1，不再启动 27.0；不得因旧文档或旧会话记录回退。Xcode 应用名称和安装位置可以不同；动态查找候选并用 `<XCODE_APP>/Contents/Developer/usr/bin/xcodebuild -version` 确认版本与 build number，不能仅凭应用名称判断。文档中的 Xcode 27.0 RC（27A266a）结果仅作为历史验证记录。
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

纯文档、注释且不影响构建或运行行为的修改，无需启动 Xcode、构建或设备验证。低影响显示调整无需为形式新增单元测试，但仍必须完成视觉对齐和设备验收；逻辑或状态回归应优先用能重现问题的针对性测试验证。

## 8. Xcode 27 MCP

任何 Xcode MCP 操作都先使用 `axiom-xcode-mcp` Skill，并读取对应 setup/tools/reference。

### 连接

1. Xcode 27 已启动且打开 `AngelLive.xcworkspace`。
2. Xcode Settings > Intelligence 中启用 Model Context Protocol 和 Xcode Tools。
3. 首次连接批准 Xcode 的 PID 级权限弹窗；MCP 客户端重启后 PID 改变，可能需要再次批准。
4. 优先使用客户端已注册的 Xcode MCP server。新电脑可按 Skill 的客户端配置方式注册 `xcrun mcpbridge`。
5. 多个 Xcode 同时运行时，动态取得目标 Xcode 27 的 PID，并为 bridge 设置 `MCP_XCODE_PID=<PID>`。同时设置 `DEVELOPER_DIR=<XCODE_APP>/Contents/Developer`，不要写死旧机器的 PID 或 Xcode Beta 小版本路径。
   多版本并存时，UI 工具也必须使用已核验版本的完整应用路径；不要用 `getApp("Xcode")` 或共享 bundle identifier 定位。`getApp` 会自动启动所匹配的应用，名称匹配可能拉起默认旧版本，bundle identifier 也不能区分多个安装。
6. Xcode 升级或更换应用路径后重新发现 toolchain、进程、workspace 和工具 schema；不要复用旧 Beta 的 PID、连接或工具参数。Skills 导出成功不等于 MCP workspace build 或设备验证通过。

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

若出现 Cocoa 4099/helper connection 不存在：确认 Xcode、workspace、MCP 开关和权限弹窗，激活目标 Xcode 后重连一次；仍失败按下述恢复流程处理，不在尚未尝试适用的恢复步骤时直接放弃验收。

原始 stdio bridge 在 sandbox 内出现 4099 时，还要检查 XPC 权限边界。2026-09-17 已验证：同一 Xcode 在默认 sandbox 内无法连接 helper，经正常权限审批在 sandbox 外运行 bridge 后可取得工具列表和 workspace；不要将这类隔离错误直接判为 Xcode 或 Device Hub 不可用，也不要绕过审批。
原始 JSON-RPC 响应先保存到临时文件，再向模型输出状态和证据路径摘要。已经返回但被输出截断或上下文压缩丢失的响应，不能靠继续轮询重放；先读已保存响应，或用只读状态查询恢复判断，避免重复安装及设备 session 因空等而过期。
必须按 JSON-RPC `response.id` 等待当前请求的最终 `result`/`error`；进度通知、其他请求的响应或缺省的 `isError=false` 都不能证明当前请求成功。2026-09-17 已观察到安装响应晚于提前发出的截图响应，先收到 `NotRun`、后收到安装成功；此时应修正请求等待顺序，不要据此反复重装。
Device Hub 的整组操作应复用同一个持续运行的 stdio bridge；不要用每调用一次工具就启动并终止 bridge 的短连接脚本。2026-09-17 的 iPad 验收中，此做法反复触发新 PID 授权，并伴随 `Automation Mode has been disabled` 和连接失效；这类工具生命周期问题应先修正，不能当作 App 启动失败。

### 工具冲突、超时与进程重启恢复

本流程适用于 Xcode MCP、bridge、JEV、Device Hub 和本轮测试 App。用户已授权在实际冲突、挂起或连接失效时关闭相关进程、重启并重试；满足以下范围的常规恢复无需重复询问。恢复由当前工具或设备唯一负责人执行，其他代理先停止对同一目标发请求。

1. **先确认状态**：保存失败响应、请求 ID、时间、日志位置及当次 workspace/设备/session。客户端等待超时不等于服务端操作终止；先读取已保存响应和只读状态，检查日志或进度是否仍在变化。正常构建或依赖解析仍有进度时继续等待，不因一次超时直接杀进程，也不并发重发 build、install 或交互请求。
2. **释放冲突并重连**：停止重复客户端或本轮遗留请求，优先取消当前操作、正常结束旧 session，再重连一次。session 无法正常结束时，先确认旧操作者和对应客户端已停止，记录失效状态，才创建新 session。权限或 sandbox/XPC 边界问题仍走正常审批，不通过重启或另起客户端绕过。
3. **关闭并重启故障进程**：重连无效且已确认进程挂起、失联或冲突时，动态核验进程的完整路径、PID、父子关系及归属，先正常退出，再对拒绝退出的精确 PID 发送 TERM；只有确认仍未退出且不会丢失未保存工作时才使用 KILL。退出后确认旧进程已结束，再启动一个新实例。优先重启本轮 bridge/JEV 等客户端或目标测试 App；证据指向 Xcode、Device Hub 或模拟器本身时，再重启对应应用或已有设备。禁止用宽泛的 `killall` / `pkill -f` 清理同名进程，禁止批量终止系统服务或其他任务进程。
4. **保护用户现场**：重启 Xcode 前保存本任务编辑，记录目标应用路径、workspace 和运行目标；若存在无法确认已保存的编辑、用户正在使用的窗口/设备，或会中断其他任务，则先协调该影响后再执行。常规恢复不删除 DerivedData、缓存、App、插件、账号或模拟器数据，不重启整台电脑，不创建替代模拟器。模拟器仍遵守第 9 节的单平台数量与设备选择约束。
5. **重新发现并验证**：启动已核验路径的工具并重新打开本 workspace，重新获取 PID、工具 schema、`XcodeListWindows`、tabIdentifier 和设备/session 状态，不能沿用重启前的连接标识。必要的系统权限弹窗如实交由用户批准。设备恢复后先观察截图和 hierarchy，按第 9 节新包门禁确认安装证据，再继续未完成的验收；安装结果不确定时先查证，不能盲目重复安装。工具恢复成功不等于构建、交互或视觉通过。
6. **限定重试并交付证据**：同一故障默认最多执行 2 轮适用的恢复流程，每轮重连和对应故障进程重启各最多一次；根因已明确为不支持的能力、缺失凭据或待批准权限时停止无效重试。记录每轮原因、关闭/重启对象、结果和证据；达到上限仍失败时报告具体阻塞、缺失验收及恢复条件，继续独立工作，不无限重启或降低视觉门槛。用户要求停止或表示已测试时立即停止恢复和设备操作。

## 9. JEV / Device Hub / 模拟器 / 真机验收

iOS 模拟器的常规 UI 交互与回归测试优先使用 JEV，先读 `.jev-ios/AGENT.md` 与 `.jev-ios/SKILL.md`；不必每次重新询问用户是否切换工具。JEV 尚未覆盖的操作或实际故障再使用 Device Hub，并说明原因。tvOS 继续使用 Device Hub；macOS 按下述原生应用流程验收，不推定 JEV 支持这两个平台。

使用 Device Hub 时先读 `device-interaction` Skill。该 Skill 要求主代理把 Device Hub session 委派给子代理，并确保一个 session 只有一个代理操作。JEV 同样保持单一设备负责人；切换工具前结束旧 session，不让两个工具同时控制同一设备。

JEV 沿用下述构建与新包门禁，不另建构建链路。最后编辑后已在同一设备成功安装的新包可以直接接管，无需仅为换工具重复构建安装。先观察当前截图与可访问性树，再编写小范围、有步骤及费用上限的场景；只能使用实际观察到的标签，不盲目重放结果未确认的操作。每次交互后核对结果状态，保留原始观察、截图及报告到被忽略的 `runs/`；语义断言通过不能代替视觉或后端验收。凭据不得写入场景、日志或提交文件，也不得发送给测试模型。未完成实际运行时，只能报告接入状态，不能声称测试通过或速度提升。

2026-09-29 本机 JEV／AXe 验证中，系统标签栏 `RadioButton` 可被观察但未生成点击目标；空 `SecureField` 被报告为 `TextField / secure=false`。遇到这类工具限制先核对原始观察与截图，必要时用确定性输入，不修改产品语义来迎合工具；真实凭据不得进入尚未验证脱敏的观察链路。Apple 翻译在 iOS 27.0 模拟器显示系统“不支持模拟设备”提示，真实译文须另用真机验收。证据及适用范围见 `docs/RoomTitleTranslation.md`。

2026-09-18 在 Xcode 27.0 RC（27A266a）实测：Device Interaction 仅支持 iOS/watchOS/tvOS 27 模拟器，`My Mac` 明确返回不支持。macOS UI 验收改用最后编辑后的 workspace MCP build、Xcode Run 和原生应用 UI 交互/截图，确认运行的是本次构建的应用路径；不得把已安装的同名旧应用或仅构建成功当作通过，也不得声称执行了 Mac `InstallAndRun`。同名应用有歧义时用当次 build log 中的完整产物路径定位。此限制以实际工具响应为准，后续 Xcode 版本须重新核验。

2026-09-20 在 Xcode 27.1 Beta（27A9269）的 iPhone Duo 实测：`InstallAndRun` 成功后，设备交互截图仍可能返回 `Target device has invalid screen scale`。展开时默认 `simctl io screenshot` 可能抓到已关闭的外屏而输出黑图；先用该设备的 `simctl io enumerate` 确认内外屏及当前形态，再显式指定当前显示屏截图，不写死 screen ID。形态切换以 Device Hub 的 Closed / Book / Open 控件为准，不能用旋转代替。原生窗口交互由 session 唯一负责人执行；截图需视觉复核，不以黑图推断 App 崩溃，也不以全桌面截图成功推断捕获了 Device Hub。

### 模拟器选择与启动约束

- 使用已经存在、保留 Xcode 标准名称的模拟器。用户指定设备时，选择对应的已有标准设备；不得自行创建、克隆或重命名模拟器，也不得创建带任务名、日期或测试标记的临时设备。用户指定设备不等于授权新建；没有对应可用设备时先说明情况。
- 启动前检查当前设备列表和 `Booted` 状态，优先复用已运行的对应平台标准模拟器。
- 同一时间最多运行一个 iOS 模拟器和一个 tvOS 模拟器；即使型号、名称或系统版本不同，也不得为测试同时启动同平台的第二台。
- 确需切换到另一台已有标准设备时，先结束当前 Device Hub session，并关闭同平台旧模拟器，再启动目标设备。涉及用户正在操作的设备时先协调，不能擅自打断。
- 验收结束后关闭本轮 session；若改变了 Xcode 的运行目标，恢复原有标准目标。不得为了测试清空或删除已有模拟器及其应用、插件、账号数据。

### 新包门禁

源码在上次安装后有变化时，当前可见 App 一律视为旧包，不能作为证据。必须执行：

1. `DeviceInteractionStartWorkspaceSession`，绑定当前 workspace 和明确的目标设备。
2. 必要时终止目标设备上旧的 App 进程。
3. 在最后一次代码修改之后调用 `DeviceInteractionInstallAndRun`，完成 build、install、launch。
4. 确认操作成功且 App 已重新启动，随后才能截图和判断。

禁止仅因为 Simulator 或 Device Hub 已显示 AngelLive 就声称“已测试”。禁止复用最后一次成功 `InstallAndRun` 之前的截图。iOS 与 tvOS 同时运行时，也必须使用明确 UDID，不能模糊使用 `booted`。

### Device Hub 交互证据

- 新启动后先用空 interaction 的 `DeviceEventSynthesize` 获取截图和 hierarchy；仍在启动/加载则再次捕获。
- 优先使用 hierarchy 的 `hitPoint`；只有 hitPoint 尝试失败并重新捕获后，才使用截图估算坐标。
- 每次点击、滑动、切换、旋转或状态变化后重新捕获并核对可见状态与 hierarchy。
- 原始 JSON-RPC 请求须按当次 `tools/list` 校验参数名。Xcode 27 RC 的 `DeviceInteractionSynthesize` 使用 `interactionCommand`；2026-09-17 已观察到误传未知字段会被静默忽略，仍返回新截图和 `Running`，因此这些响应不能单独证明触摸已执行。
- tvOS 按焦点导航：读取 hierarchy 的 `Focused` 标记，使用 Siri Remote 命令 `r up/down/left/right/select/menu/playpause/home`，不使用触屏坐标。方向键可根据 hierarchy 顺序合并成一次命令，之后捕获确认焦点；激活或返回后核对目标页面。先确认当前工具 schema 支持该命令。
- tvOS 返回问题必须区分工具的 Siri Remote Menu 与 Device Hub 原生键盘 Escape；tvOS 27 已观察到 Escape 绕过 `onExitCommand`。快速组合按键须用日志核对实际间隔，不能把链式命令当成零等待。本项目案例见 `docs/TVFocusAndRemoteNavigation.md`；原生键盘操作仍由当前设备 session 的唯一负责人执行。
- 视觉问题检查原尺寸截图，覆盖颜色、对齐、裁切、重叠、圆角、安全区和深浅色。
- 交互问题必须验证结果状态；“发出了点击”不等于通过。
- 完成后记录设备/OS、交互路径、观察结果和安装后的截图路径，并调用 `DeviceInteractionEndSession`。

有效通过报告必须说明最后编辑后完成了新的 `DeviceInteractionInstallAndRun`；JEV 接管时同时记录所复用的新包安装证据和本次 JEV 结果。构建或安装没有完成时只能写“未运行/被阻塞”，不能从源码、旧进程、旧 build 或旧截图推断成功。用户说已经测试或要求停止时，立即停止，不再启动 JEV 测试或 Device Hub。

## 10. Skill 路由

### 新电脑及 Xcode 升级后同步 Apple Skills

新电脑缺少 Apple 原生 Skills，或 Xcode 从 Beta 升级到 RC／正式版时，都应重新导出。先核验目标 Xcode 的版本和 build number，再查看该版本实际支持的参数：

```sh
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun agent skills export --help
```

先导出到新建临时目录并清点 `SKILL.md` 与引用文件，避免混入旧版本残留：

```sh
skills_export_dir=$(mktemp -d "${TMPDIR:-/tmp}/xcode-skills.XXXXXX")
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun agent skills export --output-dir "$skills_export_dir"
```

检查当前 Agent 的技能目录及软链接实际指向。更新前将本次导出中已有的同名目录备份到技能扫描目录之外；只更新导出的 Apple Skills，不覆盖 Axiom、自定义技能或其他插件。保留 Codex 等客户端已有软链接，更新其真实目标目录。确认目标目录后使用显式参数（RC 的帮助只列出 `--output-dir`，不依赖旧示例中的位置参数）：

```sh
DEVELOPER_DIR=<xcode-27-app>/Contents/Developer \
xcrun agent skills export --output-dir <confirmed-skills-directory> --replace-existing
```

导出后比较文件清单、正文及引用资源，并验证客户端软链接仍有效。导出器可能重排 YAML front matter 的字段顺序，比较元数据时按键值语义判断，不把字段重排当作正文更新。若命令失败，保留原技能与备份，不以退出前的部分输出宣称更新完成。

导出后重新启动或刷新 Agent 会话，并通过新会话的 Skill 列表确认所需 `SKILL.md` 已被发现；旧会话可能保留此前已读取的内容。不要假设 Xcode 的安装路径或 Skill 目录在新电脑上与旧电脑一致。遇到导出器无法连接／启动 Xcode，先排查所选版本、进程与执行权限，不删除隔离属性或修改应用签名来绕过系统检查。

2026-09-10 已核验 Xcode 27.0 RC（27A266a）可导出以下 10 项；后续版本以实际导出清单为准：`adopt-c-bounds-safety`、`app-intents-specialist`、`app-intents-whats-new-27`、`audit-xcode-security-settings`、`building-document-based-swiftui-applications`、`device-interaction`、`modernize-tests`、`swiftui-specialist`、`swiftui-whats-new-27`、`uikit-app-modernization`。本次 RC 的设备交互技能补充了 tvOS Siri Remote／焦点操作，安全设置技能增加了 Checked Pointer Arithmetic 指引；同步这些技能不自动授权修改项目安全设置。

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
- iOS 模拟器交互：`.jev-ios/AGENT.md` 与 `.jev-ios/SKILL.md`；Device Hub 交互：`device-interaction`

不要在本仓库使用 `impeccable` 前端设计 Skill，除非用户以后明确要求重新启用。使用 Skill 前按 Skill 规则完整读取必要文件，并在 Skill 导致行动或暂停时简短告知用户。

新增一个具体 UI 组件或交互流程时，默认先发现并调用已注册的 SwiftUX MCP，无需用户再次提醒；先读取 conventions，再检索目标组件／流程，匹配时读取组件及源码后才定稿和分派 UI 实现。用户指定「UX MCP」时同样优先使用 SwiftUX，不要把它替换成 Figma MCP 或仅调用 Xcode MCP。遵循 SwiftUX 的单一组件／流程检索范围，不对已有页面审计、样式微调或非 UI 工作强行检索；返回 weak_match 时按其指南和项目现有样式实现，不硬套无关组件。参考结构仍须按三端 HIG、真实服务状态和本项目验收要求落地。

JEV 的默认使用范围、设备接管、新包和证据要求见第 9 节；暂停请求优先于 Skill 中的场景执行要求。

## 11. 修改与交付纪律

- Git 提交必须遵循约定式提交（Conventional Commits）：标题采用 `<type>(<scope>): <中文摘要>` 格式（`scope` 可省略），保留 `feat`、`fix`、`docs` 等标准英文类型，摘要和正文必须使用中文（代码标识符及必要技术术语除外）。提交正文必须以列表逐条写清本次实际修改的内容及目的，至少两条，不得只写一条标题或一条笼统说明，不得遗漏独立改动，也不得为凑条数虚构或重复内容。
- 使用 `rg`/`rg --files` 定位代码；编辑现有文件使用 `apply_patch`。
- 不执行破坏性 git、缓存清理、证书修改、插件数据删除或依赖升级，除非任务明确要求并已确认目标。
- 不把真实 Cookie、Token、API key、用户数据、插件私有包或设备容器内容写入日志、测试 fixture、截图说明或仓库。
- 先运行最小相关测试，再按共享影响扩大范围。不要为了显得完整而宣称未执行的验证。
- 完成后检查实际 diff 和 `git diff --check`，区分既有修改与本轮修改；只修复本轮引入的问题，不覆盖用户或其他代理的工作。
- 最终交付说明：改了什么、为何在该层修改、实际运行了哪些 build/test/device 验证、哪些平台未验证、是否存在环境阻塞。
- UI 只有在任务范围内布局、交互及适用状态通过上述门禁、root 已独立复核后，才能交付为完成；附实际实现模型与可核验的推理设置、视觉基准、验收清单和最终新包截图路径。未通过或缺少证据时明确标记未完成，列出已完成部分、缺失证据、已尝试的恢复及恢复条件；不得遗留已知视觉缺陷并称为完成，不把用户反馈写成本轮设备验证结果。
