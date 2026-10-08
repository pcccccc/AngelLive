# 播放解密参数协议

插件取得播放地址与解密密钥后，在对应的 `LiveQualityDetail` 中返回可选的 `decryption` 对象。宿主接收并验证参数，通过共享播放适配层交给 KSPlayer 的 FFmpeg 内核；宿主不实现视频解密算法。

## 插件返回字段

```json
{
  "decryption": {
    "method": "cenc",
    "key": "00112233445566778899aabbccddeeff"
  }
}
```

这里的密钥仅为合成示例。字段放在每个 `qualitys` 元素中，与该元素的播放 URL 对应；不能放在请求头、URL 查询参数或 `requestContext` 中。

- `method`：当前仅支持字符串 `cenc`。
- `key`：16 字节密钥的 32 个 ASCII 十六进制字符，接受大小写并在宿主中统一为小写。不接受空白、`0x` 前缀、Base64 或其他长度。
- 未提供 `decryption` 或值为 `null`：沿用未加密播放流程，旧插件无需增加字段。
- 声明了未知方法、缺失字段、错误类型或无效密钥：拒绝该播放返回值，错误描述不包含密钥。解密需求不能像建议性的 `playbackHints` 一样被静默忽略。

这是兼容旧响应的新增字段，不改变插件入口函数和 API 版本。`getPlayback`（旧入口 `getPlayArgs`）与 `refreshPlayback` 返回同一类型；换线路、换清晰度或刷新地址时，插件应同时返回对应的最新密钥，宿主不继承上一条线路的密钥。

## 宿主适配

1. `LivePlaybackDecryption` 在 Codable 解码时验证方法和密钥。
2. `RoomPlaybackResolver.resolvePlan` 对声明了解密需求的资源仅选择 `mePlayer`，优先于插件建议的内核顺序和低延迟 HLS 推断。
3. iOS、macOS、tvOS 的 FullUI 播放 ViewModel 都调用 `KSPlayerSessionConfigurator.apply`，将密钥写入本次 `KSOptions.formatContextOptions["decryption_key"]`。
4. KSPlayer 的 `FFmpegUtility.swift` 将 `formatContextOptions` 转为输入字典并交给 `avformat_open_input`。切换资源时覆盖密钥，未加密资源清除此选项；不修改全局默认配置。

点播资源同时声明 `playbackHints.isLive: false`。三端 FullUI 将解析后的
`RoomPlaybackPlan.isLive` 交给共享恢复协调器：点播正常 EOF 停止监测与自动恢复，
直播 EOF 继续按已有阶梯重试。该语义不从内核的 `KSOptions.isLive` 反推，因为
应用管理重连时可单独关闭内核的直播重连。真实播放错误仍走恢复处理。
已播完的视频重新配置、切换视频或直接点击播放重播后重新武装监测；同会话
的参数更新与 URL token 刷新不清除已有恢复预算。旧调用方未配置该语义时保持
原有直播恢复行为，ShellUI 的独立直链播放器未接入此变更。

播放参数只在现有播放会话中使用，不新增持久化密钥缓存。解密对象的普通及 debug 描述隐藏密钥；取播放参数的插件调用复用敏感日志抑制机制，省略请求、响应及调用期间的插件/HTTP日志。通用控制台脱敏也识别 `decryption` 与 `decryption_key`。

## 支持范围与验证边界

