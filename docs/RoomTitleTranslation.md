# 房间标题翻译

## 产品范围

第一期为 FullUI 的房间标题自动翻译，支持 Apple 原生翻译与用户自行配置的大模型接口。实时语音字幕正在按独立的 [Apple 原生方案](LiveSpeechSubtitles.md) 实现；第一版先验证播放器音频提取和原文语音转写，尚未完成真实字幕验收，下方标题翻译记录不能作为语音字幕已实现的证据。

后续增加了独立的[弹幕翻译](DanmakuTranslation.md)，复用本页的引擎、目标语言与接口配置；下方既有验收记录只对应标题翻译阶段。

默认关闭。按标题内容识别语言，自动翻译只处理英语、日语和韩语；其他语言保留原文，两个引擎使用相同的范围。不维护具体内容平台名单。原始标题继续用于模型、收藏同步、搜索匹配、分享与系统媒体信息；译文仅作为应用内展示值。

## 设置与界面

在现有设置中增加“翻译与字幕”入口。设置页复用各端现有通用设置样式：iOS 分组列表，macOS 分组表单与现有设置弹窗，tvOS 半屏设置及遥控器焦点导航。保持原有房间卡片尺寸、标题字体、行数与点击行为。

设置包含：

- 自动翻译房间标题。
- 目标语言。
- 翻译引擎：Apple 原生／大模型。
- Apple 原生固定语言包列表：英语、日语、韩语到当前目标语言，排除同语言项；显示实际安装状态，未下载时提供下载按钮。
- 大模型服务地址、模型、API Key、保存配置、删除密钥及测试翻译。

大模型服务由用户提供，兼容 Chat Completions 请求格式。基础地址包含服务要求的版本路径，例如 `https://api.example.invalid/v1`，客户端追加 `chat/completions`。界面说明标题会发送至所配置的服务，并可能产生服务费用。

语言包名称使用与设置页一致的中文，例如“英语 → 中文简体”，不随设备的系统语言变为英语。点击下载后，由当前设置页的 `translationTask` 直接调用 `TranslationSession.prepareTranslation()`，让系统弹层处理确认、资源下载与真实进度。宿主行只显示等待提示，完成后检查资源状态并显示“已下载”。公开接口没有给宿主提供字节数或百分比回调，页面提示“下载进度请查看系统弹窗”。下载任务不进入标题／弹幕的全局翻译队列，也不依赖插件是否已经安装。

译文准备期间及失败时继续显示原文，不等待翻译后才加载列表或播放。关闭开关立即恢复原文。播放器详情提供原始标题，辅助功能标签与可见标题保持一致。

## 平台能力

本机 Xcode 27.0 RC 与 27.1 Beta SDK 均将 `TranslationSession` 标记为 iOS 18／macOS 15 起可用、tvOS 不可用。因此原生引擎按编译平台和运行系统判断；tvOS 仅提供大模型引擎。原生语言资源由系统授权与管理，不在原生失败时自动改用付费服务。

## 工程边界

- 共享翻译配置、语言判断、缓存、请求调度、错误映射及服务适配放在 `AngelLiveCore/Translation`。
- 平台宿主只负责设置入口与标题展示接入。原生 SwiftUI 会话通过 FullUI host 绑定生命周期；ShellUI 不挂载有效翻译服务。
- 缓存身份包含原文、语言对、引擎及模型／端点配置；不包含密钥。缓存有界，相同请求去重。
- 关闭、换引擎、修改配置、离开界面和后台切换都需处理任务取消，旧请求不可覆盖当前展示。多个消费者或窗口不能相互误取消。
- 普通配置只存本设备偏好；API Key 使用独立 Keychain 记录，不进入插件登录、普通偏好、日志或同步数据。
- 更换服务地址要求重新提供密钥，避免把原服务凭证送到新服务。请求仅使用 HTTPS，专用会话不共享插件 Cookie，并拒绝重定向。
- HTTP 错误、无效响应和空译文映射为可理解的安全错误，不直接显示远端原始响应。

## 验收

核心验证覆盖设置默认值、语言跳过、请求合并、缓存配置隔离、取消和旧结果保护、响应解析及凭证端点边界。使用合成文本和 mock，不使用实际账号或直播平台数据。

