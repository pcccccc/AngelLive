# 宿主弹幕连接与请求并发审计

日期：2026-10-04。范围：iOS/macOS/tvOS FullUI、共享弹幕传输、插件运行时与搜索/分类请求。保留本轮之前的字幕、同步、首页和播放诊断改动；不修改 ShellUI 页面。

## 确认的问题与修复

| 路径 | 可重现的请求顺序 / 原因 | 修复位置与行为 |
| --- | --- | --- |
| HTTP 轮询弹幕 | JS session 创建成功、首个 HTTP 请求尚未成功时即通知连接成功；连续失败重试反复产生虚假的恢复提示 | `HTTPPollingDanmakuConnection` 等首个响应成功经过 `onFrame` 后通知 connected，连续失败保持一次断线通知，恢复后才清闸 |
| 弹幕驱动销毁 | 每次断开产生没有归属、没有超时的 destroy Task；插件 Promise 不结束时持续积累 | `DanmakuDriverRetirement` 仅保留最新清理任务，替换会取消，30 秒截止；清理 lease 能跨越 transport 释放，新连接不等待清理 |
| 弹幕建连期间取消 | 取 session 时退出，工作队列取消后没有结束开发者控制台的 loading 记录 | 主动断开结束该条记录，但不向 UI delegate 报连接错误 |
| 插件 WebSocket 生命周期 | 自然关闭/报错未移除全局注册项；缓存 runtime 被替换仍可能接收事件，handler 保留 JS 状态 | 每个 runtime 拥有独立 owner；自然终止一次性释放；失效同步关闭 owner，排队事件和新的 open/send/close 不可越过失效边界 |
| 插件请求跨重载回写 | 请求已发出后 reload、pin/unpin 或凭据驱动的 evict；旧请求继续交回结果或错误 | 普通调用按该插件的缓存 runtime 身份验证；旧结果转取消，pin/unpin 只淘汰目标插件。登录事务持有独立固定版本 runtime，不因普通缓存更换丢失事务状态 |
| 插件首次并发加载 | actor 的 `load()` 在 evaluate 的 await 处可重入，多个调用都看到 `isLoaded == false`，重复执行入口脚本并重置 JS 全局状态 | `LiveParseLoadedPlugin` 合并同一轮初始化 Task；成功只加载一次，失败允许下一轮重试；单个调用取消不取消其他调用共享的加载 |
| Mac 分类房间列表 | A 分类请求较慢，切 B 后 A 通过当前选择的 setter 写入 B；页码在请求前推进，失败可能跳页 | 共享 `CategoryRoomListModel` 每分类拥有自己的结果、loading、错误和已成功页码；只有成功才推进页码 |
| 分类目录 | 初次加载与重试并发，较旧目录后返回会重置当前选择并拉取旧分类；旧索引对应的房间结果也可能污染新目录 | iOS/macOS/tvOS 目录请求按代际提交；目录替换后旧房间请求不能修改新目录下的列表状态 |
| 三端搜索 | 先提交 A、再提交 B；B 先完成后 A 覆盖结果/错误，或提前结束 B 的 loading；清空后旧结果再次出现 | 共享 `SearchRequestModel` 持有请求任务和代际，搜索词/类型/页码形成固定请求；清空、切类型和退出取消旧工作，迟到结果无效 |
| tvOS 搜索入口 | 提交时修改 `roomPage` 触发隐式关键词请求，随后又按真实输入发请求；分享结果的焦点分页也误走关键词 | 提交/重试统一到搜索 owner；搜索分页独立于普通列表页码，分享结果不分页 |
| tvOS 下播轮询 | Timer 每次启动无主 Task；慢请求重叠，切房后旧 `.close/.unknow` 结果仍发送结束播放通知 | `LiveStatusPollingSession` 同时仅一项请求；换房、退出和播放器清理会停止并失效，旧请求即使忽略取消也不能结束新房间 |

跨端业务规则置于 AngelLiveCore；平台页面保留导航、键盘、焦点和错误呈现。没有增加插件专用分支、宿主 control Ping 或针对所有错误的自动重试。

## 已核对、保留的边界

