# 收藏身份元数据回写 · 本地状态缓存

> 状态:设计 v2 · 2026-06-09
> 范围:收藏域 · iOS / macOS(TV 收藏后续另议)
> 关联:本文是 `docs/SyncResilienceAndErrorModel.md` Phase③(CKSyncEngine 收藏同步)的延伸专题
> 一句话:CloudKit 同步「主播是谁 + 当前入口在哪」;本地缓存「上次本机看到他是什么状态」。`roomId/userId` 可回写,`liveState` 不进云同步。

---

## 0. 背景与目标

收藏列表刷新后,每个主播会得到最新的 `liveState` / `roomId` / `userId`。其中一小部分平台的 `roomId` 会随场次变化,如果完全不回写,其它设备可能长期拿着旧播放入口;如果无脑回写整个 `LiveModel`,又会把 `liveState` 也带上云,造成多设备状态互盖。

本文把数据边界收敛为三层:

| 层 | 存储位置 | 同步策略 | 例子 |
|---|---|---|---|
| 收藏成员关系 | CloudKit + 本地缓存 | 同步 | 是否收藏、平台、稳定主键 |
| 身份元数据 | CloudKit + 本地缓存 | 低频同步 | `roomId`、`userId`、昵称、头像、标题 |
| 直播状态缓存 | 仅本地 | 不同步 | `liveState`、状态刷新时间、失败原因 |

最终目标:

- 启动时先读本地缓存秒显收藏列表和上次直播状态。
- 后台拉 CloudKit 只合并收藏成员与身份元数据。
- 后台刷新直播状态后只更新本地缓存。
- 若刷新发现 `roomId/userId` 发生可靠变化,只把身份元数据回写 CloudKit。

---

## 1. 当前事实(已核对代码)

- 刷新路径:`AppFavoriteModel.syncWithActor()` / `pullToRefresh()` -> `refreshStatesAndApply(members:)`。
- `refreshStatesAndApply`(`AppFavoriteModel.swift:121`)当前只做刷新、更新 UI、本地落盘(`persistLocal()`),不回写 CloudKit。
- 最新数据来源:`FavoriteStateModel.syncStreamerLiveStates` 调 `ApiManager.fetchLastestLiveInfoFast`,成功返回 `dataReq`(含 `liveState` / `roomId` / `userId`)。
- preserve 平台刷新时只更新 `liveState`,不替换 `roomId/userId`。
- CloudKit 记录当前已写 `room_id` / `user_id` / `live_state`(`FavoriteSyncEngine.makeRecord`)。
- recordName = `AppFavoriteModel.favoriteUniqueKey(for:)`,当前无条件 `roomId` 优先,userId 兜底。
- `PlatformHostBehavior.favoriteIdentityKey(for:)` 已支持 manifest 声明主身份是 `userId` 还是 `roomId`,但 `favoriteUniqueKey` 尚未使用它。

---

## 2. 核心约束

### 2.1 recordName 必须稳定

对 `roomId` 会变的平台,CloudKit `recordName` 不能使用 `roomId`。正确形态是:

```text
recordName = liveType_u_userId
room_id = 当前最新 roomId
user_id = 稳定 userId
```

也就是说,`roomId` 对这些平台是**可变字段**,不是主键。只有这样才能做到「同一主播始终一条 CloudKit 记录」。

### 2.2 `liveState` 必须是本地状态

`liveState` 是高频、时效性强、跨设备容易乱序的数据。A 设备刚刷到「直播中」,B 设备稍后上传旧的「下播」,没有时间戳与合并规则时会直接互盖。

因此 Phase 1 明确:

- `liveState` 允许本地缓存,用于下次启动秒显。
- `liveState` 不作为 CloudKit 身份回写内容。
- CloudKit 拉取远端记录时,不得用远端 `live_state` 覆盖本地缓存状态。

### 2.3 有稳定身份才允许同步变化的 `roomId`

`roomId` 会变的平台,必须至少满足一个条件:

| 条件 | 处理 |
|---|---|
| 有稳定 `userId` / 主播主页 ID / slug | `favoriteIdentityKey = userId`,允许同步当前 `roomId` |
| 无稳定身份,但刷新应保留原房间信息 | `preserveFavoriteRoomInfoOnRefresh = true`,不回写变化的 `roomId` |
| 无稳定身份,仍想更新 `roomId` | 不建议自动回写;只能在能可靠证明同一主播时 delete old + save new |

CloudKit 不能解决“无法识别同一主播”的问题。没有稳定身份时,同步变化的 `roomId` 等价于创建新收藏。

---

## 3. 风险分析

| # | 风险 | 触发条件 | 后果 | 对策 |
|---|---|---|---|---|
| R1 | 云端重复记录 | `roomId` 变且 recordName 跟着变 | 同一主播多条记录 | `favoriteUniqueKey` 尊重 `favoriteIdentityKey` |
| R2 | `liveState` 互盖 | 身份回写复用全量 `enqueueSave` | 远端旧状态覆盖本地新状态 | 身份写回不能写 `live_state`;拉取时保留本地状态 |
| R3 | `serverRecordChanged` | 更新同 recordName | 上传失败仅 log | 降低写频;后续补冲突合并/重试 |
| R4 | 本地真相未落盘 | `persistLocal()` fire-and-forget 后立即 enqueue | `recordProvider` 找不到新 key | 身份回写前等待本地保存完成 |
| R5 | manifest 声明错误 | 非 preserve + 默认 roomId + 实际 roomId 会变 | 每场 churn 或重复 | 发布前做平台声明审计 |

---

## 4. 决策

Phase 1 做:

- 让 `favoriteUniqueKey` 按平台身份选主键。
- 允许 `roomId/userId` 作为身份元数据回写 CloudKit。
- 对 `roomId` 会变且 `userId` 稳定的平台,用稳定 `userId` 做 recordName,把最新 `roomId` 当字段同步。
- 启动/刷新展示优先使用本地缓存中的上次 `liveState`。
- CloudKit 拉取只更新成员关系与身份元数据,不覆盖本地 `liveState`。

Phase 1 不做:

- 不同步 `liveState`。
- 不对所有刷新结果无脑 `enqueueSave`。
- 不为没有稳定身份的平台自动同步变化后的 `roomId`。
- 不把 SwiftData 开 CloudKit 自动同步,避免与 CKSyncEngine 双同步。

---

## 5. 推荐数据模型

### 5.1 CloudKit 记录

CloudKit 继续使用 `favorite_streamers`,但语义调整为成员关系 + 身份元数据:

| 字段 | 是否建议保留/新增 | 云端语义 |
|---|---|---|
| `recordName` | 保留 | 稳定收藏主键 |
| `live_type` | 保留 | 平台 |
| `user_id` | 保留 | 稳定主播身份,可补全 |
| `room_id` | 保留 | 当前可用播放入口,允许变化 |
| `user_name` | 保留 | 昵称快照 |
| `room_title` | 保留 | 标题快照 |
| `room_cover` | 保留 | 封面快照 |
| `user_head_img` | 保留 | 头像快照 |
| `identity_updated_at` | 建议新增 | 身份元数据更新时间 |
| `live_state` | 历史字段 | 不再用于覆盖本地状态 |

> 注意:当前 `makeRecord` 会写 `live_state`。实施时要么停止写该字段,要么保证身份写回路径不改它,同时 `applyFetched` 不用它覆盖本地状态。

### 5.2 本地缓存

当前 JSON `FavoriteLocalStore` 已能保存 `[LiveModel]` 并支持启动秒显。若改为 SwiftData,建议模型上显式拆出状态字段:

```swift
@Model
final class FavoriteRoomCache {
    @Attribute(.unique) var favoriteKey: String = ""

    var liveTypeRaw: String = ""
    var roomId: String = ""
    var userId: String = ""
    var userName: String = ""
    var roomTitle: String = ""
    var roomCover: String = ""
    var userHeadImage: String = ""

    // 本地状态缓存,不参与 CloudKit 同步
    var cachedLiveState: String = ""
    var statusUpdatedAt: Date?
    var lastRefreshError: String?

    // 身份元数据版本,用于合并 CloudKit 拉取结果
    var identityUpdatedAt: Date?
    var sortOrder: Int = 0

    init(favoriteKey: String) {
        self.favoriteKey = favoriteKey
    }
}
```