三端宿主分别构建；iOS／tvOS 必须在最后编辑后重新 build/install/launch，再验证设置、引擎切换、错误状态、返回与标题展示。macOS 用实际 workspace 构建产物运行验证。真实服务翻译、原生语言资源下载及具体设备结果以本轮实际验收记录为准。

2026-09-29：使用 Xcode 27.0 RC（27A266a）工具链运行 `swift test --package-path Shared/AngelLiveCore --filter RoomTitleTranslation`，相关 1 个 suite、14 项测试全部通过。测试包含默认关闭、凭证端点绑定、自定义服务路径、请求 JSON、401／429 安全错误、语言跳过、并发去重、缓存隔离、取消及旧结果保护，以及原生请求切换 host 后旧执行结果失效。测试使用内存凭证存储与 URLProtocol 模拟服务，不能代替真实 Keychain／服务联调或 Apple 语言资源验证。

三端 workspace 诊断构建通过。iOS 在最后修改后通过 Device Hub 安装运行成功，本轮复用该新包。2026-09-29 19:55–20:00 +0800 使用 Xcode 27.1（27A9269）及新的 MCP 连接补跑最终源码：`AngelLiveMacOS / My Mac` 构建成功（19.425 秒），`AngelLiveTVOS / Any tvOS Device (arm64)` 构建成功（15.718 秒），各自随后查询 Issue Navigator 均为 0 个 error。完整响应和日志保存于临时目录 `/tmp/angellive-translation-mcp.kTcsPl/`；结束后恢复原 `AngelLive / iPhone 17 (27.0)` 目标并关闭 bridge。此两项为构建验收，未启动 macOS 应用或 tvOS 模拟器。

设备验收曾按用户要求暂停，随后于同日恢复并优先使用 JEV。Duo 的 Device Hub 输入未作用到活动屏，因此复用已有 iPhone 17（iOS 27.0）及最后编辑后安装的新包。通过应用正常订阅流程安装了一个无需登录的插件；最新观察出现仅在插件可用时显示的搜索入口，随后进入 FullUI 的“翻译与字幕”。默认首页仍可显示收藏，不能仅凭收藏／配置标签判定 ShellUI。

JEV 与 AXe 验证记录（原始证据位于被忽略的 `runs/jev-ios-translation/`）：

- 默认开关值为 0，目标语言为中文简体，引擎为 Apple 原生翻译；开启后开关值为 1，语言可切换为英语。结果来自操作后的新 AX 观察。
- 默认浅色、大模型空配置浅色及默认深色原尺寸截图均经复核，未见明显裁切、重叠或安全区异常；返回设置列表成功。结束后重启复核为关闭／中文简体／Apple，系统外观恢复浅色，无效地址未保存，用户订阅源与已安装插件保留，无活跃 JEV／Device Hub session。
- 切到大模型后，空配置的“测试翻译”按钮为 disabled；保存非 HTTPS 的合成地址会显示 HTTPS 基础地址校验错误。未输入真实 API Key，也未调用真实大模型翻译服务。
- `.jev-ios/smoke.json` 已替换占位内容，真实运行结果为 `verified / exact_labels_visible`，6 个配置标签匹配。JEV 内部耗时 2545.7 ms，CLI 整体约 12.8 秒，动作数 0、模型调用数 0；此结果仅证明已准备页面的标签可见，不能证明自主导航、后台效果或总体速度提升。报告为 `semantic-run-report.html`，原始结果为 `semantic-run-trace.jsonl`。
- Apple 原生测试唤起系统翻译弹层，明确提示翻译不支持模拟设备，需要真实设备；截图为 `apple-test-pending.png`。因此真实原生译文尚未验证，不将其归因为下载失败或应用卡死。
- JEV 当前观察能读取系统标签栏的 `RadioButton`，但没有生成可点击目标；前置导航采用新 AX 观察定位后的确定性 AXe 输入。空密钥框也被报告为 `TextField / secure=false`，本轮没有输入密钥；后续涉及真实凭据前必须重新核验安全字段识别，不能据此假定脱敏有效。

