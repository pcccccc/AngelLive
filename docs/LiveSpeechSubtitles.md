# Apple 原生实时语音字幕

## 当前产品目标与自动识别接入（2026-10-26，实施中）

用户只负责开启字幕；应用先从播放音频自动识别主播语种，无法确定时才提供手动选择。不按插件平台、国家、地区、系统语言或房间标题猜测主播语种。此前“先手选语言再开启”的方案已替换，不再作为实施依据；自动识别已接入生产代码，实际验收仍在进行，旧方案的构建与测试不能证明此新目标已完成。

已核验 Xcode 27.1（27A9275）的三端公开 Speech 接口及 Apple 官方文档：`SpeechTranscriber` 必须配置单个 `Locale`；`SpeechDetector` 只做有没有人声的 VAD，且需与转写模块一起使用；`NLLanguageRecognizer` 识别的是文本，不能直接检测音频语种。系统 27 的 AVFoundation 生成字幕支持从英语音频生成英语字幕，不能据此认定它能自动识别任意主播语言，也不能直接替代当前播放器音频链路。

自动音频语种识别采用独立本地模型路径。Whisper 提供 `detect_language`；whisper.cpp 提供 `whisper_lang_auto_detect` 及语言概率数组，官方 XCFramework 和构建脚本覆盖 iOS、macOS、tvOS。开发 PoC 已在本机 Apple M4 上实际运行多语种 tiny 与 Silero VAD，英、中、日、韩四种干净合成语音的 2／4／8 秒窗口均识别正确；加噪韩语 2 秒误猜，4 秒低置信，8 秒才达到初始候选阈值。精确静音、合成旋律、正弦音和白噪声被 VAD 排除。此结果不是直播准确率、唱歌／多人语音或三端性能保证。

本机只读 locale 查询中，`auto` 不受支持，`und` 被匹配为 `en_US`，`mul` 被匹配为已列出的 `mul_IN`。查询没有输入任何音频，结果不能证明语种检测；`mul_IN` 的具体多语种契约也未在本轮 SDK 与官方检索中确认，不能推导成任意语言自动识别。多固定语言并行试转写是另一项待验证思路，不能仅凭各路文字或未经校准的分数就认定它可靠，资源占用与实时性也未测试。

产品接入顺序为：用户开启 → 显式准备缺少的本地模型 → 收集播放音频 → VAD 判断有效语音 → 本地判语种 → 查询该语言实际 Speech 支持和资源状态 → 输出字幕／翻译。初始策略是 4 秒首窗，至少累计 0.5 秒有效语音；语种概率 ≥0.80 且领先次候选 ≥0.20 时接受，否则继续到 8 秒再试。阈值尚未经过直播语料校准。无语音时继续等待；有效语音仍无法确定时才让用户选。识别成功但当前设备／语言不支持、缺少模型、没有音频输入等情况各自说明，不能都伪装成“语种识别失败”。

自动接入使用单一 PCM 消费链和按采样数限制的预录缓冲，避免两个 AsyncStream iterator 瓜分音频；检测与指定语言的转写分阶段衔接。房间状态将“已开启”与“已确定语言”分开，检测结果不改变 activation ID；关闭、换房、手动兜底选择和显式资源下载使旧异步结果失效。字幕翻译不再用英／日／韩名单拦截来源语言，由实际翻译服务检查语言覆盖。模型和语音资源下载均需用户明确点击，识别过程不向云端发送音频。选择大模型引擎仍只发送识别文本。

只读研究证据在 `runs/translation-auto-language-research-20261026/`，真实模型 PoC、固定 URL／SHA256／MIT 许可、原始结果和资源数据在 `runs/translation-auto-language-implementation-20261026/poc/`。生产接入与最后源码的新包验收尚在进行；下方旧手选方案及旧构建记录仅保留为历史，不能证明自动识别已交付。iOS 界面验收按用户要求延后，先完成 Mac 和 tvOS。

