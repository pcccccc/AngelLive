# 播放链路韧性现状与待验收项

文档整理：2026-10-16。恢复反馈、CDN 偏好与 Playback Timeline 已实现；2026-10-04 的构建和交互范围见[历史验收记录](archive/TODOProgress20261004.md)。旧方案与估时已移至[历史规划](archive/PlaybackResilienceRoadmap20260731.md)，不再作为待实施清单。

## 当前实现

- `PlaybackRecoveryCoordinator` 与 `PlaybackTuning` 管理既有恢复规则；`PlaybackDiagnosticsSession` 观察恢复过程，不另建预算或第二套计时器。
- 取参、连接、缓冲文案来自真实调用和采样；恢复动作包含序号与上限，三端顶部提示 2 秒。
- 起播完成须观察到在播且 playhead 推进。`readyToPlay` 不代表已显示首帧；`startupCompleted` 受既有 1 Hz 采样限制，不是渲染器首帧指标。
- 每个房间 ViewModel 拥有独立会话。自动 token 刷新保留会话与恢复预算，用户换房创建新会话。暂停、后台、离开和手动切换不把中断计为失败。
- `PlaybackEventLog` 默认最多保存 500 条结构化内存事件，只在开发者模式启用时记录；不保存原始 URL、房间身份、凭据或原始错误正文。iOS/macOS 支持主动 JSON 导出，tvOS 提供只读时间轴。
- iOS 时间轴在辅助功能字号下使用自然高度的事件概览，控件、图表和事件共用滚动容器；macOS/tvOS 保留各自布局。
- `CDNPreferenceStore` 按插件和稳定 CDN 标识的摘要学习成功率、采样起播耗时，7 天失效。当前候选全部至少有 3 个样本才选择初始 index；不重排插件数组、不覆盖手动选择、不改变重新取参后的索引语义。
- 线路评分为 `0.7 × successRate + 0.3 × 500 / max(meanStartupMilliseconds, 500)`；全失败线路速度项为 0，并列保持原顺序，无稳定标识不学习。
- Stall 采用固定 12 秒阈值，未采用早期指数退避数组。阈值合理性仍需真实数据复核。

## 剩余工作

- [ ] 真实弱网及长时播放下验证恢复与线路学习效果。
- [ ] 完成三端交互和无障碍矩阵；不能沿用历史包截图作为当前包证据。
- [ ] 测量精确渲染首帧、watchdog 次数、failover 成功率、首选线路命中率和 30 秒未起播离开率；现有采样不能直接替代这些指标。
- [ ] 用实际时间轴数据评估 12 秒 stall 阈值。
- [ ] 修复 iOS/tvOS 错误状态查询的迟到结果归属问题，见[三端架构审查 A04](CrossPlatformArchitectureAudit20261016.md#a04-播放错误检查存在跨端行为分歧)。

## 保留的决策边界

- 不在失败前静默降低清晰度；清晰度语义和用户选择必须保留。
- 不在平台能力模型中加入具体来源的内核偏好白名单。
- 不为去重整体合并三端播放器 ViewModel；优先共享明确的规则和会话契约。
- 不引入额外 HEAD/下载探针或 playArgs 预热；没有实际收益与有效期契约时不增加请求。
- 不采用旧方案中的 URL 日志、以 readyToPlay 充当首帧、重排 CDN 数组及旧评分公式。
- 本文不覆盖播放器 UI 重设计、音频独立模式、全屏/PiP/AirPlay 或弹幕传输稳定性。

## 验证入口

共享实现位于 `Shared/AngelLiveCore/Sources/AngelLiveCore/Playback/`，引擎适配位于 `Shared/AngelLiveDependencies/Sources/PlaybackRecoveryAdapter.swift`。测试以对应恢复、诊断、状态机与线路偏好测试为入口；公共行为改变后构建受影响宿主。真实网络、设备与视觉结果单独记录。
