# iOS build 19 崩溃修复与验证（2026-09-15）

## 范围

通过 Bugsnag MCP 按 `testflight`、`version_code.seen_in = 19` 查询 iOS `3.0.0 (19)`。初次统计窗口为 2026-09-13 14:36 至 2026-09-15 14:36（UTC+8），共 3 个分组、11 次事件。将截止时间延长至 2026-09-15 17:37 后，仍为 3 个分组，照片权限组新增 1 次，共 12 次事件。事件中的主程序 dSYM UUID 与本轮上传的归档匹配。

| 分组 | 窗口内事件 | 新旧判断 | 本轮处理 |
|---|---:|---|---|
| [HistoryModel 缺失](https://app.bugsnag.com/personal-829/angelliveios/errors/6a741fe2f952d9851bcf8a68) | 9 | 旧分组，8 月 6 日首次出现 | 已修模型注入和呈现边界；9 月 16 日 iOS-on-Mac **本轮已覆盖场景通过，未复现崩溃**，范围见文末 |
| [照片写入触发 TCC 终止](https://app.bugsnag.com/personal-829/angelliveios/errors/6a6b3e2ce9828b141c1440aa) | 2 | 旧分组，7 月 30 日首次出现 | 为 iOS Debug/Release 补充照片添加用途说明 |
| [iPad TabBar 空对象异常](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa82ba15ab98605a9cefedd) | 1 | 新分组，9 月 15 日首次出现 | **本轮验证通过，未复现崩溃**；按用户确认从本轮待验收清单移除，真实窗口尺寸转换未覆盖 |

build 18 的方向回调、收藏模型等事件不属于本轮新增修复范围。没有发布新版本，也没有将线上分组标记为已解决。

## HistoryModel

9 份完整事件均来自 iOS App 在 Mac 上运行，系统为 macOS 15.7.9 或 27.0。既有运行数秒、没有直播元数据的启动事件，也有包含直播元数据的长时间运行事件。堆栈在 SwiftUI `EnvironmentBox`、`GeometryReader` 更新时找不到 `HistoryModel`；不能仅根据这些栈断定具体导航入口。

原模型由 `ContentView` 创建，并在其内部视图树注入。本轮新增每窗口的 `AngelLiveSceneView`，由它持有唯一的 `HistoryModel`，在 `ContentView` 外注入，以覆盖导航和模态呈现的上层边界。匹配归档的最终 `Info.plist` 确实启用了多场景，因此没有将模型改成 App 级共享单例。

另一个明确的边界是 UIKit cell 的独立 `UIHostingController`：它不会自动继承上游自定义环境。由 UICollectionView 负责点击的 `LiveRoomCard` 不应再注册自己的播放器呈现。本轮让 `disableTapGesture` 和外部导航状态一样，跳过本地 `fullScreenCover`／`navigationDestination`；保留纯 SwiftUI 卡片的本地导航。

调用链复核覆盖历史、收藏、搜索、平台详情、首页和换台入口。平台详情逐层传入非空的导航状态及 namespace；换台列表使用静态选择回调。因此，当前生产调用不会进入 UIKit cell 仅注入收藏模型、使用本地播放器的旧 fallback，本轮没有为该不可达分支增加额外修改。

上述改动修正模型注入和呈现职责；线上具体触发入口仍需 iOS-on-Mac 的新包回归确认，不能将编译通过写成已经复现并消除全部 9 次事件。

## 照片写入权限

完整线程包含 `PHPerformChangesRequest.determineAuthorizationStatusForChanges` 和 `PHPhotoLibrary` 写入调用，匹配归档缺少照片用途说明。二进制中的 `_UIImageWriteToSavedPhotosAlbum` 调用地址可符号化为 KSPlayer `IOSVideoPlayerView.handleScreenshot()`，但这只能证明相关代码已链接，不能证明线上执行了该方法。

当前宿主的 `KSCorePlayerView → KSVideoPlayer → KSPlayerLayer → player.view` 路径不创建 `IOSVideoPlayerView`，FullUI 和 ShellUI 控制层都没有截图按钮；新包 ShellUI 播放器的实际 hierarchy 也与此一致。匹配归档和当前依赖锁定同一 KSPlayer 5.0.0 revision，但归档没有记录主源码快照，因此线上事件的实际 Photos 调用入口仍未确认。

本轮针对确定的照片添加权限缺项，仅增加 `NSPhotoLibraryAddUsageDescription`，不申请读取图库。Apple 将该键定义为使用照片图库写入 API 的必要用途说明，见 [Apple 文档](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription)。新包最终 `Info.plist` 的生成结果已核验。

新包已验证一个真实可达的保存入口：设置 → 平台账号登录 → 中性测试插件 → 现有 `PlatformLoginWebSheet`／`WKWebView` → 长按普通图片保存。18:46 弹出“允许 Angel Live 将照片和视频添加到照片图库”系统授权框，显示本轮新增用途文案；允许后，图库新增 9 月 15 日 18:47 的彩色测试图片，没有发生 TCC 终止。主代理独立检查授权截图、图库图片和 hierarchy。这证明当前宿主确有无需播放器截图按钮的 Photos 写入入口，并验证了新包的完整添加流程；不能反推每次线上事件都来自该页面，也没有在旧 build 19 安装包上重放这次操作。

17:19 新增事件来自 iOS 27 的另一款 iPhone，仍为 build 19、相同主程序 UUID；完整线程同样位于 Photos 写入授权和 TCC 终止路径。该事件没有直播／播放元数据，不能据此断定具体页面，但它没有引入另一类权限根因。

## iPad TabBar

事件来自 iPadOS 27，尺寸变化触发 `UITabBarController.traitCollectionDidChange`，随后 `_tabs_rebuildTabBarItemsAnimated` 向数组插入空对象。当前源码没有手动覆盖 UIKit size class；既有 TabSection、动态平台 Tab 与播放器呈现路径需要结合运行时复现判断。不能把修改 Tab role、强制重建 TabView 或移除侧栏当作已验证的根因修复。

新包在 iPad mini（A17 Pro）上完成普通标签切换、插件安装／卸载造成的标签集合变化、播放器呈现／返回及历史导航，未出现该异常。根据上述已有测试及用户确认，iPad Tab 标记为**本轮验证通过，未复现崩溃**，从本轮待验收清单移除。本次状态更新没有重新运行设备测试，也没有修改 Tab 实现或关闭线上崩溃分组。

覆盖范围说明：窗口缩放未取得有效覆盖。两次操作 SpringBoard 提供的窗口缩放把手均进入 App Switcher，恢复后应用窗口仍为 744 × 1133；尝试从顶部下滑显示系统窗口菜单也回到主屏幕，未出现窗口排列控件。因此这些操作及屏幕旋转不计作跨 size class 验证；该限制保留为测试范围说明。

## 验证状态

- 源码静态检查：模型相关修改通过 Swift 语法解析；`project.pbxproj` 通过 `plutil -lint`；`git diff --check` 通过。
- Xcode MCP：Xcode 27.0 RC（27A266a）的根 workspace、`AngelLive` scheme 构建成功（38.781 秒），随后 Issue Navigator error 为 0。主代理独立读取构建日志确认 `BUILD SUCCEEDED`，并检查生成 App 的 `Info.plist`：照片添加用途说明存在且非空，没有声明照片读取用途；多场景仍启用。
- iPhone 18 Pro／iOS 27：最后一次源码编辑之后，`DeviceInteractionInstallAndRun` 返回 `Application installed and running`。新包完成欢迎页、默认空收藏、配置、设置和历史记录空态导航，捕获时持续 `Running`。主代理复核新包截图；历史页由共享的 `SettingView` 进入 `HistoryListView`，确实读取了 `HistoryModel`。这不代表已验证 Mac 或非空房间播放路径。
- iPad mini（A17 Pro）／iOS 27：先结束 iPhone session 并关闭该模拟器，再启动已有的 iPad；没有并行启动第二台 iOS 模拟器。工具连接恢复后，18:18 的新一轮 `DeviceInteractionInstallAndRun` 成功，后续捕获为 `Running`。18:21 在 ShellUI 添加公开 HLS 测试书签并实际播放，截图显示视频画面和 Pause 状态；实际播放器无截图按钮。该播放检查不能替代照片写入验证。
- iPad 系统设置确认未登录 Apple 账户后，使用正常来源安装流程安装临时中性插件。18:32 从 ShellUI 三个标签切换到 FullUI 五个标签，未出现崩溃。插件含三个稳定房间；后续版本增加无脚本、无账号的本地图片网页登录页，用于核查真实 WKWebView 的系统菜单。测试素材和插件包位于临时目录，不进入仓库。
- iPad 非空历史：平台列表显示三个房间，进入房间一后实际播放；左缘返回后，从设置进入历史记录，18:35 截图显示房间一，再次点击后播放器为 Pause／`Running`。主代理独立检查非空历史截图和前后 hierarchy。播放器 Back 按钮的合成点击没有生效，本轮采用可用的左缘返回手势，不将该现象直接归因于产品代码。
- iPad 快速换台：正常访问房间二以建立历史后，从历史重开房间一，打开快速换台面板并选择历史来源，切到房间二。18:40 hierarchy 的当前房间与播放器主标题均为房间二，播放状态为 Pause，应用为 `Running`；主代理复核结果截图。
- iPad 照片添加：按上节真实网页登录路径完成系统授权及保存，图库从 6 张增加到 7 张；逐张确认本轮彩色图片后删除该图，图库回到 6 张，原有图片保留。照片读取用途仍未声明；应用切到照片 App 后为 `RunningInBackground`，不是崩溃。
- 本轮遇到的 Xcode MCP 连接问题已恢复。未升级依赖、清理 Package cache 或更改签名来绕过环境问题。
- 收尾时再次通过 MCP 查询 Issue Navigator：`issues = []`、`totalFound = 0`；Device Hub 返回 `Session stopped`。正常 UI 清理后，历史记录为空、已安装插件和订阅源均为 0、ShellUI 书签为空；测试图片已删除，原有六张图片保留。本轮 localhost HTTP 服务已关闭。
- 全仓检查覆盖 650 个已跟踪及非忽略的新文件：具体内容平台标识无命中；31 个测试／fixture 文件中的数字 `liveType`／`siteId` 检查无命中。
- iPad Tab：本轮验证通过，未复现崩溃；真实窗口尺寸切换未覆盖，范围说明见上节。
- iOS-on-Mac：晚间追加清理重装，非空历史页、收藏起播及返回、标签往返、窗口放大和恢复通过，覆盖路径未复现 `HistoryModel` 缺失或布局挂起；历史记录实际起播仍受数据状态限制，详见文末追加记录。
- 本轮没有修改共享 Package 或 macOS／tvOS 宿主，未重复运行这些平台的构建或 Package 单元测试。

## 环境恢复

Device Hub session 已结束，本轮 MCP bridge 已正常退出。测试 iPad mini 已关闭，原 iPhone 18 Pro 已恢复为唯一运行的 iOS 模拟器；没有新建、克隆或删除模拟器。

恢复 Xcode 运行目标时，电脑已锁屏，UI 工具明确返回无法解锁，因此原 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)` 目标尚未恢复，当前仍为 `AngelLive / iPad mini (A17 Pro)`。没有绕过锁屏、重启 Xcode 或更改工程签名来处理该限制。

## iOS App on Mac 清理重装（9 月 15 日晚间至 16 日追加）

- 环境：Apple M1 Mac／macOS 27.0（26A5425a），Xcode 27.0 RC（27A266a），基线 `88aa021`。临时为 iOS target 的 Debug／Release 开启 Designed for iPhone/iPad on Mac，使用 `AngelLive / My Mac (Designed for iPad)`；Mac Catalyst 保持关闭。
- 按用户要求停止旧进程，执行 Xcode `Clean Build Folder`，清理成功；随后根 workspace 的 MCP `BuildProject` 成功（433.201 秒），Navigator error 为 0。MCP `RunProject` 再次构建、安装并启动成功（36.543 秒），采用无调试器附加的普通运行。
- 实际安装包为 iPhoneOS 平台、iOS 27 SDK、Debug `3.0.0 (1)`；运行包与本次构建产物的 `AngelLive.debug.dylib` SHA-256 一致，确认是清理后重建的新包。没有升级依赖、修改业务源码、删除账号或插件数据。
- 当前 Device Hub 接口没有可选的 Mac 目标，本次未执行 `DeviceInteractionInstallAndRun`。Mac 页面检查由专用子代理通过 CUA 完成，以下结果对应本次 `RunProject` 的新进程，不借用此前 iPad 或原生 macOS App 的验证。
- 新包实际打开收藏、设置、非空历史页，三列内容正常；一条历史明确下播，另一条历史进入播放后显示插件网络失败，能够返回。这两项未计为历史记录实际起播通过。
- 随后从收藏打开正在直播的内容：先显示 `CONNECTING`，后续截图出现视频画面及实时消息，实际起播通过；按 Escape 返回收藏成功。完成收藏 → 首页 → 搜索 → 收藏的标签往返，以及窗口公开 `zoom the window` 操作的放大和恢复，两种尺寸下网格无重叠、出界或明显裁切。最终停留在原尺寸收藏页，主代理独立复核最终 AX 和截图。
- MCP 查询时新进程持续运行，异常过滤未检出 `No Observable object`、`HistoryModel`、`Fatal error` 或未捕获异常。23:57 的三秒线程采样主要处于系统无障碍属性遍历和事件循环，未出现原事件的 `LazyLayoutComputer.spacing → LayoutEngineBox.sizeThatFits → IgnoresAutomaticPaddingLayout` 堆栈。采样保留在本机临时目录，文件名 `angellive-ios-mac-reinstalled-68409.sample.txt`。
- 结论：按用户确认，将上述已覆盖场景标记为**本轮验证通过，未复现 `HistoryModel` 缺失或布局挂起**。没有新增布局修复或关闭线上分组；历史记录实际起播、长时间播放及更多窗口转换场景仍保留验证缺口。
- CUA 在设置／历史路径曾报告两个导航项同时处于 selected，另有一次侧栏配置标题在截图中不可见；当前收藏页已恢复正常。这两项仅记录为待复核观察，未定位或修改实现。关键页面截图由 CUA 作为工具图片返回，工具未提供本地导出路径。
- 收尾已将 Debug／Release 的 Mac 运行支持恢复为原值 `NO`，工程文件无剩余 diff；Xcode 恢复本次开始时的 `AngelLive / iPhone 18 Pro`，未启动模拟器。新包仍留在 Mac 的收藏页；最后核对时同一进程已运行约 9 分钟，异常过滤仍无上述命中。
