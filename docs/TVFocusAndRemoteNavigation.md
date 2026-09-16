# tvOS 焦点与遥控器返回层级

更新：2026-09-16。范围仅为 tvOS FullUI；共享播放器、插件能力和 ShellUI 不参与本轮修改。

## 交互约定

| 当前状态 | 确定键 | 返回键 |
| --- | --- | --- |
| 首页 | 激活当前内容或用户选中的导航项 | 沿用系统侧栏导航行为 |
| 平台直播列表的分类侧栏展开 | 展开分类或选择子分类 | 关闭侧栏，留在列表并恢复内容焦点 |
| 平台直播列表，侧栏已关闭 | 进入当前房间 | 退出列表 |
| 平台分类加载后为空 | 保持空态 | 沿用当前侧栏显隐的返回层级；左键仍可进入分类 |
| 播放器控件隐藏 | 只显示控件，不执行暂停、刷新或收藏 | 退出播放 |
| 播放器控件显示 | 执行选中控件的动作 | 只隐藏控件 |
| 关联房间菜单展开 | 选择分区或房间 | 只关闭菜单，按当前控件显隐状态恢复播放器焦点 |
| 弹幕设置、清晰度或统计面板展开 | 操作面板中的选中项 | 只关闭面板，返回播放器控件 |

启动沿用 tvOS 原生侧栏 UX：允许侧栏默认展开，用户选择栏目后进入内容并收成胶囊。首页异步加载不应主动抢走系统侧栏的焦点。该行为依据 [Apple 的 Tab 导航示例](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation)。

## 问题与修复边界

- 首页的正式主按钮原来在异步挂载后无条件写入 `FocusState`，可能覆盖用户正在操作的导航焦点。已删除该启动任务及为自动收起侧栏增加的默认焦点偏好、共享焦点和占位交接方案。加载占位仅负责显示；透明轮播焦点代理只有在 Hero 已持有焦点时才可聚焦，用户操作轮播后仍回到主按钮。
- 列表侧栏原来独自处理返回键，整个列表没有明确的“先关闭侧栏，再退出列表”入口。返回处理由列表状态拥有者统一决定，恢复焦点时检查当前房间索引是否仍有效，空列表使用实际存在的入口。
- 分类主项、子项的最近共同容器通过 `onExitSidebar` 回调只执行收起菜单；内容区保留根级返回处理。列表作为全屏展示内容使用 `interactiveDismissDisabled()`，正常整页返回由应用显式 `dismiss()` 完成。系统交互退出限制对当前 tvOS 实际输入路径的效果仍以运行证据为准。
- 分类菜单展开时，背景房间卡片、平台信息和空态原来仍能参与焦点搜索；焦点变化回调还会据此提前收起菜单。现在展开期间禁用背景交互，菜单显隐只由明确的开关、返回或分类选择动作改变。返回收起后，在背景重新启用的视图树中恢复内容焦点，不用固定延迟或按键防抖。该结构缺陷已由源码确认，不能据此声称已捕获用户那一次偶发越级退出的完整时序。
- 分类选择曾同时通过 `roomPage` 的观察器和显式调用发出两次请求。模型现在提供单一分类选择入口，重置选中房间并只请求一次；请求快照固定分类和页码，旧响应不再覆盖当前分类，也不能结束当前请求的加载状态。自动分页在加载中不重复递增页码。
- 房间请求的 `index` 是子分类下标，不能据此判断是否归零房间焦点。默认分类下标为 `-1`、第二个子分类下标为 `1`，两者此前都会在加载后续页时错误清零；归零应依据实际第一页或明确的分类切换。
- 分类切换原来固定等待 0.2 秒就把焦点写到第一张卡片，与请求完成、空结果或卡片挂载没有关联。焦点恢复应在当前内容已挂载后进行，目标必须是实际存在的首张卡片或空态；用户继续操作遥控器时，应取消未完成的自动焦点恢复。
- 分类栏应由第一列房间、平台信息或空态上的明确左键进入，右键收起。不要用透明全高按钮意外获得默认焦点来表示用户要求展开菜单。
- 分类菜单展开时隐藏左下角的刷新提示，避免它覆盖子分类条目。
- 播放器隐藏焦点按钮原来的 primary action 为空，因此确定键不会显示控件。该动作应只进入控件显示状态。
- 播放器的关联房间菜单、设置面板和整个控制层分别注册返回处理。将优先级集中到控制层的一处入口，避免一次按键在菜单关闭后继续按页面退出状态处理。面板的显式关闭按钮仍复用各自关闭动作。

