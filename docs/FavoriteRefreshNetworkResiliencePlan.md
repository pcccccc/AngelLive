# 收藏直播状态刷新与外网韧性规划

> 状态：方案草案 · 2026-08-27
>
> 范围：`AngelLiveCore` 收藏直播状态刷新、插件 HTTP 错误分类、请求合并与三端宿主状态消费
>
> 不在本计划范围：CloudKit 成员同步协议、播放链路、音频会话、凭证兼容回退、ShellUI

## 0. 结论先行

收藏页面不能等待最慢平台。刷新开始后，本地收藏快照必须始终可见、可滚动、可点击；已完成的房间状态随到随写；页面级同步动画在短暂的前台预算结束后收束；仍在运行的慢平台继续使用完整请求预算，完成后再增量合并。

外网问题不通过 Google、Apple、Cloudflare 等独立站点预检，也不通过硬编码“海外平台”名单处理。设备路径只能作为“当前已知完全断网”的提示；插件是否可达，以该插件本轮真实请求的结构化结果为准。只有明确、快速的连接失败才能触发本轮插件级降级；纯粹慢或最终超时只影响对应房间，不连带其他插件。

本计划的核心约束：

1. 页面预算与请求预算分离。
2. `fetchLastestLiveInfoFast` 使用收藏专用策略，不再转调普通详情刷新。
3. 刷新结果增量回写，不在整组任务完成后一次性应用。
4. 网络失败、超时、熔断和跳过均保留上次状态，不写成“未开播”。
5. 熔断粒度是插件与刷新代际，不是整页或所谓“所有海外平台”。
6. 每轮刷新都有稳定代际，旧请求不能覆盖新刷新结果。
7. 共享依赖通过显式 single-flight 合并；宿主不根据相似 URL 擅自合并请求。

---

## 1. 问题边界与现状

### 1.1 已确认现象

- 收藏成员在 CloudKit 对账完成后可以正常取得，长时间等待发生在逐房间直播状态刷新阶段。
- 大部分可达平台通常在数秒内完成；不可达或很慢的平台形成长尾。
- 插件 HTTP 默认请求超时为 20 秒，普通详情刷新当前最多执行 3 次尝试，最坏会形成约 60 秒等待。
- 当前 `fetchLastestLiveInfoFast` 直接调用普通 `fetchLastestLiveInfo`，没有收藏场景专用预算和重试分类。
- 当前 `FavoriteStateModel.syncStreamerLiveStates` 为所有收藏创建任务后，等待整个 task group 完成才返回结果。
- 当前 `AppFavoriteModel.refreshStatesAndApply` 只消费最终 `FavoriteSyncResult`，无法在单个房间或单个平台完成时增量应用。
- 当前 `CloudSyncStatus` 同时影响 CloudKit 状态和收藏直播状态刷新动画，状态所有权不够清晰。

### 1.2 不属于本问题的内容

- 音频会话配置错误 `Code=-50`。
- `clearCredential` 缺失后回退到 `clearCookie` 的兼容行为。
- CloudKit 成员合并、默认 Zone 迁移和凭证同步重试。
- 播放器起播、CDN 切换和播放恢复熔断。

这些问题可以独立处理，但不得混入本次收藏刷新改造。

### 1.3 根因

```text
所有房间同时启动
        ↓
每个房间使用普通详情的宽松重试策略
        ↓
某个插件的共享依赖或房间接口不可达
        ↓
20 秒请求 × 多次尝试 × 多个同插件房间
        ↓
task group 等待最慢任务
        ↓
最终结果一次性 apply，页面同步动画持续到长尾结束
```

问题不是“并发不足”，而是页面完成条件、请求策略、错误分类和结果提交方式耦合在一起。

---

## 2. 产品目标与非目标

### 2.1 目标

- 有本地收藏时立即显示，不等待 CloudKit 或直播状态请求。
- 快平台结果在返回后立即可见，不等待慢平台。
- 页面级同步反馈在约 3～6 秒内结束或降为局部反馈。
- 开启 VPN 后需要 8～15 秒才能返回的平台继续运行，不被页面预算取消。
- 不可达插件出现明确快速失败后，本轮不再逐房间重复等待。
- 超时、网络失败和跳过保留旧直播状态与身份字段。
- 两个房间依赖同一 token 时只产生一个共享请求。
- iOS、macOS、tvOS 共用同一套 Core 规则。

