# tvOS 宿主结构

`AngelLiveTVOS/Other/SimpleLiveTVOSApp.swift` 是应用入口，负责共享服务启动、资源配置和 deep link。`Other/ContentView.swift` 根据 `AppState.pluginAvailability` 选择 FullUI/ShellUI，组织首页、收藏、平台、搜索和设置导航。

| 目录 | 职责 |
| --- | --- |
| `AngelLiveTVOS/Source/Home` | 插件首页与 tvOS 图片呈现 |
| `AngelLiveTVOS/Source/Favorite` | 收藏、ShellUI 历史及直链播放入口 |
| `AngelLiveTVOS/Source/Platform` | 平台列表、插件来源与安装入口 |
| `AngelLiveTVOS/Source/DetailPlayer` | 房间 ViewModel、播放器、控制层和焦点交互 |
| `AngelLiveTVOS/Source/Setting` | 设置、登录、同步、历史记录与开发者入口 |
| `AngelLiveTVOS/Source/Tools` | 远程输入及 App Group 插件同步适配 |
| `TopShelfExtension` | 读取共享展示快照并生成 Top Shelf 内容 |

宿主依赖 `AngelLiveCore` 的插件、播放恢复、收藏、同步和领域模型；播放器及第三方库适配通过 `AngelLiveDependencies`。焦点、遥控器、半屏/全屏导航留在宿主；不要把 tvOS 视图依赖反向引入 Core。

FullUI 使用已安装插件提供的能力。ShellUI 是独立产品模式，共享服务修改必须检查是否改变其行为；当前安装流程之外的 ShellUI 调整需要明确任务范围。

FullUI 收藏更新通过 `listVersion` 发布 Top Shelf 展示快照，列表变化不重新启动收藏网络同步。扩展优先读取快照，空快照也属于有效结果；没有发布过快照的旧安装保留原有兼容路径。宿主与扩展的插件文件通过 App Group 同步，各自运行时仍使用各自进程的 `LiveParsePlugins.shared`。

播放器复用共享恢复协调器，宿主只适配引擎状态、采样和恢复动作。遥控器操作应验证焦点与操作后的页面状态；Siri Remote Menu 与原生窗口 Escape 不能互相替代。具体回归场景见 [TVFocusAndRemoteNavigation.md](../docs/TVFocusAndRemoteNavigation.md)。
