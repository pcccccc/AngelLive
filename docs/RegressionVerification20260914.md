# 2026-09-14 逐项回归

基线：`main` / `effce36`，承接[昨天的修复与验证状态](RegressionVerification20260913.md)。本轮按场景记录实际结果；昨天的通过记录不计作今天的新验证。

后续按用户反馈修改 tvOS FullUI 收藏刷新提示；此前 Core、iPhone、iPad 结果对应上述原始基线，新改动的验证单独记录。

## 验收顺序与判定

| 顺序 | 场景 | 通过条件 | 今日状态 |
|---|---|---|---|
| 1 | Core 插件返回值、收藏身份、插件安装快照 | 相关现有测试通过，再执行 Core 全量回归 | **通过**：定向 29 项／8 个 suite；全量 295 项／39 个 suite |
| 2 | iPhone 历史、收藏与普通播放 | 新包完成历史进入播放、返回、收藏刷新、连续切房、旋转和前后台恢复 | **部分通过**：历史起播、旋转、短序列切房、前后台与收藏请求预算通过；边缘返回间歇失败，收藏标题可见回写待定位 |
| 3 | iPhone 竖屏直播手势 | 实际竖向画幅直播中左滑清屏、右滑显示；单击、双击、弹层、锁定、边缘返回协调正确 | **发现问题**：清屏、弹层和竖流边缘协调通过；暂停被恢复监控误判，另有横向流边缘返回可靠性问题 |
| 4 | iPad 首页更多列表与平台 Tab | 新包更多列表无卡片重叠；冷启动与侧栏切换正常；同名插件、元数据更新、移除选中插件时身份和选择稳定 | **进行中**：已有标准 iPad 新包安装运行成功，开始空环境与 FullUI 交互检查 |
| 5 | tvOS FullUI 收藏刷新 | 按用户新要求对齐 iOS：圆环只随前台刷新；慢请求继续回写；连续遥控器按键合并；焦点与列表位置稳定 | **提示已修改、构建通过**；17.5 新包已启动，自动化遥控受阻，圆环消失时机尚未完成设备验收 |
| 6 | 无插件启动回退 | 在已有空插件环境检查默认收藏及导航；不删除已有插件或账号来制造前置条件 | **部分通过**：iPad / iOS 27 新包默认收藏、配置、设置通过；macOS、iOS 17 尚未验证 |
| 7 | iOS 26.0／26.0.1 符号动画 | 对应系统中执行冷启动、收藏状态循环、前后台及静态图标／现有动画 A/B | **受阻**：当前已有模拟器无对应系统；新系统结果不能替代 |
| 8 | iOS App 在 Mac 上运行 | 该运行模式下检查冷启动、历史进入播放、封面导航、退出重进和窗口缩放；异常时采集可定位的主线程证据 | **未验证**：当前 Debug／Release 均关闭 Designed for iPhone/iPad on Mac 与 Mac Catalyst；原生 macOS App 不能替代 |
| 9 | tvOS 解码重连与上下文生命周期 | 真实 Apple TV 与 Address Sanitizer 检查重连、退房、替换播放项及解码／队列退出 | **受阻**：设备目录内所有 Apple TV 均为 simulated，没有发现可连接真机；ASan 生命周期验收未运行 |

## 执行约束

- 每个平台使用已有标准设备；同一平台最多一台运行。设备 session 由一个代理独占，切换前结束 session，收尾恢复原 Xcode 运行目标。
- 每轮设备结论必须对应本轮成功的 workspace `DeviceInteractionInstallAndRun`，并核对安装后的截图与 hierarchy。
- 对每个场景分别记录通过、失败、受阻或未运行。缺少插件、账号、特定流、系统或硬件时，记录缺失的前置条件，不推断通过。
- ShellUI 仅验收昨天已有修复；本轮不因此扩大源码修改范围。
- 日志与截图保留在本机临时目录，仓库只记录中性的场景、步骤和结果。
- 第 7～9 项承接昨天的崩溃研究，包含尚未修复或未定位到具体入口的问题；短时未复现不能标记为已修复，也不关闭线上崩溃分组。

## 今日结果

### 1. Core 回归通过