### 2.2 非目标

- 不检测 VPN 是否开启，也不读取 `utun` 作为产品状态。
- 不提供一个全局“能否访问外网”的布尔值。
- 不维护“国内/海外插件”硬编码名单。
- 不用单次 ping、DNS 查询或第三方公共网站代替真实插件请求。
- 不把页面 3～6 秒预算变成插件请求超时。
- 不更改普通进房、详情和播放场景的全局 HTTP 默认策略。
- 不在 UI 层通过隐藏动画掩盖仍然存在的整组等待。

---

## 3. 两套预算

### 3.1 页面前台预算

页面预算只决定“全局同步动画和系统下拉刷新何时不再等待”，不取消后台请求。

首期建议值：4 秒，允许通过 Core 配置在 3～6 秒范围内调优。

前台阶段在以下任一条件满足时完成：

1. 本轮所有房间已经完成；或
2. 页面预算到期。

预算到期后：

- `.refreshable` 可以结束系统菊花。
- 全局同步图标结束或切换为轻量的局部待更新状态。
- 未完成请求继续由刷新会话持有。
- 后续结果仍通过事件流合并。

实现不得使用“国内平台已经完成”作为条件，因为当前协议没有网络地域分类，也不应引入硬编码名单。

### 3.2 收藏请求总预算

收藏状态查询使用独立总预算，首期建议 20 秒。该预算覆盖一次房间状态操作的全部尝试，而不是每次尝试各自拥有 20 秒。

规则：

- 第一次请求可以使用剩余总预算。
- 只有明确允许的短重试才能进行第二次尝试。
- 第二次尝试只能使用剩余预算。
- 第一次已经耗尽总预算时，不再自动重试。
- 手动刷新是新的刷新代际，也是新的请求机会。

因此不得再次出现 `20 秒 × 3 次` 或 `20 秒 × 2 次`。

### 3.3 普通详情策略保持独立

`fetchLastestLiveInfoFast` 应改为真正的收藏专用入口，例如接收或内部固定 `FavoriteRefreshRequestPolicy`。普通 `fetchLastestLiveInfo` 保持原有详情语义，避免收藏改造改变进房、详情刷新或其他平台行为。

---

## 4. 网络与插件可达性模型

### 4.1 系统路径只作为提示

使用 `NWPathMonitor` 维护当前路径快照，但不能把它当作每次真实连接之前的权威 reachability 门禁。

- 当前快照明确为 `.unsatisfied`：本轮暂不批量发出请求，保留全部旧状态，并显示“当前无网络”。
- 路径恢复后：允许下一次自动或手动刷新重新发起请求。
- 快照为 `.satisfied`：只代表系统存在可用路径，不代表任一插件、域名或 VPN 分流可用。
- 请求启动后仍以 URLSession 的实际结果为准，避免路径检查与连接之间的竞态。

### 4.2 不做外网总探测

禁止以下做法：

- 请求 Google 成功就认为所有外网平台可用。
- 请求 Apple 或 Cloudflare 成功就认为插件依赖可用。
- 某一个外网插件失败后跳过全部外网插件。
- 根据插件名称或 `LiveType` 推断网络地域。

插件 A 的失败不能证明插件 B 失败，尤其在 VPN 分流、域名规则、DNS 污染或代理例外环境下。

### 4.3 真实请求即探测

插件可达性由本轮真实业务请求自适应建立：

- 有显式共享依赖的插件：共享依赖是本轮的关键请求，例如 token 请求。
- 没有共享依赖的插件：不虚构额外探针，使用每房间真实请求和插件级并发限制。
- 任一成功结果说明该插件本轮至少存在可用路径。
- 纯慢请求不产生“不可达”结论。

不能普遍要求“等待第一个房间完成后再启动其他房间”。如果第一个房间很慢，这会把插件内并发重新变成串行。无共享依赖的插件首期建议并发上限为 3，并通过调度队列在明确熔断后停止尚未启动的房间。

---

## 5. 结构化错误分类

### 5.1 分类目标

需要从 Host HTTP、URLSession、插件标准错误一路保留结构化错误，最终得到收藏刷新可判断的失败类型。不得只通过 `localizedDescription` 或字符串是否包含 `network`、`timeout` 推断熔断。

建议 Core 类型：

