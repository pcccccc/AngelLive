# Device Hub 与设备验收

**触发条件：模拟器或真机 UI 操作、安装运行、设备交接或取证。** 按根 [AGENTS.md](../../AGENTS.md) 的顺序在相关操作前读取；本流程与根指南同等效力，不能绕过根文件红线。未特别说明的路径均相对仓库根目录。

### 工具、所有权与模拟器限制

- 工具、负责人、版本、设备选择/数量及停止条件执行根 §1「Device Hub」「Xcode」「模拟器限制」「设备停止与新包」红线；Xcode 核验步骤见 [Xcode 流程](xcode-mcp.md)。没有对应可用设备时说明情况。
- 交接遵守 [协作流程](collaboration.md)；切换工具先结束旧 session，禁止两个工具控制同一设备。
- 验收结束调用 `DeviceInteractionEndSession`，按根 §1 恢复改动过的运行目标；用户反馈与本轮验证证据分别记录。

### 新包与交互证据

1. `DeviceInteractionStartWorkspaceSession` 绑定本 workspace 和明确设备；必要时终止目标 App 旧进程。最后一次代码修改后必须用 `DeviceInteractionInstallAndRun` 完成 build/install/launch，确认新包已启动才取证。同一设备已完成上述步骤可直接交接，无需仅为换工具重装。
2. 启动后以空 interaction 的 `DeviceEventSynthesize` 获取截图/hierarchy；仍在加载则再捕获。只使用实际观察到的标签，优先 hierarchy 的 `hitPoint`；尝试失败并重新捕获后才用截图估算坐标，不盲目重放结果未确认的操作。
3. 每次点击、滑动、切换、旋转或状态变化后重新捕获，核对可见状态和 hierarchy。JSON-RPC 参数按当前 `tools/list` 校验；未知字段可能被静默忽略，返回截图或 `Running` 不证明动作执行。
4. tvOS 读 `Focused` 并按当前 schema 使用 Siri Remote `r up/down/left/right/select/menu/playpause/home`，不用触屏坐标。方向键可按 hierarchy 顺序合并，之后确认焦点，激活/返回后核对页面。Menu 与原生 Escape 不等价，已观察到 Escape 绕过 `onExitCommand`；组合键间隔须用日志核验，链式命令不等于零等待，见 `docs/TVFocusAndRemoteNavigation.md`。
5. 按根指南模型分工及 [视觉门禁](ui-visual-gate.md)复核原尺寸截图中的颜色、对齐、裁切、重叠、圆角、安全区及深浅色，并验证交互结果；“发出点击”或语义断言通过不能代替视觉/后端验收。
6. 将原始观察、请求/响应、截图及报告保存到忽略的 `runs/`，记录设备/OS、最终安装证据、交互路径与结果。凭据不进入场景、日志、提交或测试模型。源码变更后旧 App、旧 build、旧截图失效，屏幕显示 AngelLive 不证明已测；未完成构建/安装只报“未运行/阻塞”，接入成功不代表测试通过或速度提升。

### 平台限制与特殊设备

- **macOS**：既有 Device Interaction 实测不支持 `My Mac`，后续以当前工具响应复核。使用最后编辑后的 workspace MCP build、Xcode Run、原生 UI 交互及截图；按本次 build log 的完整产物路径确认应用，不能用已安装的同名旧 App 或仅构建成功替代验收，不声称执行了 Mac `InstallAndRun`。
- **Apple 翻译**：已记录 iOS 27.0 模拟器提示不支持模拟设备；真实译文须真机验收，见 `docs/RoomTitleTranslation.md`。
- **iPhone Duo**：已记录安装成功后仍出现 `Target device has invalid screen scale`，默认截图可能抓到关闭的外屏。用该设备 `simctl io enumerate` 核验形态和显示屏，再显式指定当前屏截图，不写死 screen ID；形态切换用 Device Hub 的 Closed/Book/Open，不以旋转代替。原生窗口仍由 session 唯一负责人操作；黑图不证明 App 崩溃，全桌面截图不证明已捕获 Device Hub。