- 工具链：动态发现的 Xcode 27.0 RC（27A266a），Apple Swift 6.4；macOS 26.6.2（25G83）。
- 定向命令：`xcrun swift test --package-path Shared/AngelLiveCore --disable-automatic-resolution --filter 'PluginReturnValueTests|FavoriteIdentityRulesTests|FavoriteMembershipSnapshotTests|FavoriteCloudStateTests|FavoriteBackupServiceTests|FavoriteListGroupingTests|FavoriteSyncErrorDisplayTests|PluginAvailabilityServiceTests'`，29 项测试、8 个 suite 通过，其中返回值测试含 18 个参数组合。
- 全量命令：`xcrun swift test --package-path Shared/AngelLiveCore --disable-automatic-resolution`，295 项测试、39 个 suite 通过。两条命令均为单次进程设置核验后的 `DEVELOPER_DIR`。
- 日志：`angellive-core-targeted-20260914-Xv6bJg`、`angellive-core-full-20260914-MzFPgt`，位于本机临时目录。
- 首次尝试在 manifest 编译前被 sandbox 缓存写入权限阻止，实际测试数为 0；同一测试命令经自动审批后执行通过。没有清理缓存或改变依赖版本。
- 日志中的 WebSocket `-1005` 属于 `oldSocketEventsCannotDisconnectReplacement()` 主动注入的恢复测试错误，该测试通过。

### 2. iPhone 安装、导航与收藏

- 设备：复用本轮开始时已 Booted 的标准 iPhone 17 Pro / iOS 27，没有启动第二台 iOS 模拟器。
- 本轮 `DeviceInteractionInstallAndRun` 成功，新进程启动后取得截图与 hierarchy；生产源码为 `effce36`，其后尚无生产源码修改。
- MCP `BuildProject` 成功（10.471 秒），error severity Navigator issues 为 0。
- 首页已有插件和真实内容；设置 → 数据同步明确显示未登录 iCloud，未变更开关、账号或凭证。
- 历史列表打开正常；已有下播记录显示可恢复提示，确认按钮能够关闭，未出现应用退出。该步骤不能替代历史记录成功起播验收。
- 随后另一条历史记录进入真实横向画幅直播，前后截图确认画面与弹幕更新；在视频区域从左边缘滑动成功返回历史列表（response 020），完整历史起播／返回链通过。
- 源码自定义边缘层声明覆盖整页，仅接收最左侧 20pt 内的触摸。早期弹幕区域未返回的观察，随后用统一触摸起点与距离复测，结果如下。
- 横向合成流统一条件后，弹幕占位区域 `t 2 437 f 280 437 0.4` 成功返回（response 077）；重新进同一流稳定后，视频区域 `t 2 170 f 280 170 0.4` 连续两次未返回，中间已重新捕获，画面持续更新（response 080～082）。该结果不能概括为某一区域总失败；记录为边缘返回可靠性问题，待定位命中范围及识别器时序。
- 横向流旋转通过：设备转 Landscape Left 后应用为 874×402，全屏视频及控制布局更新（response 083）；转 Portrait 后为 402×874，恢复顶部视频与信息／弹幕列表，同一房间持续播放，无异常重叠或退出（response 084）。
- 连续切房基础回归通过：快速换台面板内横 → 竖 → 横 → 竖，来源分区排除当前房间，标题和播放中标记随切换更新；关闭面板后实际竖流持续播放，控制层显示，进程未变（response 088～092）。本轮短序列未观察到旧房间回写或卡死，不代表长时间压力测试通过。
- 收藏慢请求预算通过：通过正常 UI 添加两个 fixture 收藏；手动刷新日志为 rooms=2、plugins=1，首批结果约 0.754 秒，前台等待约 4.006 秒结束，完整请求约 8.221 秒结束，success=2、failure=0。慢请求未阻塞列表展示，后续下拉建立新一轮刷新（response 106～110）。
- 刷新中的 hierarchy 曾显示“正在刷新收藏”，但未捕获原生 spinner 的明确可见帧，不能给出 spinner 视觉通过结论。
- **收藏标题可见回写待定位**：慢请求返回新标题，卡片仍显示旧标题。fixture 未声明保留原房间信息，默认刷新路径会发出完整 room、替换内存项并递增列表版本，因此不能解释为主动保留标题；也尚无证据证明持久化数据丢失。后续需区分回写与渲染复用，暂不标记晚到内容可见更新通过。
- 收尾已完成：取消两个测试收藏、逐条删除三条合成历史、恢复并复核原首页选项，再卸载本轮唯一 fixture 插件和本机源；最终恢复为原 18 个插件、3 个源，原数据保留。response 139 的 `DeviceInteractionEndSession` 返回 `Session stopped`。
- 设备证据：`angellive-regression-20260914-091417/`。清理终态截图文件名 `iPhone FullUI Regression-09_49_42_094-screenshot.png`，与 hierarchy 位于系统临时目录的 `ActionArtifacts/default/DeviceInteractionSynthesize/`。

