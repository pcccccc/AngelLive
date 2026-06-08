# 收藏身份字段回写 · favoriteUniqueKey 稳定化

> 状态:设计 v1 · 2026-06-08
> 范围:收藏域 · iOS / macOS(TV 收藏后续另议)
> 关联:本文是 `docs/SyncResilienceAndErrorModel.md` Phase③(CKSyncEngine 收藏同步)的延伸专题
> 一句话:刷新直播状态后,把**补全/变化的身份字段(roomId / userId)**回写 CloudKit;`liveState` 暂不回写。前置是先让 `favoriteUniqueKey` 的语义稳定下来。

---

## 0. 背景与动机

需求起点:收藏列表刷新后已经拿到每个主播的最新 `liveState` / `roomId` / `userId`,自然会问——能不能把这些回写 CloudKit,让其它设备也拿到最新身份?

直接「刷新完无脑把所有 `LiveModel` 走一遍 `enqueueSave`」是**错的**,会制造云端重复记录。本文记录:为什么不能无脑回写、第一阶段只做什么、怎么做才稳。

**当前事实(已核对代码)**:

- 刷新路径:`AppFavoriteModel.syncWithActor()` / `pullToRefresh()` → `refreshStatesAndApply(members:)`。
- `refreshStatesAndApply`(`AppFavoriteModel.swift:121`)只做三件事:调接口刷新、更新 UI、本地落盘(`persistLocal()`)——**完全不回写 CloudKit**。
- 最新数据来源:`FavoriteStateModel.syncStreamerLiveStates`(`FavoriteStateModel.swift:100`)调 `ApiManager.fetchLastestLiveInfoFast`,成功返回 `dataReq`(含新 `liveState`/`roomId`/`userId`)。
- CloudKit 记录已支持这些字段:`FavoriteSyncEngine.makeRecord`(`:217/:218/:224`)写 `room_id`/`user_id`/`live_state`。
- recordName = `AppFavoriteModel.favoriteUniqueKey(for:)`(`:504`),**当前无条件 roomId 优先**,userId 兜底,userName 最后。

---

## 1. 两个关键约束(决定方案形状)

### 1.1 preserve 平台刷新时根本不动身份字段

`syncStreamerLiveStates` 里有分支(`FavoriteStateModel.swift:102-108`):

```swift
if PlatformHostBehavior.shouldPreserveFavoriteRoomInfoOnRefresh(for: liveModel.liveType) {
    var finalLiveModel = liveModel
    finalLiveModel.liveState = dataReq.liveState   // 只更新 liveState,roomId/userId 保留原值
    return (index, finalLiveModel, ...)
} else {
    return (index, dataReq, ...)                    // 完整替换(含新 roomId/userId)
}
```

→ **「刷新后身份字段变化」只可能发生在非 preserve 平台**。preserve 平台天然不会触发 key 变更,这缩小了风险面。

### 1.2 `favoriteIdentityKey` 已存在,但 `favoriteUniqueKey` 没用它(核心隐患)

`PlatformHostBehavior.favoriteIdentityKey(for:)`(`PlatformHostBehavior.swift:9`)由 manifest 声明:某平台身份是 `userId` 还是 `roomId`。声明 `userId` 的平台,正是「roomId 每场直播会变」的平台。

但 `favoriteUniqueKey`(CKRecord recordName)**无条件 roomId 优先**,完全没读这个声明。

今天没炸的唯一原因:**刷新不回写、roomId 冻结在收藏那一刻**,recordName 始终稳定。一旦开启身份回写、把刷新后的新 roomId 也写进去,这些 userId-身份平台的 recordName 就会**每场直播都变** → 云端堆重复记录。

> 旁证:`FavoriteService.deleteRecord`(`FavoriteService.swift:101`)删除时**已经**对 `favoriteIdentityKey == .userId` 特判用 userId 查询。说明「按平台身份选主键」是既有先例,只是 `favoriteUniqueKey` 漏了这一致性。

---

## 2. 风险分析(为什么不能无脑回写)

| # | 风险 | 触发条件 | 后果 |
|---|---|---|---|
| R1 | **云端重复记录** | roomId 变 → `favoriteUniqueKey` 变 → `enqueueSave` 用新 recordName 建记录,旧记录不删 | 同一主播云端多条;`fullReconcile` 只增不删、re-key 修复只跑一次,没有持续纠重网 |
| R2 | **serverRecordChanged** | 频繁更新同一 recordName | `makeRecord` 新建 `CKRecord(recordType:recordID:)` 不带 system fields(`:212-216` 注释自陈),`failedRecordSaves` 仅 log 不重试(`:358-360`) |
| R3 | **多设备旧状态互盖** | 把易变的 `liveState` 纳入回写 | `applyFetched` 当前**无条件覆盖**(`:254` `rooms[idx] = model`),无时间戳 → A 设备 10:00 的「直播中」会被 B 设备 10:05 推来的旧「下播」盖掉 |

