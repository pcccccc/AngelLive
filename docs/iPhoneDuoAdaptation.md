# iPhone Duo 适配

状态：代码改动已落地，整体验收尚未完成。前次验收因 Mac 锁屏及交互工具失效停止；用户现已确认解锁，并要求先提交、推送当前进度。v6 已完成最后编辑后的 workspace 构建、正式安装、Running 捕获、Closed 首页视觉复核和真实直播进入全屏；返回、双击、内屏、真实短剧、普通设备与 iOS 运行片段仍待完成。此前 v4 安装包的三形态首页已通过 root 与 Astra 独立视觉复核，实际直播跨形态、就地全屏、分类和历史列表已有设备证据；这些不能替代最终新包检查，整体完成门禁尚未通过。范围为 iOS FullUI；保留 ShellUI、插件协议、账号数据和既有测试基础设施。

## 官方依据

- Apple `app-resizability` Skill（Xcode 27.1 导出）：按 UIScreen、方向、场景生命周期、安全区、idiom 五项检查。
- Apple `swiftui-specialist` Skill：保持状态所有权、稳定视图 identity、局部环境依赖。
- Apple `device-interaction` Skill：workspace session、最后编辑后的安装、逐步截图及层级验收。
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

## 方案与边界

1. 使用当前视图的 size class 和可用尺寸决定布局。内屏不等于 iPad，外屏也不保证固定尺寸。
2. 保留原生 TabView 与现有导航树，形态变化不切换两套根视图，不清空选择、导航和播放状态。
3. 复用现有播放画面、主播信息和弹幕列表。空间足够时使用现有侧栏结构；窄宽恢复上下排列；显式全屏状态由播放页面持有。布局与动作策略分开：全屏意图由页面显式持有，不能依赖方向请求一定改变 size class；普通 iPhone 在更新全屏意图后保留旋转操作。此策略已完成 v6 构建和安装，剩余动作仍须实机态验收。
4. 播放画面保持同一结构位置和播放会话，折叠只改变布局；不将宽高、形态或方向加进播放 identity / 网络任务 key。
5. 控件尊重当前视图安全区，背景及视频可按原有意图延伸。左右安全区独立，不能从屏幕方向推断系统侧栏位置。
6. 窗口相关动作通过 FullUI 局部探针取得当前 window/scene/screen。共享组件仅在注入 FullUI 上下文时启用新路径。
7. 已采用 SwiftUI App/WindowGroup，保留其场景管理；按消费点检查前后台观察，不额外创建 SceneDelegate 或改变多窗口策略。

## 实施前检查

| 项目 | 结果与证据 |
| --- | --- |
| 启动画面 | 工程 Debug/Release 均声明生成启动画面及现有 Launch Screen storyboard |
| iPad 方向 | 工程 Debug/Release 均声明四方向；保留手机竖屏入口策略 |
| 全屏 opt-out | Info.plist / 工程未发现 UIRequiresFullScreen；不添加或删除策略键 |
| 场景入口 | AngelLiveApp 使用 WindowGroup；既有 App/测试入口改动由其他任务负责 |
| 工具链 | 设备负责人核验 Xcode 27.1（27A9275）；已有标准 iPhone Duo / iOS 27.1 模拟器 |

## 文件覆盖清单

每个发现点记录修改或不适用理由；此表随审计补全。实施完成不等于视觉通过。