### 可控前置数据

- 临时 fixture 源仅监听本机 loopback，通过正常添加源／安装同意流程使用；仅用于已确认未登录 iCloud 的测试模拟器。
- 包含两个同名中性插件及元数据更新版本、持续编码的 360×640 和 640×360 HLS、8 秒房间详情请求。
- 已完成 ZIP／manifest 一致性、SHA-256、JavaScript 语法和响应结构检查；FFprobe 确认两种视频尺寸及 H.264／AAC 编码。这些准备检查不计入宿主设备通过项。
- 合成流可验证宿主画幅识别和手势状态，不能替代真实来源的播放兼容性。临时 fixture 未写入宿主源码或共享 Package。
- 已在当前未登录 iCloud 的 iPhone 通过 App 正常源管理和安装按钮添加一个 fixture 插件，并进入三房间列表；原有插件与源保留。后续清理只针对本轮测试数据。
- iPhone 结束后已完成上述清理。下一轮 iPad 的临时服务扩展为 15 个房间供网格滚动检查，并为详情响应追加更新序号；服务在设备会话间重启，未打断运行中的播放。

### 3. 竖屏手势

- 合成 360×640 持续 HLS 实际进入竖屏控制层；response 038 的“直播画面”值为“控制层已显示”。
- 左滑 `t 320 437 f 80 437 0.4` 后，response 039 为“已清屏”，主播及更多控件消失。
- 右滑 `t 80 410 f 320 410 0.4` 后，response 040 恢复“控制层已显示”。视频图案和时间持续变化。
- 左边缘协调通过：清屏后从 `x=2` 到 `x=280`、`y=437` 右滑，仅恢复控制层（response 042／043）；控制层已显示时相同指令返回原房间列表（response 044），没有误退。
- 右边缘左滑进入清屏且未误返回（response 047～049），右滑可恢复控制层。
- 清晰度弹层保护通过：弹层打开后同样左滑不清屏、不关闭弹层（response 052／053）；选择“测试备用”后，菜单显示“清晰度 - 测试备用”，播放继续（response 055）。两项测试清晰度共用相同合成流，因此只验证选择状态与弹层交互，不验证不同编码清晰度的切流兼容性。
- 主播详情弹层保护通过：横向左滑后 sheet 仍在，底层保持“控制层已显示”；下拉 sheet 后回到播放器（response 057～060）。Device Hub 只报告了该 sheet 的空 Window，截图可见完整 sheet；未作 VoiceOver 通过结论。
- 竖流方向锁定通过：设备姿态改为 Landscape Left 后，应用 UI 仍为 Portrait，画面和竖屏控制持续更新（response 061／062）。源码在 iPhone 竖向流设置 `.portrait`，此结果符合该分支；不计为横向流旋转通过。
- 前后台恢复通过：Home 后应用进入后台（response 069），重新激活仍为同一进程，视频时钟与图案持续变化，控制层保持显示（response 070／071）。
- 单击保持控制层显示且视频继续，无意外暂停或退出（response 100）。横向流双击切换全屏，与竖向流双击暂停的行为不同（response 085／087）。
- **双击暂停／恢复失败**：早期双击序列出现暂停后自行更新（response 064～068）；进一步的单次暂停及生产状态机复现确认了下节所述自动续播问题。
- 共享 `PlaybackRecoveryCoordinator` 收到 `.paused` 仅将 `enginePlaying` 置为 false；带采样的 `handleTick` 仍会累计 stall。共享适配层对 KSME 暂停仍提供采样，未包含用户播放意图。

### 4. 暂停状态的确定性复现

