# UI 视觉术语表

**用途：** root 分派 UI 任务、Terra 量测和报告、root 复核时共用的精确用语，让每条视觉要求可执行、可检查。本表隶属 [视觉门禁](ui-visual-gate.md)，不替代根 [AGENTS.md](../../AGENTS.md) 第 1 节的视觉红线，也不替代 HIG 或对应 Skill。

**用法：**

- 验收项写成 `术语：对象 + 可量测的要求 + 参照`，例如：
  - `Concentric Radius：房间卡片封面圆角 = 卡片圆角 − 内边距，参照收藏页卡片`
  - `Tabular Numbers：播放器时间码 .monospacedDigit()，拖动进度时宽度不跳`
- 不接受“精致一点”“更原生”“对齐一下”这类无术语、无参照的要求。
- “项目参照”列里的组件优先复用，不另造同类样式。表中 API 只是实现方向，最终以同平台既有页面为准。
- 部署下限是 iOS/tvOS 17、macOS 15。iOS 26 及以上的 API 必须加可用性判断并保留旧系统降级，先查 `iOS/AngelLive/AngelLive/Common/Extensions/iOS17Compatibility.swift` 里的既有封装。

## 间距与分组

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Padding（内边距） | 内容到容器边缘的距离 | 同类容器统一用一个值，不在单个元素上叠加 `.padding()` 来凑位置 |
| Gap（间距） | 同级元素之间的距离 | 用 `HStack`/`VStack`/`Grid` 的 `spacing`，不用 `Spacer().frame(height:)` 凑 |
| Proximity（亲近性） | 相关元素靠得近，不相关的分得开 | 组内间距明显小于组间间距，标题离它所属的内容比离上一组更近 |
| Whitespace（留白） | 用空白建立层次 | 首选加大组间距，不先加分隔线或背景块 |
| Divider vs. Space（分隔线还是留白） | 决定用线还是用空白分组 | 列表行沿用系统分隔线及其缩进；卡片网格用留白，不再加线 |
| Safe Area（安全区） | 内容避开刘海、Home 指示条、窗口工具栏 | 底部浮层用 `.safeAreaInset`，不写死 34pt 之类的数值 |

## 层级与文字

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Hierarchy（层级） | 一眼看出主次 | 每屏只有一个主标题级别；用 `.font(.headline)`、`.subheadline` 等文本样式，不写固定字号 |
| Title / Subtitle（标题/副标题） | 主文字和辅助文字 | 副标题用 `.foregroundStyle(.secondary)`，字号比标题小一级，与同平台既有行一致 |
| Muted Text（弱化文字） | 次要信息降权 | 用 `.secondary` / `.tertiary` 层级，不自定义灰色 |
| Baseline Alignment（基线对齐） | 不同字号的文字按基线对齐 | `HStack(alignment: .firstTextBaseline)`；图标与文字同行时检查图标的视觉中心 |
| Line Clamp（行数限制） | 限制最多显示几行 | `.lineLimit(n)`，同类卡片的行数一致；直播标题通常是 1–2 行 |
| Middle Truncation（中间截断） | 保留开头和结尾、省略中间 | `.truncationMode(.middle)`，用于文件名、地址、版本号 |
| Tabular Numbers（等宽数字） | 数字宽度固定，变化时不跳动 | `.monospacedDigit()`；数值变化可配合 `.contentTransition(.numericText())`；适用于时间码、人数、计数器 |
| Dynamic Type（动态字体） | 跟随系统字号 | 文本样式而非固定字号；最大号下不裁切、不重叠，必要时改为纵向排列 |

## 表面、颜色与形状

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Semantic Color（语义色） | 按用途而非色值取色 | 用 `Color.primary`、`.secondary`、`.accentColor`、系统背景色或 SharedAssets，不写死十六进制颜色 |
| Accent（强调色） | 只用在可交互或需要强调的元素上 | 一屏内强调色少量出现；不给普通文字或装饰涂强调色 |
| Contrast（对比度） | 前景和背景可区分 | 深色和浅色模式都要检查；图片或视频上的文字必须有 Scrim |
| Scrim（遮罩） | 叠在图片或视频上、保证文字可读的渐变或暗层 | 项目参照：`TVHomeHeroScrim`、`PlatformAppearanceCard` 的 scrim；用 `LinearGradient`，只覆盖文字所在区域 |
| Edge Fade（边缘渐隐） | 可滚动区域边缘的淡出，提示还有内容 | iOS 26 用 `.scrollEdgeEffectStyle`（参照 `iOS/AngelLive/AngelLive/FullUI/Components/FullUINavigationStyle.swift`）；旧系统用 `.mask(LinearGradient)`，不用硬切 |
| Border Radius（圆角） | 容器圆角 | 用 `RoundedRectangle(cornerRadius:style: .continuous)`，同类卡片用同一个值 |
| Concentric Radius（同心圆角） | 嵌套圆角的内角 = 外角 − 内边距 | 封面放在卡片里时按此公式计算；iOS 26 可用 `ConcentricRectangle`（需加可用性判断） |
| Nested Cards（卡片套卡片） | 容器里再套带背景的容器 | 默认禁止；需要分组时用留白或分区标题 |
| Hairline Border（细描边） | 1 物理像素的描边 | `lineWidth: 1 / displayScale`（从环境读取 `displayScale`）；不用 1pt 粗线 |
| Material / Glass（材质） | 系统模糊材质和 iOS 26 液态玻璃 | 用 `.background(.regularMaterial)` 或 `.glassEffect`（需加可用性判断）；tvOS 的半透明背景是有意保留的特色，不改成不透明 |
| Aspect Ratio（宽高比） | 封面、播放器的固定比例 | `.aspectRatio(16/9, contentMode: .fill)` 配合 `.clipped()`；同一网格内比例统一 |
| Optical Alignment（光学对齐） | 按视觉重心而不是外框对齐 | 播放三角形、箭头、带圆角的 SF Symbol 可能需要 0.5–1pt 偏移；必须用截图证明偏差，不凭猜测加偏移 |
| Badge（角标） | 状态或计数小标签 | 项目参照：`MediaBadge`、TV 的 `liveStatusBadge` / `watchedCountBadge`；不新造角标样式 |
| Disabled State（禁用态） | 不可用但可见 | 用 `.disabled(true)` 让系统降低透明度；不只改颜色而保留可点击 |
| Destructive Action（破坏性操作） | 删除、清除等不可逆操作 | `Button(role: .destructive)`，放在确认对话框或菜单末尾 |

