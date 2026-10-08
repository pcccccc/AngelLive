# 播放页音频输出初始化

## 故障与适配

2026-10-08，iOS 模拟器上进入播放页时发生一次进程退出。符号化堆栈为
`AudioEnginePlayer.init` → `AVAudioEngine.outputNode` → `AURemoteIO` →
`AudioToolboxCore._ReportRPCTimeout` → `SIGABRT`，尚未打开媒体。
同包重新打开后可播放；系统音频服务超时的根因尚未确定。

iOS FullUI 的房间播放会话改用 KSPlayer 的 `AudioRendererPlayer`，避免在打开
房间时创建该 `AVAudioEngine` 输出节点。它仍通过系统音频服务播放声音，不能
据此保证所有系统音频故障均已消除，也不能把构建或后续未复现当作根因修复证明。

KSPlayer 的 `KSOptions.audioOutputType` 属于单个会话，默认快照既有全局默认值。
宿主必须在构造播放器前选择类型；已构造的播放器在换媒体项时继续使用原音频
输出，不能通过修改选项在播放中切换后端。音频输出、帧容量、声道映射和 PCM
交错格式使用相同的会话类型，音轨描述保存该类型用于格式更新和路由变化。

不修改 `KSOptions.audioPlayerType` 全局默认值。iOS ShellUI、macOS 和 tvOS
继续使用其原有默认输出；本次宿主接入仅在 iOS FullUI。

依赖以 KSPlayer 5.0.0 为基线，固定到包含会话接口和测试的提交
`c166a4ec71c724c92001f43cd8f161af2a903375`；未升级其他播放器或 FFmpeg 依赖。

## 验收

- 两个输出类型不同的选项和音轨描述可以同时存在，格式更新保持各自的 PCM
  布局，不影响默认会话。
- 对应 Package 测试及受影响宿主构建通过。
- 最后一次编辑后安装新包，在相同模拟器确认实际输出为 `AudioRendererPlayer`，
  正常起播、持续视频和音频输出，并连续进入和退出播放页。
- 记录构建、安装、日志和交互证据；未运行的检查明确标为未验证。

原始崩溃与运行日志仅保留在本机临时证据目录，不写入仓库。

当前验证状态：KSPlayer 新增 5 项定向测试通过，扩展单元测试 59 项 / 9 个
suite 通过；AngelLiveDependencies 21 项 / 5 个 suite 通过，其他依赖锁定值
未变化。Xcode 27.0 RC 的 iOS、macOS、tvOS workspace MCP 构建通过，
三端构建后 error 级 navigator issues 均为空。iOS 最后一次源码修改后已完成
新的 `DeviceInteractionInstallAndRun`，返回安装与启动成功。Device Hub 后续
截图调用返回会话失效，清理后由 AXe 接管同一新包。

iPhone 17 / iOS 27.0 模拟器实测三个不同公开视频，包含上次崩溃时选择的视频；
手工进入、退出共五轮，顺序为 A、B、C、C、C。前三个样本均取得两张不同
播放画面，五轮均确认返回列表，整个过程保持同一 App 进程。日志中的七次
媒体打开全部使用 `AudioRendererPlayer`，五轮退出均有 `KSMEPlayer` 释放记录；
自动媒体重开不计作手工测试轮次。与测试前基线相比无新增 App 崩溃报告，
本轮日志未出现原 RPC 超时或 SIGABRT。

运行日志确认双声道音轨准备；交错 PCM 布局由源码和单元测试验证，未在
运行日志中直接观察。声音听感、真机播放、macOS/tvOS 播放交互仍未验证。
后续视频轨 CENC 样本的设备对照见 [播放解密参数协议](PlaybackDecryptionProtocol.md)。
本轮未复现闪退，不代表系统音频服务超时根因已确认。