- 直接编译未修改的生产 `PlaybackRecoveryCoordinator.swift` 和 `PlaybackTuning.swift`，仅用临时无副作用日志 stub 替代控制台依赖；未修改仓库测试或宿主源码。
- 输入：episode → bufferFinished → 健康采样（playhead=100、buffered=20、isPlaying=true）→ paused → 20 个静止的 1 秒 tick（playhead=100、buffered=20、isPlaying=false）。
- phone 与 desktopTV 默认配置均在第 1 秒进入 suspect，第 12 秒执行 `reloadPlayArgs`（attempt 1／max 3）。对应 buffering 正向对照也在第 12 秒恢复。
- 结论：生产状态机确实没有将暂停排除在 stall 恢复之外；独立复现证明恢复动作发出，下面的设备步骤确认了实际自动续播。
- **设备确认失败**：response 093 仅发送一次 `d 201 437`；随后 094／095 均为空捕获，没有第二次双击或其他 UI 输入。日志记录 `09:38:29.755` bufferFinished → paused，`09:38:41.639` paused → preparing，随后 readyToPlay → bufferFinished，暂停约 11.884 秒后自行重建续播；截图视频时间继续前进，进程未变化。
- 因此可将“主动暂停被自动恢复覆盖”与“第二次双击重复响应”分离。日志未直接输出字面 `[Recovery]`，恢复动作归因由未修改生产状态机的确定性复现补充，而不是从该日志标签推断。
- 工具链：Xcode 27.0 RC（27A266a）／Swift 6.4／Swift 6 模式。证据目录：`angellive-pause-watchdog-20260914-X9JABl/`，含 `result.log`、harness、日志 stub 和生产源码 SHA-256。
- 这 4 个临时场景不计入前述 Core 295 项测试，也未用于关闭线上崩溃分组。

### 5. iPad 空环境与 FullUI

- 设备：已有标准 iPad Pro 13-inch (M5) / iOS 27；开始前已关闭本轮 iPhone，没有同时运行第二台 iOS 模拟器。
- response 140 创建 workspace session，141 `DeviceInteractionInstallAndRun` 成功，142 空捕获取得新进程；随后 MCP `BuildProject` 成功（12.113 秒），Navigator error 为 0。
- 欢迎页完成后默认进入 ShellUI 收藏，显示“暂无收藏”；配置页显示标题、地址及空输入时禁用的添加按钮；设置及返回导航正常（response 145～148）。未通过删除已有插件制造空环境。
- ShellUI 中插件管理与数据同步入口按当前源码隐藏；配置页将 `.json` 识别为订阅源并展示订阅安装 sheet，这是后续准备 fixture 的正常入口。
- 随后用户亲自为该 iPad 登录 iCloud。早先系统设置的未登录证据不再代表当前状态；本轮尚未在 iPad 添加任何 fixture 源或插件。
- 后续保留用户账户与同步开关，使用同步后的现有内容检查 FullUI 网格、侧栏和冷启动。本机源会参与源同步，因此不向已登录设备添加 loopback fixture；同名插件、可控元数据更新和移除选中插件的测试前置尚不具备，不以普通切换替代。
- 设备代理服务多次容量错误后移交；旧专用 helper／MCP bridge 已退出，接手代理重新连接。未重启 Xcode、App 或模拟器来规避交接问题。

### 6. 特殊运行环境核对

- 使用动态核验的 Xcode 27.0 RC，通过 `devicectl list devices` 及 `simctl list runtimes --json` 只读检查；未启动、停止或改变目录中的设备。
- 目录内 Apple TV 的 `hardwareProperties.reality` 均为 `simulated`，因此现有 tvOS 模拟器无法补齐真实 Apple TV 验收。
- 可用 iOS runtime 包含 17.5、18.5、26.5、27.0，没有 26.0／26.0.1；不能以其他系统替代符号动画同系统 A/B。
- 本机目录证据：`angellive-device-inventory-20260914-5zrzzxsw/devices.json`，只在临时目录保留，报告不记录个人设备名称与标识。
- 一次额外的独立 CLI `-showdestinations` 在锁定依赖解析阶段退出 74，未取得有效目标清单。该上下文错误不计作 MCP 构建失败，也不能证明目标不存在；未变更依赖或清理缓存。用户提醒后停止这条辅助排查，回到现有 MCP 会话逐项验收。

### 7. tvOS 26.5 启动与 iCloud 前置检查

