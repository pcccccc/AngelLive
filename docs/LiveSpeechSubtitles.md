# Apple 原生实时语音字幕

## 目标与第一版范围

在 FullUI 的直播画面中显示主播语音的原文字幕，先采用 Apple 本机语音识别，不录制麦克风，不调用付费语音服务。字幕默认关闭，独立于房间标题和弹幕翻译开关。

设置复用现有“翻译与字幕”页面的分组、系统开关和选择器。固定提供英语、日语、韩语、中文普通话四种来源语言，由用户选择与主播一致的语言；是否可用及模型是否安装均查询系统真实状态。第一版不自动检测语音语言、不增加其他语言，也不将原文字幕自动翻译成中文。

语音模型与文字翻译语言包是两类资源，分别展示状态。模型仅在点击“下载”后安装，显示 Speech `AssetInstallationRequest.progress` 的真实百分比；打开直播或开启字幕不会自动下载。失败显示明确错误，不能把未完成安装当作就绪。

## Apple 能力选择

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

- `AngelLiveCore/Translation/LiveSubtitleSettings.swift`：本设备开关和来源语言，不影响标题／弹幕设置。
- `AngelLiveDependencies/LiveSubtitleSession.swift`：播放器音频桥接、格式转换、模型状态、显式下载和 Speech 生命周期。
- `AngelLiveDependencies/LiveSubtitleViews.swift`：共享设置行与字幕覆盖层，由三端 FullUI 页面使用。

不需要 API Key，不改变插件协议，不将音频、字幕或账号凭据写入日志、仓库及同步数据。

## 验收门禁与当前进度

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
- 另行显式启用原生联调，使用 macOS 官方语音合成的中性视频，KSME 解码音频经生产 `LiveSubtitleSession` 送入 SpeechAnalyzer，识别出“Today we are checking the subtitle feature”。暂停后字幕清空，停止后任务正常退出并移除自身音频回调；1 项／1 组通过，耗时 6.788 秒。日志 `/tmp/angellive-subtitle-native-tests.log`。这证明真实识别链路，不等同于手机直播画面已经验收。

该原生联调默认不运行，仅在设置 `ANGELLIVE_SUBTITLE_AUDIO_FIXTURE` 指向无敏感内容的合成视频时启用。需先在 App 中明确点击安装英语语音模型；独立测试进程先通过 `AssetInventory.reserve(locale:)` 登记所用语言，再查询资源。首次未登记时只读状态仍为 supported，测试按前置条件失败；登记后使用已安装资源成功，不触发自动下载。

macOS 27.0（26A428）：初版设置中点击英语模型下载，观察到真实进度由 0% 增至 26%，随后显示“已就绪”。来源切换为日语显示“尚未下载”，切回英语仍为“已就绪”。最后源码后的 MCP `RunProject` 再次成功，实际进程已核对为本次 Debug 产物；新包复核英语模型就绪、字幕开关开／关、重启后的偏好恢复和深色设置布局，最终恢复关闭／英语。证据位于 `runs/live-subtitles-mac/`，最终新包截图为 `final-new-build.png`；没有把初版截图作为最终包证据。

iPhone 17／iOS 27.0 模拟器：最后源码后新的 `DeviceInteractionInstallAndRun` 成功，并捕获 Running 状态。首轮截图遇到一次 `Session not found`，单次重试后成功。结束 Device Hub 后由单一设备负责人使用 AXe，完成“设置 → 翻译与字幕 → 来源语言”的实际交互：四项可见、选日语后值更新、恢复英语、返回设置页。模拟器显示“当前设备不支持实时字幕”，开关保持关闭；原尺寸可见区域无明显裁切或重叠。当前环境没有 `jev-ios` CLI，因此本轮没有 JEV scenario 通过记录。报告与截图位于 `runs/live-subtitles-ios/`，所有 Device Hub session 已结束。

仍未验证：iOS／tvOS 真机语音能力和真实直播中的字幕显示、字幕与控制区的画面关系、tvOS 安装及遥控器焦点、额外浅／深色组合。当前只证明 macOS 的真实转写链路和三端构建，不将这些结果扩大为三端真实字幕通过。

## 官方参考

- [Discover generated subtitles and subtitle styles（WWDC 2026）](https://developer.apple.com/videos/play/wwdc2026/256/)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer（WWDC 2025）](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)

本次 UI 参考现有三端“翻译与字幕”页面及 SwiftUX conventions；SwiftUX 未返回匹配的字幕覆盖组件，沿用现有页面样式实现。
