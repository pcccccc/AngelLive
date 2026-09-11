# 联名应用图标

本次联名版本在 iOS、macOS、tvOS 安装包中默认使用小声逼逼图标。设置中的“应用图标”提供“小声逼逼（联名）”与“AngelLive 原版”两项。

## 资源与兼容

- iOS/macOS 保留主图标资源名 `AngelLive`，其内容使用现有联名作品；原版 Icon Composer 资源完整保存在 `AngelLiveClassic.icon`，包括深浅色图层。
- tvOS 保留主品牌资源名 `App Icon & Top Shelf Image`，替换其中普通图标和 App Store 图标的三层画面；Top Shelf 图片不变。原版普通图标保存在 `AngelLiveClassic.imagestack`。
- 三端保留旧 `XiaoShengBB` 备用资源，并新增 `AngelLiveClassic` 备用资源。不要移除旧名称，以免影响已经选过联名图标的安装。
- iOS/tvOS 的原版选项调用 `setAlternateIconName("AngelLiveClassic")`；联名选项调用 `setAlternateIconName(nil)`，恢复安装包默认。系统返回的 `nil` 和旧 `XiaoShengBB` 都对应联名选项。失败时维持原选中项并展示系统错误。
- tvOS 在 `Other/Info.plist` 的 `CFBundleIcons.CFBundleAlternateIcons` 中使用字符串数组声明这两个图层堆栈名，不设置 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`。Xcode 27.0 RC 的该编译选项会生成 iOS 字典格式，与 [Apple 明确规定的 tvOS 数组格式](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleicons/cfbundlealternateicons) 不符，会触发上传的 `Missing Image Asset / Alternate Icon` 校验错误。主图标及 Top Shelf 仍由资源编译器生成；不要将 iOS 的备用图标构建配置复制到 tvOS。
- macOS 未保存偏好时使用联名图标；旧偏好值 `primary` 继续代表用户选过的原版，`xiaoShengBB` 继续代表联名。原版使用命名 Icon Composer 图像，无法取得时回退到已有原版渲染图。

## 平台行为

iOS/tvOS 的切换由系统管理，使用已有设置入口和错误反馈。macOS 沿用 `NSApplication.applicationIconImage`：设置仅改变应用运行期间的 Dock 图标，退出后及 Finder 中的安装包仍显示联名默认图标；原版选择会在下次启动时重新应用。

验证时需要在最后一次编辑后重新构建并安装，检查默认联名图标、切回原版、再切回联名、重启后的选中项，并核对设置预览与系统图标。已有安装应保留系统备用图标选择，不通过删除应用数据来验证默认值。

tvOS 上传前还要检查最终 `.xcarchive/Products/Applications/AngelLiveTVOS.app/Info.plist`：`CFBundleAlternateIcons` 必须是包含 `XiaoShengBB` 和 `AngelLiveClassic` 的数组，`CFBundlePrimaryIcon` 为 `App Icon`。用 `xcrun assetutil --info <app>/Assets.car` 确认两个名称都有 `ImageStack` 资源。模拟器切换成功不能替代这项归档检查，修改配置后必须重新 Archive。

## 2026-09-11 验证记录

- 上传修复复核：最后一次 tvOS 配置修改后，`AngelLiveTVOS-SimpleLive` 在 Xcode 27.0 RC 的 workspace MCP 构建成功，Issue Navigator 无 error。核验当日 11:56 生成的 `Release-SimpleLive` 归档（2.0.0 / Build 1）：备用图标为字符串数组，两套名称均匹配 `Assets.car` 中的三层 `ImageStack`。新构建的 22 项备用图标资源与此前归档的名称、尺寸及图像摘要一致。本轮未重新上传 App Store Connect，也未重新运行设备图标切换测试；iOS/macOS 未重新验证。11:35 的旧归档仍包含错误字典，不能用于本次修复后的上传。
- 静态检查：10 个 Icon Composer 包/图层堆栈的引用有效，原版资源与修改前逐文件一致；联名主图标内容与已有联名资源一致，tvOS 主图标及商店图标尺寸正确。三个工程文件语法和 `git diff --check` 通过。
- tvOS：`AngelLiveTVOS` workspace MCP 构建成功，Issue Navigator 无 error。最后一次源码修改后通过 Device Hub 重新构建、安装、启动，在 Apple TV 4K（第三代）/ tvOS 27 模拟器验证默认联名主屏幕图标、设置切回原版、系统成功提示、原版主屏幕图标、重启后保持原版，再切回联名。选中项与系统图标一致，设备会话已结束。
- iOS：`AngelLive` workspace MCP 构建成功，Issue Navigator 无 error。最后一次源码修改后通过 Device Hub 重新构建、安装、启动，在 iPhone 17 Pro / iOS 27 模拟器验证默认联名图标、设置切回原版、系统成功提示、设置预览和主屏幕图标、重启后保持原版，再切回联名。设置预览、选中项与系统图标一致，设备会话已结束。
- macOS：`AngelLiveMacOS` workspace MCP 构建成功，Issue Navigator 无 error。通过 `RunProject` 启动本轮新构建，在 macOS 26.6.2 本机补充检查默认联名、设置切回原版和再切回联名，预览与选中值正确；调试器读取的实际 `NSApp.applicationIconImage` 图像也分别匹配原版和联名。已恢复验证前未保存的图标偏好，并停止本轮启动的进程。
- 限制：Device Hub 不支持 Mac 本机，因此 macOS 未完成 `DeviceInteractionInstallAndRun` 验收；读取系统 Dock 的原生工具超时，实际 Dock 画面及 Mac 重启持久化未验证。未运行单元测试，未验证真机、iPad、额外外观模式、App Store/发行变体。全仓具体内容平台标识扫描及测试 `liveType` / `siteId` 映射检查通过。所有设备会话已结束，Xcode 已恢复原 scheme 和目标设备。
