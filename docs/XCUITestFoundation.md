# 三端 XCUITest 底座与历史冒烟

## 本轮范围

首批测试使用 Xcode 27.1，从根 `AngelLive.xcworkspace` 构建三个正式宿主 scheme。测试通过 Debug 专用启动路由打开真实 FullUI 历史页面，验证历史类型切换、删除、清空范围、重启持久化及 tvOS 遥控器焦点。

这组测试不覆盖首页至历史页的完整导航、真实插件安装、在线起播、CloudKit 多设备同步、投屏或 tvOS 分类侧栏。测试通过不能替代这些链路的验收，也不能替代实际布局截图复核。

## 测试入口

| 平台 | Scheme | UI Test target | Test Plan |
| --- | --- | --- | --- |
| iOS / iPadOS | `AngelLive` | `AngelLiveUITests` | `iOS/HistorySmoke.xctestplan` |
| macOS | `AngelLiveMacOS` | `AngelLiveMacOSUITests` | `macOS/TestPlans/HistorySmoke.xctestplan` |
| tvOS | `AngelLiveTVOS` | `AngelLiveTVOSUITests` | `TV/TestPlans/HistorySmoke.xctestplan` |

所有 UI target 均按串行执行，不启用模拟器克隆或同平台并行。商店 macOS 变体与 tvOS 另一产品 scheme 不纳入本轮冒烟。

## 启动与数据隔离

测试 runner 为每条用例生成 UUID，首次启动传入：

```text
--ui-testing --ui-test-run-id <UUID> --ui-test-reset
```

验证持久化时复用同一个 UUID，移除 `--ui-test-reset` 后重新启动。无初始状态的恢复启动必须失败，不能自动补回已删除数据。Release 不提供测试路由。

`UITestHistoryContext` 创建两条合成直播记录和两条合成短剧记录；短剧记录通过现有进度存储 API 写入。文件位于当前 App 缓存中的 UUID 专属目录，defaults 使用相同 UUID 的专属 suite。重置只作用于该次运行，拒绝符号链接目录。

有效测试启动隔离共享 defaults、插件目录、插件凭据访问及本地收藏文件；历史页注入独立历史、进度和离线收藏模型。宿主不启动正式首页、云同步、凭据导入、更新器、Top Shelf 同步或遥控输入服务。不得把真实 Cookie、Token、私有插件或用户历史写入 fixture、日志或附件。

macOS 测试启动关闭主窗口自动呈现及恢复，由 runner 通过原生 File > New Window（⌘N）创建真实主 WindowGroup，并断言只有一个窗口。测试交互前激活目标应用，保留严格可点击性和结果断言。桌面仍须避免其他应用抢占前台；普通启动沿用原自动呈现与恢复行为。

## 用例与证据

- iOS：点击与横滑切换；两类单项及最后一条删除；分别清空当前类型；取消清空；删除后重新启动。
- macOS：类型切换；上下文菜单取消及删除；两类最后一条删除；清空确认与类别隔离；重新启动后仍保持删除及清空结果。
- tvOS：焦点移动与 Select 激活分离；向下进入首卡；长按菜单取消回源；删除转邻卡及最后一条返回类型；分类清空；重启持久化。

UI 测试使用条件等待和稳定业务身份，不以发出事件代替结果断言。tvOS 检查实际 `hasFocus`；方向键测试不代表实体触控板滑动通过。关键状态截图及 hierarchy 保存在测试结果附件中。

执行前先动态核验 Xcode 版本和现有设备，保留用户数据与其他任务现场。workspace MCP 工作流为选择 scheme/destination、`BuildProject(buildForTesting: true)`、检查错误导航器、`GetTestList`、`RunSomeTests`；定向问题解决后运行该测试计划全量。必须等当前请求最终响应，再发下一项构建或运行操作。

验证记录同时保存源码状态、设备/OS、测试数量、首次失败、修复及最终结果。被取消、未运行、跳过和工具阻塞均不算通过。最后修改后的新包截图用于复核历史页面布局，不能复用旧包证据。

## 本轮执行状态