- 用户已为现有 Apple TV 4K (3rd generation) / tvOS 26.5 登录 Apple 账户，本轮保留该账号与设备数据。
- 重新连接 Xcode MCP 后，workspace 与非 workspace 的 Device Hub session 接口均拒绝选择 26.5，可选列表只包含 27.0；未创建有效 session，也未完成 `DeviceInteractionInstallAndRun`。此限制不能解释成 tvOS 26.5 本身不支持 iCloud。
- 改用 MCP `RunProject`，在明确选中的 tvOS 26.5 上完成构建与启动，耗时 19.615 秒，`buildErrors=[]`。原生 Device Hub 窗口实际显示 26.5，方向与选择遥控按钮可用；经原生 UI 捕获确认新包已进入收藏、配置、设置导航。
- 初次构建曾因 `TVFavoriteRefreshIndicator` 未进入 Xcode 的源文件清单失败。磁盘文件与自动目录收录配置均存在；刷新文件时间戳并由 IDE 重新识别后构建通过，未修改源码或工程配置，未清理缓存。
- 无本地插件时显示“暂无收藏”，设置中没有 iCloud 同步入口；未出现云端插件提示。以上只证明应用启动和当前空环境，不能证明 CloudKit 账户不可用或读取成功。
- 调试运行跟踪多次返回错误，之后延迟状态才显示实际调试进程已运行；该结果到达时已开始停止并恢复普通运行，未执行 CloudKit 状态查询。不将工具跟踪错误归因于 iCloud。
- 本轮结论：26.5 新包普通运行已验证；自动化 Device Hub session、CloudKit 账户状态、实际云端读取和写入均未完成验证，收藏刷新完整场景仍待验收。
- 证据目录：`angellive-regression-20260914-111521/`，其中 response 004／005 为会话选择失败，007 为新包构建启动成功。截图与运行工具输出仅保留在本机临时目录。
- 收尾 response 017 普通运行成功（5.045 秒，`buildErrors=[]`），018 Navigator error 为 0。原生 Device Hub 保留在 26.5 新包界面；CUA 提示用户已改变窗口状态后立即停止操作，最终截图仅在工具输出中，未生成可交付的本地 PNG。

### 8. tvOS 收藏刷新提示对齐 iOS

- 用户在 tvOS 17.5 报告“部分收藏仍在更新”长时间显示。代码核对：两端共用 `FavoriteRefreshSession`，前台预算为 4 秒；单个房间请求总预算为 20 秒，同插件最多 5 个并发，请求排队可延长后台完成时间。
- iOS 的圆环仅跟随手动刷新与 `isFavoriteStatusRefreshing`；tvOS 额外依赖 `pendingPluginIds`，在前台结束后持续显示文字，直到后台全部完成，随后还展示结果 3 秒。因此两端等待感不同，不是 tvOS 配置了另一套更长的前台超时。
- 修改仅在 FullUI 的 `FavoriteMainView` 和 `TVFavoriteRefreshIndicator`：提示输入收窄为刷新布尔值与手动周期；前台结束后收起小圆环，保留 0.2 秒最短反馈与 0.4 秒淡出，不再显示后台等待及完成统计悬浮文字。
- 共享请求、CloudKit、后台结果回写、遥控器按键合并和 ShellUI 均未修改。此修复缩短界面等待反馈，不宣称加快上游网络请求。
- 修改前复用现有 Apple TV 4K (3rd generation) / tvOS 17.5，收藏页可见正在直播 20 项；观察时原提示已消失，未取得之前那次等待的精确持续时长。
- 最后源码编辑后 MCP `BuildProject` 成功（11.616 秒），编译日志明确包含两个修改文件，Navigator error 为 0；随后 `RunProject` 成功（5.01 秒），完成 17.5 新包安装与启动。
- 新包交互验证受阻：原生 Device Hub 遥控方向按钮返回解码错误；旧 Simulator 开启键盘捕获后两次方向键未观察到焦点变化，遥控器浮窗未被 CUA 暴露。新包当时停在推荐页骨架状态，未能进入收藏并触发手动刷新，因此不声称圆环出现、4 秒后消失、慢回写或连续按键已实测通过。
- 未创建有效 Device Hub API session，未完成 `DeviceInteractionInstallAndRun`；上面新包证据来自 MCP `RunProject`，与 API 设备验收分开记录。停止操作后保留设备、账号和新包。

