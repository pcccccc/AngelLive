# Angel Live 2.2.0 发布准备

更新日期：2026-09-25。应用记录：[App Store Connect · Angel Live](https://appstoreconnect.apple.com/apps/6755570692/distribution)。

## 版本与正式打包入口

商店现状由用户提供，本次未登录 App Store Connect 重新核验。

| 平台 | 当前商店版本 / 状态 | 本次版本（Build） | Scheme / Target | Archive 配置 | 最低系统 |
| --- | --- | --- | --- | --- | --- |
| iOS | 2.1.0 / 可分发 | 2.2.0（32） | AngelLive | Release | iOS 17.0 |
| macOS | 2.1.0 / 可分发 | 2.2.0（32） | AngelLiveMacOS-AppStore | Release | macOS 15.0 |
| tvOS | 2.1.1 / 可分发 | 2.2.0（32） | AngelLiveTVOS | Release | tvOS 17.0 |

三个正式宿主的 Bundle ID 均为 `dev.idog.AngelLive`。tvOS 嵌入的 `TopShelfExtension` 同步为 **2.2.0（32）**，Bundle ID 为 `dev.idog.AngelLive.TopShelfExtension`。

Build 32 按本地已有最大构建号 31 递增选择；尚未核对 App Store Connect/TestFlight 上已上传的构建号。上传前若发现冲突，三端及 Top Shelf 扩展一并递增。

本次仅调整上述 target 的 Debug/Release 版本号；保留普通 `AngelLiveMacOS` 和 tvOS `SimpleLive` 变体配置。没有变更签名团队、Bundle ID、证书或 provisioning profile。

## 已完成的配置检查

- 三个共享 scheme 的 ArchiveAction 均使用 Release。
- tvOS 正式宿主与 Top Shelf 扩展的版本号、构建号、App Group 一致。
- macOS 商店 target 定义 `APPSTORE`，不链接 Sparkle，使用 `Info-AppStore.plist`。
- 版本来自 target build settings，源 Info.plist 没有另写固定版本覆盖它们。
- `git diff --check` 通过。

## 构建与归档状态

使用根目录 `AngelLive.xcworkspace`、Xcode 27.0 RC（27A266a）验证。

| Scheme | 本次 workspace MCP BuildProject | Release Archive / 导出 / 上传 |
| --- | --- | --- |
| AngelLive | Debug / iOS 模拟器构建通过，error 0 | Release 归档成功，上传成功；部分第三方 dSYM 警告 |
| AngelLiveMacOS-AppStore | Debug / My Mac 构建通过，error 0 | Release 归档成功；上传被分发签名不匹配阻塞 |
| AngelLiveTVOS | Debug / tvOS 模拟器构建通过，error 0 | Release 归档成功；上传缺少可用分发签名证书 |

本次三端构建产物的 Info.plist 均已核对为 2.2.0（32），tvOS 嵌入扩展也一致；新 tvOS 构建日志未再出现扩展版本不匹配警告。

上表记录准备阶段的 MCP Debug 构建；随后用户明确要求上传。上传阶段在三端 Info.plist 增加 `ITSAppUsesNonExemptEncryption = false`，按用户确认声明无非豁免加密；这不替代隐私清单。

正式归档与上传记录保存在被 Git 忽略的 `build/release-2.2.0-32/`。三端 Release 归档已成功，2.2.0（32）与加密声明已核对，系统权限下签名验证通过。Mac 含 arm64 / x86_64，确认没有 Sparkle；tvOS 嵌入扩展版本一致。前一轮 iOS 17.5 的导航回归验证不能替代本次 Release 包的设备验收。

- iOS：`ios-upload.log` 返回 `Uploaded AngelLive` 和 `EXPORT SUCCEEDED`，进程退出码 0；Apple 提示 22 个第三方框架缺少 dSYM，主 App 的 dSYM 存在。上传成功不等于后台处理或审核通过。
- macOS：`macos-upload.log` 返回缺少 Mac App Distribution 证书，且商店描述文件不包含当前 Apple Distribution 证书，退出码 70。已向用户请求自动更新签名资料的明确授权，等待回复；归档无需重做。
- tvOS：`tvos-archive.log` 返回 `ARCHIVE SUCCEEDED`；`tvos-upload.log` 在分发签名阶段返回 `No signing certificate "iOS Distribution" found`，退出码 70，未上传成功。与 macOS 一并等待用户授权更新发布签名资料。

上传阶段的新 MCP 进程授权被自动审批拒绝，未重新授权；使用官方 `xcodebuild`，结果单独记录，不作为 MCP 验证。自动签名更新参数 `-allowProvisioningUpdates` 也被自动审批拒绝，实际上传命令已移除该参数，使用现有签名资料。

命令行解析必须从独立工作目录运行并传入 workspace 绝对路径：KSPlayer 的 manifest 会检测当前目录旁的本地 FFmpegKit；从仓库根目录运行会误选相邻开发仓库，导致稳定版本依赖解析失败。本轮从临时目录解析成功，32 个锁定依赖全部未变，`Package.swift`/`Package.resolved` 未修改。实际归档日志确认线上 KSPlayer 5.0.0、线上 FFmpegKit 8.1.2。

## 打包顺序

1. 打开根目录 workspace；分别选择表中的正式 scheme。
2. iOS 选择 Any iOS Device，tvOS 选择 Any tvOS Device；macOS 选择对应 Mac 构建目标。
3. 执行 Product → Archive；在 Organizer 核对平台、2.2.0（32）、宿主与嵌入扩展版本，以及符号文件。
4. 检查实际归档的签名、distribution provisioning、entitlements 与所需资源；Mac 商店归档确认没有 Sparkle。
5. 完成 Validate App，再通过 App Store Connect 分发流程上传；在各平台的 2.2.0 新版本中关联处理成功的 build。

## 上传前尚待完成

- **宿主隐私清单**：仓库未找到自有 `PrivacyInfo.xcprivacy`，但宿主/共享代码使用了 UserDefaults 等 API。需要按实际调用补核 required-reason 声明与最终包的清单；第三方 SDK 的清单不能证明宿主声明完整。参考 [Apple required-reason API 文档](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。
- **分发产物验证**：源码中的 development 签名或推送 entitlement 不能证明最终分发签名结果；以 Archive/导出产物为准。
- **商店信息**：核对已上传 build、创建/确认三端 2.2.0 版本、更新说明、截图、隐私/出口合规问卷及审核信息。现有“可分发”状态属于旧版本，不代表 2.2.0 已通过审核。
- **正式包验收**：用本次 Release 包检查启动、插件安装与浏览、播放、收藏与同步；tvOS 额外检查 Top Shelf，macOS 检查商店版菜单与关于窗口。

## 更新说明草稿

- iOS：改进首页导航栏随滚动显示的体验，统一导航栏边缘效果，更新关于页面与交流入口。
- macOS：更新菜单栏的关于窗口，优化项目与交流入口的展示。
- tvOS：修复 Top Shelf 收藏直播展示，更新关于页面与设置入口。

上述说明是本轮已完成改动的摘要，不是自上一商店版本以来的完整变更清单。