```swift
enum FavoriteRefreshFailureKind: Sendable, Equatable {
    case deviceOffline
    case fastUnreachable(FastUnreachableReason)
    case timeout
    case authenticationRequired
    case notFound
    case rateLimited
    case blocked
    case upstream
    case invalidResponse
    case cancelled
    case unknown
}
```

错误对象应携带：

- 标准化类型。
- 底层 error domain/code，供诊断和单测使用。
- 是否收到 HTTP 响应。
- 尝试次数与总耗时。
- `pluginId` 和刷新代际。

不得记录 Cookie、Token、Authorization、完整敏感 URL 查询参数或用户私密数据。

### 5.2 可以进入快速不可达判断的错误

首期候选：

- 明确无网络或无路由。
- DNS 无法找到主机 / DNS 查询明确失败。
- 无法连接目标主机 / 连接被拒绝。
- 在尚未收到 HTTP 响应前发生的底层连接失败。

`connection reset`、`networkConnectionLost` 等可能来自临时抖动、服务端主动断开或风控，不能单次一票熔断，建议同插件本轮连续出现 2 次后再打开网络熔断。

### 5.3 不触发网络熔断的错误

- 超时。
- HTTP 4xx / 5xx。
- `AUTH_REQUIRED`、`NOT_FOUND`、`RATE_LIMITED`、`BLOCKED`。
- 解析失败、字段缺失和无效响应。
- TLS 证书或协议错误。
- 用户或刷新代际取消。

这些错误仍可决定单房间是否重试；若未来需要把某种业务错误视为插件共享失败，必须由插件协议显式声明，不能冒充网络不可达。

---

## 6. 重试策略

| 错误类型 | 自动重试 | 熔断 | 状态写入 |
|---|---:|---:|---|
| 取消 | 0 | 否 | 不写入 |
| 设备无网络 | 0 | 全局本轮暂缓 | 保留旧状态 |
| 明确快速连接失败 | 0 | 插件本轮计数 | 保留旧状态 |
| 完整超时 | 0 | 否 | 保留旧状态 |
| `AUTH_REQUIRED` / `BLOCKED` | 0 | 否 | 保留旧状态并暴露原因 |
| `RATE_LIMITED` | 0 | 否 | 保留旧状态 |
| 明确解析/参数/业务失败 | 0 | 否 | 保留旧状态 |
| 冷启动 `NOT_FOUND` | 最多短重试 1 次 | 否 | 最终失败时保留旧状态 |

`NOT_FOUND` 首期兼容规则：

- 同插件本轮尚未有成功结果时，允许等待 300～500 ms 后短重试一次。
- 同插件本轮已经成功过时，默认不重试。
- 第二次尝试必须受同一个请求总预算约束。

这只是兼容旧插件冷启动假阴性的过渡策略。长期方案是让插件标准错误携带显式 `retryable` 和 `retryReason`，由插件声明该次 `NOT_FOUND` 是否可能来自运行时预热，Core 不永久内置某个平台的特殊规则。

---

## 7. 插件级本轮熔断

### 7.1 状态机

每个刷新代际为每个 `pluginId` 创建独立状态：

```text
closed
  ├─ 任一成功 ─────────────→ reachable
  ├─ 1 次强确定快速失败 ───→ open
  ├─ 1 次 reset/lost ──────→ suspect
  └─ timeout/业务失败 ─────→ closed

suspect
  ├─ 任一成功 ─────────────→ reachable
  ├─ 再次快速连接失败 ─────→ open
  └─ timeout/业务失败 ─────→ closed 或保持 suspect

open
  └─ 本轮不再调度尚未启动的房间
```

### 7.2 作用范围

- 只影响同一 `pluginId`、同一刷新代际。
- 不影响其他插件。
- 不落盘为长期“不可用平台”。
- 已经成功或正在返回数据的房间结果仍可合并。
- 被跳过房间保留旧状态，记录为 `skippedByCircuit`，不记录为下播。

### 7.3 超时不打开插件熔断

超时只说明某次请求在预算内没有完成，不能证明插件整体不可达。多个房间分别超时可以用于诊断和降低后续自动刷新频率，但首期不得因此跳过其他房间或其他插件。

---

## 8. 共享依赖与 single-flight

### 8.1 目标

同一插件的多个房间依赖相同 token、签名预热或 bootstrap 请求时，只允许一个请求在飞。其他调用者等待同一结果，而不是各自重复请求。

### 8.2 显式契约

