# 默认画质

FullUI 的播放设置提供「最高画质」「均衡」「省流」，由共享 `PlayerSettingModel.defaultPlaybackQuality` 持久化到 `AngelLive.Setting.DefaultPlaybackQuality`。首次使用及存储值无效时为「最高画质」，保持既有起播行为。设置在下次进入房间时生效，不改变正在播放的选择。

`RoomPlaybackResolver.initialSelection` 仅负责首次起播。最高画质复用原 `automaticSelection` 的第 0 档逻辑，保持插件既有默认与锁定档位回退语义。均衡、省流优先在已学习的 CDN 线路中挑选未锁定、具有有效绝对 URL 或声明 `refreshOnSelect` 的档位；该线路无候选时依插件线路顺序寻找其他线路。所有线路无候选时退回既有自动选择。

同名画质的 HLS、FLV、DASH 格式备选按一个档位计数，选用插件顺序中首个可用格式。标题只剥离独立格式标记；帧率、HDR 等其余信息保留，空标题各自保留。`qn` 是插件透传标识，不用于排序或合并，0 也无特殊意义。

画质判定是 best effort：整条候选线路全部档位均能识别分辨率（360p、480p、540p、720p、1080p、1440p、2160p、2K、4K）时稳定按分辨率从高到低排列；否则全部档位都能识别通用等级「原画、蓝光、超清、高清、标清、流畅」时按等级排列。两种条件均不满足时保持插件顺序，不把未知档位混入推断排序。相同分辨率保留插件顺序，不推断帧率或 HDR 的优劣。均衡取去重后的 `count / 2` 档，中间偏低；省流取末档。没有可比信息时效果取决于插件的档位顺序，不能保证实际码率最低。

三端首次选择之后的手动切换、取参刷新和播放恢复继续使用现有选择逻辑，尽量保持用户当前 CDN 和画质。iOS 换房先按相同偏好与学习 CDN 准备目标档位，提交时复用该选择，避免需要重取流的档位被准备两次。macOS 按根页面同一已安装插件条件隔离，tvOS 读取现有 `AppState.pluginAvailability`；ShellUI 不应用新偏好。

相关测试位于 `DefaultPlaybackQualityTests`，覆盖分辨率乱序、文字等级、未知与混合顺序、格式去重与不同帧率、锁定/空地址/重取流、CDN 学习、空线路及单/双档、最高画质兼容和设置持久化。设备与三端宿主构建仍须按项目门禁验证，核心测试不能代替设备验收。

验证入口：

```sh
swift test --package-path Shared/AngelLiveCore --filter DefaultPlaybackQualityTests
swift test --package-path Shared/AngelLiveCore --filter 'RoomPlaybackResolverTests|PluginErrorProtocolTests'
```

2026-10-13 使用 Xcode 27.0 RC（27A266a）执行上述测试，分别通过 13 和 25 个测试。首轮三个 workspace scheme 均构建通过，但 macOS 新增设置行的外层布局使行高偏离既有页面，该轮视觉验收不通过。

随后由 `gpt-6-astra / high` 按原页面重写三端新增布局：macOS 复用完整 `PanelNavigationRow` 的标题/副标题结构；iOS 使用已有的导航式 Picker；tvOS 使用已有的 45pt 行高，删除额外占用间距的独立说明项。修订后的三个 workspace scheme 均重新构建通过，error navigator 均为 0。

macOS 原生 UI 工具报截图生成/资产目录错误后，通过 Xcode 调试器使用应用已有的设置导航通知进入页面，缓存实际运行的 NSView 渲染图核对尺寸。首次仅将默认画质 Picker 设为右对齐后，实测仍与应用图标 Picker 相差 18px，未作为通过。Astra 随后将 FullUI 的两个同类 Picker 都固定到相同右侧锚点，ShellUI 保留原有对齐方式。最后编辑后再次执行 workspace BuildProject、检查 error navigator 为 0，并 RunProject 启动新产物后重新捕获。

最终原尺寸图为 2120×1808px：「应用图标」与「默认画质」首行均为 110px（含 2px 分隔线），两组卡片均为 218px；两个 Picker 圆形箭头最大横向范围均为 x=1897…1936，四条对应水平像素切片一致，右边缘偏差为 0。证据文件名为 `AngelLive-default-quality-aligned.png`，原始响应保存在本次临时 MCP 记录中。该证据确认上述实际行高与控件位置；NSView 缓存没有捕获窗口合成材质，不能作为侧栏材质、全窗口颜色或完整交互验收通过证据。

iOS 的 `DeviceInteractionInstallAndRun` 在 600 秒内没有返回匹配的最终响应，未确认新包安装/启动，没有设备截图或交互通过证据。tvOS 仅构建，未安装或交互验收。JEV 缺运行凭据，未执行语义测试。真实直播的默认选流与后续手动切档仍待设备验收。