默认焦点 API 依据 [Apple 的 defaultFocus 说明](https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:))与 [focusScope 说明](https://developer.apple.com/documentation/swiftui/view/focusscope(_:))。焦点偏好用于初始和自动迁移；不能用重复延迟设焦点来替代用户的遥控器导航。

## 验收

以最后一次源码修改后的 workspace MCP 构建和 Device Hub 新安装为准，逐次检查单个返回键后的页面、菜单及焦点状态。启动、菜单取消与播放退出分别记录，不能把“已发出按键”算作通过。

2026-09-16 验证环境：`AngelLive.xcworkspace` / `AngelLiveTVOS`，Apple TV 4K (3rd generation) 模拟器，tvOS 27.0。以下 12:55 以前的记录属于早期版本，当时已完成对应源码的 MCP 构建、零 error 检查及 `DeviceInteractionInstallAndRun`；最新源码的结果见本节末尾。

此前版本的冷启动空捕获中，加载占位先获得焦点，正式内容到达后交给主按钮；收起动画结束后的截图确认只剩系统导航胶囊。这只证明了动画结束后的状态，不代表首帧未展开。后续启动录屏确认，子页面和根级默认焦点方案均未消除首次展开。用户确认保留原生启动 UX 后，已撤销这些启动焦点干预；以下早先记录不能代替撤销后的新包验收。

此前版本中，手动展开系统侧栏后，再次捕获仍保留侧栏焦点。平台主分类侧栏的一次返回、播放器关联菜单的一次返回、清晰度面板的一次返回和最后退出播放回到原列表均已通过。

早期版本补充验收使用当时源码的新安装：确认分类子项实际持有焦点后，单次返回关闭整个侧栏并恢复房间卡片焦点；确认播放控件已完全隐藏后，单次确定显示控件并聚焦暂停按钮，视频继续播放。控件可见时的一次返回只隐藏控件。

这部分工具响应、截图与 hierarchy 路径保存在临时证据索引 `/tmp/angellive-tvos-focus-evidence.json`。关键稳定截图时间为 12:53:53（冷启动）、12:55:03 / 12:55:05（子项返回前后）、12:55:25 / 12:55:35（隐藏态确定键前后）。早期验收结束时已关闭对应 session，并恢复原来的 `AngelLive` / `iPad mini (A17 Pro) (27.0)` 目标；之后的房间分类排查重新建立了 session。

验证控件显示状态下的返回时，确定键与返回键应在 5 秒自动隐藏期限内连续执行。不能以十几秒前的截图推定返回时控件仍然可见。分类子项则需明确看到子项的 `Focused` 标记，不能只以子项已经展开作为前置条件。

本轮没有重新运行 Core 单元测试、iOS 或 macOS 构建；未验证实体 Apple TV 和其他 tvOS 版本。

### 恢复系统启动 UX 后的验收状态

14:33 安装的版本已经恢复原生系统侧栏启动 UX；它早于后续的分页焦点修复、刷新提示避让和分类背景焦点隔离，不能代表最终源码的验收结果。

当前模拟器输入仍需核验：在未传 `activationBundleId` 的情况下，Device Hub 的 `r down` 没有沿先前截图中的系统侧栏移动，而是进入内容区；Simulator 原生方向键与 Return 的对照也未取得稳定结果。用户随后指出手动打开的菜单被后续自动返回关闭，因此上述跨截图操作没有建立可靠的前置状态，不能据此判定 App 缺陷或工具路由异常。后续先读取用户当前窗口，重新建立前置状态再操作；房间分类的最终交互结果不能复用此前版本的记录。

输入对照依据 [Apple 的 Device Hub tvOS 操作说明](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-the-tvos-simulator)：方向键移动焦点、Return 激活、Escape 返回。此处仅记录本次环境现象，不将它作为禁用某种工具或修改系统导航的通用规则。

用户随后明确，偶发问题发生在房间分类菜单的主分类和子分类焦点下，检查对象是返回键。右键成功不能代替返回键验证。旧包重复检查主分类 5 次、子分类 4 次，均在前置截图确认菜单项持有焦点后发送一次 Menu，结果都留在房间列表；这只表示该样本未复现越级退出。返回后部分 hierarchy 缺少 `Focused` 标记，但原图仍显示首卡放大，不能仅据标记缺失断言焦点丢失。

新修复增加 `RoomListNavigation` 调试记录，仅包含动作、焦点下标、菜单显隐和加载状态，以便核对 Exit 与焦点变化的顺序，不记录房间或插件私有数据。

背景焦点隔离后的最终代码于 15:12 通过 workspace MCP `BuildProject`（12.536 秒），Issue Navigator 的 error 数为 0，随后通过 workspace session 的 `DeviceInteractionInstallAndRun` 重新构建、安装和启动。测试沿真实的“推荐 → 左上角侧栏 → 配置 → 平台 → 房间列表”路径进入。

新包于 15:18–15:19 完成主分类 5 次、子分类 5 次单次返回。每次按键前均由 hierarchy 确认目标菜单项持有焦点；10 次均收起分类菜单、留在房间列表、恢复房间卡片 `Focused` 标记，App 进程保持不变。这组日志累计恰好 10 个 `exitCommand`，全部发生在 `expanded=true`，且 `dismissList` 为 0。root 独立核对了原始 hierarchy、日志及代表截图。工具可能在动画中途截取返回后的画面，不能把过渡帧当裁切或重叠故障；后续空捕获已核对收起动画结束后的稳定画面。

补充重选首个子分类、切到第二个子分类后的返回均留在列表，总计 12 个 Exit，`dismissList` 仍为 0。第二个子分类的数据更新后，AX 未输出 `Focused` 标记，但原图显示原生卡片放大；向下后日志与实际高亮从 `mainContent(0)` 移到 `mainContent(4)`，向上后恢复 `mainContent(0)`。这证明该样本实际可以导航，不能把 AX 标记缺失作为丢焦结论。随后打开分类菜单并单次返回，15:25:26 的稳定原图显示侧栏已收起、首卡仍高亮，刷新提示仅在菜单收起时出现。

对应本机证据为 `/tmp/angellive-sidebar-isolation-{build,nav,install}.json`、`/tmp/angellive-sidebar-isolation-main-{1..5}-{before,after}.json`、`/tmp/angellive-sidebar-isolation-sub-{1..5}-{down,menu}.json` 和 `/tmp/angellive-sidebar-isolation-second-{down-check,up-check,menu-stable}.json`。这组结果覆盖 tvOS 27.0 模拟器上的上述返回操作；未验证实体 Apple TV、其他系统版本或 iOS/macOS。

### 右键收起后的再次展开

用户后续补充了另一条失败路径：房间列表左键打开分类、右键回到列表、再次左键打开时，焦点没有进入分类。上面的单次 Menu 循环不能代替这条重新进入路径的验证。

原实现把菜单焦点任务放在有出入场动画的条件内容中，只依赖该子视图的挂载生命周期。现在将任务放到持续挂载的 `SidebarView` 根容器，并使用 `.task(id: isSidebarExpanded)`，每次展开都明确请求主分类焦点；关闭状态不写入分类焦点。依据 [Apple 的 task(id:) 说明](https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:))，id 变化会取消旧任务并重新启动。该修改不依赖动画完成时间，也不增加固定延迟或按键防抖。