- 三端弹幕取计划任务已有取消和房间快照校验；连接对象创建后的重连已有退避、工作队列串行、超时、旧 socket 身份和旧 HTTP 响应代际门禁。
- **首次 `getDanmakuPlan` 失败发生在 transport 创建之前，不会进入 transport 自动重连。** iOS 回前台、tvOS 重开弹幕以及重新进入房间可以重新取计划；Mac 单纯切换飞屏显示不会重新取计划。本次保留这一边界，没有把认证、缺能力和解析错误统一变成无限重试。
- 不把“没有聊天消息”视为掉线。2026-09-16 已有真实复现证明某些服务不接受宿主额外 control Ping；继续由插件应用层心跳和传输错误驱动恢复。
- HTTP single-flight 依照显式请求契约合并；一个等待者取消不能取消其他等待者需要的共享请求。JavaScriptCore 对象留在串行 JS 队列，网络任务不阻塞 JS 队列。
- 单元测试使用中性 fixture 和可控完成顺序，故意让部分请求忽略取消，验证真正的结果提交门禁。测试不代替真实插件、账号、服务器和切网验收。

## 本轮验证

使用 Xcode 27.0 RC（27A266a）；所有命令显式选定当前工具链，未修改全局 Xcode 选择。

- 最小回归：6 个 suite、59 项定向测试通过（13.558 秒）。新增 26 项回归，Core 总数从本轮之前的 440 增至 466。
- 首次全量运行暴露既有测试依赖有限次数 `Task.yield` 轮询，重负载下等不到 Promise 登记；已替换为 JS 队列上的明确登记信号。修正后登录相关 10 项定向测试通过（0.147 秒）。
- 最后源码的 `swift test --package-path Shared/AngelLiveCore`：62 个 suite、466 项全部通过（24.046 秒）。
- `swift test --package-path Shared/AngelLiveDependencies`：4 个 suite、20 项全部通过（0.078 秒）。
- workspace MCP `BuildProject`：macOS `AngelLiveMacOS / My Mac` 通过（19.418 秒，request 1008），tvOS `AngelLiveTVOS / Apple TV 4K (3rd generation)` 通过（63.301 秒，request 1011）；构建后的 Issue Navigator error 均为 0（1009、1012）。
- iOS `AngelLive / iPhone 18 Pro` 最后源码 workspace MCP 构建通过（79.155 秒，request 1022），Issue Navigator error 为 0（1023）。随后 `DeviceInteractionInstallAndRun` 成功安装并启动新包（1025）。
- 全仓扫描 737 个文件（652 个文本、85 个二进制），实际具体内容平台标识和测试真实数字映射均为 0；5 个通用词歧义已逐项核对。`git diff --check` 通过；未改 ShellUI 目录，tvOS 工程原有两处签名修改保留。

测试日志保存于被忽略的 `runs/host-concurrency-audit-2026-10-04/`；MCP 原始响应继续保存在本轮复用的 `runs/live-subtitle-ui-2026-10-04/response-*.json`。没有重新启动 bridge 或创建第二个设备控制进程。

### iOS 新包交互

当前机器未找到 JEV CLI，按项目既定回退使用 Device Hub；同一设备始终由一个子代理负责，root 只代发至原有 bridge。iPhone 18 Pro / iOS 27.0 模拟器上验证了搜索入口、链接/口令与关键词切换、清空输入、明确的无结果状态，以及两次顺序提交后的最终输入和页面状态。最后关键词保持 `source-b` 且显示“暂无搜索结果”；切回链接/口令模式后恢复待搜索说明态。root 已独立核对安装响应、hierarchy 和原尺寸截图，未见裁切、重叠或 loading 卡住。

这两次提交是顺序交互，不作为真实请求重叠或乱序完成的证据；请求逆序返回由可控单元测试覆盖。未使用真实账号或凭据，没有可进入的直播结果，因此结果详情往返未验证。

证据：同一 `runs/host-concurrency-audit-2026-10-04/` 下的 `ios-search-device-validation.json`、`id1030-keyword-settled-screenshot.png`、`id1034-rapid-final-screenshot.png`、`id1035-share-mode-return-screenshot.png`。截图文件中的 `rapid` 只是文件名，实际覆盖范围以上述顺序交互为准。

设备 session 已结束（1036），Xcode 恢复本轮开始前的 `AngelLive / LaoPC`（1037）。未清空、创建、克隆或重命名模拟器。源码快照 `source-snapshot.json` 在测试结束后复核未发生变化。

仍未验证：真机、真实切网/弱网、各插件服务端的长时间 WebSocket/HTTP polling 行为，以及 macOS/tvOS 本轮页面交互。自动化结果证明上述宿主状态规则，不证明所有网络失败都来自宿主或都已消失。