宿主不能看到两个 URL 相同就自动合并，因为请求可能拥有不同方法、body、Cookie、账号或授权头。建议为 Host HTTP 增加显式、可选的请求字段：

```json
{
  "singleFlightKey": "app-token",
  "successCacheTTLms": 60000,
  "failureCacheTTLms": 30000
}
```

首期限制：

- 仅允许幂等 GET / HEAD 使用宿主缓存。
- key 的实际作用域包含 `pluginId + sessionContextRevision + method + singleFlightKey`。
- 同一 key 的在途请求返回同一个 `Task` 结果。
- 成功和失败缓存分别设置上限，宿主可以收紧插件请求的 TTL。
- 日志只记录 single-flight 命中，不记录 token 或敏感请求头。

建议 Core 组件：`PluginHTTPFlightCoordinator` actor。

### 8.3 失效

以下情况使失败缓存和本轮熔断立即失效：

- 用户手动下拉刷新或点局部重试。
- 观察到 Wi-Fi / 蜂窝等系统路径指纹变化。
- 插件升级、重载、禁用后重新启用。
- 插件登录态或 session revision 变化。
- App 回到前台且失败缓存已经过期。

系统不保证暴露所有 VPN 分流变化，因此不能承诺百分之百识别 VPN 开关。手动刷新必须始终绕过失败缓存；短 TTL 负责限制未被系统观察到的残留判断。

---

## 9. 刷新会话与增量事件

### 9.1 新的所有权

慢请求必须在页面前台预算结束后继续存在，因此任务不能只属于 `.refreshable` 调用栈。建议由 `FavoriteRefreshSession` actor 持有当前刷新任务、调度队列、插件状态和刷新代际。

建议职责：

- 创建 `generationID`。
- 读取系统路径快照。
- 按插件分组并限制并发。
- 执行收藏专用请求策略。
- 维护插件熔断与成功状态。
- 通过 `AsyncStream<FavoriteRefreshEvent>` 输出增量事件。
- 在取消、手动刷新和路径变化时关闭旧代际写回资格。

### 9.2 事件模型

```swift
enum FavoriteRefreshEvent: Sendable {
    case started(generationID: UUID, total: Int)
    case roomUpdated(generationID: UUID, oldKey: String, room: LiveModel)
    case roomStale(generationID: UUID, key: String, reason: FavoriteRefreshFailureKind)
    case pluginProgress(generationID: UUID, pluginId: String, completed: Int, total: Int)
    case pluginUnavailable(generationID: UUID, pluginId: String, skipped: Int)
    case foregroundFinished(generationID: UUID, pendingPlugins: Set<String>)
    case completed(generationID: UUID, summary: FavoriteRefreshSummary)
}
```

`foregroundFinished` 只结束页面全局反馈，不等于整个刷新会话完成。

### 9.3 刷新代际

- 每次启动、下拉刷新或明确重试产生新的 `generationID`。
- `AppFavoriteModel` 只接受当前代际事件。
- 旧代际晚到结果不得覆盖新状态。
- 用户手动刷新时，旧会话取消或失去写回资格。
- `CancellationError` 不计入失败、重试或熔断。
- single-flight 可以安全共享仍在运行的幂等请求，但旧代际缓存结果必须重新通过当前代际校验后才能写入。

### 9.4 Swift 6 任务所有权

页面预算计时不能复用“请求超时竞速”实现。请求超时需要取消输掉的任务；页面预算到期则只产生 `foregroundFinished` 事件，绝不能取消请求任务。

建议 `FavoriteRefreshSession.start` 返回一个刷新句柄：

```swift
struct FavoriteRefreshHandle: Sendable {
    let generationID: UUID
    let events: AsyncStream<FavoriteRefreshEvent>
    let foregroundCompletion: Task<Void, Never>
}
```

任务所有权规则：

- `AppFavoriteModel` 在 `@MainActor` 上只创建一个事件消费任务；`AsyncStream` 不允许页面和模型各自消费一次。
- `.refreshable` 等待 `foregroundCompletion.value`，事件消费任务继续存活并接收后台结果。
- 新代际启动时取消旧事件消费任务和旧刷新会话；模型释放时取消存储任务。
- 存储的长任务使用弱引用或显式结束路径，避免 `owner → Task → owner` 的长期引用环。
- 刷新会话内部继续使用结构化 task group，但按并发上限逐步加入任务，不一次性创建所有房间任务。
- 不使用 `Task.detached`、`DispatchSemaphore`、`@unchecked Sendable` 或 `nonisolated(unsafe)` 规避隔离检查。
- `AsyncStream` 必须在完成、取消和异常路径调用 `finish()`，并通过 `onTermination` 取消对应会话资源。
- 事件数量受本轮收藏数约束；若以后允许无界事件源，必须增加明确缓冲策略，不能依赖默认无界缓冲。

