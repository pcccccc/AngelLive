# 应用图标

从 2026-11-20 的调整起，iOS、macOS、tvOS 安装包默认使用 AngelLive 原版图标。设置中的“应用图标”依次提供“AngelLive 原版”和“小声逼逼（联名）”。

## 资源与兼容

- iOS/macOS 的主图标 `AngelLive.icon` 使用原版 Icon Composer 资源，逐文件与 `AngelLiveClassic.icon` 一致，包括深浅色图层。
- tvOS 的 `App Icon & Top Shelf Image` 中，普通图标和 App Store 图标使用各自的原版三层图像。普通图标与 `AngelLiveClassic.imagestack` 一致。Top Shelf 图片沿用原资源。
- 三端都保留两个备用资源名。`XiaoShengBB` 对应联名作品，`AngelLiveClassic` 对应原版，兼容已保存的系统选择。
- iOS/tvOS 选择原版会调用 `setAlternateIconName(nil)`，使用安装包主图标。选择联名会调用 `setAlternateIconName("XiaoShengBB")`。系统返回 `nil` 或 `AngelLiveClassic` 时显示原版，返回 `XiaoShengBB` 时显示联名。失败时保留原选中项并展示系统错误。
- iOS/tvOS 上一版把联名作为主图标，所以当时选用联名且系统值为 `nil` 的用户，升级后会看到原版，可在设置中重新选择联名。系统值为 `AngelLiveClassic` 的用户继续看到原版，系统值为 `XiaoShengBB` 的用户继续看到联名。
- tvOS 在 `Other/Info.plist` 的 `CFBundleIcons.CFBundleAlternateIcons` 中使用字符串数组声明这两个图层堆栈名，不设置 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`。Xcode 27.0 RC 的该编译选项会生成 iOS 字典格式，与 [Apple 明确规定的 tvOS 数组格式](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleicons/cfbundlealternateicons) 不符，会触发上传的 `Missing Image Asset / Alternate Icon` 校验错误。主图标及 Top Shelf 仍由资源编译器生成；不要将 iOS 的备用图标构建配置复制到 tvOS。
- macOS 未保存偏好或偏好值为 `primary` 时，启动后使用安装包原版图标。偏好值为 `xiaoShengBB` 时，启动后恢复联名 Dock 图标。联名优先加载命名 Icon Composer 图像，并使用已有联名渲染图作为回退。

## 平台行为

iOS/tvOS 的切换由系统管理，沿用已有设置入口和错误反馈。macOS 在运行期间用 `NSApplication.applicationIconImage` 显示联名 Dock 图标，切回原版时将此属性设为 `nil`，由系统恢复安装包图标。Finder 和 DMG 安装窗口显示 `.app` 自带的原版图标。

验证时使用最后一次编辑后构建的新包，检查默认原版图标、切换联名、切回原版、重新启动后的选中项，以及每项预览与实际图标是否对应。在已有安装上覆盖升级，分别检查 `nil`、`AngelLiveClassic`、`XiaoShengBB` 的兼容行为，保留设备上的应用数据。

tvOS 上传前还要检查最终 `.xcarchive/Products/Applications/AngelLiveTVOS.app/Info.plist`：`CFBundleAlternateIcons` 必须是包含 `XiaoShengBB` 和 `AngelLiveClassic` 的数组，`CFBundlePrimaryIcon` 为 `App Icon`。用 `xcrun assetutil --info <app>/Assets.car` 确认两个名称都有 `ImageStack` 资源。模拟器切换成功不能替代这项归档检查，修改配置后必须重新 Archive。

## 2026-09-11 验证记录（联名作为默认的历史版本）

- 上传修复复核：最后一次 tvOS 配置修改后，`AngelLiveTVOS-SimpleLive` 在 Xcode 27.0 RC 的 workspace MCP 构建成功，Issue Navigator 无 error。核验当日 11:56 生成的 `Release-SimpleLive` 归档（2.0.0 / Build 1）：备用图标为字符串数组，两套名称均匹配 `Assets.car` 中的三层 `ImageStack`。新构建的 22 项备用图标资源与此前归档的名称、尺寸及图像摘要一致。本轮未重新上传 App Store Connect，也未重新运行设备图标切换测试；iOS/macOS 未重新验证。11:35 的旧归档仍包含错误字典，不能用于本次修复后的上传。
- 静态检查：10 个 Icon Composer 包/图层堆栈的引用有效，原版资源与修改前逐文件一致；联名主图标内容与已有联名资源一致，tvOS 主图标及商店图标尺寸正确。三个工程文件语法和 `git diff --check` 通过。
- tvOS：`AngelLiveTVOS` workspace MCP 构建成功，Issue Navigator 无 error。最后一次源码修改后通过 Device Hub 重新构建、安装、启动，在 Apple TV 4K（第三代）/ tvOS 27 模拟器验证默认联名主屏幕图标、设置切回原版、系统成功提示、原版主屏幕图标、重启后保持原版，再切回联名。选中项与系统图标一致，设备会话已结束。
- iOS：`AngelLive` workspace MCP 构建成功，Issue Navigator 无 error。最后一次源码修改后通过 Device Hub 重新构建、安装、启动，在 iPhone 17 Pro / iOS 27 模拟器验证默认联名图标、设置切回原版、系统成功提示、设置预览和主屏幕图标、重启后保持原版，再切回联名。设置预览、选中项与系统图标一致，设备会话已结束。
- macOS：`AngelLiveMacOS` workspace MCP 构建成功，Issue Navigator 无 error。通过 `RunProject` 启动本轮新构建，在 macOS 26.6.2 本机补充检查默认联名、设置切回原版和再切回联名，预览与选中值正确；调试器读取的实际 `NSApp.applicationIconImage` 图像也分别匹配原版和联名。已恢复验证前未保存的图标偏好，并停止本轮启动的进程。
- 限制：Device Hub 不支持 Mac 本机，因此 macOS 未完成 `DeviceInteractionInstallAndRun` 验收；读取系统 Dock 的原生工具超时，实际 Dock 画面及 Mac 重启持久化未验证。未运行单元测试，未验证真机、iPad、额外外观模式、App Store/发行变体。全仓具体内容平台标识扫描及测试 `liveType` / `siteId` 映射检查通过。所有设备会话已结束，Xcode 已恢复原 scheme 和目标设备。
