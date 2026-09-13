# 2026-09-13 修复与验证状态

本记录区分源码修复、构建／测试通过和设备交互通过。用户要求标记验证状态后提交，本轮停止继续设备验收；未执行的项目不标为通过。没有发布版本，也没有将 Bugsnag 分组标记为 resolved。

## 修改与验证矩阵

| 项目 | 源码状态 | 构建／测试 | 设备验证与限制 |
|---|---|---|---|
| 插件返回 null／undefined 导致 JSON 序列化异常 | 已修复共享解码入口，必填结果转为可恢复错误，Optional 保留 nil | Core 全量 295 项测试、39 个 suite 通过；新增返回值测试含 18 个参数组合；iOS、macOS、tvOS CLI workspace 构建通过 | 未在设备上注入异常插件返回值；单元测试覆盖当前、租借和隔离凭据三个入口 |
| iOS 首页“更多”列表卡片重叠 | 网格列宽与卡片使用同一容器尺寸计算 | 最后源码修改后 iOS CLI 与 MCP workspace 构建通过，Navigator error 为 0 | **已验证**：iPhone 18 Pro / iOS 27 新包进入更多列表并滚动，两列卡片、头像和文字无重叠；iPad 尺寸未验证 |
| iOS FullUI 竖屏直播左滑清屏、右滑显示 | 已实现独立控制层状态、方向锁定、弹层手势保护和返回边缘协调 | iOS 构建通过 | **未验证完整交互**：本轮播放的是横向画幅直播，不能作为竖屏手势、旋转或弹层冲突通过证据 |
| 无插件时默认进入 ShellUI 收藏 | 共享安装快照决定首帧模式，三端根导航选择回退收藏 | 阶段验证中 34 项 Core 测试通过，三端 MCP 构建通过；后续共享修复的 Core 全量与三端 CLI 构建也通过 | **部分已验证**：此前本项最后编辑后的 iPhone 17e / iOS 27、Apple TV 4K 第三代 / tvOS 27 新包，空 ShellUI 收藏与基础导航通过；macOS 空 ShellUI、iPad 和 iOS 17 分支未验证。详见[启动记录](StartupCachePresentation.md) |
| tvOS FullUI 收藏刷新反馈 | 改为顶部悬浮圆环与结果提示；连续手动刷新合并，慢请求回写同步播放列表与 Top Shelf | 本项修改后的 tvOS MCP 构建通过、Navigator error 为 0；3 项相关 Core 测试通过；后续 tvOS CLI 构建通过 | **部分已验证**：此前新包安装、启动通过，但设备无收藏，带列表进度／慢请求结果／连续遥控器按键／焦点稳定未验证。本轮未启动 tvOS。详见[收藏刷新记录](FavoriteRefreshNetworkResiliencePlan.md) |
| iPad Tab identity 与选择值不稳定 | 列表和选择统一使用 pluginId，元数据更新保持身份，插件移除回退有效选择 | 最后源码修改后 iOS CLI 与 MCP 构建通过 | **受阻**：iPad 首次安装会话初始化超时，第二次报模拟器无法连接；没有成功 InstallAndRun 或新包 UI 证据。同名插件、元数据更新、移除选中插件、冷启动及侧栏切换均未验证 |
| SF Symbol 动画、iOS App 在 Mac 上的 HistoryModel／布局挂起、tvOS 解码上下文竞争 | 完成研究和文档更正；这些根因或触发路径尚未全部修复 | 现有构建／Core 测试不能证明这些线上问题消失 | **未验证／待复现**：iOS 26.0／26.0.1 同系统 A/B、iOS App 在 Mac 上运行、真实 Apple TV 重连与解码生命周期均未执行。详见[崩溃研究](BugsnagCrashResearch20260913.md) |

## 最后一轮 iPhone 新包验收

- 工具链：Xcode 27.0 RC（27A266a），根 `AngelLive.xcworkspace`，`AngelLive` scheme。MCP `BuildProject` 成功，耗时 27.792 秒，Navigator error 为 0。
- 设备：已有标准 iPhone 18 Pro / iOS 27。**最后一次源码修改后，新的 `DeviceInteractionInstallAndRun` 成功并确认 App 重新运行**；之后未修改源码。本文件等文档更新不改变安装包。
- 已验证：首页加载 → 更多列表 → 滚动；配置 → 已有平台房间列表 → 返回；平台列表下拉后选择保持；设置 → 历史列表打开；首页 → 已有直播 → 视频和弹幕持续更新；后台 → 前台后同一进程继续更新；左边缘返回首页。
- 未验证：历史记录进入播放、收藏下拉刷新、竖屏清屏与显示、旋转、连续切房、弱网、长时间稳定性、深浅色及减少动态效果。
- 历史列表后的 Device Hub session 曾丢失，旧 App 进程收到 SIGTERM（15）。现有日志未识别信号发送方，也没有对应的新宿主崩溃报告；记录为验收中断，不能推断为应用闪退。恢复会话后继续使用同一份新安装包完成播放与前后台检查。
- 播放页两次点击 hierarchy 的 Back hitPoint 只显示控制层，未完成按钮返回；可能与控制层自动隐藏时序有关，尚不能认定按钮缺陷。左边缘返回已实际通过。

## 验收收尾

- iPhone 续接会话与第一次 iPad 会话已收到 `DeviceInteractionEndSession` 成功回执。第二次 iPad 安装失败后，工具进程在中断时退出，未取得该会话的 EndSession 回执，不能声称所有 session 均正常结束。
- 本轮 Python／MCP bridge 已退出，仅本轮启动的 iPad 已关闭；最终 Booted 列表为空。没有新建、克隆、改名或清空模拟器，没有启动 tvOS 验收。
- Xcode 已恢复原 `AngelLive` / `iPhone 18 Pro` 标准运行目标；恢复目标时未启动设备或 App。

## 证据索引

构建日志保留在本机临时目录：

- `angellive-plugin-return-core-full-20260913.log`：295 项 Core 测试通过。
- `angellive-plugin-return-{ios,macos,tvos}-build-20260913.log`：共享 JSON 修复后的三端 CLI 构建通过。
- `angellive-tab-identity-ios-build-20260913.log`：最后 Tab 修改后的 iOS CLI 构建通过。
- `angellive-device-validation-20260913-223912/`：本轮 MCP 返回；response 008 为 iPhone 新包 InstallAndRun，019 为历史列表，025 为直播，027 为前台恢复，030 为边缘返回，031 为结束 iPhone session。
- 安装后截图文件名：`Verify iPhone FullUI Regression-22_43_45_371-screenshot.png`（更多列表）、`Continue iPhone Regression-22_53_40_889-screenshot.png`（直播）。完整本机路径见临时验收报告 `AngelLive-Simulator-Round-2026-09-13.md`。

临时日志与截图不提交到仓库。上述截图只证明对应可见状态，不能替代未执行的交互或真实设备验收。KSPlayer 相邻仓库的本地诊断修改不包含在本次提交范围。
