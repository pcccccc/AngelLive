# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。

## 项目概述

AngelLive 是一个多平台直播聚合应用，支持 iOS、macOS 和 tvOS。聚合了 7 个国内直播平台（哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易CC），功能包括播放、CloudKit 云同步收藏、弹幕显示等。

## 构建命令

```bash
# 打开工作区（必须使用工作区，不要单独打开 .xcodeproj）
open AngelLive.xcworkspace

# 命令行构建
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLive -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLiveMacOS -destination 'platform=macOS' build
xcodebuild -workspace AngelLive.xcworkspace -scheme AngelLiveTVOS -destination 'platform=tvOS Simulator,name=Apple TV' build

# 运行测试（AngelLiveCore 包）
cd Shared/AngelLiveCore && swift test
```

## 架构

**MVVM + Service 层**，通过 Swift Package 共享代码：

```
View (SwiftUI) → ViewModel (@Observable) → Service → AppState
```

### 工作区结构

- `AngelLive.xcworkspace` - 主工作区（使用这个，不要单独打开项目）
- `iOS/AngelLive.xcodeproj` - iOS 平台
- `macOS/AngelLiveMacOS.xcodeproj` - macOS 平台
- `TV/AngelLiveTVOS.xcodeproj` - tvOS 平台

### 共享包（位于 `Shared/`）

- **AngelLiveCore** - 核心业务逻辑：ViewModels、Services、Models、DanmakuKit
- **AngelLiveDependencies** - 集中管理第三方依赖，按平台条件引入
- **SharedAssets** - 跨平台共享的颜色、图片、设计资源

### 关键文件

| 组件 | 位置 |
|------|------|
| 全局状态 | `*/AppState.swift`（各平台各有一份） |
| 直播 API 服务 | `Shared/AngelLiveCore/Sources/Services/LiveService.swift` |
| CloudKit 同步 | `Shared/AngelLiveCore/Sources/Services/FavoriteService.swift` |
| 收藏 ViewModel | `Shared/AngelLiveCore/Sources/Models/AppFavoriteModel.swift` |

## 平台要求

- **Swift 6.2**（swift-tools-version）
- iOS 17+、macOS 15+、tvOS 17+
- Xcode 15+

## 依赖说明

本项目使用 **KSPlayer LGPL 版本** 支持 FLV 直播流。如没有 LGPL 仓库权限，请联系 KSPlayer 作者获取，或修改代码使用 GPL 版本。

## 关键模式

### 状态管理
使用 `@Observable` 宏（iOS 17+），通过 Environment 注入。AppState 持有所有 ViewModel。

### 并行搜索
`LiveService.searchRooms()` 使用 TaskGroup 并发搜索多个平台。

### CloudKit 同步
`FavoriteService` 处理 iCloud 收藏同步，使用 Actor 保证线程安全（`FavoriteStateModel`）。

## 支持的直播平台

| 平台 | 分类列表 | 搜索 | 弹幕 | 实现方式 |
|------|----------|------|------|----------|
| 哔哩哔哩 | ✅ | ✅ | ✅ | JS 插件 |
| 斗鱼 | ✅ | ✅ | ✅ | JS 插件 |
| 虎牙 | ✅ | ✅ | ✅ | JS 插件 |
| 抖音 | ✅ | ✅ | ✅ | JS 插件（需 Cookie） |
| 快手 | ✅ | ✅ | ❌ | JS 插件 |
| YY | ✅ | ✅ | ❌ | JS 插件 |
| 网易CC | ✅ | ✅ | ❌ | JS 插件 |

> YouTube 已移除。

## JS 插件系统（LiveParse）

各直播平台的 API 解析通过 JavaScriptCore JS 插件实现，位于 `LiveParse/Sources/LiveParse/Resources/` 目录：

### 插件结构

每个插件包含：
- **manifest.json** — 声明 pluginId、version、apiVersion、entry 入口文件、可选 preloadScripts
- **index.js** — 入口脚本，导出 `globalThis.LiveParsePlugin` 对象

命名规范：`lp_plugin_{平台}_{版本}_{文件类型}.{ext}`

### 插件 API（v2 方法名）

| 方法 | 用途 | 需要 Cookie |
|------|------|-------------|
| `getCategories` | 获取分类列表 | 否（抖音从本地数据） |
| `getRooms` | 获取房间列表 | 抖音需要 |
| `getPlayback` | 获取播放地址 | 抖音需要 |
| `search` | 搜索房间 | 抖音需要 |
| `getRoomDetail` | 获取房间详情 | 抖音需要 |
| `getLiveState` | 获取直播状态 | 抖音需要 |
| `resolveShare` | 解析分享码 | 抖音需要 |
| `getDanmaku` | 获取弹幕参数 | 抖音需要 |

### 关键机制

- **preloadScripts**：manifest 中声明需要预加载的脚本（如抖音的 `webmssdk.js` 用于签名）
- **浏览器环境 shim**：JSRuntime 启动时注入 `window`/`document`/`navigator` 全局对象，供第三方脚本使用
- **Cookie 注入**：JS 插件通过 `payload.cookie` 或 `_dy_runtime.cookie` 获取 Cookie
- **v1→v2 兼容**：Swift 侧 `callWithFallback` 先尝试 v2 方法名，失败时回退 v1

### 测试

```bash
cd LiveParse && swift test
```

抖音测试需要手动填入 Cookie：编辑 `Tests/LiveParseTests/DouyinTests.swift` 中的 `douyinTestCookie` 常量。

## 深度链接（tvOS）

格式：`simplelive://room/{platform}/{roomId}` - 供 Top Shelf 扩展使用。
