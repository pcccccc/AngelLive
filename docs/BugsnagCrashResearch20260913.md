# Bugsnag 剩余崩溃研究（2026-09-13）

## 范围与结论

对上一轮留下的 5 类问题及其关联分组，读取了 47 份完整事件，包括全部线程、设备系统、应用生命周期和符号化堆栈。筛选为最近 30 天、open、unhandled，iOS `3.0.0 (18)` 与 tvOS `2.0.0 (23)`。这些是本次调查采用的错误版本，不代表已经核实商店最新发布版本。旧版本缺失符号的事件按用户要求跳过。

| 问题 | 样本 | 本次结论 | 状态 |
|---|---:|---|---|
| tvOS FFmpeg 无效内存访问 | 7 | 每次均同时存在旧视频解码器重建与读线程重连；锁定依赖源码存在上下文提前释放的竞争 | 高可信根因，尚未修复内核或完成运行时复现 |
| iOS RenderBox 符号动画 | 30 | 全部为 iPhone / iOS 26.0、26.0.1；与收藏图标替换动画路径吻合 | 高可信候选，尚未完成同系统 A/B 复现 |
| iPad Tab 标识重复 | 4 | 全部为 iPadOS 27 启动；宿主使用显示名作为列表 ID、可变元数据作为 Tab 选择值 | 已修宿主身份缺陷；9 月 15 日更新：**本轮验证通过，未复现崩溃**，实际覆盖范围见下文 |
| HistoryModel 缺失 | 5 | 全部是 iOS App 在 Mac 上运行，不是原生 macOS 宿主 | 已调整模型注入边界；9 月 16 日 **本轮已覆盖场景通过，未复现崩溃**，范围见下文 |
| SwiftUI 布局 App Hang | 1 | 同样是 iOS App 在 Mac 上运行，主线程停留在惰性布局测量 | 9 月 16 日 **本轮已覆盖场景通过，未复现挂起**；根因仍未定位，本轮未新增布局修复 |

研究阶段未发布版本或将 Bugsnag 分组标记为 resolved。随后按用户要求整理验证状态并提交代码，交付时的验证范围见[修复与验证状态](RegressionVerification20260913.md)。

## 1. tvOS：旧解码线程与重连释放上下文竞争