这次修改已于 15:39 通过 workspace MCP 构建（11.646 秒），Issue Navigator error 数为 0，随后完成新的 workspace `DeviceInteractionInstallAndRun`。同一标准 tvOS 27.0 模拟器上，重新经配置入口进入房间列表后，逐步的左／右／左验证 3 轮、同一命令内 `r left r right r left` 连续验证 5 轮均通过。每轮第二次打开后主分类持有焦点，下一次下键能移到另一主分类，右键能恢复房间卡片焦点。

root 独立比较了每轮快速操作前后的累计日志：每轮准确增加 2 个 `openSidebar`、1 个 `closeSidebar` 和 2 个 `sidebarFocusRequest`；这确认中间确实收起过，第二次展开也确实重新请求焦点。所有轮次 `dismissList` 为 0，最后单次 Menu 回归与稳定空捕获均留在列表。原图可能捕获到菜单动画中途，最终返回的稳定原图为 15:47:30。

本轮证据索引：`/tmp/angellive-reopen-{build,nav,install}.json`、`/tmp/angellive-reopen-slow{1..3}-*.json`、`/tmp/angellive-reopen-fast{1..5}-{sequence,down,reset}.json` 与 `/tmp/angellive-reopen-menu-stable.json`。此前已安装包的单步序列未复现用户现象，因此这里不把特定的旧包动画内部时序写成已观测事实；新任务触发方式和新包上述交互结果均已核验。