[FFmpeg 官方 MOV/MP4 demuxer 文档](https://ffmpeg.org/ffmpeg-formats.html#mov_002fmp4_002f3gp)说明，`decryption_key` 接收十六进制表示的 16 字节密钥，用于 CENC / AES-128 CTR。当前适配提供单个默认密钥；多密钥、密钥轮换、其他加密方案和许可证流程不属于此接口。

该适配面向默认 KSPlayer 的 FFmpeg 内核。AVPlayer 和 VLC 变体没有获得相同的解密参数支持。HLS/DASH 分片是否向内部 MOV demuxer 传递选项、实际安装包的 FFmpeg 构建能力，以及真实资源能否播放，均需样本验证；不能由配置传递单测推断成功。

本轮不修改 ShellUI、插件私有实现或任何具体内容平台配置。

## 2026-10-08 参数适配验证

- Xcode 27.0 RC（27A266a）下，Core 全量 508 项测试／67 组通过，包含旧模型兼容、严格解码、日志保护和解密内核选择。
- Dependencies 使用 SwiftPM `--build-system native`，全量 21 项测试／5 组通过，包含同一 KSOptions 的密钥替换及清除。默认 SwiftPM 构建在本机遇到缺少 Metal Toolchain 的环境错误，native 结果仅代表该构建路径。
- workspace MCP `BuildProject`：`AngelLive`／iPhone 17（27.0）、`AngelLiveMacOS`／My Mac、`AngelLiveTVOS`／Apple TV 4K（3rd generation，27.0）均成功；各次构建后 Issue Navigator 的 error 列表为空。
- 全仓具体内容平台标识及数值 `liveType`／`siteId` 检查未发现命中；`git diff --check` 通过。
- 需要外部服务或原生资源的 opt-in 集成测试未启用。此阶段尚未安装新包或播放加密样本；后续设备结果见下。

## 2026-10-08 加密样本设备验证

通过应用正常订阅及安装流程接入临时中性测试插件，同一公开 CENC / AES-128 CTR
视频地址分别返回无密钥、正确密钥和有效格式的错误密钥。样本为约 2.7 秒的
H.264 分片 MP4，只有视频轨，前 0.5 秒为明文。密钥、样本地址、临时插件及
原始设备数据仅保留在本机测试目录，不写入仓库。

- iPhone 17 / iOS 27.0 模拟器使用最后一次源码修改后成功完成
  `DeviceInteractionInstallAndRun` 的新包；AXe 接管同一新包，测试期间未修改宿主源码。
- 手工进入顺序为正确密钥、无密钥、错误密钥、正确密钥。正确密钥两轮均无
  损坏码流或帧解码错误并到达 EOF；补拍以 `bufferFinished` 为锚点，取得明文前导之后
  两张清晰且内容不同的连续画面。首轮缓冲截图不计为后段解密证据。
- 无密钥与错误密钥均在加密段出现明显花屏和原生解码错误；有首帧或到达
  EOF 不代表正确解密。四轮保持同一 App 进程，没有新增崩溃报告。
- 独立离线对照中，正确密钥解出的 82 帧与明文文件逐帧摘要全部一致；无密钥
  和错误密钥只有前 15 帧一致。普通 FFmpeg 运行可在花屏时仍退出 0，不能用
  退出码代替帧验证。离线工具版本与 App 内嵌版本不同，不作为 App 结果替代。
- 观察到短点播结束后宿主仍按 Room 会话 EOF 恢复逻辑重新获取地址并重开。
  自动重开次数不计作手工测试轮次；本轮没有修改播放结束或恢复策略。
- 模拟器日志有 VideoToolbox 初始化失败，随后软件解码成功；EOF 也被播放器
  记录为读帧错误。上述日志不等于加密段损坏，不能笼统声称原生日志没有 error。

本次确认插件到宿主再到默认 KSPlayer / FFmpeg 内核的单密钥 MP4 解密路径。
真机、macOS/tvOS 实际播放、带加密音轨、HLS/DASH 分片、多密钥及密钥轮换
仍未验证，不能由此样本推断所有资源均可播放。

## 2026-10-08 点播结束适配

针对上一轮公开样本自然播完后反复重开的现象，三端 FullUI 已将播放计划的
直播／点播语义接入共享恢复协调器。点播正常结束进入空闲恢复阶段并停止采样，
成对结束回调和播放器 attach 的 `start()` 不会重新触发恢复；同地址直接重播
按实际起播状态重新武装。真实错误继续恢复，停止会话后的旧回调保持忽略。

- 恢复协调器 19 项同步测试通过，覆盖正常 EOF 两种顺序、零起播结束、直接重播、
  同会话配置、直播／点播切换、真实错误及 token 更新后的恢复预算。
- 最后修改后的 Core 全量 515 项测试／67 组、Dependencies 全量 21 项／5 组通过。
- Xcode 27.0 RC（27A266a）workspace MCP `BuildProject`：iOS／iPhone 17（27.0）、
  macOS／My Mac、tvOS／通用模拟器目标均成功；各次 Navigator error 为 0。
  Xcode 已恢复原来的 iOS scheme 与设备目标。
- iPhone 17／iOS 27.0 在最后源码修改后重新成功完成
  `DeviceInteractionInstallAndRun`；结束 Device Hub session 后，由唯一设备负责人
  使用 AXe／simctl 接管同一新包。公开 CENC 样本首次正常播放和同地址直接重播
  均有加密段清晰画面及自然结束日志，每次结束后静置观察超过 20 秒，没有自动重开。
  原始 JSON 日志核对为一次输入打开、一次成功 seek 到 0、两次目标为
  `playedToTheEnd` 的状态转换；不能把该词作为旧状态的日志也计成一次结束。
  两次未确认触控不计为通过，最终重播以重新观察到的可见 Play 按钮及 seek 日志为准。
- 首次与重播保持同一 App 进程；未见损坏码流／帧解码错误或新增崩溃，日志中
  没有测试密钥。模拟器仍使用软件解码，不能据此声称所有原生 error 日志均消失。
- 临时插件与订阅源已通过正常 UI 删除，原有插件及订阅源保留；设备 session、
  日志采集及临时服务均已结束。全仓平台中立性检查与 `git diff --check` 通过。

macOS、tvOS 本轮仅验证构建；真机及其他加密容器／多密钥的验证边界保持如上。