**架构层反对 liveState 回写**:`FavoriteSyncEngine` 头注释(`:7-11`)明确分工——引擎只管「成员关系(增/删/拉列表)」,**直播状态刷新不走引擎、各设备本地做**。`liveState` 是高频、低收益、跨设备时序敏感字段,把它塞进云同步与既有架构相悖,且无 `status_updated_at` + merge 规则前必然触发 R3。

---

## 3. 决策

**第一阶段只做「身份补全 / 稳定化」,`liveState` 不进云回写。**

- ✅ 做:roomId / userId 从「空 / "0" / 缺失」变为有效值时,回写到云端,让 recordName 收敛、跨设备身份对齐。
- ✅ 做:先让 `favoriteUniqueKey` 按平台身份选主键(key 稳定),这是回写安全的前提。
- ❌ 不做:`liveState` 回写(留待将来,需先建 `status_updated_at` 并改 `applyFetched` 覆盖策略)。
- ❌ 不做:刷新后对全部结果无脑 `enqueueSave`(只 diff 出真变化才入队)。

收回上一版「liveState 变了就上传」的提议:改为「身份字段补全优先,liveState 先不进云同步」。

---

## 4. 实施方案(五步,代码改动留待后续单��执行)

> 本文档只描述方案;具体编码不在本次交付范围内。

### 步骤 1 · `favoriteUniqueKey` 尊重 `favoriteIdentityKey`

`AppFavoriteModel.swift:504`,改为按平台身份选主键,**保留 `_r_`/`_u_`/`_n_` 桶前缀**(re-key 匹配逻辑依赖前缀,不变):

```
identity = PlatformHostBehavior.favoriteIdentityKey(for: room.liveType)
若 identity == .userId:  有效 userId → "_u_";否则有效 roomId → "_r_";否则 "_n_"
否则(.roomId,默认):    有效 roomId → "_r_";否则有效 userId → "_u_";否则 "_n_"
```

userId-身份平台的 recordName 从此用 userId,roomId 怎么变 key 都不动 → R1 在最需要它的平台上**根本不会发生**。

### 步骤 2 · re-key 修复标记保持 v1(**不** bump 到 v2)

`FavoriteSyncEngine.reKeyRepair.v1` **尚未上线**,没有任何线上设备跑过旧语义的 re-key。改完 `favoriteUniqueKey` 后,v1 修复在**首次发布时第一次跑**就直接按新语义把云端 recordName 收敛 → 不存在二次迁移,v2 多余。

> 自测边界:开发机 / TestFlight 若已把 `reKeyRepair.v1` 置过 true,那台设备不会自动重跑。删 App 重装或清掉该 UserDefaults key 即可。属自测细节,不影响线上首发。

### 步骤 3 · 刷新后只 diff 身份字段,不 diff liveState

只有当某收藏的**身份字段补全或变化**时才入队;`liveState` 变化**不**触发回写。

**diff 位置(推荐)**:在 `syncStreamerLiveStates` 的 TaskGroup 内做——那里同时持有旧 `liveModel` 和新 `dataReq`/`finalLiveModel`,是**权威配对**(按 index,不受后续 dedup/排序打乱)。把「身份变更项」作为第三个返回值上浮给 `AppFavoriteModel` 入队。

> 备选(更简单但有边界):在 `refreshStatesAndApply` 里用旧 `members` ↔ 新 `resp.0` 按 `isSameStreamer` 配对 diff。缺点:roomId-身份平台若 roomId 变且无 userId,`isSameStreamer` 可能配不上。故首选 TaskGroup 内配对。

**入队判定**(对每个非 preserve 平台的刷新成功项):

- 旧 key == 新 key,但身份字段值变了(如 userId 由空补全) → `enqueueSave(新)`(同 recordName 更新字段)。
- 旧 key != 新 key → 走步骤 4(delete old + save new)。
- key 与身份字段都没变 → **跳过**(常态,避免 churn)。

### 步骤 4 · key 变更兜底:delete old + save new

正常情况(步骤 1 稳定 key 后)极少触发,但保留兜底。需要给引擎加一个能**按显式旧 key 删除**的入口(现有 `enqueueDelete(room)` 会用 room 算出**新** key,删不掉旧记录):

