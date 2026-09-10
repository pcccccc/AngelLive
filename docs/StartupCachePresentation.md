# 三端启动与首页缓存

更新：2026-09-10

## 问题

三端复用了 `PlatformAPICredentialLifecycle`。此前该 modifier 在异步启用 API 凭据策略前，用“正在准备平台…”替换整个根页面。首页的缓存恢复任务因此不能开始；iOS/macOS 从未确认插件切换到 FullUI 时，还会移除并重建已经出现的视图树。

首页缓存本身采用先展示快照、再刷新数据的机制，但根页面门控发生在缓存读取之前。

## 当前行为

- 三端根 `PluginAvailabilityService` 显式启用 `managesAPICredentialPolicy`。首次构造时仅从本地插件目录确定 FullUI 策略，不读取 Keychain、不执行插件请求。该初始化每个进程只运行一次，重建根视图或增加窗口不会重复扫描。
- 安装、卸载及目录复查继续由同一根服务处理，先同步发布凭据策略，再发布插件列表和 FullUI/ShellUI 状态。
- `PlatformAPITokenVault` 在请求执行路径上读取主 actor 管理的策略。授权数据仍由 vault 和现有运行时管理，首个请求不需要等待某个视图的 `.task` 启用策略。
- `PlatformAPICredentialLifecycle` 只维护前台凭据状态，不替换根内容。离开前台或视图消失时，SwiftUI 取消其维护任务；窗口可见性不再决定已有请求是否使用凭据。
- `PluginHomeFeedModel` 保持先恢复缓存、后检查目录确认状态与刷新内容。过期快照仍可展示，目录尚未确认时不清空；确认没有可用来源后移除快照。没有缓存时使用各端现有首页占位。

## 边界

- 仅三个宿主的根服务显式启用策略管理；普通 `PluginAvailabilityService()`、独立 vault、扩展均默认不启用。没有已安装插件时策略关闭，ShellUI 不会因此读取 API 凭据。
- 不改变凭据注入函数范围、Keychain 存储、设备授权刷新、凭据代际检查或登录状态变更时的缓存失效规则。
- “缓存先显示”不意味着缓存永久存在，也不意味着可以绕过登录播放。tvOS 的缓存可能被系统回收；网络数据和可播放性仍由现有请求流程确认。
- 这次移除的是根页面等待门控，未承诺固定启动耗时；主线程其他初始化及图片解码仍可能影响首屏速度。

## 回归覆盖

- 不调用视图生命周期的 activate，首个 FullUI 请求仍使用已保存凭据并覆盖调用方传入的凭据。
- ShellUI 的请求在安全存储不可用时仍不读取 API 凭据。
- 本地目录模式变化可启用或关闭策略，无需挂载或销毁窗口。
- 过期首页缓存可在目录尚未确认时恢复，确认没有来源后才清除。
- 原有凭据隔离、设备授权和首页协议测试继续运行。

设备验收需在最后源码修改后重新构建、安装和启动；启动后的单张截图不能证明启动全过程无瞬时闪屏。

## 本轮验证

- Xcode 27 RC workspace MCP 最终构建：iOS `AngelLive` 15.433 秒、macOS `AngelLiveMacOS` 24.183 秒、tvOS `AngelLiveTVOS` 24.543 秒，均成功；各端 Navigator error 为 0。
- 最后源码版本 Core 测试：`PlatformAPITokenTests`、`PlatformDeviceAuthTests`、`PluginHomeFeedCacheStoreTests`、`PluginAvailabilityServiceTests`、`PluginHomeFeedTests`，共 48 项测试、5 个 suite 全部通过。
- iOS 最后编辑后完成新的 InstallAndRun，并再次安装运行确认进程已更换；两次首捕获均为有内容的首页，设置导航正常。未录制整个启动过程，未测量缓存命中耗时。
- tvOS 最后编辑后 InstallAndRun 成功，空截图及一次重试均失败，工具报 `Target device has invalid screen scale`；首次 UI 和再次启动未完成验收，不能用旧截图替代。
- macOS Device Hub 不支持运行验收，本轮仅验证构建。
- 设备会话均已结束，恢复原 tvOS scheme/destination；未删除缓存或修改账号、持久设置。全仓具体内容平台标识及测试映射扫描无命中，`git diff --check` 通过。
