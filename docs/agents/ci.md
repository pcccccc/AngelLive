# 测试入口与 CI 排查

**触发条件：设计、编写或运行测试，处理 CI 与测试失败。** 按根 [AGENTS.md](../../AGENTS.md) 的顺序在相关操作前读取；本流程与根指南同等效力，不能绕过根文件红线。未特别说明的路径均相对仓库根目录。

验证范围、共享 scheme、三层报告及纯文档/低影响显示修改的验证要求统一按根 §6「验证矩阵」执行。

Package 级测试入口：

```sh
swift test --package-path Shared/AngelLiveCore
swift test --package-path Shared/AngelLiveDependencies
```

通过 Xcode MCP 测试时，先 `GetTestList`，迭代阶段使用 `RunSomeTests`，最终再按风险运行 `RunAllTests`。只报告实际运行过的 targets、测试数量和结果；未运行的平台明确写“未验证”。

### 测试入口与覆盖边界

- 根目录不是 Swift Package，不能在根目录运行 `swift test` 充当宿主验证。两个 Package 的实际测试 target 分别为 `AngelLiveCoreTests`（`Shared/AngelLiveCore/Tests/`）和 `AngelLiveDependenciesTests`（`Shared/AngelLiveDependencies/Tests/`）；以后者 manifest 中的 `Fixtures` 资源规则为准，不把测试文件存在等同于已被当前入口执行。
- Package tests 验证共享逻辑和依赖适配；workspace host builds 验证平台集成、条件编译和链接；UI tests 与[设备门禁](device-hub.md)设备验收验证导航、交互和实际呈现。报告要求执行根 §6。
- 当前 `AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` 的 Test Action 引用各自 `HistorySmoke.xctestplan`，测试 target 为 `AngelLiveUITests`、`AngelLiveMacOSUITests`、`AngelLiveTVOSUITests`。`AngelLiveMacOS-AppStore` 和 `AngelLiveTVOS-SimpleLive` 当前未显式配置这些测试入口；运行前核验 scheme、test plan、实际测试列表和 destination，不虚构宿主单元测试 target，也不把历史冒烟测试当成全部业务覆盖。
- 按故障和契约设计可重复的回归测试，优先证明修复前能复现、修复后通过；无法执行修复前验证时注明原因。并发、取消、旧请求回写和恢复状态机测试用可控依赖与明确同步点，不用无依据的长时间等待掩盖时序问题。凭证、插件及账号状态使用中性 fixture 和明确前置条件。
- 纯逻辑、PCM 缓冲及格式转换单元测试使用符合被测接口契约的固定数据，不为构造 fixture 查询系统 Speech 资源、已安装模型或个人环境。真实识别与模型集成另设明确前置条件；系统服务返回 `nil` 不能靠跳过单元测试或自动下载资源掩盖。
- `AngelLiveDependencies` 中部分音频、模型和 DLNA 集成测试依赖环境变量、外部素材或真实设备；报告实际执行、跳过与禁用数量及原因。未准备前置条件时标记未验证，不能将整个测试命令成功解释为这些集成场景通过。

### CI 与失败处理

- `.github/workflows/ci.yml` 是 CI 当前执行范围的依据：`core-tests`、`dependency-tests` 分别执行两个 Package 的测试；`platform-builds` 对根 §6 列出的共享 scheme 执行 Debug workspace build。当前 workflow 没有执行 UI tests 或设备视觉验收；本地 Release、VLC 变体、真机和发布验证另按任务范围执行，不由默认 CI 结果推断。
- Dependencies tests 和 host builds 需要私有依赖权限，当前仅在受信任的引用运行，fork PR 会跳过；跳过不等于通过。不得为获取 secrets 改用 `pull_request_target` 执行不受信任代码，不将私有依赖、凭证或日志中的敏感数据放入公共缓存或产物。
- 验证实际 Xcode/Swift 版本、runner、依赖锁定和播放器内核；runner 标签不代表实际版本。调整 CI 时核对 runner 可用工具链与 workflow 显式配置，不从本机版本推断远端环境；配置不符须在获授权范围修正，不靠放宽检查掩盖。
- 工具版本检查先完整捕获命令输出，再匹配版本；不要把 `xcodebuild -version` 直接管道到 `head` 等提前退出的消费者。CI 已出现写入端 `Broken pipe` 崩溃，应保留原命令失败退出码，不能用忽略错误来处理。
- 排查 CI 先核对远端仓库、workflow、run URL/ID、触发事件、head SHA、attempt、失败 job/step 与平台，再读取完整相关日志，定位依赖链中的首个有效错误。区分依赖解析、权限/工具链、编译/链接、测试断言、超时和取消；末尾的汇总错误不能替代根因。记录命令、退出码、测试数量和日志或 result bundle 位置，不能用旧 SHA 或旧包证明新修改。
- 遵守根 §1「测试诚信」红线；先修复真实原因，再重跑失败入口与受影响回归。只在有明确暂态故障证据时重试，保留首次失败与重试记录；需求变化导致的契约与测试调整由 root 复核。
- 最终报告区分通过、失败、跳过、取消、阻塞及未执行，列出对应 SHA、job 和证据。CI 未完成或所需检查被跳过时保留未验证状态；未经用户授权，不因此提交、推送、合并或发布。
