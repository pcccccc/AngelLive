# Angel Live

[![CI](https://github.com/pcccccc/AngelLive/actions/workflows/ci.yml/badge.svg)](https://github.com/pcccccc/AngelLive/actions/workflows/ci.yml)

<p align="center">
  <img src="./ScreenShot/logo.png" alt="Angel Live Logo" width="120" />
</p>

## 背景

本项目基于 [dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live/) 进行适配。

## 特别感谢

### PackyCode

感谢 PackyCode 对本项目的赞助。

<a href="https://www.packyapi.com/register?aff=7cYv">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./ScreenShot/sponsors/packy-dark.png" />
    <img src="./ScreenShot/sponsors/packy-normal.png" alt="PackyCode" width="420" />
  </picture>
</a>

<br />

PackyCode 是一家稳定、高效的 API 中转服务商，提供 Claude Code、Codex、Gemini 等多种中转服务。具备自动故障转移、智能路由和无限并发等多种功能，让 AI 编程成为真正的生产力工具。

[点此链接注册，立即开始使用！](https://www.packyapi.com/register?aff=7cYv)

### Bugsnag

<a href="https://www.bugsnag.com">
  <img src="https://images.typeform.com/images/QKuaAssrFCq7/image/default-firstframe.png" alt="Bugsnag Logo" width="150" />
</a>

感谢 Bugsnag 提供的开源许可，也感谢 [Telegram 社区](https://t.me/angelliveapp) 各位成员的问题反馈与建议。

## 支持平台

**iOS 17+ · macOS 15+ · tvOS 17+**

适配 26 系列系统与 Liquid Glass。

## 问题反馈

[Telegram](https://t.me/angelliveapp) · [提交 Issue](https://github.com/pcccccc/AngelLive/issues/new/choose)

## 开发环境配置

> ⚠️ **重要提示**：本项目默认使用 [KSPlayer](https://github.com/TracyPlayer/KSPlayer) LGPL分支 播放器内核。可通过环境变量 `USE_VLC=1` 切换为 VLCKit 内核（两者互斥，不能同时引入，否则内嵌的 FFmpeg 符号会冲突）。

1. **克隆项目**

   ```bash
   git clone https://github.com/pcccccc/AngelLive.git
   cd AngelLive
   ```

2. **打开项目**

   使用 Xcode 打开 `AngelLive.xcworkspace`。

3. **配置 Bugsnag（可选）**

   本地配置文件为 `Shared/AngelLiveDependencies/Sources/Resources/BugsnagSecrets.local.plist`，已被 Git 忽略。不配置密钥也可使用仓库中的占位配置构建。

4. **运行项目**

   选择对应平台的 scheme，再选择模拟器或真机运行。

## 开源项目致谢

感谢以下开源项目及其作者的贡献：

- **播放与弹幕**：[KSPlayer](https://github.com/TracyPlayer/KSPlayer)（FLV 播放）、[FFmpeg](https://github.com/FFmpeg/FFmpeg)、[DanmakuKit](https://github.com/qyz777/DanmakuKit)
- **界面与图像**：[ColorfulX](https://github.com/Lakr233/ColorfulX)、[Kingfisher](https://github.com/onevcat/Kingfisher)、[Shimmer](https://github.com/markiv/SwiftUI-Shimmer)、[SimpleToast](https://github.com/sanzaru/SimpleToast)、[swiftui-toasts](https://github.com/sunghyun-k/swiftui-toasts)、[AcknowList](https://github.com/vtourraine/AcknowList)、[Pow](https://github.com/EmergeTools/Pow)
- **网络与数据**：[Alamofire](https://github.com/Alamofire/Alamofire)、[Starscream](https://github.com/daltoniam/Starscream)、[GZipSwift](https://github.com/1024jp/GzipSwift)、[SWCompression](https://github.com/tsolomko/SWCompression)、[SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON)、[swift-nio](https://github.com/apple/swift-nio.git)、[swift-protobuf](https://github.com/apple/swift-protobuf.git)、[UDPBroadcastConnection](https://github.com/gunterhager/UDPBroadcastConnection)
- **开发工具**：[InjectionNext](https://github.com/johnno1962/InjectionNext)

## 支持项目

[爱发电](https://afdian.com/a/laopc)

## Star History

<a href="https://www.star-history.com/#pcccccc/SimpleLiveTVOS&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=pcccccc/SimpleLiveTVOS&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=pcccccc/SimpleLiveTVOS&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=pcccccc/SimpleLiveTVOS&type=Date" />
  </picture>
</a>
