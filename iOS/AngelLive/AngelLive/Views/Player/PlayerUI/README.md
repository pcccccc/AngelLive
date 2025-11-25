# PlayerUI

本目录中的播放器 UI 组件源自 [KSPlayer](https://github.com/kingslay/KSPlayer)，并根据 AngelLive 项目的需求进行了修改和优化。

## Fork 说明

这些文件是从 KSPlayer 项目 fork 并修改而来：

- **CorePlayerView.swift** - 核心播放器视图组件
- **VideoPlayerView.swift** - 完整视频播放器视图
- **VideoPlayerViewBuilder.swift** - 播放器控件构建器
- **VideoControllerView.swift** - 播放器控制层视图
- **GestureView.swift** - 手势处理视图
- **AirPlayView.swift** - AirPlay 支持
- **ViewExtension.swift** - 视图扩展工具

## 主要修改

1. **移除非 iOS 平台代码**：删除了 tvOS、macOS、visionOS 相关的条件编译代码，专注于 iOS 平台
2. **优化播放控制层**：
   - 采用 iOS 16+ 液态玻璃材质效果（`.ultraThinMaterial`）
   - 重新设计按钮布局，适配直播场景
   - 移除进度条和时间显示（直播不需要）
   - 添加弹幕控制功能

## 原始项目

KSPlayer 是一个功能强大的 iOS/macOS/tvOS 视频播放器框架，支持多种格式和流媒体协议。

- **项目地址**：https://github.com/kingslay/KSPlayer
- **原作者**：kintan, Ian Magallan Bosch
- **许可证**： GPL-3.0 license

## 致谢

感谢 KSPlayer 项目的作者和贡献者们提供了优秀的播放器基础框架。
