# 可选独立音频播放协议

状态：已接入默认 KSPlayer 的 FullUI 点播链路，宿主注册 `Host.capabilities.dualStream`。本轮完成三端构建、中性合成样本的新包交互与截图复核；真实来源、iOS/tvOS 真机及长时后台场景仍未验证，支持范围见下文。

## 资源声明

`getPlayback` 与 `refreshPlayback` 的 `LiveQualityDetail` 可包含：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `audioUrl` | 可选字符串 | 与主视频处于同一点播时间线的完整 HTTP/HTTPS 音频地址 |
| `audioUserAgent` | 可选字符串 | 音频请求 UA；空白或缺失时沿用主路 UA 解析结果 |
| `audioHeaders` | 可选字符串字典 | 独立音频请求头；缺失时为空，不继承视频 Cookie、Referer 等请求头 |

音频使用与视频相同的 `decryption` 声明。当前仅覆盖未加密或同一默认 CENC 密钥，不支持两路密钥不同、密钥轮换或许可证流程。密钥规则继续遵循[播放解密协议](PlaybackDecryptionProtocol.md)。

```json
{
  "roomId": "episode-a",
  "title": "第 1 集",
  "qn": 1,
  "url": "https://media.example.invalid/video.mp4",
  "liveCodeType": "flv",
  "liveType": "fixture.plugin",
  "playbackHints": {
    "isLive": false,
    "streamFormat": "dash",
    "selectionBehavior": "refreshOnSelect"
  },
  "audioUrl": "https://audio.example.invalid/audio.mp4",
  "audioUserAgent": "fixture-agent",
  "audioHeaders": { "X-Fixture": "audio-request" }
}
```

`streamFormat` 位于既有 `playbackHints` 中，用于描述实际主路格式。上例代表音视频分离的 MP4 输入；插件不得为选择某个播放器而伪造格式。

## 兼容与校验

- 三个字段缺失或为 `null` 时，保持原单流行为，原资源仍可自带音轨。
- 字段类型错误时拒绝该返回值，错误描述不保留输入值。声明了解密需求时，不得吞掉其校验错误。
- 空地址、相对地址、缺少 host 或非 HTTP/HTTPS 地址不加入音频播放计划；不改变原视频地址。
- 首期只接入现有解析结果 `isLive == false` 的资源，包括 `hlsVod` 的既有点播推断。插件应显式声明 `playbackHints.isLive: false`。
- 两路必须可 seek、具有相同时间起点；时长相近不等于时间线一致。首期不接入直播窗口漂移、独立时间偏移和多音轨选择。

## 能力协商

插件只在 `Host.capabilities.dualStream === true` 时采用独立音频返回值；否则使用插件已有的兼容单流结果。

能力来自宿主实际注册，Core 单独加载时默认为 `false`。JS getter 是动态只读值，已创建 runtime 可观察到后续注册。仅解析字段或单元测试通过不能作为注册依据。

注册范围为默认 KSPlayer 的 FullUI 点播入口。ShellUI、VLC 以及未实现的播放入口不能据此被宣告支持。该布尔值不承诺 PiP、远端投送、录制合流或语音字幕采集支持。

## 播放所有权与生命周期

- Dependencies 的组合播放器向宿主暴露一个逻辑播放器；视频为主时钟，音频播放器不创建第二个 `KSPlayerLayer`，不独立注册遥控命令或 Now Playing。
- 锁定版本的子播放器初始化仍会执行既有音频会话配置；宿主不为音频子路新增音频会话管理策略。
- 视频不等待音频。音频准备期间保持静音，确认对齐后才可发声；视频暂停、缓冲或 seek 时从路不得继续推进。
- 视频继续拥有业务时间线、结束事件与恢复状态；音频正常发声期间，通过 KSPlayer 的公开逐帧同步接口将视频渲染节奏对齐音频实际输出时间。重复、倒退或不可用的音频时钟立即撤回，视频恢复自身时钟，不通过反复 seek 音频追赶。
- seek、倍速、音量、应用静音、前后台和中断遵循同一播放意图。异步结果必须核对资源与操作代次，旧结果不能恢复新会话的声音。
- 换集、换线路、刷新 URL 或密钥时整体替换两路资源，不继承上一批音频地址、请求头或密钥；先停旧声音再释放实例。
- 音频失败只终止从路，本批次不自动重试、不触发主路恢复或重取流。视频恢复预算保持原有语义。
- 音频自然 EOF 与失败分开处理，不触发换集；之后用户向后 seek 或重播，应能重新对齐音频。视频正常结束决定逻辑播放结束。
- 首期不新增周期音频 seek 或独立重试计时器；逐帧等待与丢帧复用锁定内核的原有规则。

## 呈现与诊断边界

独立音频首期不开放 PiP 或远端播放，避免只转移视频。FullUI 的 AirPlay/DLNA 入口需按当前实际播放计划限制；不改变普通单流的既有入口。

诊断仅记录固定事件、终止原因和有限数值。音频地址、签名、请求头、原始错误正文和密钥不得进入日志。播放解析继续复用既有敏感调用日志抑制；通用结构化控制台识别并隐藏 `audioUrl` 与 `audioHeaders`。

## 验证与开放门槛

1. Core：旧响应兼容、字段校验、路由、请求参数、刷新替换、能力注册与日志保护。
2. Dependencies：可控播放器回归，以及实际独立加密音视频的自然播放、连续 seek、倍速、暂停、EOF、重播和资源释放。
3. 宿主：受影响五个共享 scheme 构建，三端最后编辑后的新包播放与交互证据。iOS/tvOS 使用 Device Hub；macOS 使用实际构建产物原生运行。
4. 同步验证应记录自然推进和控制操作后的漂移范围；仅有 ready、seek 成功或音频数据解码不能证明音画同步。

临时样本必须为中性合成素材或明确授权的测试输入，不提交用户数据、私有插件、真实播放地址或凭据。
