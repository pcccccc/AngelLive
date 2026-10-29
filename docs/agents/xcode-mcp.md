# Xcode 环境、MCP 与工具恢复

**触发条件：构建、签名、环境配置、Xcode MCP 或相关工具故障。** 按根 [AGENTS.md](../../AGENTS.md) 的顺序在相关操作前读取；本流程与根指南同等效力，不能绕过根文件红线。未特别说明的路径均相对仓库根目录。

## 环境准备

- **Xcode**：版本选择、完整路径核验及命令/UI/MCP 工具链一致性执行根 §1「Xcode」红线；连接时按下文重新发现 PID、workspace 与工具 schema。
- **官方 Skills**：缺少任务所需 Apple 官方 Skill 时，先从选定 Xcode 导出并读取；升级后核对并同步，步骤见[技能同步流程](apple-skills-sync.md)，不沿用旧版清单或假称已读取。
- **工程与依赖**：打开根目录 `AngelLive.xcworkspace`，按已提交 `Package.resolved` 解析；不随意删除锁文件、缓存或 DerivedData，不做任务外依赖变更。播放器选择遵守根指南架构约束，VLC 须在首次解析前设置 `USE_VLC=1`。
- **密钥与签名**：Bugsnag 密钥仅放忽略的 `Shared/AngelLiveDependencies/Sources/Resources/BugsnagSecrets.local.plist`，占位配置可无密钥构建。模拟器不更换签名，真机使用本机证书/provisioning；不为构建擅改 team、bundle identifier 或 entitlements，不提交密钥。
- **设备状态**：新设备的插件和账号通过正常安装/登录/同步准备，不复制或提交私密容器；模拟器选择与数量限制执行[设备门禁](device-hub.md)。

使用 MCP 前读取 `axiom-xcode-mcp` 及对应 setup/tools/reference；版本选择严格执行根指南 Xcode 版本规则。

### 连接与构建

1. 核验根指南 Xcode 版本规则选定的 Xcode 已打开本仓库 `AngelLive.xcworkspace`，Settings > Intelligence 的 MCP / Xcode Tools 已启用。优先使用已注册 server；多实例时动态核验目标完整路径/PID，设置 `MCP_XCODE_PID` 与命令级 `DEVELOPER_DIR`。UI 工具必须用已核验的完整应用路径，不用 `getApp("Xcode")` 或共享 bundle identifier，以免启动旧版。
2. 本仓库 MCP 的 PID 级标准授权弹窗（“Allow … to access Xcode?”）已获用户授权：核验是本轮客户端和目标 Xcode 后，首次连接及客户端重启均直接点 `Allow`。仅覆盖此连接，不扩展到其他权限、项目或服务，也不替代 sandbox 审批。
3. 每次连接先 `XcodeListWindows`，按 `workspacePath` 选本仓库并取得有效 `tabIdentifier`。升级、更换路径或重连后重新发现 toolchain、PID、workspace、schema 和设备/session，不复用旧标识或参数。
4. 修改后 `BuildProject`；失败读取 `GetBuildLog` 和 `XcodeListNavigatorIssues`，以结构化诊断定位并修复，再重新 build；成功后仍检查 error severity 的 navigator issues。CLI 构建与 MCP workspace 构建分别报告，本地 Package 的解析上下文可能不同，不得互相冒充。

### Bridge 与响应

- 原始 stdio 仅作回退：`MCP_XCODE_PID=<已核验PID> DEVELOPER_DIR=<已核验Developer目录> xcrun mcpbridge`。直接使用 JSON-RPC 时以协议 `2025-06-18` 完成 `initialize`，再发 `notifications/initialized`。
- 整组 Device Hub 操作复用一个持续运行的 bridge，不每次调用重启客户端，以免反复授权、Automation Mode 被禁用或连接失效。
- 响应先保存文件，再输出状态/路径摘要；按 `response.id` 等待当前请求最终 `result/error`。进度通知、其他响应或缺省 `isError=false` 均不算成功。输出截断或上下文丢失先读已存响应/只读状态，不靠轮询重放；安装完成前不抢先截图或据此反复重装。
- Cocoa 4099/helper 失联时检查 Xcode、workspace、开关、授权，激活目标后重连一次；sandbox 内还须排查 XPC 边界，必要时经正常审批在 sandbox 外运行 bridge，不能直接判工具不可用或绕过审批。

### 工具冲突、超时与恢复

用户已授权在实际冲突、挂起或连接失效时恢复本轮 Xcode MCP、bridge、Device Hub 或测试 App，无需重复确认；由唯一负责人执行，其他代理停止对同一目标发请求。仅按以下顺序恢复：

1. 保存失败响应、请求 ID、时间、日志和 workspace/设备/session，先查已存响应及只读状态。客户端超时不等于服务端停止；构建/解析仍有进度时继续等待，不并发重发请求或直接杀进程。
2. 取消本轮遗留操作、停止重复客户端，正常结束旧 session 后重连一次；无法结束时先确认旧操作者/客户端已停，记录失效状态再开新 session。权限或 sandbox/XPC 问题仍走审批。
3. 重连无效且已确认故障时，核验精确路径、PID、父子关系和归属：先正常退出，再 TERM；确认仍未退出且不会丢失未保存工作才 KILL。确认旧进程结束后只启动一个实例；先恢复 bridge/测试 App，有证据才重启 Xcode、Device Hub 或已有模拟器。禁止宽泛 `killall`、`pkill -f` 或批量终止系统/其他任务进程。
4. 重启 Xcode 前保存本任务编辑，记录应用路径、workspace 和运行目标；存在未确认保存内容、用户正在使用的窗口/设备或其他任务影响时先协调。常规恢复不删 DerivedData、缓存、App、插件、账号或模拟器数据，不重启电脑，不创建替代模拟器，始终遵守[设备门禁](device-hub.md)数量限制。
5. 重启后按本节重新发现连接、窗口和设备状态，标准 MCP 弹窗按既有授权处理，其他权限仍按需审批。先观察截图/hierarchy，核验[设备门禁](device-hub.md)新包证据后继续；安装结果不确定先查证，不盲目重装。
6. 同一故障默认最多 2 轮，每轮重连、故障进程重启各最多一次。已知不支持、缺凭据或待授权即停止无效重试；记录每轮对象、原因、结果及证据，达上限报告阻塞/缺失验收/恢复条件并继续独立工作。工具恢复不代表验收通过；用户要求停止或表示已测试时立即停止恢复和设备操作。