所有跨 actor 类型，包括事件、策略、摘要、结构化错误和 HTTP 响应快照，都必须真正符合 `Sendable`。不要跨 actor 传递可变 `NSError`、URLSession delegate 或 JavaScriptCore 对象；底层错误先提取为不可变 domain/code/分类快照。actor 方法每次 `await` 后都要重新核对当前代际和熔断状态，避免 actor reentrancy 让旧状态继续调度新任务。

---

## 10. 增量回写与状态所有权

### 10.1 拆分 CloudKit 和直播刷新状态

建议将现有单一 `syncStatus` 拆为至少三个维度：

```swift
cloudMembershipPhase       // CloudKit 成员同步
favoriteForegroundPhase   // 页面预算内的全局反馈
pluginRefreshPhases        // 各 pluginId 的 pending / reachable / unavailable / completed
```

`isCloudSyncing` 只表达 CloudKit 成员同步，不再被慢平台请求长期占用。收藏直播状态可以提供独立的 `isFavoriteStatusRefreshing` 和 `pendingPluginIds`。

### 10.2 房间补丁

`AppFavoriteModel` 增加按稳定身份应用单条补丁的能力，不再要求每次创建完整最终数组：

- 按现有 `favoriteUniqueKey` 找到旧房间。
- 成功结果只更新确认的新字段。
- 网络失败、超时、熔断和跳过不覆盖 `liveState`、`roomId`、`userId` 等旧字段。
- 身份变化只有在成功且满足现有“非降级变化”规则时才产出 CloudKit 回写候选。
- 分组和排序使用稳定 identity；可以批量合并短时间内到达的事件，避免每个房间都触发整页重建。

建议对 100～250 ms 内到达的补丁做主线程批处理，再重建受影响分组。禁止通过随机 section ID、清空列表再插入或全局 `listVersion` 强制重载来实现更新。

`AppFavoriteModel` 的可观察 UI 状态必须由主 actor 所有。实施时优先把类型整体隔离为 `@MainActor`；如果三端现有调用关系暂时不允许整体标注，则所有读写可观察状态的入口都必须显式隔离到 `@MainActor`，不能由刷新 actor 直接修改。

### 10.3 旧状态与新鲜度分离

不要把“状态未更新”塞进 `LiveState.offline`。建议以 sidecar 元数据表达新鲜度：

```swift
enum FavoriteStatusFreshness: Sendable, Equatable {
    case fresh(updatedAt: Date)
    case refreshing
    case stale(reason: FavoriteRefreshFailureKind, lastUpdatedAt: Date?)
}
```

`LiveModel.liveState` 继续表达上一次确认的直播状态；新鲜度表达本轮是否成功更新。

---

## 11. 三端 UI 消费规则

Core 输出统一状态，平台宿主按各自交互习惯显示。首期不修改 ShellUI。

共同规则：

- 本地快照出现后页面立即可交互。
- 全局刷新反馈只持续到 `foregroundFinished`。
- 后台仍有慢插件时，只在对应平台分组、标题或房间区域显示局部“更新中”。
- 快速失败触发插件降级时显示“该平台当前不可达，已保留上次状态”，提供重试入口。
- 单房间超时只显示“状态未更新”，不提示整个插件或所有外网不可用。
- 自动刷新失败不频繁弹 Toast；手动刷新可以提供紧凑结果反馈。
- UI 文案使用插件显示名，但内部状态键使用稳定 `pluginId`。

iOS 首页摘要遵守 `PluginDrivenHomePagePlan.md`：刷新过程中不因单卡状态变化重置滚动位置；完整收藏页可以按现有产品规则重算分组，但 identity 必须稳定。

---

## 12. 建议代码分层

### 12.1 `AngelLiveCore`

建议新增或调整：