### 9. tvOS 收藏封面更新对齐

- iOS 的收藏 UIKit 容器观察 `listVersion`，每次数据更新后重新配置卡片；macOS 直接使用当前收藏模型的封面 URL。两端 Kingfisher 都使用 URL 缓存，没有对同 URL 的图片内容强制重新下载。
- tvOS 的 `LiveCardView` 原先只接收 `LiveModel`，而该模型的相等判断仅比较房间身份，不能表达封面、标题等内容变化。本轮在 FullUI 收藏的竖向和横向分组中，把现有 `listVersion` 作为独立卡片输入，确保元数据回写能触发卡片更新。
- 保留稳定房间 ID 和卡片状态，不使用 `.id(listVersion)` 重建卡片，也不改变共享模型的身份相等语义。其他页面使用默认版本，ShellUI 行为不变。封面仍遵循三端现有的 URL 缓存策略；同 URL 内容替换不是本次修改已解决的场景。
- 最后源码修改后 MCP `BuildProject` 成功（14.775 秒），编译日志包含 `FavoriteMainView.swift` 与 `LiveCardView.swift`；构建及运行后 Navigator error 均为 0。MCP `RunProject` 成功（4.565 秒），完成既有 tvOS 17.5 新包安装与启动。
- 新包启动出现系统 Apple ID 验证弹窗；尝试用遥控器选择“以后”时，工具仍返回动作解码错误。随即停止设备操作，未更改账号或插件数据。因此新封面、标题刷新和焦点保持均未完成设备验收，不能仅凭构建通过宣称修复已实测通过。
- 证据目录：`angellive-regression-20260914-125048/`，response 005 为 BuildProject，007 为 RunProject，006／008 为 Navigator。没有有效 Device Hub API session，也没有 `DeviceInteractionInstallAndRun` 通过记录；本轮新包依据为普通 MCP RunProject。iOS、macOS 未重新构建或运行。

### 10. tvOS 重复“已下播”分组

- 确认生成路径缺陷：原 `groupedByLiveState()` 使用原始可选状态分组，`nil` 与明确下播值会分别生成 section，但 `liveStateFormat()` 将它们都显示为“已下播”。多个无效原始状态值同样可能生成重复的“未知状态”。这也违反 section 以标题为稳定 ID 的前提。
- 在 Core 新增 `groupedByDisplayLiveState()`，创建 section 前按现有显示状态统一分组，保留所有房间、组内顺序及既有状态分组顺序。tvOS FullUI 收藏页从当前房间列表显式调用；按平台分组仍使用原路径。共享模型、原分组 API、ShellUI 和云端数据不变。
- 新增 3 项回归覆盖缺失状态与下播合组、多个未知值与排序、刷新状态迁移及空分组移除；同时验证跨来源同房间编号不会丢失条目。定向 `FavoriteListGroupingTests` 6 项通过。
- 最后源码修改后 Core 全量 298 项 / 39 个 suite 通过，包含新增 3 项；使用 Xcode 27.0 RC（27A266a）/ Swift 6.4，依赖解析关闭自动更新。证据目录：`angellive-favorite-grouping-20260914-thi7QI/`，含 `targeted.log` 与 `full.log`。源码和依赖锁在测试前后哈希一致。
- 最后修改后 tvOS workspace MCP `BuildProject` 成功（16.408 秒），Navigator error 为 0；目标为既有 Apple TV 4K (3rd generation) / tvOS 17.5。证据目录：`angellive-regression-20260914-130259/`，response 005／006。
- 设备验收受阻：response 007 调试运行及 009 普通运行均返回 `Failed to track run action`，没有成功安装启动或新进程证据。当前可见推荐页且已无 Apple ID 弹窗，但不能据此把当前包视为最后修改后的新包，因此没有用其截图宣称分组、刷新或焦点通过。未创建有效 Device Hub API session，也未完成 `DeviceInteractionInstallAndRun`。结束自己的桥接进程并保留设备、目标与数据。
- iOS、macOS 宿主未重新构建或运行。全仓 566 个文本文件的平台标识与测试真实映射编号扫描无命中，`git diff --check` 通过。

其他设备场景继续执行中。