## 状态与反馈

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Skeleton（骨架屏） | 加载时的占位轮廓 | 项目参照：`LiveRoomCardSkeleton`（iOS/macOS）、`TVRoomCardSkeleton`、`PlatformDetailSkeletonView`；骨架尺寸必须与真实卡片一致，加载完成时不跳版 |
| Empty State（空状态） | 无数据时的说明和下一步 | `ContentUnavailableView`，或项目参照 `PluginManagementEmptyState` / `TVPluginEmptyState`；必须给出原因和可执行的操作 |
| Error State（错误态） | 请求失败的呈现 | 与空状态的视觉结构一致，附重试按钮；不把错误显示成空列表 |
| Loading Button（加载中按钮） | 提交后按钮内显示进度 | 按钮宽度不变，文字换成 `ProgressView`，期间禁止重复点击 |
| Press State（按下态） | 按下时的即时反馈 | 用系统 `ButtonStyle`；自定义样式时读取 `configuration.isPressed`，不能没有反馈 |
| Haptic（触感反馈） | 关键操作的触觉确认 | iOS 用 `.sensoryFeedback`，只用于确认类操作，不在滚动时连续触发 |
| Touch Target（点击热区） | 可点击区域 | 至少 44×44pt；小图标用 `.contentShape(Rectangle())` 扩大热区，视觉尺寸不变 |

## 动效

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Easing（缓动） | 速度曲线 | 进场快、收尾缓；不用 `.linear` 做界面过渡 |
| Spring（弹簧） | 物理感动画 | 用 `.smooth`、`.snappy`、`.bouncy` 预设；界面过渡不用明显回弹 |
| Stagger（错峰） | 多个元素依次进场 | 间隔很短，只用于首次加载，刷新和翻页时不重复播放 |
| Shared Element（共享元素转场） | 元素从列表平滑过渡到详情 | 用 `matchedTransitionSource` 配合 zoom 转场，参照 `iOS17Compatibility.swift` 的封装 |
| Directional Motion（方向性动效） | 动画方向与导航方向一致 | 前进从右进，返回向右出；sheet 从下进 |
| Exit Motion（退场动画） | 元素消失的方式 | 退场比进场更快、更轻；用 `.transition` 定义，不能直接闪掉 |
| Reduce Motion（减少动态效果） | 尊重系统设置 | 读取 `accessibilityReduceMotion`，开启后改为淡入淡出或无动画 |

## 控件选型

| 术语 | 选择依据 |
| --- | --- |
| Button Hierarchy（按钮层级） | 一组按钮里只有一个主按钮（`.borderedProminent`），其余用 `.bordered` 或纯文字 |
| Tabs vs. Segmented（标签栏还是分段控件） | 切换整个页面用 TabView；同一页面内切换视图用 `Picker(.segmented)` |
| Modal vs. Drawer（模态还是抽屉） | iOS 用 sheet 配合 `presentationDetents`；macOS 用 sheet 或 inspector；tvOS 用 `fullScreenCover` 或 sheet，沿用同类页面 |
| Switch vs. Checkbox（开关还是复选框） | 即时生效的卡片行与弹层设置项三端统一用 `Toggle`（macOS 用 `.switch` 并配珊瑚橙强调色）；多项勾选集合才用 `.checkbox` |
| Popover vs. Tooltip（弹出框还是提示） | 可交互内容用 `.popover`；macOS 纯说明用 `.help()` |
| Progressive Disclosure（渐进披露） | 低频能力放进更多菜单或二级页（见 `PRODUCT.md`「高频直达」） |
| Floating Bar（悬浮控制条） | 播放器控制层；自动隐藏后不能拦截底层手势 |

## tvOS 焦点（网站词汇表未覆盖）

| 术语 | 含义 | 原生实现与检查点 |
| --- | --- | --- |
| Focus State（焦点态） | 当前被遥控器选中的元素 | 卡片用 `.buttonStyle(.card)` 或系统焦点效果；用 `@FocusState` / `isFocused` 驱动自定义样式 |
| Focus Lift（焦点放大） | 焦点元素放大并投影 | 放大后不被相邻元素或容器裁切；网格要预留放大所需的间距 |
| Focus Section（焦点分区） | 让焦点在区块之间可预期地移动 | `.focusSection()`；从侧栏或顶部移入时落在合理位置 |
| Default Focus（默认焦点） | 页面打开时的初始焦点 | `.defaultFocus` / `prefersDefaultFocus`；返回页面时恢复离开前的焦点 |
| Focus Effect Disabled（关闭系统焦点效果） | 自定义焦点样式时关闭系统效果 | `.focusEffectDisabled()` 后必须自己提供明显的焦点态，不能让焦点不可见 |
| Menu Button（返回键） | 遥控器 Menu / 返回键 | 逐层返回；在根页面交还给系统 |