```
enqueueIdentityRefresh(oldKey: String, room: LiveModel):
    newKey = favoriteUniqueKey(for: room)
    if oldKey != newKey { 入队 .deleteRecord(recordID(forKey: oldKey)) }
    入队 .saveRecord(recordID(forKey: newKey))
    kickSend()
```

删除自动入批、不经 `recordProvider`(与现有删除路径一致);保存的新 key 在本地真相里已存在(刷新后的列表已 `persistLocal`),`nextRecordZoneChangeBatch` 的 `byKey[recordName]` 能取到。

### 步骤 5 · liveState 暂不回写(将来若做的前置条件)

将来要把 `liveState` 纳入云同步,**必须先**:

1. CloudKit 加可选字段 `status_updated_at`(`makeRecord` 写、`liveModel(from:)` 读)。
2. 把 `applyFetched`(`:245`)的无条件覆盖改成「仅当远端 `status_updated_at` 较新才覆盖本地」,否则保留本地新鲜状态。

在此之前,`liveState` 维持现状:仅在 add 时作快照写入,各设备本地刷新为准。

---

## 5. 前置配置要求(运维/插件侧)

步骤 1 把 key 与平台身份绑定后,**正确声明 manifest 的 `favoriteIdentityKey` / `preserveFavoriteRoomInfoOnRefresh` 成为安全前提**。危险组合是:

> 非 preserve + 身份声明为 roomId(或未声明,默认 roomId)+ 该平台 roomId 实际每场变。

这种平台一旦开回写就会每场 churn(delete+save)。处置:给这类平台在 manifest 里声明 `favoriteIdentityKey: userId`(key 走 userId,稳定)**或** `preserveFavoriteRoomInfoOnRefresh: true`(刷新不动 roomId)。本文档应附一份「各平台身份/preserve 声明现状」核对清单(实施时补)。

---

## 6. favoriteUniqueKey 调用点审计(改语义为何全局安全)

全部调用点(Swift,已穷举,无任何散落的手写 `_r_`/`_u_` 字符串):

| 文件 | 用途 | 改 key 语义后是否一致 |
|---|---|---|
| `AppFavoriteModel.swift` | 定义 / `mergeLocalAndCloud` / `removeFavoriteRoom` | ✅ 同一函数,全局一致 |
| `AppFavoriteModel+Backup.swift:33/36` | 导入去重 | ✅ 一致 |
| `FavoriteService.swift:88` | `searchRecord` 去重 | ✅ 一致 |
| `FavoriteSyncEngine.swift`(多处) | recordName 映射 / applyFetched / re-key / 迁移 / nextRecordZoneChangeBatch | ✅ 一致 |

结论:`favoriteUniqueKey` 是唯一真源,改函数体即全局一致;唯一跨版本影响是云端已存的旧 recordName,由步骤 2 的 v1 re-key 首发时收敛。`isSameStreamer` / `deduplicated` 用多维度匹配(userId 或 roomId),独立于本 key,不受影响。

---

## 7. 待定 / 不确定点(实施时定)

- **不确定点 A**:diff 位置最终选 TaskGroup 内配对(推荐)还是 `refreshStatesAndApply` 配对——影响 `syncStreamerLiveStates` 返回签名是否加第三项。
- **不确定点 B**:步骤 4 的引擎新入口命名与是否需要节流。鉴于步骤 3 的 diff 闸 + 身份补全本质是「每个收藏一次性」事件,常态频率极低,Phase 1 可不加显式节流;churn 的真正闸门是 manifest 正确声明(第 5 节)。

---

## 8. 验证清单(实施后)

1. 三端 build:iOS / macOS BUILD SUCCEEDED(TV 收藏本期不动)。
2. `LiveParse` / `AngelLiveCore` 单测通过(`cd Shared/AngelLiveCore && swift test`)。
3. 两台设备同一 iCloud 账号:
   - userId-身份平台收藏 → 反复刷新 → CloudKit 控制台确认该主播**始终一条** recordName(无每场新增)。
   - 收藏时 userId 为空、刷新后补全 → 确认云端记录 `user_id` 被回写、recordName 不漂。
   - 非 preserve 平台 roomId 变 → 确认 delete old + save new,云端无残留旧记录。
4. CloudKit 控制台:无同一主播多条重复;`favorite_streamers` 总数与本地收藏数一致。
5. 关「收藏 iCloud 同步」开关 → 纯本地、完全不触发任何回写。

---

## 9. 明确不做(out of scope)

- `liveState` 回写(见步骤 5 前置)。
- CKSubscription 静默推送(属 `SyncResilienceAndErrorModel.md` Phase③+)。
- 默认 Zone 迁移复活隐患(独立问题,见该文档「仍潜伏」)。
- TV 端收藏的同步对齐。
