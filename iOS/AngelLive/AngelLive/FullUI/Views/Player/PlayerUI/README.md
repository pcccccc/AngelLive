# PlayerUI

本目录服务 iOS FullUI，播放器 UI 组件源自 [KSPlayer](https://github.com/kingslay/KSPlayer)，并按 AngelLive 的直播与控制层需求适配。页面状态和导航由宿主负责，播放器与第三方适配通过共享 Package 接入。

## 当前文件

- `KSVideoPlayerView.swift`：播放器与覆盖层组合。
- `KSVideoPlayerViewBuilder.swift`：播放器视图构建接口。
- `VideoControllerView.swift`：常规直播控制层。
- `VerticalLiveControllerView.swift`：竖屏直播控制层。
- `GestureView.swift`：手势适配。
- `ViewExtension.swift`：视图辅助扩展。
- `KSVideoPlayerModelFallback.swift`：`!canImport(KSPlayer)` 条件下的模型兼容定义。

核心播放器桥接位于 `Common/PlayerCore/KSCorePlayerView.swift`；`AirPlayView.swift` 位于父目录 `FullUI/Views/Player/`，不是本目录文件。

## 呈现边界

控制层沿用既有直播操作和弹幕能力。iOS 26 及以上按代码可用性使用 `glassEffect`，旧系统降级为 `.ultraThinMaterial`；普通材质不等于 Liquid Glass。短剧进度与选集界面由独立短剧页面承载。

修改布局需遵循仓库现有页面尺寸、状态所有权与最后编辑后新包视觉验收要求。不要据本目录服务 iOS 的用途，推断所有来源代码的多平台条件编译都已删除。

## 来源与许可记录

原项目作者：kintan、Ian Magallan Bosch。原文档记录来源许可证为 GPL-3.0；此处保留来源与归属说明，本次文档清理未重新核验上游许可证，也不将该历史记录当作当前依赖整体许可结论。

感谢 KSPlayer 作者及贡献者。