SwiftData 只作为本地缓存容器使用,不要启用 SwiftData CloudKit 自动同步。

---

## 6. 启动与刷新流程

### 6.1 启动/进入收藏页

1. 先读取本地缓存,立即展示收藏列表。
2. `liveState` 使用上次本地缓存值,可在 UI 上按需展示“上次刷新”时间。
3. 后台启动 CKSyncEngine,拉取远端成员变化。
4. 合并远端身份元数据时保留本地 `cachedLiveState`。
5. 后台刷新各平台直播状态,刷新结果只写本地缓存。

### 6.2 刷新成功后

对每个非 preserve 平台的成功结果做身份 diff:

| 情况 | 处理 |
|---|---|
| 只有 `liveState` 变 | 只更新本地缓存 |
| `roomId/userId` 从空或 `"0"` 补全 | 更新本地缓存 + 入队身份回写 |
| `userId` 稳定且 `roomId` 变化 | 更新本地缓存 + 入队身份回写 |
| 主 key 从旧 key 迁到新 key | delete old + save new |
| 无稳定身份且 `roomId` 变化 | 默认不回写,除非平台配置允许且能证明同一主播 |

### 6.3 CloudKit 拉取后

远端记录转本地缓存时:

- 新收藏:插入本地缓存,`cachedLiveState` 可为空或使用历史 `live_state` 作为首次快照。
- 已有收藏:合并 `roomId/userId/userName/avatar/title`,保留本地 `cachedLiveState/statusUpdatedAt/lastRefreshError`。
- 删除记录:删除本地缓存对应收藏。

---

## 7. 实施方案

### 步骤 1 · `favoriteUniqueKey` 尊重 `favoriteIdentityKey`

`AppFavoriteModel.favoriteUniqueKey(for:)` 改为按平台身份选主键,保留 `_r_` / `_u_` / `_n_` 桶前缀:

```text
identity = PlatformHostBehavior.favoriteIdentityKey(for: room.liveType)
若 identity == .userId:  有效 userId -> "_u_";否则有效 roomId -> "_r_";否则 "_n_"
否则(.roomId,默认):    有效 roomId -> "_r_";否则有效 userId -> "_u_";否则 "_n_"
```

`userId` 身份平台的 recordName 从此不随 `roomId` 漂移。

### 步骤 2 · re-key 修复标记是否 bump 按发布事实决定

若 `FavoriteSyncEngine.reKeyRepair.v1` 确认尚未上线,可保持 v1;首次发布时直接按新语义收敛云端 recordName。

若 TestFlight / 线上设备已经跑过旧 v1,必须 bump 到 v2 或提供显式重跑策略,否则这些设备不会自动重做 re-key。

### 步骤 3 · 在 TaskGroup 内产出身份变更事件

推荐在 `FavoriteStateModel.syncStreamerLiveStates` 的 TaskGroup 内比较旧 `liveModel` 与新 `dataReq/finalLiveModel`。这里按 index 配对最可靠,不会受后续 dedup/排序影响。

返回值建议携带:

```swift
struct FavoriteIdentityChange: Sendable {
    let oldKey: String
    let newRoom: LiveModel
    let changedFields: Set<Field>
}
```

其中 `changedFields` 只包含身份元数据,不包含 `liveState`。

### 步骤 4 · 身份写回前先落本地

当前 `persistLocal()` 是 fire-and-forget。身份回写依赖 `nextRecordZoneChangeBatch` 从本地真相取 room,因此推荐在刷新流程中增加可等待保存:

```text
applyRoomList(resp.rooms)
await FavoriteLocalStore.shared.save(resp.rooms)
enqueueIdentityMetadataChanges(resp.identityChanges)
```

这样 saveRecord 的 `recordProvider` 能稳定找到新 key 对应的本地记录。

