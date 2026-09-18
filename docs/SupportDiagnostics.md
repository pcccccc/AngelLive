# 问题诊断与反馈

FullUI 的设置页和错误页提供“问题诊断与反馈”。用户无需打开开发者模式；ShellUI 不提供此入口。报告仅在本机保存，分享由用户主动发起。

## 用户流程

1. 遇到错误时，打开错误页的“诊断与反馈”，先查看当前错误摘要。
2. 如果需要定位插件或请求失败，点按“开始记录”，用“返回并复现”回到原页面重复出现问题的操作。记录页显示真实计时，离开此页不会停止记录。
3. 回到设置中的“问题诊断与反馈”，点按“结束记录”生成报告。每次录制最长五分钟。
4. 查看生成时间、记录时长与采集数量，可补充发生时间、操作路径、预期结果和实际现象。点按“检查并分享报告”前会保存尚未保存的补充；保存失败时保留草稿并显示错误。
5. 完整预览独立成页。iOS 和 macOS 底部提供复制、系统分享文本和分享文件，文件在打开预览时于本地准备；tvOS 在预览页开启临时局域网下载，在同一网络的手机上扫码下载完整文本。下载链接五分钟后失效，离开分享界面也会关闭。

页面按开始、复现、分享三个阶段呈现，只显示当前可用内容；重新记录和清除报告都需要确认。开始与记录状态复用同一面板，状态、真实计时、五分钟进度和具名操作集中显示，三端录制布局见 [录制交互规范](SupportRecordingDesign.md)。TV 报告、描述编辑与预览下载的当前设计见 [TV 报告规范](SupportTVReportDesign.md)，实际验证结果按下文轮次记录；iOS/macOS 的报告与分享仍沿用 [第一轮界面规范](SupportDiagnosticsDesign.md)，尚待下一轮设计复核。tvOS 使用双栏及遥控器焦点，预览页按返回键先关闭已开启的手机下载，再返回摘要页。

未开始录制时，错误页只能生成当前错误快照，不能恢复已经丢失的历史请求。报告会明确说明没有采集到的内容。

## 记录范围

- 应用版本、系统、录制起止时间。
- 页面切换、搜索、进入直播间、重试、清晰度或线路切换、前后台变化，以及账号和插件管理入口。
- 插件标识、版本、调用方法、开始时间、耗时、结果和操作关联 ID。
- JavaScript 异常的消息、堆栈、脚本位置（运行时能够提供时）。
- HTTP 方法、URL、状态码、耗时、请求与响应头、文本正文、失败原因，以及正文类型、原始字节数和截断标记。

操作时间线描述应用中的业务操作，不采集逐次触摸、键盘事件或屏幕录像。搜索事件只记录搜索类型；插件请求正文仍可能包含搜索词等输入，分享前需要检查。播放器内部、WebSocket 帧及原生流解析器未经过插件 HTTP bridge 的流量不在本轮 HTTP 记录范围内。

## 关联与缺失语义

同步进入插件函数时，为调用捕获不可变上下文；HTTP 请求在发起时固定关联，不能在响应到达时按“当前调用”猜测归属。

JavaScript Promise 的后续回调无法证明原始调用归属时，HTTP 单独记录并标记 `uncertain` 或 `unassociated`；候选调用仅作为排查线索，不等同于因果关系。跨录制会话不能证明归属的请求不得放入新会话。

停止录制会冻结当前报告。之后返回的响应不会修改已生成报告。仍在进行、超过数量或大小限制的内容会在报告中注明；空记录不能解释为调用成功。

## 内容处理与保存

常见凭证字段、Cookie、Authorization、URL 查询值等在进入诊断内容时脱敏。登录事务和敏感运行时调用继续省略请求与响应正文，仅保留协议级状态。二进制响应只记录类型和大小，不转为可分享的原始数据。

脱敏无法识别任意自由文本中的个人信息，因此导出前始终提供可检查的预览。报告不包含自动上传地址，也不会自动发送给开发者。

缓存目录只保留最近一份报告；系统可能清理缓存。删除报告同时删除本机导出的副本。tvOS 临时下载服务只接受带随机路径的读取请求，不能上传或修改报告，不发布到公网。

## 实现位置

