# 弹幕连接恢复

2026-09-06：宿主修复。连接与驱动处理位于 AngelLiveCore，三端播放页消费恢复状态。ShellUI 未使用这两条连接链路，本次不调整其行为。

## 已修复路径

- `timer` 缺失表示保持现有定时器，只有显式 `off` 停止。同模式、同有效间隔的配置不会重新计时，避免连续收帧把心跳一直推迟。
- WS 和 HTTP 轮询均持续退避重试：前期基础间隔为 2、4、8、16、30 秒，8 次尝试后每 60 秒重试，每次增加 0～1 秒抖动。退出或暂停连接会取消重试；配置缺失、非法 WS 地址不盲目重试。
- WS 心跳由插件的 `timer` / `onTick` / `writes` 驱动。宿主不额外发送 WebSocket control Ping，也不因缺少 Pong 或房间没有聊天消息主动断线；服务端关闭、网络错误和驱动失败仍进入现有恢复流程。
- 驱动的 create/open/frame/tick 串行处理，重复 tick 合并；单次驱动调用 30 秒超时。取消旧任务的同时改变会话代际，旧结果不得回写新会话。新 socket 忽略旧 socket 的事件；握手前的写入等 socket open 后发送。
- HTTP 轮询失败取消请求、停止旧定时器、销毁旧驱动并重建。响应必须匹配请求所属会话；驱动完成响应处理前保持请求在途，避免重叠推进轮询状态。
- iOS 用独立的连接意图记录是否应恢复。处于断线或重连状态时切后台，回前台仍可重新连接；显式退出播放页则清除此意图。
- 三端取消未完成的弹幕取参任务并检查房间快照，delegate 同步在 MainActor 更新状态。iOS 原地切房清空飞屏时恢复引擎播放，并使旧的异步图片弹幕结果失效。

`webSocketIsReconnecting(attempt:maxAttempts:)` 的 `maxAttempts == 0` 表示持续重试，宿主提示不应显示为“次数/0”。插件入口、消息模型和应用层心跳帧格式不变。

## 回归验证

`DanmakuConnectionRecoveryTests` 使用可控时钟、延迟驱动和记录型 socket engine，覆盖心跳连续收帧、显式停止/配置变化、过期定时器、长时间断网、串行与 tick 合并、驱动超时、旧会话回写、建连期间退出、旧 socket 事件、握手前写入、非法端点清理、轮询重试以及不注入 control Ping 的插件心跳。

### 2026-09-16：移除宿主强制 Ping

用户提供的对照复现中，连接先正常接收弹幕，在第 30 秒收到宿主额外发送的 control Ping 后约 50 毫秒被服务端关闭；仅发送插件应用层心跳的连接持续正常。源码中的独立探活定时器与该时间点一致，插件驱动协议也未声明服务端接受 control Ping。此前将 Ping/Pong 当作所有连接的默认要求并不成立。

本次删除该定时器和匹配 Pong 的超时状态，保留插件心跳、串行驱动、会话隔离及错误重连；不增加来源特判或修改插件协议。静默失效的发现依赖传输层错误或插件驱动失败，不再由宿主固定的 Pong 截止时间判定。

最后源码修改后，使用 Xcode 27.0 RC（27A266a）完成：

- `swift test --package-path Shared/AngelLiveCore --filter DanmakuConnectionRecoveryTests`：15 项通过。覆盖无插件定时器时推进 91 秒不注入 Ping、不主动断开；插件每 30 秒发送 text/binary 心跳，连续三个周期无 Pong 仍保持连接，显式 `off` 后停止发送。
- `swift test --package-path Shared/AngelLiveCore`：39 个 suite、299 项测试全部通过。
- workspace MCP `BuildProject`：`AngelLive`（iOS 模拟器）、`AngelLiveMacOS`、`AngelLiveTVOS`（tvOS 模拟器）均通过，各次构建后的 Issue Navigator error 数均为 0。
- 全仓库具体内容平台标识扫描无命中，测试中的 `liveType` / `siteId` 使用中性标识。

Device Hub 验收使用已有的 iPad mini (A17 Pro) / iOS 27.0 模拟器。在最后源码修改之后完成新的 `DeviceInteractionInstallAndRun`，返回 `Application installed and running`，09:41:53 的首次截图确认新进程已启动。随后从用户指定的同一分类页面依次进入三个正在直播的房间，每间持续观察超过两分钟：

| 房间 | 观察区间（本地时间） | 连续时长 | 结果 |
| --- | --- | --- | --- |
| A | 09:48:52–09:51:25 | 153 秒 | 聊天和飞屏持续出现新消息，无断连记录 |
| B | 09:54:51–09:57:28 | 157 秒 | 聊天和飞屏持续出现新消息，无断连记录 |
| C | 09:59:43–10:02:26 | 162 秒 | 聊天和飞屏持续出现新消息，无断连记录 |

三个房间均跨过多个 30 秒周期，未复现此前的周期性断连。每次进入房间均收到连接成功事件，观察区间内没有 `弹幕服务断开` 或 `[DanmuWS] websocket error`；聊天截图和视频画面也持续更新。日志会截断较早记录，连接计数按房间进入时点和相邻 capture 核对，不将滚动窗口的累计计数下降当作进程重启或断线。

截图、hierarchy 和日志保留在本机工具产物的 `ActionArtifacts/default/DeviceInteractionSynthesize/`，共用前缀 `danmaku-heartbeat-20260916-r2-`；首末原图分别为 `09_48_52_118` / `09_51_25_680`、`09_54_51_267` / `09_57_28_457`、`09_59_43_903` / `10_02_26_157`，文件后缀为 `-screenshot.png`。主代理已独立复核各房间首末原图及日志。

验收结束调用 `DeviceInteractionEndSession` 时返回 `Session doesn't exist anymore`，该会话已不存在。随后核对 workspace 仍为原 `AngelLive` scheme 与 iPad mini (A17 Pro) (27.0) 运行目标。

以上设备结果仅覆盖 iOS 模拟器的正常网络和这三个房间。macOS、tvOS 的设备交互、真机及真实切网/弱网行为未验证。

### 2026-09-06：历史验证记录

最终源码的 `AngelLiveCoreTests` 全量测试通过：34 个 suite、231 项测试，其中本次新增 14 项恢复回归测试。

最终源码的 macOS、tvOS workspace MCP 构建通过，Issue Navigator 的 error 数均为 0。iOS 在最后源码修改后通过 workspace Device Hub 重新构建、安装并启动，error 数为 0；iPhone 17 Pro Max / iOS 27.0 模拟器上，同一真实直播间持续观察超过 90 秒仍有新聊天和飞屏，原地快速换台后新房间的聊天和飞屏也正常。

同一新进程通过 Home 进入后台后再次激活，重新连接并恢复新聊天和飞屏。Device Hub session 已结束，workspace 恢复至原 iOS scheme 和运行目的地。macOS、tvOS 的设备交互与真实断网/弱网尚未验证。

设备验收应在最后修改后重新安装：确认聊天与飞屏均有新消息，原地切房后飞屏继续，切后台再返回后重新收到消息。真实切网、弱网和不同插件服务端仍需设备与网络条件验证，单元测试不能代替这些现场证据。