### 列表模型的持有方式

用户在后续版本仍报告分类菜单单次返回会退出整个房间页，因此上述通过样本不能视为该偶发问题已经解决。15:58 对当前安装附着检查，主分类、子分类各一次 `r menu` 都留在房间列表；附着 session 没有取得导航控制台日志，未捕获用户报告的失败时序。

随后源码检查发现列表模型的持有方式不正确：`ListMainView` 在初始化器中创建 `@Observable LiveViewModel`，却用普通属性存储。相同视图身份被父级重新构造时，新模型的侧栏默认关闭，而焦点等动态状态仍可能被保留。现改为 `@State` 持有模型，并由页面任务执行一次初始加载，避免临时视图值的模型构造启动额外请求，也避免从播放器返回时重复初始加载。现有导航日志追加模型实例标识，用于核对展开、焦点请求和返回是否读取同一实例。这是已确认的所有权缺陷；它与用户那次越级返回的因果关系仍需运行证据，不能仅凭源码推断完全复现。

最终源码于 16:09 通过 workspace MCP `BuildProject`（11.1 秒），Issue Navigator error 为 0，随后完成新的 `DeviceInteractionStartWorkspaceSession` 和 `DeviceInteractionInstallAndRun`。在标准 Apple TV 4K（第 3 代）、tvOS 27.0 模拟器上，主分类单次 Menu、子分类单次 Menu、连续左／右／左后单次 Menu 各 2 轮，均关闭侧栏、留在房间列表并恢复首卡焦点。root 独立读取原始日志：8 次展开、8 次菜单焦点请求、6 次 Exit、8 次关闭均为同一模型实例，6 次 Exit 的 `expanded` 全为 true，`dismissList` 为 0；并查看 16:17:04 子项聚焦和 16:17:12 返回后的原尺寸截图。

证据索引为 `/tmp/angellive-model-state-{build,nav,start,install}.json`、`/tmp/angellive-model-state-{main,sub,lrl}*-*.json`。原生 Mac Escape 对照未完成：CUA 选择 Device Hub 应用时阻塞，由 root 中断，未实际发送 Escape。以上结果仅覆盖工具注入的 Siri Remote Menu，不能代替键盘 Escape 或实体遥控器验证；iOS、macOS 和其他 tvOS 版本本轮未验证。

### 分类区域直接处理返回

用户在模型持有方式修复后再次报告同一问题，说明上一轮修改不足以解决。当前机器已有一个 Simulator 窗口显示标准 tvOS 27.0 设备；它与 RC Device Hub 是不同的输入表面。读取该既有窗口成功，但自动化发送 Return、Left 后设备层的焦点与页面没有变化，因此未继续盲发 Escape，也不能声称复现了真实键盘返回。