- `Shared/AngelLiveCore/Sources/AngelLiveCore/Diagnostics/`：录制生命周期、脱敏、报告模型与缓存、公共界面、临时局域网下载。
- `LiveParse/Plugin/JSRuntime.swift` 与 `LiveParsePluginManager.swift`：插件异常及 HTTP 上下文。
- `Services/PluginConsoleService.swift`：有界记录及录制会话标识。
- 三端 FullUI 设置、错误视图与操作发起位置：入口、导航及操作关联。

自动化测试覆盖脱敏、报告冻结与恢复、录制会话隔离、并发请求归属、异常信息和下载路径限制。设备验收应使用最后编辑后的新包，分别验证录制、复现、停止、预览、分享入口及 tvOS 遥控器焦点；构建通过不能替代这些交互验证。

## 基础诊断功能验证（2026-09-18，界面改版前）

使用 Xcode 27.0 RC（27A266a）：

| 验证范围 | 实际结果 |
| --- | --- |
| AngelLiveCore 全量测试 | 43 个套件、317 项通过；串行运行，包含本次新增的 15 项诊断与下载测试 |
| iOS `AngelLive` | 首轮 Xcode MCP workspace 构建通过，Issue Navigator 无 error；最终源码的模拟器命令行构建通过 |
| macOS `AngelLiveMacOS` | 最终源码的 workspace 命令行构建通过 |
| tvOS `AngelLiveTVOS` | 最终源码的模拟器 workspace 命令行构建通过 |
| 局域网下载服务 | 在 Mac 上实际启动 listener 并通过 HTTP 下载，文本与 UTF-8 内容长度一致，错误路径返回 404，停止后清除入口 |
| 新包安装与界面交互 | 未完成：Mac 锁屏阻塞新的 Xcode 授权与 Device Hub；未执行 `InstallAndRun`，没有新包截图，不将此项计为通过 |

macOS/tvOS 的命令行构建不等同于 MCP workspace 验证。电视端手机扫码、三端界面滚动与分享、深浅色及 tvOS 焦点行为仍需在解锁后完成新包验收。

命令行验证从临时目录使用 workspace 的绝对路径运行，避免播放器依赖清单根据工作目录误选相邻本地组件。使用仓库原有锁定依赖，未修改依赖版本、签名配置或设备数据。

## 第一轮三端界面改版验证（2026-09-18，录制交互第二轮修改前）

本轮使用 Xcode 27.0 RC（27A266a），修改共享诊断界面，覆盖 FullUI 的开始、复现、报告摘要与独立预览。最后一次源码修改修正了 tvOS 不支持 `DisclosureGroup` 的编译范围，之后重新构建三个宿主。

| 验证范围 | 实际结果 |
| --- | --- |
| Core 诊断回归 | `SupportDiagnosticsTests`、`SupportReportSharingTests`、`PluginRuntimeDiagnosticsTests`，3 个套件、15 项通过 |
| iOS `AngelLive` | 最终 workspace MCP `BuildProject` 通过，Issue Navigator 无 error；iPad mini（A17 Pro）、iOS 27 上完成开始记录、返回设置、重入后继续计时、停止、补充保存、预览、复制与系统分享面板开关；最后源码修改后再次 `InstallAndRun` 成功并复核稳定报告页截图 |
| macOS `AngelLiveMacOS` | 最终 workspace MCP `BuildProject` 通过，Issue Navigator 无 error；Xcode Run 启动本次构建产物后复核深色报告页；完整主流程及重新记录取消已通过原生 UI 验证 |
| tvOS `AngelLiveTVOS` | 最终 workspace MCP `BuildProject` 通过，Issue Navigator 无 error；Apple TV 4K（第 3 代）、tvOS 27 两次 `InstallAndRun` 均返回安装运行成功 |
| tvOS 交互与视觉 | **未完成**。首个 session 中模拟器异常关闭；恢复后分次遥控指令间系统侧栏丢失焦点，最后工具返回 `Session not found`。未取得最终包诊断页截图，不将焦点、报告滚动或二维码行为计为通过 |

macOS 的 Device Interaction 返回不支持 My Mac，因此使用 workspace MCP build、Xcode Run、精确构建产物路径及原生应用 UI 截图验证，没有执行 Mac `InstallAndRun`。系统分享只验证面板打开和取消，没有对外发送报告。

