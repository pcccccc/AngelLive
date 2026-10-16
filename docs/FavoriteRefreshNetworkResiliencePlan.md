# 收藏刷新与网络韧性现状

维护日期：2026-10-16。本次依据代码整理，不代表重新完成构建、真实网络或设备验收。旧方案、34 项测试及分批设备结果见[历史记录](archive/FavoriteRefreshNetworkResiliencePlan20260913.md)；自动刷新循环另见[专项记录](TVFavoriteAutomaticRefreshLoop20260927.md)。

## 当前共享边界

三端 FullUI 通过 `AppFavoriteModel` 消费共享收藏刷新状态；`FavoriteRefreshSession` actor 持有一轮刷新、任务和代际。网络状态刷新与 CloudKit 成员同步分开，后者见[同步可靠性](SyncReliabilityRoadmap.md)。ShellUI 不在本轮整理对应的实现范围。

| 代码入口（相对仓库根目录） | 当前职责 |
| --- | --- |
| `Shared/AngelLiveCore/Sources/AngelLiveCore/Models/FavoriteRefreshPolicy.swift` | 请求预算、结构化失败、可注入请求与计时边界 |
| `Shared/AngelLiveCore/Sources/AngelLiveCore/Models/FavoriteRefreshSession.swift` | 调度、插件粒度降级、前台完成与后台完成、代际取消 |
| `Shared/AngelLiveCore/Sources/AngelLiveCore/Models/AppFavoriteModel.swift` | 自动/手动入口合并、增量回写、页面观察状态 |
| `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Plugin/PluginHTTPFlightCoordinator.swift` | 显式 single-flight 请求合并与有界缓存 |

## 已实现的行为与约束

- 本地收藏先显示；已完成状态增量回写，前台反馈结束不取消仍有预算的后台请求。
- 默认前台预算 4 秒、单房间总预算 20 秒；兼容的 not-found 重试退避 400 毫秒，总预算覆盖首次请求、退避和可选重试。全局并发上限 20，单插件上限 5。
- 自动入口在首次等待前登记共享任务；相同收藏成员及插件目录在刷新中、后台长尾期间及完成后 60 秒内复用有效结果。成员或目录变化会使其失效。
- 手动刷新不受自动有效期限制；并发手动入口合并，创建阶段结束后可替换旧轮，不等待旧轮网络全部返回。
- 旧代际的完成与结果不能覆盖新轮；异步写入后仍须核对归属。身份与数据持久化问题继续按[三端架构审查](CrossPlatformArchitectureAudit20261016.md)跟踪，不据此宣称所有收藏联动已经正确。
- 超时、网络失败及跳过保留已有直播状态，不伪造“未开播”。明确的未开播业务结果按成功刷新处理。
- 设备网络路径只提供断网提示；纯超时不等于插件不可达。插件降级依据本轮真实请求的结构化失败，不使用外部公共站点预检或具体内容平台名单。
- 共享请求必须显式声明合并键；隔离键包含插件、session revision、方法和 single-flight key，不根据 URL 相似度擅自合并。

## 宿主反馈与验证边界

iOS 收藏模型由 App 层共享；macOS 页面自动加载/恢复与显式手动刷新分开；tvOS 遥控器刷新入口由根视图处理。tvOS FullUI 使用顶部圆环，前台结束但请求未完成时显示部分更新提示；结果反馈与该页观察到的刷新关联。

这些是代码与历史变更记录中的行为，不能替代当前工作树的新包验收。历史记录中的 iOS 冷启动、页面往返和手动刷新证据属于当时版本；macOS 交互与真机冷启动未完成验证。早期 tvOS 安装阻塞后来已有成功安装记录，但无收藏基线仍不足以验证列表交互。

仍需完成：

- 使用最新包验证三端冷启动、页面往返、手动刷新与连续按键，只产生预期轮次。
- 在有收藏的 tvOS 上验证圆环、慢请求/结果文案、焦点、深浅色及减少动态效果。
- 真实网络复测 20/5 并发配置、部分插件慢响应与超时；旧 147 房间单次对比未显示明确耗时收益，不能推断长期性能。
- 覆盖离线/恢复、取消、成员与插件目录变化、手动替换和迟到结果；同时核对持久化及 Top Shelf 更新。
- 复核相关 Core 测试并按改动构建受影响宿主；历史测试数量不作为本次验证结果。

本文件不再保留虚拟类型签名、建议文件树和已完成实施阶段；需要追溯设计过程时读取历史记录。