执行证据集中在被忽略的 `runs/xcuitest-foundation-2026-10-21/`。开始前已创建检查点提交 `2abaf0d3`，保留原有历史页及发布准备改动；本轮新增测试和修复继续保留在工作区。

工具链为 Xcode 27.1（27A9275），均使用根 workspace MCP。以下结果仅代表本测试计划，不代表整个仓库所有测试通过。 iOS 的 7/7 结果对应本轮冒烟完成时的源码；同仓后续 iPhone Duo 适配（包括历史空态的局部窗口上下文接入）不包含在该结果中，应由其新包验证。

| 平台 | 本轮实际目标 | 构建 | 最终核心冒烟 | 证据 |
| --- | --- | --- | --- | --- |
| iOS | 既有 iPhone 17 / iOS 27.0 模拟器 | 通过 | **7/7 通过**，无跳过、失败或未运行 | `results/57-BuildProject`、`results/59-RunAllTests` |
| macOS | My Mac / macOS 27.0（26A428） | 通过（2026-10-24 MCP 复测） | **6/6 通过**，无跳过、失败或未运行；清空、两类最后一条删除与重启持久化已收尾 | `runs/macos-history-finish-20261024/results/13-BuildProject`、`runs/macos-history-finish-20261024/results/16-RunAllTests` |
| tvOS | 既有 Apple TV 4K（第 3 代）/ tvOS 27.0 模拟器 | 通过 | **5/5 通过**，无跳过、失败或未运行 | `results/44-BuildProject`、`results/48-RunAllTests` |

Core 的 `UITestHistoryContextTests` 5/5 通过；参数校验最后修改后又定向复测 1/1 通过，分别见 `core-tests.log` 与 `core-parameter-tests-approved.log`。这些不是 Core 全量测试结果。

### 已定位并修复

- iOS 测试最初定位到 SwiftUI 原生 alert 的内层 Button，该节点存在但不可点击。按实际 hierarchy 改为外层操作按钮，仍要求 `isHittable`；不使用坐标或放宽断言。
- iOS 原类型条的原生 collection cell 在点击后保留选中位，横滑回另一类型后使两项同时暴露为 Selected。现在用位于原 cell 实际边界的无障碍元素表示两个类型，状态跟随 JX `selectedIndex`，激活仍调用原有选择路径；不改变原生布局或视觉状态。点击和两个横滑方向均检查选中互斥。
- tvOS 原生上下文菜单由外层 Cell 持有焦点，确认 alert 由外层 Button 持有焦点。按实际层级修正查询，并按实际水平/垂直方向移动；保留严格 `hasFocus` 和删除/清空结果断言。失败时在 XCTest 中断前保存截图和完整 hierarchy。
- macOS 首次实际运行时只有菜单栏，没有窗口；日志明确由测试等待失败后主动终止应用，没有发现相应的新崩溃报告。仅设置自动呈现策略未解决；原生 ⌘N 单变量诊断通过，最终测试合同改为显式新建一个真实主窗口。
- Swift 6 下的 XCTest 生命周期隔离、JX 数据源 override 隔离及 macOS SceneBuilder 条件分支编译问题均已在 workspace 构建中修复，未加入 unsafe 隔离豁免。

### 初轮视觉和验证边界（后续 macOS 收尾见下文）

iOS 最新类型切换截图及 hierarchy 位于 `results/58-RunSomeTests/attachments/`：原类型条保持 56 pt，卡片保持 173.5 × 137.6 pt，标题、副标题、图标和间距未改；当前类型唯一选中。tvOS 最新全量附件位于 `results/48-RunAllTests/attachments/`，结合定向删除邻卡截图复核原按钮、卡片焦点和短剧空态。iOS 全量新包的空态与剩余短剧第 2 集 / 1:00 进度截图也已复核，位于 `results/59-RunAllTests/attachments/`。逐项记录见 `visual-review.json`。

本轮未新增布局；仅对上述实际尺寸、默认外观、已有列表及空态给出截图结论。iPad、横屏/分屏、动态字体、长文本、另一外观模式、真实 VoiceOver 操作及实体遥控器未验证，不据此次冒烟推断通过。macOS 已取得真实历史窗口的类型切换及短剧列表截图（`results-macos/14-RunSomeTests/attachments/`）；已复核原 44 pt 类型按钮、20 pt 左侧间距、标题和进度副标题。直播空态录像帧也已复核，短剧空态及完整交互验收尚未完成。