macOS 使用 workspace `RunProject` 启动并核验实际进程为本次 Debug 产物。开关及 Apple／大模型切换、空配置测试按钮禁用已验证；Apple 测试触发系统语言下载页面，提示需要英语和简体中文资源，本轮未下载，未取得译文。原尺寸截图复核发现大模型输入框把内层标题重复显示在右侧；已修复为显式 prompt 和隐藏内层 label，并在 20:37:07 +0800 将 URL prompt 改为 `Text(verbatim:)`，避免占位文字被解析成链接。仅修改 macOS 三个字段。最后修改后的 MCP `BuildProject` 成功（12.374 秒），Error Navigator 为 0，`RunProject` 成功（4.808 秒）；证据为 `/tmp/angellive-mac-final-mcp.26IiXM/bridge-transcript.log` 的 id 5／6／7。最终原尺寸截图 `runs/mac-translation/translation-settings-llm-empty-final.png` 经 root 复核：三个输入框等宽，提示文字均位于框内，URL 为普通灰色单行文字，无重复标签或换行挤压，空配置测试按钮禁用。macOS 视觉覆盖当前深色外观，未另切换系统浅色。

tvOS 已对已有标准 Apple TV 4K（第 3 代）／tvOS 27.0 执行最后源码后的 `DeviceInteractionInstallAndRun`，明确返回安装运行成功，启动截图与 hierarchy 显示 FullUI。遥控器导航未稳定到达翻译面板；后续请求返回 `Session not found`，因此翻译面板、开关和返回焦点仍未验证。不能以启动成功或发出按键代替交互通过。证据位于 `runs/tvos-translation/`，原始 MCP transcript 在临时目录 `/private/tmp/angellive-tvos-mcp.UvFkRX/`。

实际房间译文及真实大模型服务联调仍未完成，不能以设置页或构建通过代替。

最终生产源码冻结、JEV 骨架加入后的全仓扫描覆盖 614 个 UTF-8 文本文件、85 个二进制文件：仅存在已核对的通用变量／查询示例歧义命中，未发现实际具体内容平台标识；测试中的 `liveType`／`siteId` 无真实编号命中。二进制未做 OCR。`git diff --check` 通过。

### 2026-09-30 固定常用语言

自动来源语言统一为英语、日语和韩语，标题与弹幕、Apple 与大模型均在识别后执行范围判断；其他语言不创建翻译请求。Apple 设置固定列出对应语言对并查询真实安装状态，不再依赖先遇到缺少资源的内容。切换目标语言会排除同语言项。

最终源码使用 Xcode 27.1 Beta（27A9269）工具链运行 `swift test --package-path Shared/AngelLiveCore --filter 'Translation|DanmakuLanguageDetection'`，4 组、43 项测试通过；root 独立运行的原始日志为 `/tmp/angellive-common-language-tests-root.log`。包含非目录语言在两个引擎的跳过、语言变体、固定目录、安装状态映射、取消与刷新期间切换开关的回归。

三端 workspace MCP 构建均成功：iOS 24.704 秒、macOS 31.107 秒、tvOS 36.718 秒，各次构建后 Issue Navigator error 均为 0。原始 MCP 记录为 `/tmp/angellive-common-languages-mcp.log`。

macOS 最后编辑后的 workspace MCP build 成功（31.107 秒）、Issue Navigator error 为 0，随后 RunProject 成功。root 核对运行进程属于本次 Debug 产物，通过原生 UI 验证：中文目标显示三行下载入口，英语目标只显示日语和韩语，切换大模型保留自动语言范围说明且隐藏语言包。深色原尺寸截图已在当次会话复核，布局无明显裁切或重叠；恢复中文简体／Apple 与原开关值后关闭弹窗。本轮没有点击下载或测试翻译，不证明实际资源下载或译文效果。

iPhone 17／iOS 27.0 在最后源码后完成新的 `DeviceInteractionInstallAndRun`，确认 Running 并结束 Device Hub session 后交由 JEV／AXe。原尺寸截图 `runs/ios-common-languages/apple-zh.png` 与目标切换截图 `apple-en.png` 确认三行／两行语言对；模拟器的实际资源查询结果为不支持，页面显示“当前系统不支持”。`final-llm.png` 确认大模型仍说明固定自动来源语言，保留原布局。既有连接配置 smoke 仅匹配 5/6 个标签，“测试翻译”位于当前视口下方，结果为 `blocked / low_confidence`（0 动作、1 次模型调用），不记为通过；本轮固定列表与目标切换的通过依据是另行保存的操作后 AX 观察和截图。