| 文件/范围 | 处理与状态 |
| --- | --- |
| FullUI/Components/FullUIWindowContext.swift | 已实现弱引用局部窗口探针；当前 screen/scene 在使用时取得；不缓存屏幕尺寸 |
| FullUI/Views/DetailPlayerView.swift | 已按局部 size class 统一全屏含义；宽度至少 720pt 时复用 400pt 侧栏，保留至少 320pt 播放区 |
| FullUI/Views/Player/PlayerContainerView.swift | 已按容器布局与所属 scene 生命周期处理；视频尺寸探测独立于设备类别，不因折叠重建播放任务 |
| FullUI/Views/Player/UnifiedPlayerControlOverlay.swift | 已统一全屏、返回、局部窗口旋转动作 |
| FullUI/Views/Player/PlayerUI/KSVideoPlayerView.swift | 已统一全屏布局，媒体单独延伸安全区 |
| FullUI/Views/Player/PlayerUI/KSVideoPlayerViewBuilder.swift | 已传递当前窗口及全屏状态；保留 ShellUI 使用的旧全局 helper |
| FullUI/Views/Player/PlayerUI/VideoControllerView.swift | 已按可用空间选择控制密度、全屏与返回 |
| FullUI/Views/Player/QualitySelectionSheet.swift | 已按局部 size class 选择布局 |
| Common/PlayerCore/PlayerGestureView.swift | FullUI 使用所属屏幕亮度和 scene 事件；nil 上下文保留 ShellUI 路径。既有手势排除带不计为安全区实测证据 |
| FullUI/Views/ShortDrama/ShortDramaPlayerView.swift | 已去除反向加安全区和负偏移；媒体与前景分离；展开状态返回退出页面，不误发旋转 |
| FullUI/Views/ShortDrama/ShortDramaDetentPanel.swift | 已用安全容器尺寸和局部 size class；尺寸变化重新计算 detent，保留既有间距与控件 |
| FullUI/Views/ShortDrama/ShortDramaOrientationController.swift | 已从本地 host trait 读取方向策略；保留左右方向恢复含义 |
| FullUI/Views/PlatformDetailView.swift | 骨架与内容网格均已按局部 size class 选择列数 |
| FullUI/Views/Home/HomeView.swift | 滚动前景遵循安全区；展开轮播显式滚动回中，保留分页 identity、选中内容与自动轮播语义；下拉距离扣除系统 adjustment，保留刷新控件动态 inset。前景图片与背景使用相同的安全区延伸高度、缩放和底边锚点，消除顶部白带与图像接缝；文字与点击区域保持原布局 |
| FullUI/Components/LiquidRefreshIndicator.swift | 已移除用 inset 阈值猜传感器/方向；按本地安全框定位现有独立刷新图形 |
| Common/Components/DevConsoleOverlay.swift | FullUI 已绑定局部 scene；浮球四边限制与半高面板随安全框变化更新；保留 ShellUI 原路径 |
| Common/Components/ErrorView.swift | FullUI 使用局部 size class 选择已有横向结构；ShellUI 保留原分支 |
| Common/Components/FavoriteTabSymbolAnimator.swift | 仅有 FullUI 消费；已去除全局窗口兜底，在挂接与本地尺寸变化后重查当前 tab 图标 |
| FullUI/Views/UIKit/ViewControllers/{FavoriteList,RoomList,HistoryList,PlatformDetail}ViewController.swift | 四处 ErrorView 的 UIHostingController 已显式注入 FullUI 上下文；历史/平台 segmented 左右锚点已绑定各自安全区 |
| FullUI/Views/UIKit/ViewControllers/SubCategoryViewController.swift | 子分类前景栏已绑定自身顶部/左边安全区，管理按钮绑定右边安全区；保留原 16pt / 8pt 设计间距 |
| FullUI/Views/UIKit/ViewControllers/RoomListViewController.swift | 实测分类容器从 466pt 缩为 382pt 后卡片仍为旧 205.5pt。已用局部 FlowLayout 在 bounds 宽度变化时失效 delegate metrics，沿用原两列公式及 20/15/24pt 间距；不改 JX 或父子控制器生命周期 |
| Core DanmakuKit | 已完成：iOS 图层比例使用本地 trait，并观察 displayScale 变化；后台图片/混排使用本次绘图上下文比例；GIF 保留当前帧和 animator，仅更新比例；tvOS/macOS 保留原分支 |
| Core WelcomeView / WelcomePageView | 已实现 usesResizableLayout 默认 false 的兼容参数，只有 iOS FullUI 启用局部 size class 间距；其他宿主保留原路径 |
| ContentView.swift | 已注入 FullUI 上下文；保留设备对应栏目产品策略和同一导航树，避免折叠触发根视图替换 |
| AngelLiveApp.swift / Info.plist / project 与 schemes | 已满足启动/方向/场景策略；保留其他任务修改 |
| Common/Constants.swift | 明确保留：共享设备类别 helper 的剩余用途为产品栏目、方向策略与 ShellUI，不能全局改含义 |
| Common/Utils/DeviceTopSensor.swift | 明确保留且不计为已迁移：仓库无消费点的旧 helper；本次活跃刷新路径已不再推断传感器 |
| FullUI/Views/Player/PlayerUI/ViewExtension.swift | 明确保留：通用忽略安全区 wrapper 无消费点 |
| FullUI/Views/FavoriteView.swift / Setting/PlatformLoginWebSheet.swift | 已检查：滚动边缘或网页底边的既有延伸，无对称左右 inset 假设 |
| UIKit CategoryGrid / CategoryManagement / Favorite / History / Room collections | 已检查：自身 adjustedContentInset 与尺寸失效路径；固定 sectionInset 为设计间距，保留 |
| Core SupportDiagnosticsView / Dependencies KSPlayerFallback | 已检查：SwiftUI scenePhase 已是局部环境；设备名/电池等非布局语义保留 |
| ShellUI / macOS / tvOS | 本次不更改对应交互；共享代码的 iOS 改动及默认参数必须隔离 |