### 步骤 5 · 引擎新增身份元数据写回入口

不要直接把“状态刷新后的完整 LiveModel”无脑交给现有 `enqueueSave`。推荐新增语义更窄的入口:

```text
enqueueIdentityMetadataRefresh(oldKey: String, room: LiveModel):
    newKey = favoriteUniqueKey(for: room)
    if oldKey != newKey { 入队 .deleteRecord(recordID(forKey: oldKey)) }
    入队 .saveRecord(recordID(forKey: newKey))
    kickSend()
```

同时调整 `makeRecord` / `applyFetched`:

- `makeRecord` 不写新的 `live_state`,或身份写回路径不改变云端 `live_state`。
- `applyFetched` 合并已有本地记录时保留本地 `liveState`。

### 步骤 6 · 可选增加 `identity_updated_at`

为身份元数据增加时间戳后,多设备同时刷新不同 `roomId` 时可按更新时间合并:

- 远端 `identity_updated_at` 新于本地 -> 覆盖本地身份字段。
- 远端旧于本地 -> 保留本地身份字段,必要时重新入队本地新值。

Phase 1 可以先不加,但一旦发现多设备身份字段来回覆盖,应优先补它。

---

## 8. 平台配置要求

实施前必须补一份平台清单:

| 平台 | `roomId` 是否可能变化 | 是否有稳定 `userId` | 建议配置 |
|---|---|---|---|
| roomId 稳定的平台 | 否 | 可有可无 | 默认 `favoriteIdentityKey: roomId` |
| roomId 会变且 userId 稳定 | 是 | 是 | `favoriteIdentityKey: userId` |
| roomId 会变但无稳定身份 | 是 | 否 | `preserveFavoriteRoomInfoOnRefresh: true` |

危险组合:

> 非 preserve + 默认 roomId + 实际 roomId 每场变化。

这个组合会导致 recordName churn,必须在上线前消除。

---

## 9. 调用点审计

`favoriteUniqueKey` 是当前主键唯一真源,调用点集中:

| 文件 | 用途 | 改 key 语义后是否一致 |
|---|---|---|
| `AppFavoriteModel.swift` | 定义 / `mergeLocalAndCloud` / `removeFavoriteRoom` | 一致 |
| `AppFavoriteModel+Backup.swift` | 导入去重 | 一致 |
| `FavoriteService.swift` | 旧默认 Zone 查询去重 | 一致 |
| `FavoriteSyncEngine.swift` | recordName 映射 / applyFetched / re-key / 迁移 / nextRecordZoneChangeBatch | 一致 |

需要额外注意:`removeFavoriteRoom` 当前按 `favoriteUniqueKey` 删除本地项。改 key 语义后,如果某条本地旧缓存仍是旧 key 语义,应通过 re-key / 本地迁移先收敛,避免删除漏项。

---

## 10. 验证清单

1. iOS / macOS build 通过;TV 收藏本期不动。
2. `AngelLiveCore` 相关测试通过。
3. 启动收藏页:
   - 断网时仍能展示上次本地收藏。
   - `liveState` 显示上次本地缓存值。
4. userId 身份平台:
   - 反复刷新导致 `roomId` 变化后,CloudKit 控制台始终只有一条 recordName。
   - 其它设备拉取后拿到新 `roomId`。
   - 其它设备本地 `liveState` 不被远端覆盖。
5. 收藏时 userId 为空、刷新后补全:
   - 云端 `user_id` 被补全。
   - recordName 按预期收敛。
6. 无稳定身份的平台:
   - `roomId` 变化不自动制造新云端记录。
7. 关闭「收藏 iCloud 同步」:
   - 纯本地刷新状态。
   - 不触发身份元数据回写。

---

## 11. 明确不做(out of scope)

- `liveState` CloudKit 同步。
- SwiftData CloudKit 自动同步。
- CKSubscription 静默推送(属 `SyncResilienceAndErrorModel.md` Phase③+)。
- 默认 Zone 迁移复活隐患(独立问题,见 `SyncResilienceAndErrorModel.md`)。
- TV 端收藏同步对齐。
