# 结构化付费留言宿主接口方案

> 状态：设计提案，尚未实现；2026-10-04。仅覆盖 FullUI。外部插件协议、插件输出与宿主渲染需分别验收，本文不宣称已具备真实消息来源。

目标是让插件明确声明付费留言，宿主按统一展示数据渲染。宿主不根据正文、金额格式、来源名称或专用事件字段猜测付费身份，不解释币种，不处理购买或礼物转换。

## 1. 已核验链路与旧文档差异

当前代码优先于旧路线图中的行号和三字段描述：

| 层 | 当前入口 | 事实 |
|---|---|---|
| 驱动解码 | `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Danmu/LiveParseDanmakuPlan.swift` | `LiveParseDanmakuMessage` 已包含 `text`、`nickname`、`color`、`image`、`segments`；没有结构化付费块。消息数组逐项容错 |
| 宿主展示模型 | `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/Danmu/DanmakuDisplayMessage.swift` | `DanmakuDisplayMessage` 保留有序图文片段，旧图片转换为片段；限制每条 32 个片段、8 张图片 |
| 两种传输 | 同目录 `WebSocketConnection.swift`、`HTTPPollingDanmakuConnection.swift` | 均转换为 `DanmakuDisplayMessage` 交给 delegate，扩展不能仅接 WebSocket |
| 翻译 | `Shared/AngelLiveCore/Sources/AngelLiveCore/Translation/DanmakuTranslationPipeline.swift` | 翻译后重新创建展示模型；新元数据必须显式透传，否则会被丢失 |
| 共享飞屏样式 | `Shared/AngelLiveCore/Sources/AngelLiveCore/DanmakuKit/Core/DanmakuDisplayModelFactory.swift` | 当前三处正文关键字判断共同控制白字与橙色背景，已集中到共享工厂，不是三端各自持有 |
| iOS FullUI | `FullUI/ViewModels/RoomInfoViewModel.swift` | 屏蔽词 → 翻译 → `deliverDanmakuMessage` → 聊天列表与飞屏调度；聊天模型支持 `segments` |
| macOS | `ViewModels/RoomInfoViewModel.swift`、`Models/ChatMessage.swift` | 相同 delegate 主链；当前聊天模型没有 `segments`，不能宣称聊天与飞屏混排已完全对等 |
| tvOS | `Source/DetailPlayer/RoomInfoViewModel.swift` | delegate/翻译后进入飞屏调度；付费卡片需独立宿主展示状态 |

外部插件仓库的当前文件及输出未在本次重新核验。`DanmakuRenderingRoadmap.md` 中关于外部脚本已解析哪些字段的历史描述不能作为当前接口证据。

## 2. 提议的插件输出

沿用既有路线图提出的可选 `superChat` 字段，避免同时引入两个表示相同语义的块。名字是通用协议标识；宿主 Swift 类型采用 `PaidMessage`。以下是待外部协议仓库接受的提案，不是已存在的运行时接口：

```typescript
interface DanmakuMessage {
  text: string;
  nickname: string;
  color?: number;
  image?: DanmakuImage;
  segments?: DanmakuSegment[];
  superChat?: {
    id?: string;
    priceText?: string;
    tier?: number;
    avatar?: string;
    durationSec?: number;
  };
}
```

```json
{
  "text": "感谢分享这段内容",
  "nickname": "观众A",
  "segments": [{ "type": "text", "text": "感谢分享这段内容" }],
  "superChat": {
    "id": "message-42",
    "priceText": "5.00 示例单位",
    "tier": 1,
    "avatar": "https://images.example.invalid/avatar.png",
    "durationSec": 30
  }
}
```

字段语义：

