# 房间标题翻译

## 产品范围

第一期为 FullUI 的房间标题自动翻译，支持 Apple 原生翻译与用户自行配置的大模型接口。AI 实时字幕保留为后续阶段：先验证播放器音频提取和语音转写，再复用文本翻译能力。

默认关闭。按标题内容识别语言，不维护具体内容平台名单。原始标题继续用于模型、收藏同步、搜索匹配、分享与系统媒体信息；译文仅作为应用内展示值。

## 设置与界面

在现有设置中增加“翻译与字幕”入口。设置页复用各端现有通用设置样式：iOS 分组列表，macOS 分组表单与现有设置弹窗，tvOS 半屏设置及遥控器焦点导航。保持原有房间卡片尺寸、标题字体、行数与点击行为。

设置包含：

- 自动翻译房间标题。
- 目标语言。
- 翻译引擎：Apple 原生／大模型。
- 大模型服务地址、模型、API Key、保存配置、删除密钥及测试翻译。

大模型服务由用户提供，兼容 Chat Completions 请求格式。基础地址包含服务要求的版本路径，例如 `https://api.example.invalid/v1`，客户端追加 `chat/completions`。界面说明标题会发送至所配置的服务，并可能产生服务费用。

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

## 参考

- [Apple：Translating text within your app](https://developer.apple.com/documentation/translation/translating-text-within-your-app)
- [Chat Completions 接口参考](https://developers.openai.com/api/reference/resources/chat)
- SwiftUX `get_conventions` 与单组件检索：标题翻译开关未获得匹配组件；用户确认直接复用项目现有通用设置样式。
