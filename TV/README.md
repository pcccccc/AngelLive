# AngelLive tvOS

tvOS 宿主提供遥控器浏览、直播播放、弹幕、收藏、插件管理和 Top Shelf。内容能力来自用户安装的插件；没有可用插件时进入 ShellUI，保留本地工具与配置入口。

从仓库根目录打开 `AngelLive.xcworkspace`，选择共享 scheme `AngelLiveTVOS` 或 `AngelLiveTVOS-SimpleLive`。工程依赖本地的 `AngelLiveCore`、`AngelLiveDependencies` 和 `SharedAssets`，不要仅打开此目录中的工程来代替 workspace 验证。

开发环境、签名和模拟器约束见根目录 [AGENTS.md](../AGENTS.md)。默认播放器为 KSPlayer；更换内核属于独立依赖变更。模拟器构建不需要修改 development team、bundle identifier 或 entitlements。

入口与模块关系见 [ARCHITECTURE.md](ARCHITECTURE.md)。焦点、半屏播放器和 Siri Remote 返回行为见 [焦点与遥控器导航记录](../docs/TVFocusAndRemoteNavigation.md)。

共享逻辑修改先运行相关 Package 测试，再构建 tvOS scheme。UI 变更需在最后修改后重新安装应用，使用遥控器方向键与 Select/Menu 验证实际结果；构建通过不能代替焦点和播放验收。全新模拟器没有插件和账号，应通过应用支持的流程准备，不能复制用户的私密容器。