该轮未验证 iPhone、真机、各平台完整深浅色及最大辅助字体矩阵。当时的扫描未报命中；第二轮复扫扩大了歧义标识审查，补清理两处平台专用注释。测试 `liveType` / `siteId` 使用中性占位。

## 第二轮录制交互验证（2026-09-18）

用户选择先重做「记录过程（开始、计时、结束）」。本轮已实际调用 SwiftUX MCP 的 `get_conventions`、`search_catalog`、`get_component` 和 `get_component_source`，采用 `audio-input-bar` 的录制控件结构，并按三端原生布局调整。报告编辑和分享区域仍待单独设计复核。

- iPhone 18 Pro / iOS 27：对比度修正后的 workspace MCP `BuildProject` 通过（4.007 秒），Issue Navigator 无 error；旧 session 失效后重新启动 session，最后编辑后的 `InstallAndRun` 明确成功。开始后计时从 0:01 增长，返回设置再重入显示 2:12，进度同步推进，结束后出现「诊断报告已就绪」。root 独立复核了开始、记录、重入截图及结束后的 hierarchy。验收后已结束 session。
- macOS：所有最终编辑后的 workspace MCP `BuildProject` 通过（11.016 秒），Issue Navigator 无 error；最终录制态深色与浅色的 `RenderPreview` 均成功，root 已逐张复核状态、层级、尺寸和布局。
- Mac 实际交互未验证：CUA 先后返回 `failedToCreateImageDestination` 和 `failed to write kernel assets`；MCP `RunProject` 返回无法触发或跟踪运行。没有把 Preview 当作真实应用运行或点击验证。Preview 使用系统默认强调色，真实宿主主题色尚未复核。
- tvOS 27：最终宿主深色样式修改后的 workspace MCP `BuildProject` 通过（22.554 秒），Issue Navigator 无 error；随后新的 `InstallAndRun` 明确成功，空交互捕获确认 `applicationState=Running`，session 已结束。录制组件 Preview 已生成，布局完整；它不经过设置／错误页的诊断宿主，因此不能验证两处宿主的深色导航标题修复。
- TV 实际录制交互未验证：Siri Remote Menu 后侧栏首项一度明确聚焦，但下一请求焦点回落首页；一次合并遥控指令的恢复尝试又进入了首页播放器。未能可靠到达诊断页，按约定停止重复导航。因此诊断页默认焦点、开始后的焦点迁移、返回重入、停止，以及宿主标题对比都不计通过。
- 本轮未修改诊断服务、报告格式和会话契约，也未重跑上一轮的 15 项 Core 诊断测试；录制行为需以新安装包的设备操作确认。
- iPhone 深色 Preview 因 `XCPreviewAgent UpdateTimedOutError` 未产出，不计通过；未全面实测最大辅助字体、VoiceOver、减少动态效果及本轮 iPad 新包。

所有设备证据均以对应平台最后源码编辑之后的结果为准，上一节的截图和安装记录不能证明本轮通过。最终全仓扫描覆盖 662 个跟踪或未忽略文件，具体内容平台文本标识无实际命中；二进制资产未做 OCR。`git diff --check` 通过。所有 Device Hub session 已结束，iPhone 模拟器已关闭，Xcode 恢复 `AngelLive / iPad mini (A17 Pro) (27.0)`。

本轮原始响应、截图与 hierarchy 位于 `/private/tmp/angellive-feedback-v2-mcp.nTZ3YT/`；全仓扫描证据位于 `/private/tmp/angel-live-platform-scan.ooRgyb/`。临时证据目录不属于仓库，不提交运行数据。

## TV 按钮与原设置页对齐（2026-09-18 后续修正）

用户指出 TV 录制页与原页面视觉不一致，录制与返回按钮宽高混杂。本次以 TV `SettingView.menuListView` 为来源，将录制操作改成同一列的系统原生横向行：单行 body 文字、尾部符号、15 pt 行间距、相同列宽与系统自然高度；开始／结束保持第一行，返回位于第二行。计时移到左侧独立状态区，右侧栏采用与设置页一致的半屏减 50 pt 布局。Preview 也使用实际 TV 诊断宿主的深色环境。