macOS 早期测试曾因 Enable UI Automation 系统认证超时而未运行；在新的有效请求中由用户完成认证后，runner 已正常执行。电脑控制工具拒绝访问 `coreautha`，未读取或保留系统密码，也未修改认证策略。随后首次全量 6 条均因无窗口失败（`results-macos/6-RunAllTests`）；窗口修复后定向 3 条通过 2 条，清空失败时截图和日志显示其他桌面窗口遮挡。增加交互前激活后，定向清空已通过取消、确认和直播空态，但点击短剧后仍停在直播类型，失败截图再次显示其他应用在前台（`results-macos/16-RunSomeTests`）。不能把此次失败认定为业务数据丢失，也不能计为通过；离线复核合成事件与录像进一步确认：点击坐标 `(550,88)` 是最新短剧按钮中心，录像第 27 秒 App 在前台、第 28 秒已切至其他聊天；没有旧几何坐标证据。需要无前台干扰的时段复测清空，再跑完整 6 条。

恢复时全仓扫描覆盖 Git 跟踪及未忽略文件中的 739 个文本文件，另盘点 93 个二进制文件。六处短词歧义经复核为通用恢复计数/查询占位及对应说明，没有确认的具体内容平台标识；`liveType` / `siteId` 数字映射候选为零。有限词表、未对二进制 OCR 等边界保留在 `connection-4/neutrality-snapshot.json`，不把扫描结果扩大为未知标识绝对不存在。

前一阶段 Xcode Issue Navigator 的 error 查询为零（`connection-2/response-60.json`）；后续 macOS 已产生上述实际测试失败，不能继续把旧查询作为最终无错误结论。最新 workspace 构建通过，`git diff --check` 通过。