```text
Models/
  AppFavoriteModel.swift
  FavoriteStateModel.swift
  FavoriteRefreshEvent.swift
  FavoriteRefreshPolicy.swift
  FavoriteRefreshSession.swift

Services/
  ApiManager.swift
  NetworkPathObserver.swift

LiveParse/Plugin/
  JSRuntime.swift
  LiveParsePluginError.swift
  PluginHTTPFlightCoordinator.swift
```

职责：

- `FavoriteRefreshPolicy`：页面预算、请求总预算、并发和重试决策。
- `FavoriteRefreshSession`：代际、任务生命周期、插件调度、熔断和事件流。
- `ApiManager.fetchLastestLiveInfoFast`：收藏专用请求入口。
- `JSRuntime` / Host HTTP：保留结构化底层错误，支持显式 single-flight。
- `AppFavoriteModel`：主 actor 上消费事件、增量合并、持久化和身份回写。

### 12.2 平台宿主

- iOS、macOS、tvOS 只消费 Core 公开状态并实现各自局部反馈。
- 不在宿主复制超时、错误分类或插件名单。
- 未明确点名时不修改 ShellUI。

---

## 13. 实施阶段

### Phase 0：建立可测试边界

- 为直播状态请求抽取可注入协议，例如 `FavoriteLiveInfoFetching`。
- 为路径状态和时间抽取可测试依赖。
- 记录当前基线：首个结果时间、页面反馈时间、完整刷新时间、尝试次数。
- 把跨 actor 的事件、错误和响应快照设计为 `Sendable` 值类型，不新增 `@unchecked Sendable`。

完成标准：测试可以稳定模拟快成功、慢成功、快速失败、超时和取消，不依赖真实插件网络。

### Phase 1：收藏专用请求策略

- 让 `fetchLastestLiveInfoFast` 不再转调普通详情刷新。
- 引入 20 秒总预算和按错误类型重试。
- 保留结构化底层网络错误。
- 失败时返回旧状态语义，不再调用通用失败回填覆盖直播状态。

完成标准：单房间完整超时不再触发第二个 20 秒请求；业务错误不被连续请求 3 次。

### Phase 2：刷新会话与增量回写

- 引入 `generationID` 和 `FavoriteRefreshEvent`。
- 用刷新会话取代“task group 全部结束后返回最终数组”的页面完成语义。
- `AppFavoriteModel` 增量合并成功结果。
- 页面预算到期后结束全局反馈，后台任务继续。
- 拆分 CloudKit 成员同步与直播状态刷新状态。

完成标准：一个 15 秒慢请求存在时，2 秒完成的房间在 2 秒附近更新；页面全局反馈不超过配置预算。

### Phase 3：插件调度与本轮熔断

- 按 `pluginId` 分组和限制并发。
- 实现结构化快速失败计数和本轮熔断。
- 超时不打开插件网络熔断。
- 被跳过房间保留旧状态和新鲜度原因。

完成标准：同插件首批请求明确快速失败后，不再为其所有剩余房间逐条等待；其他插件不受影响。

### Phase 4：共享请求 single-flight

- 为 Host HTTP 增加显式 single-flight 契约。
- 实现成功/失败短缓存和失效规则。
- 迁移需要共享 token 的插件调用方式或测试夹具。
- 增加并发、取消、失败缓存和 session revision 测试。

完成标准：两个房间同时请求同一共享依赖时，网络层只执行一次真实请求。

### Phase 5：三端状态反馈与真机验证

- iOS、macOS、tvOS 接入 Core 的前台阶段和插件局部状态。
- 验证 Wi-Fi、蜂窝、VPN 开启/关闭、弱网和无网络。
- 检查列表 identity、滚动位置、焦点和排序稳定性。
- 根据真机日志调整页面预算和插件并发上限。

完成标准：达到第 15 节成功标准，且无 CloudKit、身份回写和三端入口回归。

---

## 14. 测试与观测

### 14.1 Core 单元测试

至少覆盖：