机器可读的逐文件五项检测及理由保存在 `runs/iphone-duo-adaptation/coverage-audit.json`（忽略提交的本地证据）。该清单的 HEAD 对照不是任务前脏工作区快照；其他任务修改独立保留。

## 视觉参考与验收

复用现有 DetailPlayerView 的播放器、400pt 信息面板、StreamerInfoView、ChatTableView、RoomActionDock，以及既有控制层字体、图标、边距和触控尺寸。短剧参照 `docs/ShortDramaModePlan.md` 及既有 44pt 控件、48pt 选集格、8pt 网格间距与 60×84pt 海报；历史/分类栏参照 CategoryManagement 的同类安全区约束。不新增另一套卡片或设置行样式。布局实现使用 GPT-6 Astra/high 或 GPT-6.1 Sol/high，出现视觉破坏交 Astra/high 实际重写。

| 场景 | 状态 | 所需证据 |
| --- | --- | --- |
| Duo Closed / Book / Open 首页 | 通过静态复核 | v4 三形态截图经 root 与 Astra 独立复核：单页填满，标题/副标题/页码完整，顶部无白带、接缝及静止刷新圈。正式安装后的 v4-official-closed-home.png 再次通过；原三张图页码随时间变化，不能据此声称选中项不变 |
| Duo 首页刷新 | 通过所列交互 | 正式安装后 response-84/85 及 v4-official-refresh-released.png / v4-official-refresh-complete.png：实际释放与刷新完成，静置圈消失，首页层级保留；root 与 Astra 独立复核完成态 |
| Duo 播放中来回折叠、全屏与返回 | 此前版本通过所列交互；v6 仅 Closed 进入全屏 | v2 同一直播页面 Closed→Book→Open→Closed，画面与聊天持续更新；展开屏全屏隐藏信息侧栏，返回恢复。v4-open-player-controls-native.png / v4-open-player-fullscreen-native.png 补充真实可见控件截图与就地进入/返回。未采集播放器 session ID，不能宣称零丢帧 |
| 分类房间与子分类网格 | 通过所列尺寸 | v2-closed-category.png：382pt 容器、163.5pt 卡片恢复两列；v2-closed-category-grid.png / v2-book-category-grid.png：4→6 列。相关源码在后续版本未修改 |
| 历史列表与空态 | 通过所列尺寸 | root 与 Astra 独立复核 v3-closed-history.png / v3-open-history.png：两列/三列重排，segmented 与清空按钮避开系统侧栏；v3-shortdrama-history-empty.png：空态文字完整。后续仅 Home 修改 |
| 开发者控制台 | 通过所列尺寸 | v3-closed-console.png / v3-open-console.png：半高面板、分段栏、关闭及空态可达；临时开发者模式已恢复关闭 |
| Duo 旋转与内屏分屏左右两侧 | 分屏入口工具阻塞 | 官方 Home 指示条拖拽在原生直线工具中仅返回系统主页；另一确定性手势工具依赖本版 Xcode 不存在的 SimulatorKit.framework，未执行触摸。尚未取得真实 Split：窄分屏全屏、Back 恢复详情与左右安全区均未验证；不据此认定产品失败或通过 |
| 普通 iPhone 与 iPad 窄/宽布局 | 待验证；锁屏与工具阻塞 | 需 v6 新包验证原有旋转/全屏/返回和窄宽安全区；不得用 Duo 或旧包证据替代 |
| 长文本、大字体、深浅色 | 通过所列状态 | v4 Closed 默认字号浅色与 Accessibility Large 深色首页经 root / Astra 复核：主标题两行，副标题按原规则截断，页码分离，收藏卡片文字不穿侧栏；其他字体档位未穷举。设备已恢复原 light / large 设置 |
| 加载、空态、错误 | 通过所列空错状态 | 历史/控制台空态与短剧 Open 空/错误态已有截图，图标、标题、说明、重载/重试及返回可达；open-player-portrait-loading.png 实际为网络错误态，不能当作加载态通过。未截取瞬时加载动画 |
| 亮度、后台恢复 | 待验证 | 所属屏幕及场景的实际交互证据 |
| 短剧播放、选集面板与折叠 | 通过已列形态，其他交互待验证 | 独立中立插件通过正常流程安装，横/竖/横三集各 24 秒实际接续；Closed 长标题、选集及关闭控件可见。Open 竖片保持比例，打开面板前后暂停时间均为 16.292 秒、选中第 3 集。Book 面板边界避开系统栏；弯折渲染模糊不用于验证文字或尺寸。拖动 detent、空错及普通设备继续验证；样片不证明真实内容接口 |
| macOS 窗口、tvOS 焦点 | 不适用 | 本次不修改对应宿主或其共享行为 |