本轮直接调整命令归属：在主、子分类按钮共同祖先 `mainSidebarContent` 注册局部 `onExitCommand`，调用列表传入的关闭回调，回调没有退出页面操作；根级处理保留为内容区及未交接焦点时的入口。另在全屏内容根设置 `interactiveDismissDisabled()`，限制非程序化关闭。Apple 文档说明该修饰符不影响显式 `dismiss()`，但未逐项保证 tvOS 全屏展示的所有输入路径，因此不能单凭这个修饰符断言问题已解决。日志区分 `sidebarExitCommand`、根级 `exitCommand`、`dismissList` 和 `listDisappeared`，用于跟踪真实按键。

本轮生产源码于 16:33 通过 workspace MCP 构建（10.668 秒），Issue Navigator error 为 0。构建证据为 `/tmp/angellive-native-owner-{build,nav}.json`；新的设备安装与实际按键结果单独记录，不复用此前的 Menu 通过样本。

随后完成新的 workspace `DeviceInteractionInstallAndRun`。主项、子项各一次工具 Menu 回归均只记录 `sidebarExitCommand → closeSidebar`，没有进入根级 Exit 或整页退出；菜单已关闭时的一次 Menu 则记录 `exitCommand → dismissList → listDisappeared`，正常返回平台网格。root 独立检查了这些原始日志。对应证据为 `/tmp/angellive-native-owner-{start,install,main-after,sub-after,page-exit}.json`。

为等待用户实际按键，将新包停在子分类焦点并保留会话。首次等待期间会话失效：最后截图为 16:36:21，系统进程记录显示 App 在 16:38:22 收到 SIGTERM，随后位于电视桌面；没有取得实际按键后的 App 导航日志，不能把这个进程结束认定为菜单越级返回或 App 崩溃。约两分钟的间隔提示可能存在工具空闲清理，但未取得明确的工具超时日志。系统证据为 `/tmp/angellive-native-owner-process-exit.log`。之后重新安装同一源码版本，恢复子项焦点，并用仅观察的空捕获保留会话；这些捕获不发送遥控器指令，不能代替用户实际输入验证。

恢复后的有界等待未检测到用户事件，10 次空捕获中 App 进程、子项焦点和导航日志行数均未改变，因此实际按键验证仍未完成。结束 workspace session 后，本机观察到它启动的 App 也结束。为保留用户手测现场，随后通过非 workspace 的检查 session 从电视主屏启动同一已安装新包，仅恢复分类子项焦点，再结束检查 session；这次 App 进程仍正常运行。最终恢复 Xcode 原来的 `AngelLive` / `iPad mini (A17 Pro) (27.0)` 目标并关闭 relay。交接证据为 `/tmp/angellive-native-owner-restore-focused.json`、`/tmp/angellive-native-owner-restore-post-end-ps.txt` 和 `/tmp/angellive-native-owner-final-restore.json`。此恢复方式仅用于最后源码已安装之后的手测交接，不能替代修改后的新包安装门禁。

### 快速左键接返回键的焦点交接

用户再次报告列表左键打开分类后返回会直接退出页面，并明确指出等待较长时间后再返回无法覆盖问题。此前等待菜单持有焦点后的 Menu 通过记录不能作为此路径已经修好的证据。

代码原来在 `isSidebarExpanded` 变为 true 时立即禁用背景；分类内容条件插入后，另一项任务才请求菜单焦点。现将背景禁用条件改为侧栏展开且 `FocusState` 已指向主／子分类，避免打开动作先移除原卡片的焦点资格。菜单接到焦点前，原内容的根级返回回调仍可按展开状态收起菜单。此改动没有引入固定延迟或按键防抖；`FocusState` 赋值与实际焦点迁移的先后仍须用快速输入核验，不能仅凭代码认定所有窗口已经消除。

导航诊断新增 Debug 系统日志，保留未连接调试会话时的通用动作、焦点与页面消失记录。17:22:36 的 workspace MCP 构建通过（10.789 秒），Issue Navigator error 为 0；设备验收必须使用此次编辑后新安装。Device Hub 的 `r left r menu` 可以链式发送，但工具没有公开两键间隔参数，也会等待动画；同一条命令不等于已证明零间隔，验证须核对日志时间和命令实际归属。