1. 本地快照立即可用，不等待状态刷新。
2. 快房间先返回并立即产生 `roomUpdated`。
3. 页面预算到期产生 `foregroundFinished`，慢任务未被取消。
4. 慢任务在 10～20 秒内成功后补丁合并。
5. 完整超时不自动开始第二个完整预算。
6. 超时不触发插件熔断。
7. DNS/拒绝连接等快速失败触发插件本轮降级。
8. 单次 reset 进入 suspect，连续快速失败才打开熔断。
9. 插件 A 熔断不影响插件 B。
10. 无网络时不启动批量请求，全部保留旧状态。
11. 网络失败和熔断不把直播状态改成未开播。
12. 冷启动 `NOT_FOUND` 只短重试一次，且受总预算限制。
13. 已有同插件成功时后续 `NOT_FOUND` 默认不重试。
14. `AUTH_REQUIRED`、业务失败和取消不触发网络熔断。
15. 两个房间共享一次 single-flight 请求。
16. 手动刷新清除失败短缓存并创建新代际。
17. 旧代际晚到结果不能覆盖新代际。
18. 失败项不产生身份字段降级和 CloudKit 身份回写。
19. 100～200 条收藏时并发上限生效，不一次性创建无界网络压力。
20. 页面预算到期只结束前台反馈，不向慢请求传播取消。
21. `AsyncStream` 消费者终止时会结束流并清理会话任务。
22. actor 在网络 `await` 后重新检查代际，不能继续调度已经失效的刷新。

### 14.2 集成与设备场景

| 场景 | 期望 |
|---|---|
| 正常 Wi-Fi，所有插件可达 | 结果随到随写，刷新正常完成 |
| 无 VPN，某插件立即连接失败 | 该插件快速降级，其他插件继续 |
| 无 VPN，某插件黑洞式超时 | 页面预算结束；该房间最终 stale；不熔断其他插件 |
| VPN 已开启，目标插件 8～15 秒成功 | 页面先恢复，随后补上新状态 |
| VPN 分流只覆盖一个插件 | 不对其他插件做推断 |
| 刷新中切换 Wi-Fi / 蜂窝 | 旧代际不覆盖新结果，失败缓存失效 |
| 刷新中开关 VPN | 若系统观察到路径变化则失效；手动刷新始终可重试 |
| App 进入后台再回来 | 不把暂停当失败；按代际和 TTL 决定恢复或刷新 |

设备验收必须在最后一次代码修改后重新 build、install、launch；模拟器只能覆盖确定性 UI 和基础网络场景，VPN、蜂窝和 IPv6-only 结论以真机为准。

### 14.3 诊断指标

每轮记录：

- `generationID`。
- 收藏总数、插件数。
- `timeToFirstPatch`。
- `foregroundDuration` 与预算到期时 pending 数量。
- `fullDuration`。
- 每插件成功、失败、超时、熔断跳过数量。
- 每类错误和实际尝试次数。
- single-flight 命中与真实请求次数。
- 被旧代际丢弃的结果数量。

日志不得包含真实凭证、Cookie、Token、Authorization 或完整敏感查询参数。

---

## 15. 成功标准

- 有本地收藏时，页面立即可操作，不出现由直播状态刷新造成的全屏等待。
- 大部分平台在几秒内完成时，其最新状态立即出现，不等待最慢平台。
- 页面级同步动画在 3～6 秒内结束或降为局部状态。
- 无 VPN且某插件明确快速不可达时，本轮剩余房间快速跳过，不再出现约 60 秒的整页等待。
- 有 VPN且插件只是慢时，请求继续运行，并可在 10～20 秒内补上状态。
- 慢或超时不被误判为未开播，也不被升级为“所有外网不可用”。
- 业务错误不再无差别执行 3 次完整请求。
- 两个房间依赖同一 token 时只产生一次共享请求。
- 手动刷新、路径变化和新代际不会被旧失败缓存或旧请求结果污染。
- iOS、macOS、tvOS 使用同一套 Core 规则；未指定时 ShellUI 无改动。

---

## 16. 明确禁止

- 用公共网站预检插件可达性。
- 用 `NWPathMonitor.satisfied` 证明某个平台可达。
- 检测 `utun` 并把 VPN 开关作为业务状态。
- 硬编码国内/海外插件名单。
- 页面预算到期时取消全部慢请求。
- 超时后重新执行一个完整 20 秒请求。
- 单个插件失败后跳过其他插件。
- 将网络失败、超时、熔断或跳过写成下播。
- 使用字符串模糊匹配作为最终熔断依据。
- 用 UI 隐藏、全局重载或随机 identity 掩盖状态机问题。
- 把本计划的收藏策略扩散为全局 HTTP 默认策略。

最终验收句：

> **页面不等最慢平台；慢平台继续跑；只有结构化的快速连接失败才能让同一插件在本轮停止继续调度，所有降级都保留上次可信状态。**