已获用户授权与同仓 XCUITest 任务协调并取得独占时段，禁止并发控制同一 Xcode/设备。任何缺少新包截图的项目保持待验证，不以源码审查或构建成功替代。

v4 的正式新包门禁已补齐：response-81 建立同一设备的 workspace session，response-82 为最后源码编辑后的 `DeviceInteractionInstallAndRun`，明确返回安装并运行成功；随后 response-83 空交互捕获为 `Running`。此前 `simctl` 安装与产物哈希是辅助证据，不冒称官方安装回执；上表的局部通过结论仍不代表整体适配已完成。

## 当前验证记录

- 首轮 `AngelLive` / iPhone Duo workspace MCP `BuildProject` 成功（31.6 秒，`errors=[]`），见 `runs/iphone-duo-adaptation/response-5.json`、`first-build.log`。这是中间版本编译，后续 Welcome / UIKit / Danmaku 编辑必须再构建。
- 构建后 Issue Navigator 仍有 4 条另一任务的 macOS `HistorySmokeTests` 失败记录（`response-6.json`），不属于本次 iOS 编译诊断，也不能将其记为通过。
- 全仓文本平台中立性初扫及人工分类：6 个歧义词命中均为通用变量/旧扫描说明；已知具体内容平台标识 0，测试数字 `liveType` / `siteId` 0。扫描词表有明确边界，最终编辑后重跑，见 `platform-neutrality.json` 和 `platform-neutrality-review.json`。
- 主体实施后三端 workspace MCP 构建全部成功：`AngelLiveMacOS` / My Mac（46.16 秒，response-10）、`AngelLiveTVOS`（36.17 秒，response-14）、`AngelLive` / iPhone Duo（34.748 秒，response-17），均 `errors=[]`。构建后 issues 仍仅有上述历史 macOS 用例记录。完整日志保存在本轮 `runs/iphone-duo-adaptation/`；源码哈希保存为 `final-build-source-snapshot.json`。后续轮播整改必须重新构建 iOS。
- Xcode 27.1 下 `swift test --package-path Shared/AngelLiveCore --filter Danmaku`：59 项测试、10 个 suite 通过，日志 `danmaku-core-tests.log`。新增 iOS-only `DanmakuDisplayScaleTests` 不在此 macOS 运行结果中；UIKit 实际运行另行记录。
- UIKit 换屏脚本已准备；首次长 JSON 未送达 bridge，不计为执行结果。已处理本任务 PTY 行长限制并拆分脚本，实际执行结果仍待记录。
- Duo 安装响应 response-22 明确成功，使用空启动参数和环境。初次 response-25 报告 Hanging；线程采样显示主线程正常等待，response-26 已恢复 Running 且首页加载完成，没有证据表明产品死锁。
- 设备负责人显式切换 Closed / Partially Open / Open，response-27/28/29 均为 Running。内屏的官方截图捕获到黑外屏，依据当次显示枚举补取活动内屏截图；没有创建新模拟器。Book 与 Open 约间隔 50 秒仍出现相同轮播分割，排除瞬时切页动画，已触发 Astra 对 HomeHeroCarousel 的实际布局整改。当前截图属于 response-17 构建，不能作为整改后验收证据。
- 轮播整改后 iOS workspace MCP 构建 response-33 成功（12.208 秒，`errors=[]`），response-34 仅保留上述 4 条既有测试记录；response-35 确认新包安装并运行。root 比较此前构建哈希，后续产品源码仅 HomeView 改动，其他两端无需重复构建。整改后截图与交互仍须逐项复核。
- response-35 新包的 Closed→Book→Open→Closed 截图确认轮播单页、完整标题与同一选中项，root 与 Astra 独立复核。另一个现有内容入口已真实起播，Closed 全屏及返回链路通过（`final-closed-fullscreen-entered.png`；同名前缀但不含 `entered` 的图是未生效尝试，不能用作通过证据）。
- 后续发现两项真实视觉问题：Home 静止和刷新完成后仍有悬浮圈（`home-idle-before-refresh.png`、`home-after-refresh-completed.png`）；分类实宽 382pt、卡片仍 205.5pt，成为居中单列（`final-closed-category.png`）。Astra 已修复系统 inset 与下拉距离混用，以及 RoomList FlowLayout 旧 delegate metrics。JX 源码存在 `addChild`，不能将该问题描述为没有 containment。
- 第二轮整改后 response-51 构建成功（12.156 秒，`errors=[]`）。旧设备 session 过期导致 response-53 安装未执行，按实际响应重新建立同一设备的 session，response-56 明确安装并运行。没有删除设备/缓存/账号数据。v2 截图确认刷新完成后无滞留圈、分类恢复两列；手动轮播与自动轮播均可运行。
- 恢复正确静止下拉距离后，首页顶部 24pt 白带暴露。Astra 将图片背景按实际安全区向上延伸；response-68 构建成功（13.575 秒），response-72 安装成功。v3 白带消失，但 Closed 图出现图片重复接缝；这次结果判定不通过，Astra 继续修改前景与背景图层，使两者取相同图片尺寸、缩放与锚点，并延续顶部渐变颜色。
- v4 的 response-79 workspace MCP 构建成功（15.037 秒，`errors=[]`），response-80 仍只有既有 4 条 macOS 测试记录。Device Hub MCP session 多次失效后停止重复创建，沿用同一设备的原生 Device Hub 交互；动态取得本次构建产品后安装，退出码为 0，安装后的主程序与 debug dylib 哈希均与构建产物一致，见 `v4-install-provenance.json`。v4 三形态首页经 root 与 Astra 独立截图复核通过。
- JEV 的实际本地入口已发现且 doctor 可运行、AXe 可用；模型 provider 凭据不齐，未将 doctor 成功写作 UI 场景通过。证据为 `jev-doctor.json`。Device Hub MCP session 失效属于工具验证问题；原生设备交互与截图仍可用，不据此判定 App 启动失败。
- v4 后续正式安装 response-82 成功，response-83 确认 `Running`，均来自同一持续运行的 bridge；未为正常响应的客户端重启进程。root 已复读原始回执，并核对 `final-source-hashes-v4.json` 中 54 个源码文件均未发生变化，`git diff --check` 通过，ShellUI 无源码差异，见 `root-source-verification.json`。该哈希清单包含另一任务的既有修改，仅证明构建输入保持，不能用作修改归属声明。
- 短剧测试输入来自 `runs/season-episode-groups-20261019/fixture` 的既有中立样片，复制到本轮 `shortdrama-fixture/`，使用独立 `fixture.duo.short-drama` 命名空间和 loopback 动态端口，不改旧 fixture 或覆盖已安装插件。索引与 ZIP 哈希一致，短剧路由声明齐全，横向 640×360 / 竖向 360×640 媒体各 24 秒，HTTP Range 预检为 206。设备安装与交互结果须单独记录；预检本身不算播放器通过。
- 设备通过既有源管理及单插件安装流程添加中立样片；原有插件保留。横/竖/横三集按顺序实际加载并接续。`v4-official-shortdrama-closed-playing.png` 虽文件名含 playing，画面实际为末集结束态（00:24/00:24，中央播放按钮），不可当作截图当刻正在播放；`v4-shortdrama-closed-episodes.png` 为打开的选集面板，root 已复核长标题、当前集与系统栏避让。后续折叠及选集交互另记。