官方来源：[Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)、[SpeechDetector](https://developer.apple.com/documentation/speech/speechdetector)、[文本语言识别](https://developer.apple.com/documentation/naturallanguage/identifying-the-language-in-text)、[系统生成字幕](https://developer.apple.com/videos/play/wwdc2026/256/)、[Whisper](https://github.com/openai/whisper)、[whisper.cpp 接口](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h)、[三端构建脚本](https://github.com/ggml-org/whisper.cpp/blob/master/build-xcframework.sh)。

## 现有实现与第一版范围（旧手选方案已暂停）

在 FullUI 的直播画面中采用 Apple 本机语音识别，并通过当前翻译引擎显示目标语言字幕；不录制麦克风。字幕每次进入房间默认关闭，用户在播放器中明确选择主播语言后开启，独立于房间标题和弹幕翻译开关。

设置复用现有“翻译与字幕”页面的分组和选择器；原全局字幕开关所在行显示“在播放器中开启”，语言选择只用于语音资源准备，不改变运行中的房间。固定提供英语、日语、韩语、中文普通话四种来源语言，由用户选择与主播一致的语言；是否可用及模型是否安装均查询系统真实状态。不自动检测语音语言、不增加其他语言。字幕翻译复用现有目标语言、Apple／大模型引擎和安全凭据；默认目标为中文简体。等待或翻译失败时保留原文，同语言直接显示原文。

iOS 播放器设置和更多菜单、macOS 播放器齿轮、tvOS 播放按钮的 FullUI 上下文菜单提供“选择语言并开启字幕”，复用共享快捷动作及语言按钮。取消不启动；选择语言后连续识别和翻译，可主动关闭或更改语言。模型下载、目标语言和翻译引擎仍进入已有完整设置页；视频信息统计保留在原菜单中。

每个房间 ViewModel 持有独立的 `LiveSubtitlePlaybackState`，不同窗口不共享开关。换房成功提交和真正退出时停止；换源、画质、布局和同房间后台恢复保留用户选择，但识别任务按播放器生命周期取消和重建。打开语言面板时捕获 activation ID，换房或关闭后的旧面板动作不能启用当前房间。旧全局启用偏好不再恢复，持久化语言仅为语音资源候选，不被当作任何新房间已确认的主播语言。

Apple 自动翻译在支持策略选择的系统上优先使用已安装的低延迟资源；低延迟资源未安装而默认资源已安装时，使用默认资源。资源检查与实际会话选择保持一致，实时字幕所需的 iOS／macOS 26 及以上自动翻译使用不可请求下载的会话。准备／失败短提示单独位于字幕上方，四秒后消失，不替换仍可阅读的字幕；重复失败不续期，真实译文恢复或显式配置变化后解除失败提示去重。

语音模型与文字翻译语言包是两类资源，分别展示状态。模型仅在点击“下载”后安装，显示 Speech `AssetInstallationRequest.progress` 的真实百分比；打开直播或开启字幕不会自动下载。失败显示明确错误，不能把未完成安装当作就绪。

Speech 模型文件由系统共享，但语言登记属于当前应用。状态查询、识别和显式下载都先登记系统规范化后的语言，再检查资源；登记本身不下载模型。共享租约避免设置查询结束时释放播放器仍在使用的资源，仅释放本功能新增的临时登记。用户显式下载成功的登记继续保留；已有登记不由本功能清理。登记失败显示“暂时无法准备语音模型”，不误导为缺少模型或设备不支持。

## Apple 能力选择

### 2026-10-25 可用性复核与手动操作边界

系统版本、真机支持、模型安装和文字翻译服务是分别检查的前置条件：

| 路径 | 系统与运行环境 | 运行前置条件 |
| --- | --- | --- |
| 播放音频 → 原文字幕 | iOS／iPadOS／macOS／tvOS 26 及以上 | `SpeechTranscriber.isAvailable`、所选语言支持、语音模型已安装，以及当前播放内核提供解码音频回调 |
| 原文 → Apple 译文 | iOS／iPadOS 18、macOS 15 及以上；iOS／iPadOS 模拟器不支持，tvOS 不使用此 provider | 所选语言对受支持、资源已安装；自动路径不申请下载 |
| 原文 → 大模型译文 | 用户配置的兼容云端接口，随宿主可用；不是 Foundation Models，也不要求启用 Apple Intelligence | HTTPS 服务地址、模型、可读取且与地址绑定的 API Key，以及实际网络、鉴权、额度和模型权限 |

字幕使用云端翻译也必须先满足第一行的本机语音识别条件，云端接口不会接收音频或替代语音转写。同语言字幕直接显示原文，不要求配置翻译服务。当前字幕翻译来源仍限定英语、日语、韩语；中文普通话用于原文字幕，其他来源不再静默忽略，显示不支持的原因。

Apple 没有提供完整的 SpeechTranscriber 支持机型名单，DTS 明确建议在运行时查询 `isAvailable`；不能把某一代芯片、Apple Intelligence 的机型范围或升级到系统 26 当作字幕支持承诺。应用按实际结果分别提示系统版本、当前设备、模拟器、语言或播放内核限制。登记语音语言失败继续提示暂时无法准备模型，不误报成设备永久不支持。

本轮保留现有手动开关、下载和“测试翻译”操作。用户在 2026-10-25 对“每次进入直播默认关闭”方案表示仍需考虑，因此没有改变开关持久化、跨窗口状态或进入房间后的启动语义；该产品决策仍待确认。不会在打开设置时测试云服务，也不会自动安装语音或翻译资源。

大模型配置完整仅表示本机前置满足，不能宣称服务连通。用户主动点击“测试翻译”后，以实际响应判断；字幕运行中按标准化错误显示缺配置、缺密钥、安全存储、认证失败、限流、服务不可达或无效结果，保留原文。开启字幕时即检查已知的本地翻译前置，同语言直出跳过检查；失败短提示复用已有两行气泡与去重规则。三端既有设置说明明确：房间标题、弹幕和语音识别文本会发送至配置的服务，不发送音频。

官方依据：

- [SpeechTranscriber 的系统可用性与运行时设备检查](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Apple DTS：不要依赖固定机型名单，使用 isAvailable](https://developer.apple.com/forums/thread/802863)
- [Apple 文字翻译：系统要求及 iOS／iPadOS 模拟器限制](https://developer.apple.com/documentation/translation/translating-text-within-your-app)

本轮构建、测试和设备证据另见本文末尾追加的验收记录；历史记录不能替代本轮最后源码的新包验收。

Apple 提供两条相关路径：

| 能力 | 用途与约束 | 本项目选择 |
| --- | --- | --- |
| AVFoundation generated subtitles | OS 27 的 Apple 播放器可以从英语音频生成字幕，包括 HLS 直播；依赖 Apple 播放与媒体选择路径 | 记录为后续可选路径，第一版不更换播放器 |
| SpeechAnalyzer / SpeechTranscriber | OS 26 起提供流式、本机语音转写；硬件、语言和模型可用性须动态查询 | 第一版将现有播放器解码音频送入此接口 |

不能将系统辅助功能“实时字幕”直接视为应用可控制的字幕接口，也不能将 tvOS 不支持文字 `TranslationSession` 推导为所有语音 API 都不支持。三端分别按编译条件、系统版本和 `SpeechTranscriber.isAvailable` 判断；tvOS 的实际硬件效果仍需单独验收。

## 音频接入与播放边界

默认 KSPlayer 的 KSME 路径提供 `AudioRecognize.append(frame:)`。在音频回调内立即复制 PCM，再通过有界流交给识别任务；不在实时音频回调中执行语音识别或重采样。识别任务复用 `AVAudioConverter`，用 input-block 接口处理采样率和声道转换。

当前 KSAV 和 VLC 路径没有这组回调，显示不支持提示。保留现有选源、低延迟播放与播放器回退规则；不会为了字幕强制改用另一内核，以免影响起播或短时效播放地址。

字幕属于当前播放 session，在播放器 ready 后接入。开关、语言、播放地址、播放器实例或前后台状态变化时取消旧任务；ready 重建音频回调列表后重新绑定。退出、停止或回退到不支持的内核时结束输入流和分析器，只移除自身识别回调。

字幕显示最新识别片段，不持续累积整场文本；暂停或一段时间未收到识别结果时清空。字幕位于现有视频底部，两行上限，控件点击和 tvOS 焦点不由字幕层截获。ShellUI 不挂载此能力。

## 模块与凭据

- `AngelLiveCore/Translation/LiveSubtitleSettings.swift`：本设备语音资源语言偏好及非持久化、每房间独立的字幕运行状态，不影响标题／弹幕设置。
- `AngelLiveCore/Translation/LiveSubtitleTranslationPipeline.swift`：字幕独立翻译，一个进行中的请求和一个可覆盖的最新待处理输入；来源遵守现有英语／日语／韩语范围，按 Speech 片段起始时间隔离迟到结果。
- `AngelLiveDependencies/LiveSubtitleSession.swift`：播放器音频桥接、格式转换、模型状态、显式下载和 Speech 生命周期。
- `AngelLiveDependencies/LiveSubtitleReservations.swift`：共享语言登记、并发使用与显式下载后的保留。
- `AngelLiveDependencies/LiveSubtitleViews.swift`：共享设置行与字幕覆盖层，由三端 FullUI 页面使用。

Apple 原生识别和翻译不需要 API Key；选择大模型翻译时沿用既有用户配置。大模型仅发送识别文本，不发送音频。不改变插件协议，不将音频、字幕或账号凭据写入日志、仓库及同步数据。

## 验收门禁与当前进度

各轮记录按时间追加，历史失败及当时的未完成项保留用于追溯；当前交付状态以最后一轮实际验收结果和末尾真机清单为准。

以下为 2026-10-01 首次文档提交时的进度；后续实际结果记录在下一节。

已验证：

- 独立设置持久化测试通过，覆盖默认关闭、开关／语言恢复以及与标题／弹幕设置隔离。
- macOS workspace MCP `BuildProject` 成功，之后 `RunProject` 成功启动本次构建产物。首轮构建的播放器属性错误已修复。
- macOS 27.0 本机探测 `SpeechTranscriber.isAvailable` 为 true，四种来源语言均为 supported，但模型尚未安装；这不是转写成功证据。
- 三端 UI 挂载仅修改 FullUI，语法解析通过。语法解析不能替代平台构建和设备交互。

提交时仍待完成：

- PCM 复制与连续重采样测试结果复核。
- iOS、tvOS 最终 workspace 构建及对应设备设置／控制交互。
- 点击下载后的真实进度、最终安装状态和重新进入页面的状态恢复。
- 使用合成语音验证真实识别文本、暂停、停止、切换和退出后的清理。
- 原尺寸截图检查字幕裁切、控制区重叠、深浅色和 tvOS 焦点。

使用合成音频及中性 fixture，保留新包安装、截图和原始结果；不以 mock、构建、旧包或系统能力探测宣称“字幕已经出来”。后续验收完成后追加实际结果和未支持范围。

## 本轮实际结果（2026-10-01）

使用 Xcode 27.1 Beta（27A9269）和默认 KSPlayer 5.0.0，最终生产源码的三端 workspace MCP 构建均成功：iOS 9.578 秒、macOS 11.531 秒、tvOS 29.877 秒；各次随后查询 Error Navigator 均为 0。原始响应为 `/tmp/angellive-subtitle-mcp-206.json`、`-201.json`、`-109.json`，对应诊断为 `-207.json`、`-202.json`、`-110.json`。

共享测试：

- Core 全量 379 项／51 组通过，包含新增的独立字幕偏好测试；日志 `/tmp/angellive-subtitle-core-all-tests.log`。
- Dependencies 常规运行报告 10 项／3 组通过，两个需外部前置条件的联调项跳过。新增 PCM 测试含 2 组交错／非交错复制和 6 组采样率／声道转换用例；日志 `/tmp/angellive-subtitle-dependencies-all-tests.log`。
- 另行显式启用原生联调，使用 macOS 官方语音合成的中性视频，KSME 解码音频经生产 `LiveSubtitleSession` 送入 SpeechAnalyzer，识别出“Today we are checking the subtitle feature”。暂停后字幕清空，停止后任务正常退出并移除自身音频回调；1 项／1 组通过，耗时 6.788 秒。之后将测试播放器静音，重新运行仍识别出同一句话，暂停和停止清理再次通过，耗时 6.733 秒；该测试最终保留静音模式。日志为 `/tmp/angellive-subtitle-native-tests.log` 和 `/tmp/angellive-subtitle-native-muted-tests.log`。这证明使用解码音频的真实识别链路，不等同于手机直播画面已经验收。

该原生联调默认不运行，仅在设置 `ANGELLIVE_SUBTITLE_AUDIO_FIXTURE` 指向无敏感内容的合成视频时启用。需先在 App 中明确点击安装英语语音模型；独立测试进程先通过 `AssetInventory.reserve(locale:)` 登记所用语言，再查询资源。首次未登记时只读状态仍为 supported，测试按前置条件失败；登记后使用已安装资源成功，不触发自动下载。

macOS 27.0（26A428）：初版设置中点击英语模型下载，观察到真实进度由 0% 增至 26%，随后显示“已就绪”。来源切换为日语显示“尚未下载”，切回英语仍为“已就绪”。最后源码后的 MCP `RunProject` 再次成功，实际进程已核对为本次 Debug 产物；新包复核英语模型就绪、字幕开关开／关、重启后的偏好恢复和深色设置布局，最终恢复关闭／英语。证据位于 `runs/live-subtitles-mac/`，最终新包截图为 `final-new-build.png`；没有把初版截图作为最终包证据。

iPhone 17／iOS 27.0 模拟器：最后源码后新的 `DeviceInteractionInstallAndRun` 成功，并捕获 Running 状态。首轮截图遇到一次 `Session not found`，单次重试后成功。结束 Device Hub 后由单一设备负责人使用 AXe，完成“设置 → 翻译与字幕 → 来源语言”的实际交互：四项可见、选日语后值更新、恢复英语、返回设置页。模拟器显示“当前设备不支持实时字幕”，开关保持关闭；原尺寸可见区域无明显裁切或重叠。当前环境没有 `jev-ios` CLI，因此本轮没有 JEV scenario 通过记录。报告与截图位于 `runs/live-subtitles-ios/`，所有 Device Hub session 已结束。

Apple TV 4K（第 3 代）／tvOS 27.0 模拟器：最后源码后另建 workspace session，`DeviceInteractionInstallAndRun` 成功；随后捕获 Running 首页与“立即观看”焦点，证明新包启动。两次有效捕获后遥控器操作返回 `Session not found`。同一持续运行的 bridge 内进行一次完整重试，Start 返回新的 key，但紧接的 InstallAndRun 返回 `Session with that key doesn't exist`；已核对请求字段符合当次 schema，且使用的 key 与新返回值完全一致。停止交互，End 返回 session 已不存在，恢复 `AngelLive`／iPhone 17 运行目标。设置入口和字幕相关焦点仍被 session 故障阻塞，不能计作通过。原始响应为 `/tmp/angellive-subtitle-tvos-final-mcp-5.json` 至 `-13.json`；新包首页证据位于 `runs/live-subtitles-tvos/07-home.png`。

仍未验证：iOS／tvOS 真机语音能力和真实直播中的字幕显示、字幕与控制区的画面关系、tvOS 设置及字幕交互、额外浅／深色组合。当前只证明 macOS 的真实转写链路、三端构建和上述实际交互，不将这些结果扩大为三端真实字幕通过。

### 2026-10-02 翻译补齐与推送前状态

macOS 实际直播播放器曾显示 Apple 识别的英语字幕，原图为 `runs/live-subtitles-mac/2026-10-02/live-caption-retry.png`；这张图仅证明原文识别和字幕覆盖层，未显示中文翻译。该播放源随后出现起播超时，稳定性未计作通过。

随后增加字幕翻译 pipeline，复用既有 Apple／兼容 AI provider，自动翻译不触发语言包下载。Speech 结果携带片段 ID，同片段更新合并，换段／配置变化／退出取消旧任务；成功显示译文，等待或失败回退原文，错误复用原有短提示。Core 新增 5 项状态与取消测试已通过。用户要求停止截图并推送，因此最新字幕翻译尚无最终 workspace 三端构建及真实中文字幕画面证据，前述三端构建结果只对应翻译补齐前的源码。

### 2026-10-04 已安装资源策略与原文回退修复

本轮在 macOS 27.0（26A5425a）复现：英语到简体中文的系统默认资源为 `installed`，低延迟资源为 `supported`；强制低延迟的 `installedSource` 调用实际返回 `TranslationError.Cause.notInstalled`。此前共享 provider 固定检查低延迟资源，因此没有使用已经安装的默认资源。

修复落在共享 Apple provider：按语言对与策略分别缓存资源状态，自动执行优先选择已安装的低延迟资源，否则使用已安装的系统默认资源。标题、弹幕与字幕遵守同一规则。显式下载单独核验下载策略，不由默认资源已安装推断低延迟下载完成。字幕覆盖层同时修正错误提示的优先级，翻译失败时保留原文；无字幕文本时仍显示短提示。

通过生产 `AppleRoomTranslationProvider` 与 `LiveSubtitleTranslationPipeline` 的独立原生联调，实际获得：

> Today we are checking the subtitle feature. → 今天我们正在检查字幕功能。

真实资源查询选中 `systemDefault`，并独立核对同策略 `installedSource` 会话的 `canRequestDownloads` 为 `false`；生产 host 使用对应的已安装资源会话完成上述翻译。没有下载模型、使用大模型接口或操作用户设置。此记录证明真实翻译管线，不是 App 播放器画面验收。原始结果在本地忽略目录 `runs/live-subtitles-native-chain-2026-10-04/` 的 `native-provider-pipeline-result.json` 及对应日志中。

最后生产源码经 Xcode 27.0 RC（27A266a）的 CLI workspace 构建通过 iOS `AngelLive`、macOS `AngelLiveMacOS`、tvOS `AngelLiveTVOS`，日志均显示 `BUILD SUCCEEDED` 且无 error。本轮没有可复用的 MCP 连接，未重新申请连接授权；这些明确记为 CLI 构建，不记为 MCP 构建或新包界面运行。构建日志与生产文件校验值位于 `runs/live-subtitles-build-2026-10-03/`。

同一轮 macOS 原生音频联调通过：中性合成视频由 KSME 解码，经生产 `LiveSubtitleSession` 输入 Apple Speech，实际识别出 `Today we are checking the subtitle`。测试在出现 `subtitle` 时停止等待，因此记录的是已识别片段，不能把上面的完整翻译输入当作这次 Speech 的输出。暂停后字幕清空、停止后识别任务退出且自身音频回调移除均通过。PCM 复制覆盖 2 组交错／非交错用例，连续转换覆盖 6 组采样率／声道组合；合计 3 项测试／1 组通过，耗时 7.089 秒。

音频测试使用 `swift test --build-system native --filter LiveSubtitleAudioTests`，显式设置中性 fixture 路径。默认 SwiftBuild 路径的 Metal 编译 shim 失败，改用工具仍支持的 native 构建后成功；没有修改 Xcode、系统工具或依赖版本。原始日志为 `runs/live-subtitles-build-2026-10-03/dependencies-live-subtitle-audio-swift-native.log`。Speech 联调与文字翻译联调为分别运行的真实阶段测试，尚不能视为一次 App 播放器内的完整字幕翻译验收。

将上述 Speech 的实际识别片段再单独送入生产翻译管线，得到 `Today we are checking the subtitle` → `今天我们正在检查字幕`，约 2.985 秒。该 1 项联调通过；结果 `native-provider-pipeline-from-speech-text-result.json` 明确标注为两阶段验证，并非同一次播放器／UI 端到端运行。

Core 定向验证：原生资源策略测试 11 项通过；字幕与资源组合 18 项／3 组通过，包含显式启用的真实翻译联调。全量并行回归保留了失败记录：首轮 395 项／52 组出现 2 个 issue，分别为插件敏感 Promise 的等待和弹幕云端排队断言，单独重跑各 1 项通过；音频编译结束后的全量再次运行出现 3 个 issue，集中在两项字幕测试的第二次调用等待及其后续断言，单独重跑字幕组 5 项通过。对应日志依次为 `core-all-tests.log`、`core-rerun-login-registry.log`、`core-rerun-danmaku.log`、`core-all-tests-final.log`、`core-final-rerun-live-subtitle-translation.log`，均在 `runs/live-subtitles-native-chain-2026-10-04/`。不能把定向通过写成全量并行通过，也不能仅据这些日志将失败归因为外部构建负载。

保持相同 Xcode RC 与默认构建后端，显式 `swift test --no-parallel` 的串行对照 exit 0，日志报告 395 项／52 组通过，耗时 35.767 秒；逐项开始／完成记录确认采用串行执行。真实翻译 opt-in 在该全量运行中默认跳过，已在前述 18 项定向运行中实际执行通过。日志为 `core-all-tests-explicit-serial-default-backend.log`。字幕失败项使用 2 秒墙钟轮询等待 provider 调用，串行通过与单组通过支持其对并行调度敏感，但不证明唯一根因；本轮保留该测试同步缺口，没有放宽超时或修改断言。

交付前全仓中立性复扫覆盖 712 个非忽略文件（627 个文本、85 个二进制连续标识检查），具体内容平台标识及测试数值映射命中均为 0；二进制未做 OCR。`git diff --check` 通过。原有 tvOS 工程签名配置改动保留，未纳入字幕修复。

本轮仍未验证 iOS 真机的语音识别与译文、最终新包的播放器字幕画面、字幕与控制区重叠及深浅色表现。macOS 原生应用自动化访问未获准后停止该路径；未重复申请权限，也未以旧包或历史截图补充最终界面证据。

### 2026-10-04 不依赖设备的测试收尾

修复上述字幕测试的等待方式：受控 provider 通过单消费者事件流通知请求到达，状态断言等待 Observation 变更，移除 2 秒墙钟轮询；测试结束先重置 pipeline，再恢复未决 continuation 并关闭事件流，防止失败路径继续启动待处理请求。每项测试使用框架的 1 分钟挂起上限，未改为串行执行。迟到结果、重置和配置变化的原有断言保留。

新增使用生产默认 600ms 节流的连续文本回归：首请求未完成时提交多个片段修订，只允许首条与最新待处理文本进入翻译。第二次请求相对首次 enqueue 的下限检查不依赖 actor 到达间隔，也不设完成耗时上界；这证明合并与节流逻辑，不代表实际直播的字幕延迟。

最终字幕定向 6 项／1 组通过，耗时 0.616 秒；默认并行 Core 全量 396 项／52 组通过，耗时 17.096 秒，两个命令均 exit 0。字幕组在全量并行运行中耗时约 13 秒，未再触发之前的固定等待失败。真实原生翻译 opt-in 在这次常规全量中跳过，沿用前述单独运行的真实联调证据。日志位于 `runs/live-subtitle-test-sync-2026-10-04/` 的 `core-live-subtitle-translation-targeted-final.log` 和 `core-all-tests-default-parallel.log`。此次仅修改测试与文档，生产源码校验值未变，未重复构建 App 或操作设备。

### 2026-10-04 同次播放器音频与翻译联合验证

将此前分别运行的识别和翻译阶段合并到一次测试：40.1 秒中性合成视频经 KSME 解码、生产 `LiveSubtitleSession`／Speech 识别，再将本次识别结果送入生产 `LiveSubtitleTranslationPipeline`／Apple provider，实际输出 `今天我们正在检查字幕`。播放器保持静音，未使用麦克风、云端服务或自动下载资源。

从本次识别任务启动计，首个原文 `Today we are checking` 为 1150ms，首个中文为 7509ms。暂停后原文清空，并按宿主语义重置翻译；恢复后重新识别及翻译成功。连续观察 30 秒产生 32 次不同识别更新、10 个片段；停止后任务退出并移除自身回调，定位视频起点、建立新识别 session 后再次得到中文并完成清理。这些仅为本机合成 fixture 指标，不代表真实直播延迟，也不包含 App 界面的字幕显示验收。

音频组 3 项／1 组通过，耗时 34.877 秒，其中联合链路 34.850 秒；PCM 复制的 2 个参数用例及重采样的 6 个参数用例同时通过。最终日志为 `runs/live-subtitle-audio-integration-2026-10-04/dependencies-live-subtitle-audio-integration-attempt3.log`，结构化结果为同目录 `integration-result.json`。前两次在测试编译阶段发现隔离声明问题，已修正测试；没有以编译失败作为运行结果，也未修改生产音频逻辑。

Core 继续补齐默认节流下的 reset、active／pending 请求随配置变更退役、英语／日语／韩语规范化、同语言直出、不支持来源及云端错误后恢复。超时另外通过生产 HTTP provider 与专用 URLProtocol 验证，未调用收费服务。定向 22 项／2 组通过，默认并行全量 400 项／52 组通过（17.642 秒）；日志位于 `runs/live-subtitle-core-matrix-2026-10-04/`。该全量中的真实原生资源 opt-in 项默认跳过，真实链路证据来自上文显式启用的联调。

首轮新增 reset 测试错误地假定主 actor 会在 600ms 内恢复，已改为同步安排取消并等待明确请求事件，保留原失败日志。最后独立复核又将下限基准统一为首次 enqueue 前时刻，排除 provider 调用传递开销；仅此基准变更后的定向 1 项通过（0.639 秒），日志 `reset-baseline-targeted.log`。没有因这次测试基准调整更改生产节流或扩大超时。

### 2026-10-04 首轮界面与共享依赖验收

Dependencies 最后共享源码的常规全量采用 Xcode 27.0 RC 和 native 构建后端，10 项／3 组通过（0.922 秒），PCM 复制与连续重采样、DLNA fixture 均执行。两个需要实际资源的 opt-in 默认跳过；字幕联合链路已在上文单独启用通过。日志为 `runs/live-subtitle-dependencies-final-2026-10-04/dependencies-full-native.log`。

iPhone 18 Pro／iOS 27.0 模拟器在最后修改后重新执行 workspace MCP `BuildProject`，111.325 秒成功，Error Navigator 为 0；随后新的 `DeviceInteractionInstallAndRun` 成功。本轮通过同一持续 bridge 操作，构建间隔导致旧设备 session 过期时重建设备 session，没有重启 bridge；不把过期或参数校验错误记为 App 失败。

新包实际验证：设置页面的模拟器“不支持”资源状态；播放器“更多 → 实时字幕”与齿轮“字幕语言与设置”两条路径；字幕开关及明确的不支持提示；英语切为日语并恢复英语；设置 sheet 在控制层隐藏后保持显示；横竖屏表单布局；合并弹窗路由后的原有主播详情入口。More 的两条 sheet 路由合并到稳定容器上的一个 item presenter，最终截图显示完整设置页正常打开。齿轮的早期未弹出尝试是控制层已自动隐藏、点击只唤起控件；采用确定性唤起后点击已通过，未据此修改原有齿轮交互。

模拟器的部分半屏 sheet 未进入 Device Hub 的 AX 层级，已通过原尺寸截图复核实际呈现。字幕关闭／英语／中文简体／Apple 原生的原始偏好、竖屏和原 Xcode 目标已恢复，设备 session 结束。结果索引为 `runs/live-subtitle-ui-2026-10-04/ui-acceptance-result.json`；本段验证的是 UI 和模拟器不支持反馈，不代表模拟器产生了真实识别或译文。

### 2026-10-04 最后共享源码与 macOS 实际中文字幕

设置中的真实资源检查发现：模型文件虽已安装，当前 App 尚未登记该语言时仍会显示缺少模型。本轮将登记与释放收敛到共享 `LiveSubtitleReservations`，资源查询、识别和下载使用同一套租约。并发用户共用登记；只释放本功能新建的临时登记；借用系统已有登记时接受系统语言变体且不释放它；用户显式下载成功后保留登记。登记失败单独显示暂时不可用。原生联调已删除测试侧的手动登记，避免绕过生产路径。

Apple 的“测试翻译”也采用已安装资源优先策略，仅在确实没有已安装的可用资源时进入可请求下载的系统会话。自动字幕始终使用已安装资源会话。本次 macOS App 中测试翻译直接得到 `一个中性的直播间标题`，没有出现不必要的语言包下载弹窗。

最后共享源码验证结果：

- Core 默认并行全量 **403 项／52 组通过**，52.335 秒。弹幕组额外定向 **12 项通过**；测试超时使用可控事件驱动，生产超时、节流与并发策略保持原样。日志位于 `runs/danmaku-timeout-determinism-2026-10-04/`。
- Dependencies native 后端全量 **20 项／4 组通过**，其中两个外部前置条件的 opt-in 默认跳过；共享登记 **10 项定向通过**。日志为 `runs/live-subtitle-reservations-2026-10-04/full-native.log` 与 `targeted-reservations-final.log`。
- 另外显式启用真实音频联合链路，**1 项通过，36.899 秒**：40.133 秒合成视频由 KSME 解码，经生产登记、Speech 与 Apple 翻译得到 `今天我们正在检查字幕`。首原文 1285ms、首译文 8466ms；暂停清空 113ms、恢复原文 1362ms；连续观察 30 秒有 32 次识别更新、11 个片段，停止、重新开始和退出清理通过。测试静音且不使用麦克风；这些是本机 fixture 数据，不是直播延迟。原始结果为同目录 `results.json`、`audio-integration-40s.log`。

macOS 使用 Xcode 27.0 RC（27A266a）workspace MCP 构建成功，79.416 秒，Error Navigator 为 0；`RunProject` 启动后核对了实际 Debug 产物路径和新进程。通过应用正常安装流程加载中性本机合成视频 fixture，真实播放器依次显示准备状态、英语原文和中文 `今天我们正在检查字幕。`。该阶段新包的原尺寸画面为 `runs/live-subtitle-ui-2026-10-04/mac-final-player-chinese-sentence.png`，AX 同步记录为 `mac-final-player-chinese-sentence-ax.txt`。不是 mock 字幕或独立测试窗口。

该新包还实际完成：字幕关闭后清空、重新开启后恢复；暂停清空与继续播放；关闭并重新打开播放器后恢复识别；齿轮菜单进入完整设置；原有视频信息统计仍可用。设置中将来源切换到尚未安装的日语，显式点击下载，观察真实进度 0%、46%、86% 到“已就绪”；退出设置后重新进入仍显示就绪，最后恢复英语。截图为 `mac-final-speech-download-progress.png`、`mac-final-japanese-model-ready.png`、`mac-final-video-statistics.png`。本次实际界面采用深色，未将它写成 macOS 浅色验收。

字幕关闭、英语、中文简体、Apple 原生及标题／弹幕翻译关闭的原始配置已恢复。仅本轮临时插件和订阅源已通过 App 移除，安装数回到原来的 17 个、订阅源回到 1 个，本机 fixture 服务已停止。显式下载的日语系统语音模型保留，不删除系统共享资源。

### 2026-10-04 最终 iOS 模拟器回归

最后共享源码与 iOS 界面修改后，Xcode 27.0 RC 的 workspace MCP `BuildProject` 成功（96.537 秒），Error Navigator 为 0；iPhone 18 Pro／iOS 27.0 随后完成新的 `DeviceInteractionInstallAndRun`。本轮原始响应为 `runs/live-subtitle-ui-2026-10-04/response-305.json`、`response-306.json`、`response-308.json`。

新包完成深色及最大辅助功能字体下的完整设置页、四种来源语言、实际选择日语并恢复英语、播放器更多菜单开关、齿轮字幕设置 sheet 和返回播放／首页。开启后显示可读的模拟器不支持反馈，关闭状态与英语选择正确同步；原尺寸截图核对了换行、表单内容及 sheet。首轮已覆盖浅色、常规字体、横竖屏和原有主播详情入口，第二轮覆盖最后源码及新增外观／字体组合。

最后恢复本轮开始时的浅色、large 字体、字幕关闭、英语及竖屏，退出播放并结束设备 session；设备保留原来的 Booted 状态。恢复首页与结束响应为 `response-336.json`、`response-337.json`。本机 JEV／AXe 不可用，因此使用 Device Hub；未声称 JEV 场景通过。模拟器不支持真实 Speech 字幕，本段只证明界面交互与明确的能力反馈。

### 2026-10-04 最终 tvOS 模拟器回归

Apple TV 4K（第 3 代）／tvOS 27.0 在本轮最后共享源码后完成 workspace MCP 构建（92.232 秒，error 为 0）及新的 `DeviceInteractionInstallAndRun`。通过 App 正常流程安装单个中性本机 fixture，实际进入 FullUI 翻译与字幕设置；四种来源语言可见，选择日语后正确返回来源按钮，再恢复英语。字幕关闭、模拟器不支持语音资源及 Apple TV 的兼容 AI 翻译说明均可读。本轮没有配置真实 AI 凭据或调用收费服务。

验收发现半屏设置按 Siri Remote Menu 返回时焦点跳到第一个菜单项，随后在 FullUI 的 `selectedIndex` 收起边界恢复原项焦点。此修改后再次构建成功（44.182 秒，error 为 0），并完成新的安装启动。最终包验证字幕页返回、立即 Select 再次进入，以及通用设置返回，均恢复对应菜单项。root 已复核 hierarchy 及稳定原尺寸截图；详见 [TVFocusAndRemoteNavigation.md](TVFocusAndRemoteNavigation.md) 的本日记录。

仅本轮 fixture 和本机订阅源已通过 App 正常删除流程移除；最终稳定页面不再包含该插件／来源，恢复初始无插件状态。设备 session 正常结束，tvOS 模拟器恢复原先的 Shutdown，iOS 模拟器保持原来的 Booted。清理与结束响应为 `runs/live-subtitle-ui-2026-10-04/response-414.json` 至 `response-416.json`。此结果不代表实体 Apple TV 语音识别或 AI 翻译已通过。

### 2026-10-04 macOS 菜单收尾与锁屏边界

同日后续 TODO 实施增加首页、同步和播放诊断功能后的最终构建及设备覆盖，集中记录在 [TODO 实施与验收](archive/TODOProgress20261004.md)。下文字幕画面仍对应各自当时的新包，不作为后续最后包的 macOS 界面证据。

正常清理测试记录时复现：历史页外层的删除菜单被 `LiveRoomCard` 内层收藏菜单覆盖，封面和标题右键都只显示收藏。现将可选的删除历史回调传给卡片，在唯一上下文菜单中同时呈现收藏和删除；其他调用者默认为 nil，不增加删除项。

该修改后，workspace MCP 构建成功（98.867 秒），Error Navigator 为 0；`RunProject` 成功（23.948 秒），并核对新进程运行于本次 Debug 产物。原始结果为 `runs/live-subtitle-ui-2026-10-04/response-212.json` 至 `response-214.json`，复制后的日志为 `mac-post-history-build.log` 和 `mac-post-history-run.log`。原有九个字幕生产文件校验值未变，另保存全部十二个生产修改文件的校验值到 `final-production-with-ui-fixes-sha256.json`。

原生界面工具随后返回 Mac 已锁定且无法自动解锁，因此本轮没有取得菜单修复后的界面证据。以下项目保持未完成：新菜单的封面／标题右键和实际删除、日语模型在 App 重启后的就绪显示、macOS 浅色界面，以及此最后包的中文字幕截图。上文真实中文字幕是本轮相同字幕源码在菜单修改前的新包证据，不将其冒充最后包截图。

Mac 上的临时插件与订阅源此前已移除，但尚有一条本轮 fixture 历史记录，须解锁后通过修复后的菜单删除；未清空其他历史。最后启动的 App 已用 MCP 正常停止，临时本机媒体服务已停止。没有修改系统外观、账号、权限或共享模型来绕过锁屏；已向用户说明只需解锁，无须再次授权。

### 待真机可用后的验收

用户已说明真机需次日才可提供，真机验收另行执行。真机可用后，按以下顺序记录最终新包的实际结果；模拟器布局和 macOS 合成视频链路通过不替代手机真实直播验收。

- 记录实际设备、系统、构建及安装结果，先检查已有模型，不自动下载资源或更改账号配置。
- 在同一次播放中观察音频识别、中文翻译和字幕显示，分别记录首条原文、首条译文及连续更新的延迟。
- 覆盖持续讲话、长句修订、停顿与字幕清空，再检查暂停恢复、切换房间／播放源、前后台及退出后的清理。
- 检查横竖屏、控制层显隐、大字体及浅／深色，确认字幕不被裁切、不遮挡关键控件。
- 按设备已安装资源覆盖默认／低延迟策略；缺少模型、下载后返回、其他来源语言和 AI 引擎单独记录，未运行的组合保持未验证。

## 官方参考

- [Discover generated subtitles and subtitle styles（WWDC 2026）](https://developer.apple.com/videos/play/wwdc2026/256/)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer（WWDC 2025）](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)

本次 UI 参考现有三端“翻译与字幕”页面及 SwiftUX conventions；SwiftUX 未返回匹配的字幕覆盖组件，沿用现有页面样式实现。

## 2026-10-25～26 可用性修复与本轮验收

本轮证据集中于被忽略的 `runs/translation-availability-20261025/`，总索引为 `verification.json`。不沿用上面历史记录宣称本次真机或译文已经通过。

- Core 定向 48 项／3 组通过，全量日志汇总 627 项／78 组通过；原生翻译 opt-in 在常规全量中默认跳过。新增检查覆盖缺云配置不发送字幕、补齐配置后恢复、同语言无需翻译配置、缺密钥和安全存储失败。日志为 `core-targeted.log`、`core-full.log`。
- Dependencies 最后源码全量日志汇总 37 项／8 组通过，两个外部前置 opt-in 默认跳过，日志 `dependencies-full-final-fixed.log`。中间一轮 UI 泛型约束因依赖的 `Image` 别名产生编译歧义，Astra 已限定为 `SwiftUI.Image` 后重跑成功；首次失败日志 `dependencies-full-final.log` 保留。
- 另行显式启用 40 秒中性合成音频联合测试，实际因本机默认英语到中文简体翻译资源未安装而失败，未自动下载；`native-audio-translation.log` 保留该 1 项前置失败，不计为翻译成功。设置中的语音模型“已就绪”不能推导为文字翻译语言包已就绪。
- 本机 iPhone 15／iOS 27.0（24A437）已配对且开启开发者模式，Xcode 将其列为可用运行目标；Device Hub 仍拒绝选择物理设备，仅返回模拟器候选（`device/response-107.json`、`response-108.json`）。因此本轮没有手机真机转写或译文证据，也未通过更换签名、复制容器或其他方式绕过前置条件。
- Xcode 27.1（27A9275）可见设置 `Allow External Agents to Use Xcode Tools` 原本已为 `Always`，未更改隐藏权限；新 bridge 连接时出现的 Allow 按本轮用户授权处理。设置截图为 `device/xcode-intelligence-always.png`。

UI 由 `gpt-6-astra / high` 实际修改，设备由 `gpt-6.1-sol / high` 单一负责人操作，root 独立复核 diff 和新包证据。参照三端原有翻译设置行、footer 和播放器短提示；macOS／tvOS 保留原有默认标签布局。

iOS 首轮新包 `InstallAndRun` 成功后，root 在 `device/ios-apple-light.png` 及对应 AX JSON 中发现实际差异：原页面同类行 60pt、文字 x=74pt，而字幕行 52.333pt、文字列不同。该结果作为失败证据保留。Astra 随即将共享 Section 改为三个标签插槽，iOS 三行直接传入现有 `TranslationSettingLabel`，复用 30×30pt 图标、字号及 12pt 间距，不添加固定行高或偏移；启动与持久化语义保持原样。最终新包复验结果在本节后续记录中列明。

iOS Device Hub 首轮及恢复后的 session 均在安装成功后失效，相关 `Session not found`、重新关联和结束响应保存在 `device/response-111.json` 至 `response-122.json`。JEV 未安装；结束旧 session 后由同一设备负责人通过现有 AXe／原生 Device Hub 窗口交互回退，复用已确认的新包。整改后的 workspace MCP build 为 `response-123.json`（21.553 秒）、Error Navigator 为 `response-124.json`（0）；随后最后源码 `InstallAndRun` 为 `response-126.json`，主动结束 session 为 `response-127.json`，均返回成功。安装成功仅证明新包运行，布局必须另行核对。

仍待验证的能力包括：手机真机同次播放的语音与译文、当前缺失资源下的实际译文、配置真实云服务后的在线翻译，以及未取得新包证据的播放器长提示、额外尺寸／动态字体／外观组合。用户仍在考虑手动启动方式，本轮未改成每次进房默认关闭。

### 最终 iOS 设置行复验

上述最后源码 `InstallAndRun` 后的新包截图为 `device/ios-final-apple-light.png`，AX 为同名 JSON。root 独立查看原图并递归提取 frame：顶部两项自动翻译、目标语言、字幕开关、来源语言、语音模型共六行均为 60pt 高、370pt 宽、x=16pt；六行文字均 x=74pt、文字框高约 20.333pt、相对行顶 y≈19.833pt。图标采用相同 30×30pt 容器及现有字号，截图中控件边缘、文字基线与对齐列一致，长 footer 正常折行；该浅色标准字号状态通过。结构化量测为 `ios-final-geometry.json`。这些设置证据不代表真实字幕或译文输出已通过。

root 另行检查 `device/ios-final-llm-light.png`、`ios-final-llm-dark.png` 和 `ios-final-llm-dark-large.png`：标准深浅色下缺配置说明及禁用的测试按钮可见，较大字号下字幕行、资源值和长说明没有观察到裁切或重叠。这仅覆盖上述有限组合，不扩大为最大无障碍字号、全部 iPad、方向或播放器状态通过。

界面收尾期间原生工具返回 `Mac is locked and automatic unlock could not unlock it`，已请求用户解锁，未尝试绕过桌面锁定。iOS 模拟器已恢复浅色和原字号，接口地址、模型及密钥未修改；仅测试期间临时选择的大模型引擎尚待解锁后恢复为原 Apple 引擎，该恢复在未完成前必须明确保留为待办。锁屏阻塞与 Device Hub session 失效分别记录，MCP 构建仍可继续。

### 最终 tvOS 设置与焦点复验

`AngelLiveTVOS` 最后源码 workspace MCP build 成功（50.977 秒，`device/response-130.json`），Error Navigator 为 0（132）。首个设备会话在安装前失效，恢复后的 `InstallAndRun` 135 成功，136 捕获 `Running`；这些明确属于最后源码新包。设备为已有 Apple TV 4K（第 3 代）／tvOS 27.0 模拟器，未创建或克隆设备。

root 独立查看 `device/tv-final-apple.png`／`.txt` 和 `tv-final-llm.png`／`.txt`：既有同类 Toggle 行为 66pt，设置主列和说明对齐；字幕禁用状态、“请在真机上使用”及详细原因完整。向下导航后服务地址字段的 `Focused` 状态可见，云端缺配置原因与数据范围说明完整（说明块约 131.5pt 高），测试按钮为 `Disabled`，没有观察到文字裁切或重叠。顶部“自动翻译房间标题”Toggle 与服务地址字段的焦点路径取得实际证据；禁用的实时字幕 Toggle 没有被当作可聚焦或已开启。未输入／保存配置、发送真实翻译请求、下载资源，亦未以导航过程中经过播放页作为字幕输出证据。

### 构建收尾与仍未完成项

| 平台 | 最后源码 workspace MCP 构建 | 新包界面与交互 |
| --- | --- | --- |
| iOS `AngelLive` | 通过，21.553 秒，Navigator error 0 | iPhone 17 Pro／iOS 27.0 模拟器的上述设置与有限外观／字号组合通过；不代表真机播放通过 |
| tvOS `AngelLiveTVOS` | 通过，50.977 秒，Navigator error 0 | Apple TV 4K／tvOS 27.0 模拟器的上述设置及有限焦点路径通过 |
| macOS `AngelLiveMacOS` | 通过，19.014 秒，Navigator error 0；Run 成功并核对实际产物进程 | 最后源码新包截图受桌面锁屏阻塞，视觉验收未完成；前次 Mac 图片不能替代 |

macOS 最终构建／诊断／运行／停止分别为 `device/response-151.json` 至 `response-154.json`，原始日志已保存为 `mac-final-build.log` 与 `mac-final-run.log`。所有设备 session 已结束，本轮启动的 iOS／tvOS 模拟器均已关闭（`device/final-booted.json`）；没有创建、克隆、重命名或清空设备。Xcode 已恢复原先 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)`（155、156），本轮 bridge 已正常退出。原有 `AGENTS.md` 和 iOS scheme 修改保留，未纳入本轮编辑。

截至本轮交付，**代码修复与上述常规测试／有限设备验证已完成，整体验收仍未完成**：需解锁 Mac 后恢复 iOS 测试引擎并复核最后 Mac 新包界面；手机真机完整链路、安装翻译资源后的实际译文、真实云端服务及播放器提示气泡仍缺证据。桌面锁定已由原生工具错误和只读 IORegistry 状态共同确认（`lock-state.json`），没有尝试绕过锁定。完整逐项状态在 `device/verification.json`；用户仍在考虑的手动启动方式不由本轮擅自决定。

最终全仓检查覆盖 832 个 Git 清单文件：739 个文本及 93 个二进制文件。文本歧义词、压缩媒体载荷中的短字节偶合均已人工复核，记录词表内实际具体内容平台标识与测试数值映射命中为 0；未做二进制 OCR，不对未知标识作绝对保证。清单、词表、数值候选和二进制复核分别在 `platform-neutrality-text.json`、`binary-full-scan.json`、`binary-scan-review.json`。`git diff --check` 通过。

### 2026-10-26 上午解锁后续验与现场恢复（当前状态）

用户回复继续后，原生界面已可正常操作。源码、测试及文档的 12 份记录指纹在恢复开始时均与前次最终记录一致，因此复用已安装的 iOS 新包和已有 macOS 最终产物，没有重跑已通过的单元测试或三端构建。新证据位于 `runs/translation-availability-20261025/resume-20261026/`。

macOS 通过本次 workspace MCP `RunProject` 再次启动（203，5.529 秒，build errors 为空），实际进程路径已核对为本仓库 Debug 产物。root 独立复核 `mac-final-apple.png`／`.txt` 和 `mac-final-llm.png`／`.txt`：同类开关、选择器、模型状态的控件和文字列与原页面一致，长说明正常折行；语音模型已就绪，文字翻译语言包仍显示下载；大模型缺地址／模型／API Key 的原因完整，测试按钮禁用。该默认尺寸、深色的有限设置视觉复核通过，补齐了夜间的最后源码 Mac 截图缺项；额外窗口尺寸、浅色及播放器字幕气泡未因此计作通过。Mac 引擎已通过正常 UI 恢复为 Apple，见 `mac-restored.txt`。

iOS 正常交互路径仍受工具故障阻塞：Device Hub 持续等待显示连接，AXe 创建远程自动化 session 超时；模拟器插件输入依赖的 SimulatorKit 路径在当前 Xcode 27.1 中不存在，未成功发送触摸。已有标准设备的启动过程中还观察到非预期自动关机，原因未确认；没有为此创建新设备、清空数据或修改 Xcode。原始摘要为 `ios-input-blockers.txt`，本次恢复后的 iOS 界面未计作新通过。

在设备完全 Shutdown、设备负责人停止输入并交接后，root 核对 App 容器身份和当前源码的 `roomTranslation.engine` 契约，将临时值 `llm` 单项恢复为原 `apple`。原子写入前后完整键集合、除该键以外的全部偏好值及原 POSIX 权限检查通过；随后用 Apple Foundation 的 `PropertyListSerialization` 独立读取确认持久化值为 `apple`。凭据及插件存储未编辑，完整偏好内容未复制到报告。结果及过程中未通过的严格元数据检查均保存在 `ios-engine-restoration.json`，Foundation 结果为 `ios-engine-foundation-verification.log`。这证明已清理测试偏好残留，不替代恢复后界面截图。

本次 App、模拟器及 bridge 均已关闭，Xcode 原 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)` 已恢复（204～206），原浅色及字号保留。设备负责人交接时的状态见 `device-report.json`；其中 iOS “交给 root 恢复”的历史状态由随后 `ios-engine-restoration.json` 的成功结果补齐。

**当前没有待恢复的测试引擎偏好，三端设置页的上述有限新包视觉验证已覆盖。** 手动启动方式仍按用户此前“再想想”的意见未改；手机真机语音／译文、安装翻译资源后的实际译文、真实云端请求和播放器提示气泡仍未验证，不能宣称整个字幕翻译链路已通过。

### 2026-10-26 大模型平台替代引导

用户进一步明确，重点是提醒不能使用 Apple 原生翻译的用户改用大模型平台。本次仅补充提示和对应回归检查，字幕启动与持久化语义保持原样；没有新增自动引擎切换、自动云端请求或语言包下载。

Apple 原生翻译不支持、语言资源缺失或翻译服务失败时，保留具体原因，附上“翻译与字幕”→“翻译引擎”→“大模型翻译”的操作路径，并要求填写服务地址、模型名称和 API Key，再主动点击“测试翻译”。tvOS 直接指向页面下方的平台配置，因为该端没有引擎选择器。大模型自身失败、来源语言受限、凭据错误和排队状态继续使用各自提示，避免循环推荐。旧请求在用户切换引擎后仍受原有取消和版本检查约束，不回写过期引导。

播放器沿用现有两行短提示：Apple 失败且适合改用大模型时显示“保留原文，可改用大模型。”；详细配置步骤在设置中说明。实时字幕说明同时明确，大模型文字翻译不能替代本机语音识别，因此不支持本机识别的设备不能仅靠更换翻译引擎恢复语音字幕。没有新增设置行或改变已复验的标签布局。

本次证据位于 `runs/translation-fallback-guidance-20261026/`。Core 定向 37 项／2 组、全量 631 项／78 组通过；Dependencies 全量 37 项／8 组通过，其外部前置 opt-in 默认跳过。新增测试覆盖 Apple 与大模型错误的区别、统一配置指引、显式／自动翻译失败，以及切换引擎后过期请求不能回写旧引导。真实云端配置和在线请求仍未验证。

最后源码三端 workspace MCP 构建均通过：iOS 20.201 秒（305／306）、macOS 18.674 秒（322／323）、tvOS 23.205 秒（329／330），三端 Error Navigator 均为 0。对应新包通过 MCP 安装／运行后取证，前一节旧图仅作视觉参考。

root 独立查看 iOS `device/ios-guidance-top-stable.png`、`ios-guidance-footer.png`、`ios-guidance-test-stable.png` 及 AX：同类六行均为 60pt，文字 x=74pt，基线与控件列保持一致；新增说明和完整配置路径折行正常。主动点“测试翻译”后出现模拟器不支持的具体原因及完整大模型设置步骤，Apple 引擎仍保留，没有云端请求。初次 `ios-guidance-top.png` 恰在 push 动画中，已保留为非验收截图；稳定重拍后未观察到布局问题。

macOS `device/mac-guidance.png`／`.txt` 中，新引导完整显示在原语言包说明区域，同类控件与文字列保持一致。尝试缩窄窗口后原有 600pt 最小宽度的 sheet 尺寸未变，记录在 `mac-guidance-narrow-attempt.png`；没有修改窗口策略，也不声称额外窄宽状态通过。Mac 未切换引擎、测试翻译或下载语言包。

tvOS 恢复后的新包截图为 `device/tv-guidance-top.png`、`tv-guidance-platform.png` 及同名 AX：翻译引擎说明完整两行，与服务地址等说明列对齐；顶部房间标题开关及下方服务地址字段取得实际焦点，缺配置的测试按钮禁用，未观察到重叠或裁切。首次会话中断及恢复响应均保留，不把过期 session 当作成功。本次没有输入或保存真实配置，也没有启动直播来代替提示验收。

本次新增提示的上述三端有限新包视觉与交互复验通过。手机真机语音与译文、安装资源后的实际译文、真实云端请求和播放器气泡仍缺本次运行证据；额外设备尺寸、外观及最大无障碍字号未扩大为通过。完整状态、源码指纹及全仓中立性复核在本轮 `verification.json` 和 `platform-neutrality-text.json` 中。

### 2026-10-26 房间级手动字幕与实际文本翻译（手选方案后已替换）

用户已确认本方案，取代此前仍在考虑的全局字幕启动语义。字幕每次进入房间关闭，明确选择语言才开启；同房间切换播放源保留选择，成功换房和真正退出时清除。设置页不再提供全局字幕开关，只管理语音资源语言和模型。每个窗口的房间状态独立，持久化的上次语言不作为新房间的已确认语言；旧面板动作由 activation ID 拒绝。覆盖层重建只负责取消识别和翻译任务，不清除房间意图；旧任务返回后还检查取消状态和当前 session 身份。

标题和弹幕保留各自手动开启的全局开关，按标题或每个弹幕文字片段的实际内容检测语言；移除这两条路径的英日韩白名单，保持原置信度判断。无法确定、与目标语言相同或失败时保留原文；语音字幕的四种可选语言及常用语言包目录不因此扩大。不修改插件协议，也不新增国家、地区或平台到语言的映射。macOS／tvOS 既有插件目录条件仅用于 FullUI／ShellUI 边界，Shell 直连播放不经过房间弹幕管线。

原生弹幕翻译失败通过宿主已有系统消息或短提示，提醒在“翻译与字幕”中配置大模型；字幕和设置继续使用已实现的替代引导。弹幕提示按当前配置与运行代次去重，取消、排队繁忙和消费者超时不触发替代建议。不会自动切换引擎、下载模型或向新服务发送内容。

本轮证据位于 `runs/translation-room-manual-20261026/`。字幕状态 4 项、文本相关 48 项／3 组通过；Core 全量 641 项／78 组、Dependencies 全量 37 项／8 组通过，外部资源联调 opt-in 默认跳过。首次全量中的新语言测试与短消息预算耦合、第二次全量中的原有诊断测试固定等待 50 毫秒，分别改成逐条受控消息和实际停止事件等待，均只调整测试；失败日志 `core-full.log`、`core-full-final.log` 保留，最终全量为 `core-full-verified.log`。生产默认消息时限未改。

UI 实现为 `gpt-6-astra / high`，沿三端现有菜单、系统语言确认框和设置行；SwiftUX 单一选择组件检索为 weak match，没有引入不匹配的外部布局。最后生产源码已冻结；三端新包构建、设置行对齐及播放器手动选择／取消／换房等交互尚在验收，前轮截图不作为本轮通过证据。真实云端请求和手机真机完整字幕链路仍未验证。

### 2026-10-26 自动音频语种检测与真实字幕链路

用户纠正并授权后，播放器入口改为直接“开启实时字幕”。房间状态不再要求先有语言才算开启；首轮由播放 PCM 检测语言，只有有效语音在延长窗口后仍不确定才显示语言列表。列表使用系统实际支持的 Speech 目录，检测与转写来源为动态语言 identifier，不限制旧四种候选。原资源语言偏好仅留在独立的语音资源管理页，不参与检测。

Dependencies 引入固定 SHA256 的官方 whisper.cpp XCFramework；多语种 tiny 与 Silero VAD 模型使用固定仓库提交、大小和 SHA256，约 79 MB。用户主动点击下载后才联网；临时文件校验后原子安装，取消保留已安装资源。模型推理在共享 actor 串行进行并释放 C 上下文，不占用主 actor。tvOS 使用可被系统清理的缓存目录，清理后明确要求重新下载；其他端使用不备份的应用支持目录。

一条 PCM 消费链将音频转为 16 kHz 单声道，按采样数保留最多 8 秒；推理期间继续接收音频，转写就绪后顺序消费预录与实时输入。没有人声时继续等待，不默认英语，也不弹语言选择。资源缺少、下载中、模型故障、Speech 设备／语言不支持与语种不确定分别处理；另一窗口的资源下载结束后可继续。关闭、换房、旧面板与迟到推理结果受 activation ID、Session generation 和覆盖层身份共同保护。

最终 Core 全量 645 项／78 组通过（13.302 秒），Dependencies 全量报告 52 项／10 组，其中实际 50 项通过、2 项外部 opt-in 跳过（5.343 秒）。后者实际执行了真实本地模型与自动字幕联调：没有传入来源语言，KSME 解码音频经生产检测器得到 `en-US`，4.605 秒输出“Today we are checking the local subtitle feature.”，停止后识别回调移除。测试没有下载资源、调用翻译 provider 或向云端发送音频／文本。

首次 Core 全量有一项既有短剧测试在并行编译压力下超过 60 秒；单独复查 31 项／2 组及最终完整回归均通过，未修改该功能。Dependencies 首轮测试宏用法及测试自行构造 Float32 的 Speech 输入分别导致编译失败和 signal 5；核验系统实际最佳格式为 Int16 后，只修正测试，生产始终使用系统返回格式。原失败、中止和 crash 证据保留。

最终空闲 Swift 实测中，四种干净合成语音的 4 秒窗口端到端检测为 0.162～0.402 秒，静音等四种负例为 0.009～0.012 秒；加噪韩语 2／4 秒保持不确定，8 秒识别成功。此前并行编译压力下单次最高 20.903 秒的证据也保留。以上仅为 Apple M4 本机样本，不代表直播语料准确率、手机／电视真机性能或功耗。

最后复核另复现了模型下载进度的迟到回调：独立 MainActor Task 可以晚于下载返回，导致已开始识别的状态被写回下载中。每个下载增加主 actor 生命周期保护，成功、异常、取消均等待关闭后再继续；三种场景先失败、修复后通过。修复后的 Dependencies 全量为 53 项／10 组，实际 51 项通过、2 项外部 opt-in 跳过（5.022 秒），包含真实模型与自动字幕链路；最后一次首条原文为 4.520 秒。

主要证据在 `runs/translation-auto-language-implementation-20261026/verification.json`、`source-freeze-v3.json`、`core-full-verified.log`、`dependencies-full-v3-verified.log`、`automatic-native-speech-v3-result.json` 和 `poc/REPORT.md`；UI 设计与设备记录在 `runs/translation-auto-language-20261026/`。最终三端新包与界面验收仍在收尾；Mac CUA 已两轮出现 `failedToCreateImageDestination`，不能据构建／启动宣称视觉通过。iOS 界面按用户要求延后。

最终 v3 的 workspace MCP 构建均成功：iOS 127.878 秒（851／856）、macOS 19.916 秒（858／859）、tvOS 27.597 秒（862／863），三端 Error Navigator 均为 0。Mac 860 Run 成功（3.834 秒），但原生 UI 工具仍在取得应用对象前失败；当前新包的设置与播放器视觉状态未验证。iOS 使用通用模拟器构建目标，没有操作用户正在使用的 iPhone 模拟器。

tvOS 在最后编辑后新建 864 session，865 `InstallAndRun` 成功，随后才取得截图。root 独立检查最终设置页、模型已就绪页与系统资源 sheet：左右文本基线对齐，管理按钮为同页既有的 66pt 高度，说明正常折行、无观察到的重叠或裁切。显式下载捕获了 0% 和“已就绪”，未捕获中间百分比，不宣称连续数值进度已经验收。单次 Menu 关闭资源 sheet 并恢复原管理按钮焦点；目标语言恢复为原中文简体，语音资源候选英语未变。单个中性样片实际播放，进入房间未出现字幕或语言／资源选择面板。

本轮界面验收仍未完成：tvOS 播放器上下文菜单需要长按 Select，而当前工具只公开短按，因此开启字幕、识别不确定后的语言面板及该入口的不支持提示均没有本次实际交互证据；不使用短按冒充长按。Mac 原生图像故障、用户延期的 iOS 界面，以及手机／电视真机语音与实际云端大模型连通性继续标记未验证。UI 由 `gpt-6-astra / high` 实现，有限状态的独立复核清单见 `ui-acceptance-final.json`；构建与逻辑测试不替代上述缺失验收。
