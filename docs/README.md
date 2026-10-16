# AngelLive 文档索引

维护日期：2026-10-16。当前任务见根目录 [TODO](../TODO.md)，产品与工程约束分别见 [PRODUCT](../PRODUCT.md) 和 [AGENTS](../AGENTS.md)。文档中的实现状态、构建结果和设备验收是不同结论；历史包证据不代表当前工作树已验证。

## 架构与共享层

- [三端架构与页面联动审查](CrossPlatformArchitectureAudit20261016.md)：当前共享边界、确认问题、提取机会及待验证项。
- [tvOS 宿主架构](../TV/ARCHITECTURE.md)。
- [SharedAssets 使用说明](../Shared/SharedAssets/README.md)。
- [Swift 6 迁移现状与设备验收](Swift6SendableAudit.md)。
- [SwiftUI 状态与视图拆分维护项](SwiftUISpecialistAudit.md)。

## 插件与浏览

- [首页协议与宿主架构](PluginDrivenHomePagePlan.md)、[macOS 首页交互与验收](PluginDrivenMacOSHomePagePlan.md)、[启动与首页缓存](StartupCachePresentation.md)。
- [插件管理行为](PluginManagementUX.md)、[插件管理视觉规格](PluginManagementRedesign.md)。两份分别管理业务流程与平台尺寸，不把已实现状态等同于全矩阵验收。
- [Cookie 扫码登录协议](PluginQRCodeLoginProtocolPlan.md)、[API 凭据与设备码授权](PluginAPITokenHostIntegration.md)、[认证失败恢复](AuthenticationRecovery20261004.md)。
- [iPhone 搜索标签兼容](iOSSearchTabCompatibility.md)、[iOS 刷新反馈](iOSLiquidRefreshFeedback.md)。

## 播放与弹幕

- [播放韧性现状](PlaybackResilienceRoadmap.md)、[默认清晰度](DefaultPlaybackQuality.md)、[音频输出初始化](AudioOutputInitialization.md)。
- [播放解密协议](PlaybackDecryptionProtocol.md)、[分片字节还原管线](SegmentByteRestorationPipeline.md)。
- [短剧模式](ShortDramaModePlan.md)：仍在实施及验收，不作为过期方案删除。
- [tvOS 焦点与遥控器](TVFocusAndRemoteNavigation.md)。
- [弹幕图文协议](DanmakuMixedContentProtocol.md)、[弹幕连接恢复](DanmakuConnectionRecovery.md)、[弹幕引擎与后续](DanmakuRenderingRoadmap.md)。
- [结构化付费留言方案](StructuredPaidMessages.md)：提案，尚未实施；替代旧路线图的付费留言字段和实施清单。
- [后台前台冻结调查](BackgroundForegroundFreezeBug2.md)：仍需当前依赖和真机采证，旧内核结论已标明适用版本。
- [iOS DLNA 设计与真机矩阵](iOSDLNACastingResearch.md)。

## 收藏 同步与翻译

- [收藏刷新与网络韧性](FavoriteRefreshNetworkResiliencePlan.md)、[tvOS 自动刷新循环](TVFavoriteAutomaticRefreshLoop20260927.md)。
- [同步可靠性](SyncReliabilityRoadmap.md)：真实账号、多设备及通知生命周期仍需验收。
- [标题翻译](RoomTitleTranslation.md)、[弹幕翻译](DanmakuTranslation.md)、[实时语音字幕](LiveSpeechSubtitles.md)。各功能分别记录实际支持范围与设备证据。

## 诊断 设计与发布

- [问题诊断功能与数据契约](SupportDiagnostics.md)。
- [报告界面规格](SupportDiagnosticsDesign.md)、[录制交互规格](SupportRecordingDesign.md)、[TV 报告与分享规格](SupportTVReportDesign.md)。仍含有效尺寸和未完成验收，不因旧日期删除。
- [图标设计](AppIconBranding.md)。

## 历史记录与维护规则

旧回归、崩溃样本、迁移中间结果和已替代规划移入 [archive](archive/README.md)。归档不代表线上分组已关闭或未验证项已完成；未决风险仍在待办与归档索引中保留入口。

已被明确替代的实施阶段、重复字段方案及旧估时从现行正文删除。协议、仍有效的视觉规范、未完成任务和用户正在修改的文档保留。更新文档时同时维护相对链接；不得用旧行号、机器路径或旧包截图代替当前代码与验收。