- `v4-shortdrama-closed-portrait-native.png`、`v4-shortdrama-open-portrait-paused-native.png`、`v4-shortdrama-open-episodes-native.png` 经 root 与 Astra 独立复核：竖片比例、面板对齐与关闭按钮安全区通过；Open 打开面板前后为第 3 集、16.292 秒。`v4-shortdrama-book-episodes-native.png` 确认 Book 透视下的面板边界和右侧系统栏分离，左侧系统弯折模糊不用于单独证明文字连续性、精确 pt 尺寸或拖动交互。

- `v4-closed-dark-large-home.png` 为深色 Accessibility Large 全分辨率证据，root 与 Astra 复核可见文字层级和安全区；`v4-shortdrama-open-empty-native.png` / `v4-shortdrama-open-error-native.png` 复核空态/错误态、重载/重试和返回。随后已恢复原 light / large 设置。
- 方向请求契约复核：Apple Prepare talk 明确内屏不遵循 supportedInterfaceOrientations；[requestGeometryUpdate 文档](https://developer.apple.com/documentation/uikit/uiwindowscene/requestgeometryupdate(_:errorhandler:)) 将其定义为请求并要求处理拒绝。由此不能保证仅请求旋转就一定进入全屏；root 决定补充显式全屏意图，保留普通手机旋转。这是依据官方契约的改进，不是已复现 Split 失败的声明。
- 运行片段请求 87 被 Xcode 路径校验拒绝，88 已发现有效 project path；89 未取得最终响应，客户端解析空行退出，不计为执行。只修复并重连本任务 bridge，未重启健康 Xcode / 设备；新客户端出现正常 PID 级授权弹窗，等待用户批准。

- v5 全屏补充限定为 5 个 FullUI 播放动作文件，新增显式意图、退出优先及实际 compact→regular 后的清理；不修改 Home、ShortDrama、Core 或 ShellUI 路径。差异保存在 `fullscreen-intent-contract-repair.patch`。Xcode 新客户端权限尚未批准，当前不能将 v4 的构建/截图声明为 v5 通过。
- 原生 CUA 服务随后两次返回 startup failed；正式 js_reset 后重新入口仍超时，已停止重复恢复。只读 simctl 截图最终成功，显示应用正常 light 首页，仅 Duo 一台 iOS 模拟器启动；不将工具失联推断为应用卡死。测试源/插件清理尚未确认，不宣称恢复原始数量。

## 前次停止点与恢复条件（历史记录）

- 最终源码：v5 相对 v4 仅 5 个播放动作文件改变。root 独立复核增量、54 文件哈希及 ShellUI 边界；5 文件 Swift parse 和全树 `git diff --check` 通过。`final-source-hashes-v5-unbuilt.json` 明确记录未构建，不能作为运行证据。
- 新 MCP 客户端未获 PID 级授权；本轮客户端与其 mcpbridge 已正常退出，原权限请求已失效，无本轮 build/install/交互请求遗留。没有终止健康 Xcode、Device Hub 或 App。
- CUA 正式重置后仍无法启动；AXe 实际观察最终返回 remote automation session 超时。未在无观察证据时盲点清理，也未创建替代模拟器。
- Duo 显示已恢复 `light / large`，开发者模式关闭。独立测试插件与源仍未删除：当前 19 个插件 / 3 个源，测试前为 18 / 2；仅应删除 `fixture.duo.short-drama` 及本轮源、可识别的样片历史，禁止清空用户数据。本轮 loopback fixture 服务已由 root 停止。
- Xcode 当前仍为 `AngelLive / iPhone Duo`；原 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)` 目标恢复因交互工具不可用而未完成。已向获授权协调的聊天归还操作权，并明确告知当前状态。
- 恢复后由代理重新发现连接和当前设备，正常取得新客户端授权，再完成 v5 workspace MCP build、正式安装及全屏/返回回归；补齐普通 iPhone/iPad、真实 Split、3 个 iOS Danmaku 运行片段和本表其余待验项，并精确清理测试数据、恢复目标。不得让用户替代理进行视觉验收。

最终设备证据与逐项阻塞见 `runs/iphone-duo-adaptation/device-final-manifest.json`。59 项 Core 测试和此前三端构建、v4 截图只代表各自记录版本及范围，不能用作 v5 整体适配完成声明。


## 授权后的恢复与最终验证

- 用户批准新客户端后，持续连接的 `XcodeListWindows` 返回当前 workspace。未重启健康 Xcode；已再次与获授权协调的 XCUITest 聊天确认独占操作时段。原始响应位于 `runs/iphone-duo-adaptation/resume-20261022/`。
- v5 的 `response-6` 为 workspace MCP 构建成功（14.148 秒，`errors=[]`）；`response-8` 仍为上述 4 条历史 macOS 测试记录。第一次安装因 session 不存在而失败；重建 session 后 `response-13` 明确返回安装并运行成功，但紧接的 `response-14` 捕获再次报告 session 不存在。该失效属于交互工具，不能推断 App 失败，也不能当作交互通过。
- root 复核发现 EdgeSwipe 无条件调用了整个文件被 `canImport(KSPlayer)` 包围的类型。v6 改为复用 Detail 内部的方向处理，保留本地 scene/host、手机方向策略及原延迟恢复；Builder 的内部 helper 恢复私有。没有切换或重新解析播放器依赖，也未声称可选播放器构建通过。独立补丁及两文件 Swift parse、全树 `git diff --check` 结果见 `orientation-compile-fix/`；54 个最终源码哈希见 `final-source-hashes-v6.json`。
- 用户提供的短剧测试源已完成索引、所选包 SHA256、manifest ID/版本一致性和标准短剧路由声明预检；预检不执行插件、不证明实际播放成功。源地址、包及具体插件信息仅保存在被忽略的本轮记录中。
- 原生 UI 恢复后，设备负责人仅卸载中立测试插件并删除本轮 loopback 源，插件和源数量分别从 19/3 恢复到 18/2；原有两源保留。证据为 `duo-fixture-source-cleaned.png/.txt`、`duo-plugin-baseline-restored.png/.txt`。尚未将可识别样片历史、最终运行目标恢复记为完成。

- v6 的 `response-15` workspace MCP 构建成功（12.858 秒，`errors=[]`），`response-16` 仍仅为同 4 条历史 macOS 测试记录。`response-17` 建立同设备 workspace session，`response-18` 明确返回应用已安装并运行。root 独立读取回执，54 个源码哈希仍全部匹配；已满足最终包的构建/安装门禁，实际运行捕获、视觉和交互继续单独验收。
- v6 全仓复扫覆盖 832 路径、739 文本和 93 二进制清单；6 处歧义经人工复核均为通用词，已知平台标识与测试数字映射命中均为 0。具体词表及覆盖限制见 `platform-neutrality-v6-review.json`；二进制未 OCR，未知品牌或私有字段不在该有限词表的证明范围。最终文档编辑后再次确认。

- v6 `response-19` 空捕获确认 `Running`。`v6-closed-home.png` 经 root 与 Astra 独立复核，首页单页、标题/页码分离、右侧系统栏避让以及无白带/接缝/静止刷新圈均通过当前 Closed 状态。
- 后续 workspace session 失效；唯一一次非 workspace 接管能激活同一已装包，但下一触摸再次失效，已停止继续重建。原生 Device Hub 可操作同一 v6。第一个直播入口取流/WebSocket 错误，根因未进一步判定；`v6-live-source1-error-native.png` 只记录错误态。另一个入口实际起播，Closed 全屏进入后详情隐藏，`v6-closed-fullscreen.png` 原尺寸图可见媒体与上下黑边，未见明显拉伸；该图控制层隐藏，不用于证明控件位置、返回或双击已通过。

- 随后 CUA 正式重置明确返回 Mac 已锁屏，不能自动解锁；已停止 UI 输入和进一步工具恢复，向用户请求正常解锁。此状态解释当前交互阻塞，不是产品全屏返回失败的证据。锁屏期间只继续不依赖 UI 的独立检查，不绕过系统锁屏。

本节结果优先于前次停止点；后续验收以 v6 最后编辑后的正式安装与实际截图为准。


## 当前停止点与下一步

- 当前源码为 v6，54 个构建输入哈希仍全部匹配，后续没有产品代码编辑。root 与 Astra 对上述实际截图分别复核，整体完成门槛仍未通过。
- 原生工具明确返回 Mac 已锁屏后，停止设备输入，已请求用户正常解锁。会话关闭请求没有返回最终结果；发送标准取消通知并有界等待后仍未确认，仅正常结束本轮 Python/MCP 客户端，没有重启 Xcode 或 Device Hub。该请求最终结果未知，不能写作会话成功关闭。
- 三个 iOS Danmaku 片段仅准备请求文件，未发送、未执行。此前 59 项 Core 测试不包含这些 iOS 检查。为可能的普通控制层验收准备了隔离中立样片备用目录，只有静态校验，服务未启动、插件未安装，不计作真实直播验证。
- 默认与既有 Preview 设备集合均无 Booted iOS；未创建新模拟器。Duo 的测试插件和 loopback 源已移除，恢复原 18 个插件/2 个源；仍留一条明确可识别的中立样片历史（第 3 集、约 16 秒），未清空用户历史。用户提供的真实短剧源已预检，尚未安装实测。
- 原 Xcode 目标尚未恢复：当前仍为 `AngelLive / iPhone Duo`；恢复目标为 `AngelLiveTVOS-SimpleLive / Any tvOS Device (arm64)`。因锁屏无法完成正常 UI 恢复，不能宣称现场全部恢复。
- 用户解锁后，重新协调 Xcode/设备操作时段，按实际需要取得新客户端的正常系统授权；源码未变可复用正式安装的 v6，不必为换工具重复安装。继续完成 Back/双击/旋转清理、Open 全屏往返、真实 Split、普通 iPhone/iPad、真实短剧及 3 个 iOS 运行片段，再清理单条样片历史并恢复目标。不得将缺失视觉验收转交用户。

最新设备清单：`runs/iphone-duo-adaptation/resume-20261022/device-resume-final-manifest.json`；root 独立复核记录：`root-v6-verification.json`。旧版本证据只代表各自版本与已列范围。


## 当前进度提交

用户确认 Mac 已解锁后，先要求保存并推送当前进度。本次提交仅包含 Duo 适配、对应测试源码和本文档；另一聊天尚未提交的 XCUITest 改动保留在工作区。混合的 UIKit 历史页只提交本任务的安全区锚点与 FullUI 窗口上下文，其他测试注入及无障碍标识改动不包含在本次提交。此前构建与设备证据来自当时完整工作区，不冒称本次拆分提交单独完成了重建或全部视觉验收。剩余验收及现场恢复项目继续保留，不以提交或推送表示适配完成。