- `superChat` 是对象时，代表插件已识别的付费留言；空对象仍是付费留言，展示通用高亮卡片。缺失或 `null` 为普通消息。字符串、数组等错误块类型只使该块无效，不丢正文或同帧其他消息。
- `id` 是插件给出的不透明消息标识，在同一插件、同一房间内稳定。重连重发应保持同一值。没有 ID 时宿主生成仅本次接收有效的 UUID，不用“正文+昵称+金额”合并不同消息，也不声称支持跨重连去重。
- `priceText` 是展示就绪的纯文本；缺失/空白显示“付费留言”。不解析数值、货币、不据其排序或推导时长，不按正文重写金额。
- `tier` 提议为整数 `0...6`，只决定主题配色。缺失、非整数、越界采用基础主题，不能把未知高值截为最高档。各来源如何归一化留在插件私有实现。
- `avatar` 只接受 HTTP/HTTPS URL，拒绝其他 scheme 和 URL userinfo；失败使用人物占位，不影响留言。不得随头像请求携带平台登录凭据。
- `durationSec` 是建议展示秒数，必须有限且大于零。提议宿主缺省 30 秒，有效值限制为 5...300 秒；这是展示资源上限，不推断消费金额。具体默认值和上限在 UI 实施前由产品方案确认。
- `text`/`nickname` 保留旧必填契约。`segments` 和 `image` 继续遵循 [图文混排协议](DanmakuMixedContentProtocol.md)，付费块不承载第二份正文。

每个可选子字段独立解码/校验；一个坏头像或坏档位不取消付费身份。未知字段忽略。原普通消息解码规则不借此顺带改变。

## 3. 宿主类型与接口边界

```swift
public struct PaidMessage: Sendable, Equatable {
    public let messageID: String?
    public let priceText: String?
    public let tier: Int
    public let avatarURL: URL?
    public let duration: TimeInterval
}

// 在现有展示模型增加可选值；现有 init 的新增参数默认 nil。
public struct DanmakuDisplayMessage: Sendable, Equatable {
    // 现有 text / nickname / color / segments 保持原语义
    public let paidMessage: PaidMessage?
}

@MainActor @Observable
public final class PaidMessagePresentationStore {
    public private(set) var entries: [PaidMessageEntry]
    public func receive(_ message: DanmakuDisplayMessage, receivedAt: Date)
    public func removeExpired(at now: Date)
    public func reset()
}
```

`PaidMessageEntry` 使用稳定展示 ID、接收时间、到期时间、原有正文片段及付费元数据。store 属于单个房间/播放器会话，不使用进程全局共享队列；插件与房间命名空间由创建 store 的宿主上下文确定，不信任消息自报来源。离开房间或切换播放会话必须清空。

到期时间从接收时刻计算，后台经过的时间照常流逝，回前台先剔除过期项。暂停视频不延长付费置顶。相同稳定 ID 的重发既不新增，也不延长到期；本期不支持编辑、退款、撤回协议，未来需要外部明确的操作类型才能加入。

活跃条目提议最多 20 条，满时淘汰最早接收条目；这是明确的宿主展示上限，不能无声应用到普通弹幕数组。去重 ID 的会话缓存需有有界容量并覆盖最近过期窗口，最终上限须随上述 UI 参数一并确认。超过缓存窗口的重发不保证全会话去重，不伪称服务器级 exactly-once。

共享层只负责解析、规范化、去重/到期和数据状态。具体布局、交互、焦点及系统安全区留在三端宿主；不修改 DanmakuKit 的轨道/运动后端，不引入 Metal。

## 4. 接收、翻译和显示路由

1. 解码与展示模型同时携带可选元数据；WebSocket 和 HTTP polling 使用同一转换。
2. 原屏蔽词仍先作用于正文。付费身份不能绕过用户屏蔽规则。
3. 翻译只翻译正文文本片段。昵称、价格、ID、档位、头像和时长原样保留；不能把价格交给翻译模型重新表达。队列记录使用原接收时间，翻译延迟不延长置顶。
4. FullUI `deliverDanmakuMessage` 中先判断结构化块：有块进入 paid store，无块走普通飞屏；付费内容不得同时飞屏一遍。
5. iOS/macOS 已有聊天列表可保留一条对应消息，显示“付费留言”和可用金额，不另外新增永久历史数据库。使用相同展示 ID 避免翻译完成或重连重复插入。macOS 混排能力差异必须单独实现或明确降级为现有文本，不默认扩大本期范围。
6. 关闭飞屏弹幕时同时隐藏播放器内付费 overlay，尊重现有弹幕开关；聊天列表原可见性不改变。隐藏时仍按接收时间到期，重新打开不重放已过期条目。

当前共享工厂的正文嗅探移除属于行为变更。应仅对明确 FullUI 消费者启用新样式策略；若 ShellUI 存在任何间接调用，保留默认旧策略或拆 FullUI 专用路径，不能通过共享工厂全局改动改变 ShellUI。新 FullUI 无结构化块的消息一律按普通内容显示，不因出现某些字符高亮；老插件兼容保证“内容能看见”，不保证旧启发式橙底仍存在。