17:24 的实际日志显示单链 `r left r menu` 中，打开到菜单聚焦约 120 毫秒，打开到返回处理约 558 毫秒，因此这次工具输入没有覆盖菜单交接前的阶段。工具键盘文本命令里的 Escape 字符也没有进入 App 的按键处理，不能替代原生键盘。随后曾临时延长菜单插入时间、切换背景禁用条件，准备做诊断对照；此实验未完成，不能报告为修复证据。所有临时开关与延迟在正式修复前均已移除。

### 捕获到的 Escape 越级退出与正式修复

17:29:31 捕获到非工具遥控器命令的原生 Escape：按下和松开时 `focus=leftMenu(0,0)`、`expanded=true`，随后记录 `listDisappeared`，但没有 `sidebarExitCommand`、根 `exitCommand` 或应用显式 `dismissList`。菜单在此次 Escape 前已经取得焦点，因此这次失败不能归因于等待菜单焦点，也不能用工具 Menu 的通过样本解释。原始日志位于 `/tmp/angellive-probe-legacy-list.json` 引用的 `logsPath`。原生前台窗口经只读检查确认为同一 tvOS 27.0 Device Hub。

正式修复在列表根增加硬件 Escape 处理：按下、重复和松开均返回 `.handled`，只在松开时调用一次 `handleBackCommand()`；菜单展开时收起并恢复内容焦点，菜单已关闭时才退出列表。遥控器 Menu 继续通过既有 `onExitCommand` 调用同一返回函数。选择松开时改变界面，可避免按下收起菜单后，同一按键的松开又被下一层解释为退出页面。播放器和能力弹窗仍使用各自呈现内容的返回层级，须在新包中检查没有触发底层列表退出。

移除临时探针、完成 Escape 正式处理后的 workspace MCP 构建于 17:32:55 通过（10.095 秒），Issue Navigator error 为 0。后续验收使用最后编辑后新的 `DeviceInteractionInstallAndRun`，原生 `Left → Escape` 两键之间不得插入截图或人工等待。

最终新包原生快速路径于 17:36:16 通过：同一个 System Events 脚本连续发送 Left、Escape，中间没有延迟或截图。日志中 `openSidebar` 为 16.653084，Escape down 为 16.659966，up 为 16.660993，`closeSidebar` 为 16.661077；返回到达时距打开约 7 毫秒，焦点仍为 `mainContent(0)`，没有发生菜单焦点请求。按键只收起菜单，未产生任何 `dismissList` 或 `listDisappeared`，最终 hierarchy 中原首卡仍为 `Focused`。root 独立读取了原始日志、hierarchy 和原尺寸截图。证据为 `/tmp/angellive-native-escape-main-after.json`；设备为同一标准 Apple TV 4K（第 3 代）、tvOS 27.0 模拟器。这是实际原生快速输入结果，不使用临时延迟探针，也不以工具 Menu 的慢速通过替代。

子分类补充验证于 17:40:06 通过：先确认 `leftMenu(0,1)` 实际持有焦点，再发送一次原生 Escape；down、up 均保持该子项和 `expanded=true`，up 后仅关闭侧栏，随后恢复 `mainContent(0)`，页面仍在房间列表。root 已独立核对 `/tmp/angellive-native-escape-sub-final-stable.json` 中的日志与 hierarchy。17:37–17:38 期间受并发用户输入影响的中间操作未计入此结论，不能以主分类的返回冒充子分类回归。

本轮全速 Left／Right／Left 未取得完整事件链，未计为通过；能力弹窗与播放器边界未完成本轮回归。原 workspace session 失效后没有重新构建或继续扩展测试，而是用非 workspace session 从电视桌面正常启动同一最终包。17:48:21 的最终 hierarchy 确认房间首卡持有焦点；结束检查 session 后进程仍运行。证据为 `/tmp/angellive-native-escape-final-list.json`、`/tmp/angellive-native-escape-cleanup-end.json` 和 `/tmp/angellive-native-escape-final-process.txt`。Xcode 已恢复原 scheme 与运行目标，relay 已关闭。实体 Apple TV、其他 tvOS 版本、iOS 与 macOS 本轮未验证。