本次重新调用 SwiftUX `get_component(audio-input-bar)` 核对适配契约，复用此前已读源码的结构参考，按照目的应用样式调整，不重复搜索其他组件。具体尺寸与焦点规范见 `SupportRecordingDesign.md`。

root 独立检查本轮 diff，并展开平台条件分支对照本轮前快照：iOS/macOS 有效源码一致，TV 报告内容、分享及服务实现未变；TV 诊断导航标题改用原生 principal ToolbarItem 中的语义文字。早期实现的 host/iOS/tvOS 语法检查通过，最终源码 `git diff --check` 通过。最终构建及视觉结果见下方记录，前一节设备截图不适用于本次 TV 改动。

最初的非 workspace 基线读取遇到环境阻塞：Device Hub 在标准 TV 模拟器上返回 `The device simulator cannot be connected`；一次重新开始 session 后仍失败，已结束该 session。CUA 单次读取返回 `failed to write kernel assets`。最终改用本次新源码对应的 workspace session 后，`InstallAndRun` 明确返回 `Application installed and running`，空捕获确认 `Running`，后续经应用 UI 成功进入设置和诊断页。这些结果不能推出先前工具故障的具体原因。证据目录为 `/private/tmp/angellive-tv-button-alignment-qx9kdm4f/`。

最终源码 SHA256 为 `3c8b76aee9de1a06d273c67cd80f3e9194cfda692fe19eb448e04982e409c163`。tvOS workspace MCP `BuildProject` 通过（86.203 秒），Issue Navigator error 为 0。root 独立读取了最终 JSON 响应并检查 `evidence/final3-preview-tvos-recording.png` 原图：导航标题为清晰白色，两行原生按钮同宽同高，文字、尾部图标完整，状态文字已缩小；此结论是 Preview 视觉检查，不是设备焦点验收。中间两轮 Preview 中低对比的系统标题未计通过，对应试验性 toolbar 颜色／背景修饰符已移除。

实际新包按钮对照：已有 Apple TV 4K（第 3 代）/ tvOS 27.0 模拟器的设置页，普通单行按钮为 830 × 66 pt，聚焦后为 838 × 74 pt。诊断录制态的「结束记录」和「返回并复现」均取得相同尺寸；root 比较了两种焦点归属的 hierarchy，确认上／下切换时两行交换高亮且尺寸规则一致，并检查了原尺寸截图中导航标题、图标及文字完整。计时在实际捕获中从 0:02 增长到 0:41。对应证据为 `evidence/final3-settings-hierarchy.txt`、`final3-recording-return-focused-hierarchy.txt` 和 `final3-recording-end-focused-hierarchy.txt` 及同名 PNG。

最小完整流程通过：待开始页初始聚焦开始，开始后默认聚焦返回；返回设置显示「录制中」，重入时计时继续到 2:38，停止后 hierarchy 显示「诊断报告已就绪」。root 独立核对了安装响应、重入与停止 hierarchy；实际画面展示使用已完整检查的 `evidence/final3-recording-return-focused.png`。不以这一流程证明报告编辑／分享已重做。本轮未重跑诊断服务单元测试，实体 Apple TV 未验证；iOS/macOS 本轮没有重新构建或设备测试，其有效源码与本轮前快照一致。

最终全仓扫描清单 662 个文件，其中 579 个 UTF-8 文本文件、83 个二进制文件；文本仅有恢复计数 `kick` 与通用查询示例 `hint=yy` 的歧义命中，未发现实际具体内容平台标识。测试 `liveType` / `siteId` 使用中性 fixture 或 source 占位，二进制未做 OCR。`git diff --check` 通过。Device Hub session 已结束，Xcode 恢复原 `AngelLive / iPad mini (A17 Pro) (27.0)`，bridge 已停止。

## 2026-09-18 TV 报告、描述编辑与预览下载

按 [TV 报告规范](SupportTVReportDesign.md) 补齐录制之后的界面。报告摘要采用固定两列元数据，四个主操作与设置页复用原生行规格；问题描述移至独立编辑页，使用本地草稿、明确保存和取消，主屏只显示摘要。预览保留完整报告和显式开启的手机下载，报告会话替换时关闭旧预览与下载。服务、报告格式与 ShellUI 未修改；root 展开条件编译分支对照本轮前快照，iOS/macOS 有效源码一致。