iOS 结束后恢复原中文简体／大模型、标题开启／弹幕关闭配置，未输入凭据。tvOS 在已有 Apple TV 4K（第 3 代）／tvOS 27.0 完成最后源码后的新包安装运行；遥控器焦点导航未稳定进入设置，因此翻译说明页和返回焦点未验证，证据保存于 `runs/tvos-common-languages/`。已结束全部 Device Hub session，恢复 Xcode 原 scheme／运行目标并关闭本轮 bridge，未运行真机。最终全仓扫描覆盖 621 个文本文件、85 个二进制文件的可读标识，平台标识及测试映射编号无有效命中；二进制未做 OCR。`git diff --check` 通过。

### 2026-09-30 中文名称与下载提示

语言对名称显式使用设置页的五种中文名称，避免 `Locale.current` 随设备系统语言显示英语。iOS／macOS 的下载中状态增加可见文字“正在下载…”并保留具体语言对的辅助功能标签。核对 Xcode 27.1 Beta（27A9269）Translation SDK 的公开 Swift interface，`prepareTranslation()` 仅为 `async throws`，没有资源下载进度回调；两端增加系统管理下载且无百分比的说明。

修改后运行现有 `NativeTranslationResourceTests`，1 组、7 项通过，原始日志为 `/tmp/angellive-language-pack-label-tests.log`。本轮未新增仅断言文字的测试；名称与提示的设备显示另行核验。全仓标识扫描覆盖 621 个文本文件与 85 个二进制文件的可读标识，平台名称与测试映射编号无有效命中，二进制未做 OCR。

iOS workspace MCP build 成功（21.891 秒）、error 为 0，最后源码后完成新 `InstallAndRun`、Running 捕获及 EndSession。JEV 本轮受 PID 匹配错误阻塞（调用返回错误的摘录见 `runs/ios-language-pack-labels/jev-unavailable.txt`，两次调用均退出），改用 AXe 对同包作最小观察和交互；`runs/ios-language-pack-labels/apple-zh.png` 原尺寸截图与对应 AX 树确认三行中文名称及无百分比说明，root 已独立复核，恢复原大模型／中文简体配置，未下载或测试翻译。

macOS build 成功（28.366 秒）、error 为 0，但 RunProject 返回 `Failed to track run action`，旧应用仍在运行。root 原生观察发现旧应用处于语言包准备／下载状态，保留该任务，未退出或重启。因此本轮 Mac 新界面和实际下载中的提示未完成运行验收，不能用旧包证明修改通过。原始构建记录为 `/tmp/angellive-language-pack-labels-mcp.log`。

tvOS 本轮仅作共享代码构建验证，MCP build 成功（31.169 秒）、error 为 0，未启动新的设备 session。已恢复 Xcode 原 scheme／目标；本轮没有运行真机。

### 2026-09-30 手动下载接入当前设置页

iOS／macOS 的“下载”改为当前设置页直接承载原生 `translationTask`，调用 `prepareTranslation()`。独立请求标识隔离旧结果；同语言对再次点击可重新触发，页面离开或配置改变时取消宿主请求。下载完成后重新检查资源是否已安装，再更新语言包状态。行内等待提示改为“请在系统弹窗中下载”，footer 提示在系统弹窗查看进度，保留原有布局和中文语言名称。

手动弹层初版源码后运行 `Translation|DanmakuLanguageDetection` 相关测试，4 组、43 项通过，日志为 `/tmp/angellive-native-download-sheet-tests.log`。首轮 workspace MCP 三端构建均通过：iOS 26.304 秒、macOS 36.484 秒、tvOS 38.418 秒；各自随后查询 Issue Navigator 均为 0 个 error。原始记录为 `/tmp/native-download-sheet-mcp.log`。