[当前分组](https://app.bugsnag.com/personal-829/angellivetvos/errors/6aa55336ce44e305cac67f2e) · [关联分组](https://app.bugsnag.com/personal-829/angellivetvos/errors/6aa4e2585ab98605a9963896)

7 个事件均来自 tvOS 26.6 / AppleTV14,1。视频解码线程在 `FFmpegDecode.decodeFrame` 第 72 行重新创建解码上下文，进入 `FFmpegAssetTrack.createContext` 第 310 行及 `avcodec_parameters_to_context` 后崩溃；另一线程同时处于 `FFmpegUtility.formatCtx → MEPlayerItem.reconnect → read(errorCode:) → performRead`。

已核对实际 Package.resolved 与依赖 checkout：KSPlayer 5.0.0，revision `93e942ae1f9dbdf8c2a4220ef2437073fdb575de`。关键源码与线上符号行号一致。旁边的旧诊断分支不是此次最终结论的版本依据。

1. `MEPlayerItem.openAndFindStream` 先调用 `closeFormatContext`，随后进行可能耗时的网络打开，再创建新轨道。
2. `FFmpegAssetTrack` 保留从旧流借用的 `stream` / `codecpar` 指针；持有 Swift 对象不能延长已被显式关闭的 C 上下文寿命。
3. 旧轨道的 `shutdown` 在新上下文打开后才执行；`AsyncPlayerItemTrack.shutdown` 只关闭队列、修改状态，没有等待正在运行的解码操作退出。
4. `performClose` 虽然先调用轨道 `shutdown`，同样没有等待退出便释放上下文，因此仅绕过内部重连还不完整。

源码：[重连与关闭顺序](https://github.com/TracyPlayer/KSPlayer/blob/93e942ae1f9dbdf8c2a4220ef2437073fdb575de/Sources/KSPlayer/MEPlayer/MEPlayerItem.swift#L532)、[解码线程退出](https://github.com/TracyPlayer/KSPlayer/blob/93e942ae1f9dbdf8c2a4220ef2437073fdb575de/Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift#L389)、[借用参数重新创建上下文](https://github.com/TracyPlayer/KSPlayer/blob/93e942ae1f9dbdf8c2a4220ef2437073fdb575de/Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift#L309)。

建议在内核统一解决：停止旧轨道消费、唤醒阻塞队列、确认正在执行的解码操作退出，再关闭旧格式上下文。重连、主动关闭、替换媒体项都需要经过同一生命周期边界。需避免在解码操作本身等待自己，也不能在主线程进行无界等待。单独给 `codecpar` 判空不能修复悬空指针；只复制参数也不能自动保护其他 `stream` 访问。

宿主已有 `applicationManaged` 策略及 EOF / 可重试错误恢复协调器。但该策略通过设置 `isLive = false` 实现，不能视为内核生命周期修复。`isLive` 还经过帧容量与播放速度扩展点；当前默认实现分别忽略该参数、返回 nil，当前宿主也没有覆盖这两处，未证实会改变现有缓冲或追帧行为。

这属于三端共用依赖的风险，目前本次线上样本仅证实 tvOS 命中。下一步验收应覆盖连续重连、重连时退房、替换播放项、解码失败时切换上下文、音频队列满时退出，并用 Address Sanitizer 与真实 Apple TV 验证。现有 Core 恢复状态机测试只能验证 EOF 和重试语义，不能证明 C 指针安全。

## 2. iOS：SF Symbol 替换动画是优先复现目标

[当前分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa5fbb85ab98605a9e8a220) · [关联分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa399b35ab98605a9424ca9)

30 个事件中，19 个为 iOS 26.0.1，11 个为 26.0；全部来自 iPhone，22 个发生在启动后 5 秒内，均无直播元数据。相同核心堆栈为 `RB::Symbol::Glyph::Layer::resolve_draw_transforms → RBSymbolLayer.updateForTime`。这些数据把调查重点指向启动和收藏同步图标，尚不能识别当时具体符号或选中 Tab。

`FavoriteTabSymbolAnimator` 会遍历系统 UITabBar 的内部 UIImageView，包括隐藏副本，按 description 或位置寻找目标，再对填充云符号切换 `.replace` 与持续 `.rotate`。这是优先级最高的宿主触发候选；`CloudSyncTabIcon` 也包含填充符号替换效果，但其使用面不同，不能仅因名字相近就认定为同一入口。

Apple Developer Forums 的 SF Symbols 页面有开发者的最小复现：两个填充符号来回替换时，在相同 `resolve_draw_transforms` 函数发生无效内存访问，移除替换效果或使用非填充符号可避开。这是开发者报告，不是 Apple 确认或系统修复承诺。[原始报告所在页面](https://developer.apple.com/forums/tags/sf-symbols)

下一步应在已有 iOS 26.0 / 26.0.1 设备验证收藏状态循环、启动与前后台切换，并对“正常静态 Tab 图标”与“现有动画”做 A/B。若先做保护，应在 FullUI 收藏入口停用内部 UIImageView 动画注入，通过公开 Tab 图标状态更新保留同步含义。本轮未调整图标视觉行为，也未宣称已复现。

## 3. iPad：修复不稳定的 Tab 身份

[当前分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa574fe34ecc9aa9959d29e) · [关联分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa3e723ce44e305ca6914f1)

4 个事件均为 iPadOS 27，在启动后约 1.38–1.84 秒发生，涉及两个 iPad 型号。堆栈由 `_UITabOutlineView` / `UITabGroup.setChildren` / SwiftUI TabViewCoordinator 组成，异常明确为 section snapshot 的重复 item identifier。事件没有插件列表，不能从内部数字标识反推具体插件或证明每次均由同名标题触发。

已确认两处宿主缺陷：

- iOS 的 `Platformdescription.id` 使用 `title`，而列表数据按 `pluginId` 去重；两个插件同名时依然会产生重复列表身份。
- `TabSelection.platform` 保存整个合成 Hashable 的 `Platformdescription`。元数据更新后，即使插件仍在，旧选择也可能不再等于任何当前 Tab；原有检查只比较 pluginId，没有处理这个差异。

本轮修改限定于 iOS FullUI 平台 Tab：列表 identity 和选择值统一采用稳定 `pluginId`；标题仍读取当前元数据；插件移除时，selection binding 立即回退有效首页，随后更新 `selectedTab`。ShellUI 目录及其书签导航未修改。此前工作树已有的启动模式修复继续保留。

研究结束时待验收：同名插件并存；选中插件原地更新标题和图标；移除选中插件；iPadOS 27 冷启动及侧栏切换。源码修复能消除上述身份缺陷，但尚不能把这 4 个线上事件全部标为已修复。

2026-09-15 状态更新：新包完成普通标签切换、插件安装／卸载造成的标签集合变化、播放器呈现／返回及历史导航，未复现崩溃。按用户确认，iPad Tab 标记为**本轮验证通过，未复现崩溃**，从本轮待验收清单移除；本次仅更新状态，未补测同名插件、选中插件原地更新及真实窗口尺寸变化等场景，未关闭线上分组。实际设备证据与覆盖范围见[新包记录](BugsnagBuild19Fixes20260915.md#ipad-tabbar)。

## 4. HistoryModel：集中于 iOS App 在 Mac 上运行

[当前分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa6702f5ab98605a9069623) · [关联分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6a741fe2f952d9851bcf8a68)

5 个事件的应用类型均为 iOS，设备均是 Mac：4 个 macOS 27，1 个 macOS 15.7.7。2 个为启动阶段，2 个带有直播元数据。异常为 `No Observable object of type HistoryModel found`，发生在 EnvironmentBox / GeometryReader 更新阶段，没有足够的宿主调用帧定位具体页面。

当前 `ContentView` 已持有并注入同一个 HistoryModel。实际消费点是 FullUI 历史列表和播放器；收藏、历史和分类列表的常用 UIKit 路径均传入外部导航状态，由上层呈现播放器。独立 UIHostingController 的基础房间卡片配置只注入收藏模型，仍有潜在环境边界风险，但尚未证明这些事件经过该回退入口。

2026-09-15 更新：build 19 查询中的 9 次事件仍全部来自 iOS App 在 Mac 上运行。模型已改为由每窗口 `AngelLiveSceneView` 持有并在 `ContentView` 外注入，UIKit 接管点击的卡片不再注册本地播放器呈现；iPad 新包的非空历史进入播放已通过。15 日晚间至 16 日已清理重装 iOS App on Mac 新包，非空历史页、收藏实际起播及返回、标签往返、窗口放大和恢复未复现模型缺失；历史条目因下播或插件网络失败，仍未取得历史记录实际起播通过证据。当前处理与证据见 [build 19 修复与验证](BugsnagBuild19Fixes20260915.md)。

生命周期中的 `FUWindowSceneSessionRoleSystemUI` 是系统场景标记，不能单独作为“应用额外开了一个未注入环境的窗口”的证据。当前 iOS App 只有一个 WindowGroup 声明，没有找到主动 openWindow 路径。

下一步应使用 iOS App 在 Mac 上运行的模式，分别检查冷启动、历史进入播放、封面导航、退出再进入、窗口缩放；在导航与 hosting 边界记录中性的入口名称和模型实例关联，不能记录房间标题、用户标识或凭证。原生 macOS App 编译通过不能验证此问题。本轮不以新增全局单例或临时空 HistoryModel 掩盖注入缺口。

## 5. 布局 App Hang：尚不能定位到聊天列表

[分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6aa6aa2b5ab98605a91a88e8)

唯一事件来自 iOS App 在 Mac 上运行，macOS 26.5.1 / Mac16,12，运行约 85 秒后被记录为无响应终止，带有直播元数据。主线程采样停在 `LazyLayoutComputer.spacing → LayoutEngineBox.sizeThatFits → IgnoresAutomaticPaddingLayout`，没有可定位宿主视图的调用帧。其他线程未提供证据将其归因于网络、解码或 CloudKit。

已检查播放器信息区：实际聊天列表是 UIKit `ChatTableView`；含 LazyVStack 的 `ChatListView` 仅出现在自身 Preview，没有生产调用，不能将它当成根因。应用其他首页和平台页面仍使用惰性布局，直播元数据也不能证明挂起时可见页面仍为播放器。

2026-09-16 追加：iOS App on Mac 已完成清理重装、收藏实际起播及返回、标签往返、窗口放大和恢复，未复现挂起；三秒主线程采样主要为系统无障碍接口和事件循环，未捕获上述布局堆栈。本轮未新增布局修复，长时间播放及更多窗口场景未覆盖，该分组仍未关闭；详情见 [清理重装记录](BugsnagBuild19Fixes20260915.md)。

下一步在同运行模式采集可见页面、窗口尺寸、前台切换和连续主线程采样，用 SwiftUI Instruments / Time Profiler 定位测量循环。单次被采样到的函数不足以证明死循环；本轮不作全局替换 LazyVStack、固定尺寸或移除安全区的推测性修改。

## 研究结束时的验证（设备验收前）

- 最后源码修改之后，CLI 从根 workspace 构建 `AngelLive` / Debug / arm64 / generic iOS Simulator 成功。
- `git diff --check` 通过；全仓具体内容平台标识与测试真实数字映射扫描无命中。
- 本轮没有新增或运行单元测试；上一轮 Core 295 个测试通过属于此前 JSON 修复的验证，不能算作这些新问题的复现证据。
- Xcode 27.0 RC（27A266a）MCP initialize 成功，但本次 `XcodeListWindows` 30 秒超时，未取得 tabIdentifier，因此未执行 MCP BuildProject、Navigator 验证或 DeviceInteractionInstallAndRun。桥接已关闭。
- 当前只有既有标准 iPhone 模拟器运行；没有切换用户设备、启动第二个 iOS 模拟器或新建设备。iPad UI、iOS App 在 Mac 上运行、真实 Apple TV 均未验证。
- 本轮未修改共享运行逻辑或另外两个宿主，未重复运行 macOS / tvOS 构建。

## 随后的模拟器验证

授权恢复后，iOS MCP workspace 构建通过，Navigator error 为 0；最后源码修改后的 iPhone 18 Pro / iOS 27 新包 InstallAndRun 成功。首页更多列表、平台列表、历史列表打开、普通直播播放、前后台恢复和边缘返回通过。iPad 安装会话初始化受阻，Tab 身份修复的 iPad UI 验收仍未完成；本轮未启动 tvOS。用户随后要求停止继续验收，标记状态后提交。

这轮 iPhone 检查没有复现或关闭上述剩余崩溃：未执行 iOS 26.0／26.0.1 符号动画 A/B、iOS App 在 Mac 上运行或真实 Apple TV 解码重连。详细通过项、中断和未验证项目见[修复与验证状态](RegressionVerification20260913.md)。

## 2026-09-15 追加：iOS 照片写入缺少图库用途说明

[分组](https://app.bugsnag.com/personal-829/angelliveios/errors/6a6b3e2ce9828b141c1440aa)

最新事件来自 iOS TestFlight `3.0.0 (19)`。TCC 异步终止线程本身没有携带用途说明键名，但同一时刻的工作线程位于 Photos 的 `PHPerformChangesRequest.determineAuthorizationStatusForChanges`，证明应用正在请求写入照片图库。事件的 dSYM UUID 与本地归档精确匹配；该归档最终 App `Info.plist` 缺少 `NSPhotoLibraryAddUsageDescription` 和 `NSPhotoLibraryUsageDescription`。

匹配归档二进制中的 `_UIImageWriteToSavedPhotosAlbum` 调用地址可符号化为 KSPlayer `IOSVideoPlayerView.handleScreenshot()`，这只说明相关代码已链接，不能证明它是本次事件的调用方。当前宿主使用的 `KSVideoPlayer` 渲染链不创建 `IOSVideoPlayerView`，FullUI／ShellUI 控制层均没有截图按钮；线上事件的实际 Photos 写入入口仍待确认。本轮针对已确认的照片添加权限缺项，只在 iOS target 的 Debug 和 Release 配置生成 `NSPhotoLibraryAddUsageDescription`，不声明照片读取用途，也不扩大播放器或其他页面行为。

最后修改后，Xcode MCP workspace 构建已通过，生成的 AngelLive App `Info.plist` 中 `NSPhotoLibraryAddUsageDescription` 存在且文案非空，`NSPhotoLibraryUsageDescription` 仍不存在。随后在 iPad 新包通过现有网页登录界面长按保存中性测试图片：系统正常弹出照片添加授权框，允许后图片实际进入图库，应用未发生 TCC 终止。这是已验证的可达写入入口，仍不能反推全部线上事件来自该页面；本轮没有发布或关闭线上分组。详细记录见 [build 19 修复与验证](BugsnagBuild19Fixes20260915.md)。