## 5. 三端承载边界

以下确定布局方向，尚需实施前给出原尺寸参考图及颜色方案，不能据本文宣称视觉验收完成：

| 平台 | 承载 | 交互和限制 |
|---|---|---|
| iPhone/iPad 竖向详情 | 优先使用视频下方现有聊天/信息区域顶部的摘要与卡片 | 不压缩播放器关键控制；大字体按内容增高；最多一个展开卡片 |
| iPhone/iPad 横向/全屏 | 播放器安全区内顶部摘要，点摘要展开一个卡片 | 避让返回/线路控制和本轮恢复提示；不覆盖底部字幕；收起后恢复原点击区域 |
| macOS | 当前详情聊天侧栏顶部；无侧栏的独立播放器使用顶部摘要 | 键盘与鼠标可选择/收起，最多一个展开卡片；窗口变窄时不得用固定屏幕宽度 |
| tvOS | 播放器系统安全区内非交互摘要/短卡片 | 不可 focus、不改变遥控焦点、不抢 Menu 返回；使用系统 safe area，不写死电视边距 |

头像失败是占位状态，不是整卡错误。金额缺失是通用高亮状态，不编造数值。档位只改变主题，文字/图标仍表达付费身份；配色必须覆盖深浅色、对比度、大字体和 Reduce Motion。到期淡出不移动当前遥控焦点。三端都不做自动滚动 ticker 跑马灯作为唯一可读入口。

具体 7 档配色、默认时长/上限、摘要在播放器控制展开时的避让布局属于实现前的产品/视觉验收输入。本文只锁定数据语义及不遮挡/不夺焦点边界，不把未确认视觉常量写入生产代码。

## 6. 插件兼容与跨仓库前置

| 组合 | 预期 |
|---|---|
| 旧插件 + 新宿主 | 无付费块，保留普通文本/图片/segments 展示 |
| 新插件 + 旧宿主 | 必须继续输出 text/nickname/color 等旧字段；旧宿主忽略未知块，按普通消息显示 |
| 新插件 + 新宿主 | 结构化块进入付费卡片，正文不重复飞屏 |
| 错误块 + 新宿主 | 保留原消息；错误字段局部降级，错误块类型按普通消息 |

实施门禁：

1. 在外部插件协议仓库确认其真实 `DanmakuMessage`、两个驱动返回路径及版本策略；接受上述可选块后先提交协议示例与契约测试。此处不假设已存在新 capability 或特定 minimum host version 字段。
2. 由插件维护者为已确认的付费事件输出归一化块，私有原始字段/金额映射不进入宿主、fixture 或文档。礼物事件不自动转换为留言。
3. 在宿主以中性 fixture 完成模型及生命周期，再接三端 UI。没有真实外部输出时只能验收 fixture，不能称真实来源已支持。
4. 至少一个经授权可观察的实际插件事件通过完整链路，记录插件版本、宿主版本、设备与时间；示例消息不得冒充真实事件。外部仓库发布、账号及付费操作需要各自明确授权，本文不包含这些操作。
5. 完成全仓平台标识扫描；不只扫描本文件或本次 diff。发现旧文档错误单独修订，不复制其未核验外部事实。

## 7. 测试与验收

纯测试：旧消息/空块/null/错误块/各字段错误/未知档位/无效头像/非法时长；坏付费字段不丢消息及同帧兄弟；segments 既有规则不变；两个传输同转换；翻译完整保留元数据；ID 去重不延长到期；无 ID 两条同文不合并；跨房间隔离；后台到期；有界容量；关闭/恢复开关不重放；ShellUI原路径不变。

UI：三端真实新包，覆盖无头像、无价格、长昵称/长正文、图片失败、多条并发、过期、屏蔽词、翻译延迟、横竖/窗口尺寸、深浅色、大字体、Reduce Motion。tvOS 实际确认方向键焦点与 Menu 返回；iOS/macOS确认卡片不盖字幕或恢复提示。

交付分别报告“协议提案”“宿主 fixture 验证”“插件实际输出”“三端设备视觉/交互”。任一环节未做不得写整体完成。
