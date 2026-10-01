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

本节记录截至 2026-10-01 的文档提交状态，不代表功能已经完成验收。

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

## 官方参考

- [Discover generated subtitles and subtitle styles（WWDC 2026）](https://developer.apple.com/videos/play/wwdc2026/256/)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer（WWDC 2025）](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)

本次 UI 参考现有三端“翻译与字幕”页面及 SwiftUX conventions；SwiftUX 未返回匹配的字幕覆盖组件，沿用现有页面样式实现。