2026-10-22 01:00 前后，本任务已恢复原 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)`、结束 connection-3 bridge，并把 Xcode 与原生 UI 时段释放给同仓 iPhone Duo 适配任务。之后 Duo 任务已归还操作权，但其工具故障使当前目标仍停留在 `AngelLive / iPhone Duo`。本任务恢复时重新核验 Xcode 27.1，关闭已归还的 Duo 及高占用预览模拟器；Computer Use 随后明确报告 Mac 已锁定、自动解锁失败，已请求用户手动解锁。connection-4 仅完成 MCP 初始化，尚未取得工具列表、切换目标或启动构建/测试。恢复记录见 `connection-4/recovery-status.json`；三端新一轮验证仍未完成。未删除 App、插件、缓存或用户容器数据。

## macOS 收尾复测（2026-10-24）

证据目录为 `runs/macos-history-finish-20261024/`。基于 `3a331957` 及保留的工作区改动，继续收尾上述 macOS 六条用例；本轮只修改测试与记录，不修改产品布局。补充类型选中互斥、点击前 `.runningForeground` 断言，以及直播空态、两类清空和清空后重启的截图附件。

Xcode 27.1（27A9275）/ My Mac / macOS 27.0（26A428）的根 workspace 命令行 `build-for-testing` 已成功，日志为 `build-for-testing.log`。此结果明确属于命令行构建，不是 MCP workspace BuildProject；新 MCP 客户端仍等待用户批准。

命令行必须从独立工作目录执行并传入根 workspace 绝对路径。KSPlayer manifest 检查当前目录旁的 FFmpegKit；仓库父目录存在同名开发仓库时，从仓库根启动会误选本地依赖。保持锁文件和依赖版本不变，使用独立目录及禁止自动更新参数后解析、构建成功；同类历史依据见 `Release-2.2.0.md`。

首次 `-enumerate-tests` 已启动最新 runner，但 macOS“Enable UI Automation”系统认证等待超时，发现结果中含 `Timed out while enabling automation mode`，实际测试数为 0。该命令退出码为 0 且输出 `TEST EXECUTE SUCCEEDED`，不能据此判定测试发现或用例通过；须检查 `enumerated-tests.json` 的 `errors` 和实际用例清单。已请求用户正常完成系统认证，未读取、代填密码或修改认证策略。

截至 2026-10-24 23:03 +08:00，未收到系统认证或 MCP 客户端授权完成信号，未重复发起需要认证的无效测试。定向 4 条和完整 6 条均未执行，本轮没有新的历史页面截图。最新产品、测试和工程构建输入哈希仍与成功构建前快照一致，可在完成系统认证后直接复用本轮测试包继续。汇总为 `acceptance.md`、`acceptance-status.json`；实际测试数为 0 的独立结果摘要为 `discovery-summary.json`。本轮未改变 Xcode 的 UI scheme/destination，未操作用户历史、插件、账号或缓存。

### 授权后恢复

23:33 用户要求继续时，同一 MCP 客户端授权已生效。重新发现已核验的 Xcode 27.1 和 workspace；保留其他项目窗口，在 AngelLive 窗口选择 `AngelLiveMacOS / My Mac / HistorySmoke`。workspace MCP `BuildProject(buildForTesting: true)` 成功，随后 error Navigator 为 0；`GetTestList` 确认六条均启用。初次定向四条为 3 通过、1 失败，无跳过或未运行（`response-9.json`）。失败仅为三次真实启动的持久化用例超过计划默认 60 秒；日志显示第三次启动和直播记录保留已完成，59.54 秒正切回短剧时被执行时间上限截断，没有业务断言失败。

仅该持久化用例设置 `executionTimeAllowance = 120`，测试计划最大额度从 90 秒调整为 120 秒，其他用例继续使用默认 60 秒；元素条件等待仍为 5 秒，未删减断言或跳过交互。重新 MCP 构建成功，定向复测 **1/1 通过**，实际耗时 **65.451 秒**（`response-13.json`、`response-15.json`）。新包重启后的短剧空态截图和 hierarchy 位于 `results/15-RunSomeTests/attachments/`，44 pt 类型按钮、20 pt 左侧间距、单一选中和空态无清空按钮已复核。

首次定向日志也记录聊天窗口曾遮挡测试 App；Computer Use 明确拒绝操作聊天应用，未尝试其他接口绕过该限制，已告知用户测试期间保留前台。新包测试继续使用严格可点击性、前台状态、选中互斥及实际结果断言。

### 最终结果：六条全部通过

最终 workspace MCP `RunAllTests` 为 **6/6 通过，0 失败、0 跳过、0 未运行**（`response-16.json`）。从最终 `.xcresult` 独立导出的摘要同样为 Passed / 6 passed / 0 failed / 0 skipped，实际总时长 243.028 秒；本次持久化用例耗时 63.830 秒。最终 error Navigator 为 **0**（`response-19.json`）。首次超时、参数修正及复测结果均保留，未覆盖初次失败证据。

主代理已逐张复核最后编辑后新包的五张截图及对应 hierarchy，均位于 `results/16-RunAllTests/attachments/`：短剧列表、直播最后一条删除空态、短剧最后一条删除空态、两类清空结果、重启后短剧仍为空。与初轮同状态截图对照，类型按钮维持 44 × 44 pt、左侧 20 pt、两按钮间距 16 pt；短剧卡片封面视觉边界、头像、标题和进度副标题保持原样，空态图标与两级文字清楚完整，当前类型唯一选中，空态没有清空按钮。无新增布局或偏移修补。清空按钮消失时系统标题栏按原行为收紧，不拿有清空按钮的列表标题栏高度作为空态基准。当前结论限于该默认深色窗口和六条业务用例；不扩展为所有窗口尺寸、外观或无障碍矩阵通过。

本次保留用户及其他任务的未提交改动；未操作真实历史、账号、插件或缓存。已将本次重新打开 workspace 时观察到的运行目标恢复为 `AngelLive / iPhone 17 (27.0)`（`response-20.json`），保留原有其他项目窗口。最终汇总、测试源码哈希及视觉逐项记录为 `acceptance.md`、`acceptance-status.json`、`final-tested-source-hashes.json`、`visual-review.json`。