中间源码 `7b5f09b6cc112332d2217018aae6859e996c17df0fcf89a35b7e6e0ca3f74c15` 的 TV workspace MCP `BuildProject` 通过（22.773 秒），Issue Navigator error 为 0，之后 `DeviceInteractionInstallAndRun` 明确成功。Apple TV 4K（第 3 代）/ tvOS 27.0 的报告首屏完整，默认聚焦检查报告；实际行框为普通 830 × 66 pt、聚焦 838 × 74 pt，与设置页一致。第一次实包发现部分符号撑高行框后，已将尾部图标移至不参与行高计算的 overlay，并完成新包复核。

该版本实测保存空描述后返回主屏「尚未补充」，再输入临时草稿并明确聚焦取消后，主屏仍为空；保存与取消均恢复描述入口焦点。重新记录、清除的确认弹窗取消后保留原报告，并返回对应操作。root 已独立读取相关 hierarchy；这些中间结果不能代替后续源码的新包验收。

同轮实测发现两项问题并继续修复：整篇 SwiftUI Text 能聚焦却不能向下浏览，现 TV 独立使用原生可聚焦 UITextView，保持完整原文并只在内容变化时重置位置；预览的返回按钮正常，但遥控器 Menu 越级退到设置，现移除设置与错误入口外层直接关闭整窗的处理，让诊断根和预览分别拥有返回语义。中间源码 `5788e0d3654f5c9c18f59bb9705631de6c4255400c752f91447f723a992d84c8` 通过 workspace MCP `BuildProject`（41.113 秒），Issue Navigator error 为 0，并完成新的 InstallAndRun。root 独立复核了正文下移 260 pt 后末段可见、向上恢复首段的原图与 hierarchy；正文向右能回到操作，预览按钮返回、预览 Menu、编辑 Menu 和报告 Menu 均按层返回。

复核同时发现 push 预览的操作行仍比主屏宽 80 pt，因此 TV 预览改为与编辑器一致的独立 fullScreenCover / NavigationStack 根页面，使用系统安全区域。最终源码 `a696322034e08e2c82aba2b12dfffdfe7996074a4827d35787119c04a28d2225` 通过 workspace MCP `BuildProject`（15.889 秒），Issue Navigator error 为 0，最后编辑后的新 `DeviceInteractionInstallAndRun` 明确成功。

最终新包的主屏、预览均为普通 830 × 66 pt、聚焦 838 × 74 pt。原生正文向下两次后，末段完整位于阅读视口内；此时按一次 Menu 返回报告，主操作重新获得焦点，原报告和空描述保留。root 已独立复核最后源码对应的 build、issues、install 响应及原尺寸图片、hierarchy。证据为 `evidence/final-report.png`、`final-preview.png`、`final-preview-bottom.png`，以及原始目录中对应的 `final6-*-response.json`；最终设备 session 已明确停止，Xcode 已恢复 `AngelLive / iPad mini (A17 Pro) (27.0)`。

手机下载按钮的实际激活被自动审批拒绝，理由是开启局域网下载可能暴露诊断内容、需要明确授权。本轮未执行该动作，也未绕过拒绝，不能声称已验证二维码、下载或下载展开时的 Menu。

原始响应位于 `/private/tmp/angellive-tvos-report-flow.uRaThs/`，整理后的证据与全仓扫描位于 `/private/tmp/angellive-tv-report-6rxu34s2/`。本轮未重新运行服务单元测试、iOS/macOS 构建与设备测试，实体 Apple TV、VoiceOver 和最大辅助字体未验证。

最终全仓扫描覆盖 663 个跟踪或未忽略文件：580 个 UTF-8 文本、83 个二进制或非 UTF-8 文件。文本规则的 4 行歧义命中均已复核，没有实际具体内容平台标识；34 个 Swift 测试文件中的 66 行 `liveType` / `siteId` 引用均为中性 fixture、变量或参数。二进制未做 OCR。`git diff --check` 通过，iOS/macOS 条件展开后的有效源码与本轮前快照一致。