iPhone 17／iOS 27.0 在手动弹层初版源码后完成新的 `InstallAndRun`、Running 捕获和 EndSession，JEV 接管该新包。一次真实 `inspect --launch` 返回 `Observed application PID does not match the selected app` 并退出；错误摘录见 `runs/ios-native-download-sheet/jev-unavailable.txt`，随后用 AXe 完成限定设置页验收。`apple-zh.png` 原尺寸截图与 `apple-zh-hierarchy.json` 显示三种中文语言对及系统进度提示，root 已独立复核。模拟器三行均为“当前系统不支持”，因此未点击下载，也不能据此证明真实系统下载弹层。结束后恢复原中文简体／大模型及开关值，未输入凭据。

macOS 最初因自动审批拒绝正常退出旧应用而仅构建，拒绝理由为可能中断此前保留的下载任务。用户随后明确允许退出并验证；root 正常退出旧应用，再通过新的 MCP 连接 `RunProject` 启动本轮 Debug 产物（5.879 秒），并独立核对进程路径。原始响应为 `/tmp/native-download-sheet-mac-run-mcp.log` 的 id 6。

root 通过原生 UI 首次点击“日语 → 中文简体”的下载按钮，成功显示 Apple 系统 `Download Languages to Translate` 弹层。未点击系统 Download，点击 Done 返回设置后按钮恢复；但同语言对第二次下载停在等待状态。关闭整张翻译设置、重新进入后首次下载又能显示系统弹层。这一运行结果支持隔离下载 host 的 identity，让每次手动请求重新建立 session；未把问题归为网络下载失败。

重试修复仅调整共享下载 modifier：原生 task 放入当前设置页的零尺寸背景 host，以请求 ID 重建该 host，保留整个设置页及全局标题 host 的 identity。最终源码后的 4 组、43 项测试再次通过（`/tmp/angellive-native-download-retry-tests.log`）；全仓标识及测试编号再次扫描无有效命中（`/tmp/angellive-native-download-retry-scan.json`）。macOS 最终 workspace build 成功（13.32 秒）、error 为 0，随后正常启动新包（4.318 秒）；root 独立核对进程为当次 Debug 产物，证据为同一 Mac MCP transcript 的 id 7／8／9。

macOS 27.0（26A428）深色外观下，root 验证最终新包的“日语下载 → 系统弹层 → Done 未下载返回 → 同页再次日语下载 → 系统弹层再次出现”，第二次退出后按钮也恢复正常。两次弹层的当次会话截图与 AX 树已独立复核，系统显示日语和简体中文资源；保持 Apple／中文简体／两个开关关闭的原配置并关闭设置面板。未点击系统 Download，因此实际资源传输、系统进度变化及最终安装状态未验证；iOS 真机下载仍需单独验收。

iOS 重试修复后的最终 workspace build 成功（15.514 秒）、error 为 0，并在同一 iPhone 17／iOS 27.0 完成新的 `InstallAndRun`、Running 捕获和 EndSession。root 独立核对原始 id 12／13／15／16／17 响应及 `runs/ios-native-download-retry/launch.png` 启动截图；本次未重复设置页交互，不能用初版设置截图替代最终包的系统弹层验收。

tvOS 最终源码仅构建共享 API，MCP build 成功（12.86 秒）、error 为 0，root 已核对同一 transcript 的 id 19／20；未启动 tvOS 设备 session。最终已恢复原 `AngelLive / LaoPC` 目标、结束 Device Hub session 并关闭持久 bridge，未运行真机。

tvOS 仅构建共享 API，未作设备交互。本轮未运行真机。首轮已结束 Device Hub session、恢复原 scheme／运行目标并关闭 bridge；后续 Mac 验收使用另一个持久连接。全仓扫描覆盖 621 个文本文件、85 个二进制文件的可读标识，具体内容平台标识及测试映射编号无有效命中；二进制未做 OCR。

## 参考

- [Apple：Translating text within your app](https://developer.apple.com/documentation/translation/translating-text-within-your-app)
- [Chat Completions 接口参考](https://developers.openai.com/api/reference/resources/chat)
- SwiftUX `get_conventions` 与单组件检索：标题翻译开关未获得匹配组件；用户确认直接复用项目现有通用设置样式。
