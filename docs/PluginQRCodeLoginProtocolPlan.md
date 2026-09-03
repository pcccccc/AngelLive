# 插件纯 HTTP 扫码登录与可选短信验证协议

更新时间：2026-09-02

本文档定义宿主与插件之间的"登录挑战"协议，让 macOS、tvOS、iOS 都能在不依赖 WebView 的情况下，由插件驱动纯 HTTP 扫码登录，并可在手机确认后请求宿主收集一次短信验证码。宿主负责原生二维码/验证码 UI、临时 Cookie Jar 和凭据落库。协议与具体直播平台无关，任何插件只要实现本文的函数契约即可接入。

各平台自身的接口链路、状态码和安全态引导属于插件实现细节，记录在插件仓库 `docs/research/` 下对应平台的研究文档中，本文不引用其内容。

## 1. 现状与约束

以下事实来自协议落地前的宿主代码，也是本实现保持兼容的边界：

- 登录入口是数据驱动的。`PlatformLoginRegistry` 从 manifest 的 `loginFlow` 构建可登录平台列表，`ManifestLoginFlow.kind` 目前只有 `webview` 一种语义，tvOS 把它退化为手动粘贴 Cookie 加 iCloud/Bonjour 同步。
- “需要登录”与“支持扫码登录”是两项独立能力。`auth.required` 只表示插件功能需要凭据，`loginFlow` 只表示插件提供现有网页登录/手动 Cookie 流程；二者都不能推导出插件支持二维码登录。只有 manifest 显式声明受支持的 `loginChallenge`，宿主才能展示扫码登录入口。
- 凭据只有一种宿主形态。`PlatformSessionManager.loginWithCookie` 接收 Cookie 字符串，但调用插件 `validateCredential` 时只传 `credentialAvailable: true`；插件只能用受保护的 `Host.http` 发起校验请求。校验通过后宿主写入 `SessionStore` 与 `LiveParsePlatformSessionVault`，并淘汰旧 runtime，不再通过 `setCredential` 把 Cookie 通知插件。iCloud 与 Bonjour 同步的仍是宿主间凭据数据，扫码登录不能另开一条插件可读的凭据通道。
- 插件 HTTP 走宿主桥。`Host.http.request` 对应 `__lp_host_http_request`。`authMode: "none"` 保持原有请求行为；`platform_cookie`、`login_transaction` 和 `cookieInject` 等宿主管理凭据的路径会关闭系统 Cookie、绕过 URLCache 并强制 `no-store`。宿主仅在原生 `URLRequest` 上注入 Cookie，正式/候选凭据只能发往 manifest 的 `loginFlow.cookieDomains` 或 `loginURL` host；Cookie 值不进入 JS 请求对象或返回对象。
- 普通 HTTP 桥仍通过 `allHeaderFields` 收集响应头；`login_transaction` 模式单独接管每一跳以吸收多个 `Set-Cookie` 和中间跳 Cookie，其他宿主管理凭据的请求也接管重定向以防跨源泄漏和 HTTPS 降级。
- 开发者控制台通常会记录插件函数的完整入参与前 2000 字节返回值；登录事务调用和 HTTP 子请求必须走新增的脱敏分支，`qrContent`、`challengeId`、事务 ID 和任何 Cookie 都不能进入日志。
- 插件函数统一经 `LiveParsePlugins.shared.call(pluginId:function:payload:)` 调用。兼容入口 `setCookie`、`clearCookie`、`setCredential`、`clearCredential` 由 `LiveParsePluginManager` 完全截获，只修改宿主 vault 并返回非敏感 receipt，绝不继续调用同名插件 JS 函数。新协议函数沿用同一调度入口，但只携带不透明 ID 和状态。

## 2. 责任划分

原则：平台协议在插件，秘密与生命周期在宿主。

| 关注点 | 归属 | 说明 |
| --- | --- | --- |
| 匿名设备态生成、安全脚本、签名、创建与轮询接口、状态码语义 | 插件 | 这是平台能力，宿主不得内置任何平台专属请求。 |
| 一次登录事务的临时 Cookie Jar | 宿主 | 按 host/path 吸收所有 `Set-Cookie`，包括重定向中间跳，事务结束即销毁。 |
| 二维码渲染、短信验证码输入、轮询节奏、取消、超时、刷新 UI | 宿主 | 三端 FullUI 各用原生组件，并共用 `AngelLiveCore` 中的状态机。验证码只在内存中短暂存在。 |
| 最终校验与凭据落库 | 宿主 | 事务 Jar 提升为宿主内 Cookie 字符串后走 `loginWithCookie(validateBeforeSave: true)`；插件 `validateCredential` 只收到可用性标记，并通过原生注入的 `Host.http` 校验。 |
| WebView 兜底 | 宿主 | 扫码不可用或失败时，macOS/iOS 回退到现有 `loginFlow.kind = webview`。 |

安全态引导之类的计算是普通 JavaScript，插件运行在 JavaScriptCore 里本来就能执行，因此不放到宿主。宿主只需要提供事务级 Cookie Jar 和重定向控制这两个通用能力，插件就能完整复现平台网页端的匿名会话。

## 3. Manifest 声明

在 manifest 顶层新增 `loginChallenge` 字段，`loginFlow` 保持不变作为兜底。旧宿主用 `JSONDecoder` 解析会忽略未知字段，因此新插件在旧宿主上自动退化为 WebView 登录。

`loginChallenge` 是可选能力声明，不是所有带登录能力的插件都必须实现。宿主按以下规则独立判断各登录方式：

| Manifest 声明 | 表示的能力 | 宿主行为 |
| --- | --- | --- |
| `auth.required == true` | 插件部分或全部功能需要登录凭据 | 可以展示“需要登录”提示，但不能据此展示二维码 |
| 存在 `loginFlow` | 支持现有 WebView 登录；tvOS 可使用其中的提示字段辅助 Cookie 手动输入 | 展示网页登录或手动输入入口 |
| 存在 `loginChallenge` 且 `kind == "qrcode"` | 插件明确实现本文定义的二维码挑战协议 | 宿主能力与协议版本同时满足时，展示“扫码登录”入口 |
| 不存在 `loginChallenge` | 插件未声明扫码能力 | 不调用挑战函数，不展示扫码入口，也不把缺失视为错误 |

一个插件可以只提供现有 `loginFlow`，也可以同时提供 `loginFlow` 与 `loginChallenge`。首版协议要求声明 `loginChallenge` 的插件同时保留 `loginFlow`，供旧宿主以及 macOS/iOS 扫码失败时回退；这不代表所有声明了 `loginFlow` 的插件都必须增加 `loginChallenge`。

```json
{
  "loginFlow": {
    "kind": "webview",
    "loginURL": "https://example.com/login",
    "...": "现有字段不变"
  },
  "loginChallenge": {
    "kind": "qrcode",
    "minLoginChallengeProtocol": 2,
    "functions": {
      "create": "createLoginChallenge",
      "poll": "pollLoginChallenge",
      "cancel": "cancelLoginChallenge",
      "submitVerification": "submitLoginChallengeVerification",
      "resendVerification": "resendLoginChallengeVerification"
    },
    "pollIntervalMs": 2000,
    "timeoutSeconds": 180,
    "maxRefreshes": 3,
    "hint": "打开对应 App 扫描二维码，并在手机上确认登录",
    "preferOn": ["tvos", "macos", "ios"]
  }
}
```

字段说明：

- `kind`：当前只定义 `qrcode`。未来短信验证码或设备码登录可以增加新值，宿主对未知 `kind` 一律视为不支持。
- `loginChallenge` 字段本身：可选。缺失表示插件没有声明二维码登录能力；宿主不得通过 `auth`、`credentialKinds`、`loginFlow.kind` 或函数扫描猜测支持情况。
- `minLoginChallengeProtocol`：插件所需的最低登录挑战协议版本。当前宿主版本为 `2`。只会返回五个基础扫码状态的插件可继续声明 `1`；可能返回 `verification_required` 的插件必须声明 `2`。它独立于三端不一致的 `MARKETING_VERSION`。
- `functions`：允许插件自定义函数名。基础扫码函数为 create/poll/cancel；协议 v2 另外定义 submitVerification/resendVerification。宿主按默认名回退。自定义名不得使用宿主保留的 `setCookie`、`clearCookie`、`setCredential`、`clearCredential`；否则该挑战声明视为当前宿主不支持，避免挑战调用误触正式凭据写入语义。
- `pollIntervalMs`、`timeoutSeconds`、`maxRefreshes`：宿主状态机的默认节奏，插件在 create 响应里可以逐次覆盖 `pollIntervalMs` 和过期时间。
- `preferOn`：在这些平台上扫码作为首选入口，未列出的平台仍展示但排在 WebView 之后。tvOS 没有 WebView，只要声明了 `loginChallenge` 就必然首选。
- 宿主会把轮询间隔限制在 1 至 60 秒、总超时限制在 30 至 600 秒、自动刷新次数限制在 0 至 10 次；函数名、提示文案和平台数组也会做长度限制。

`ManifestLoginChallenge` 作为新的 `Codable` 结构加入 `LiveParsePluginManifest`，`LoginPlatformEntry` 增加可选 `loginChallenge` 字段。注册表先扫描候选 pluginId，再通过共享 `LiveParsePluginManager.resolve` 取得实际会执行的 enabled / pinned / last-good / sandbox-or-built-in 有效版本；它只透传该 manifest 的显式声明，不扫描插件入口函数，也不为只有 `loginFlow` 的插件合成扫码能力。

## 4. 插件函数契约

所有函数均通过 `LiveParsePlugins.shared.call` 调用，入参与返回值都是 JSON 对象。所有函数都不接收也不返回 Cookie 值。短信验证码是用户授权提交给平台的一次性输入，会短暂传给插件的 submitVerification 函数，但不得持久化或记录日志。

### 4.1 createLoginChallenge

入参：

```json
{ "transactionId": "opaque-host-token", "platform": "tvos" }
```

`transactionId` 由宿主在调用前通过 `beginLoginTransaction` 创建，标识本次登录事务的临时 Cookie Jar。插件后续所有请求都带上它。

返回：

```json
{
  "kind": "qrcode",
  "challengeId": "opaque-plugin-token",
  "qrContent": "待编码的二维码文本",
  "pollIntervalMs": 2000,
  "expiresAt": 0,
  "hint": "可选，覆盖 manifest 的 hint"
}
```

- `challengeId` 对宿主不透明，插件内部关联上游挑战标识，这些数据只存在插件内存，随 cancel 或事务结束清除。
- `qrContent` 是待编码文本，宿主用原生二维码组件渲染，插件不生成图片。
- `expiresAt` 是 Unix 毫秒时间戳，上游没有可靠过期时间时填 0，由轮询返回的 `expired` 驱动刷新。

失败时抛出标准化错误。`code` 使用现有 `LiveParsePluginError.standardized` 的取值，宿主据此决定提示文案和是否回退 WebView：

- `NETWORK` / `TIMEOUT`：提示重试。
- `BLOCKED`：风控，提示改用 WebView 或稍后再试。
- 其他：显示 `message`，允许重试。

### 4.2 pollLoginChallenge

入参：

```json
{ "transactionId": "...", "challengeId": "..." }
```

返回：

```json
{
  "state": "waiting",
  "rawStatus": 0,
  "message": "",
  "uid": null
}
```

状态集合与语义固定，协议 v2 宿主认识以下六个值：

| state | 含义 | 宿主行为 |
| --- | --- | --- |
| `waiting` | 未扫码或未识别的中间态 | 继续轮询 |
| `scanned` | 手机已扫码，等待确认 | 更新 UI 文案，继续轮询 |
| `verification_required` | 手机已确认，但平台要求一次宿主侧用户验证 | 暂停轮询，展示验证输入；验证通过后继续同一挑战的轮询 |
| `confirmed` | 插件已完成会话兑换，正式凭据已进入事务 Jar | 停止轮询，进入提升与校验 |
| `expired` | 二维码过期 | 未超过 `maxRefreshes` 则自动重新 create |
| `failed` | HTTP、签名、风控或响应结构错误 | 停止，展示 `message`，提供重试和 WebView 兜底 |

关键约定：`confirmed` 表示插件已经把上游完成接口的响应会话写进了事务 Jar，而不是仅仅看到上游"已确认"状态。多数平台在"手机已确认"之后还需要额外一次兑换请求才会下发正式会话，插件必须在兑换成功后才返回 `confirmed`。`rawStatus` 原样保留上游状态码，方便上游新增状态时安全降级为 `waiting`。

`confirmed` 本身就是“正式凭据已就绪”的唯一协议语义，宿主随后提升事务 Jar。`credentialReady` 只为兼容早期草案而可选：缺失表示遵循最终语义；若提供，其值必须与 state 一致，否则宿主按无效响应拒绝。`uid` 可选，插件能从兑换响应或 Jar 中解析出用户 ID 时填入，供 `PlatformSession.uid` 使用。

当平台在手机确认后返回二次验证信号（例如上游 `error_code = 2046`）时，插件先调用平台的发送短信接口，成功后返回：

```json
{
  "state": "verification_required",
  "rawStatus": 2046,
  "verification": {
    "kind": "sms_code",
    "verificationId": "opaque-plugin-verification-token",
    "prompt": "请输入短信验证码",
    "maskedDestination": "138****0000",
    "codeLength": 6,
    "canResend": true,
    "resendAfterMs": 60000
  }
}
```

`verificationId` 对宿主不透明。`encrypt_uid`、`schema`、`mobile_ticket`、`verify_ways` 等平台字段全部由插件内部保存并映射到该 ID，不能塞进宿主 UI 模型。插件返回该状态前必须已经成功发送首条短信，避免宿主展示一个实际未发送的验证码输入页。

### 4.3 submitLoginChallengeVerification

入参：

```json
{
  "transactionId": "...",
  "challengeId": "...",
  "verificationId": "...",
  "code": "123456"
}
```

验证码正确时返回 `{ "state": "accepted" }`。插件应在内部保存校验接口返回的 ticket，并准备好下一次 poll 所需的 `std_verify_*` 等参数；宿主随即恢复同一 challenge 的 poll。验证码错误时返回：

```json
{
  "state": "rejected",
  "message": "验证码错误",
  "verification": null
}
```

可选的 `verification` 可替换旧描述，例如平台换发了 `verificationId` 或重置了重发等待时间。`accepted` 只表示本次短信验证通过，不表示登录完成；只有随后 poll 返回 `confirmed` 才能提升事务 Cookie。

### 4.4 resendLoginChallengeVerification

只有 verification 描述声明 `canResend = true` 时宿主才展示重发入口，并按 `resendAfterMs` 倒计时。入参不含验证码：

```json
{ "transactionId": "...", "challengeId": "...", "verificationId": "..." }
```

插件重新调用发送短信接口，返回一份新的 verification 描述。若平台不支持重发，返回 `canResend = false`，宿主不调用该函数。

### 4.5 cancelLoginChallenge

入参同 poll，返回 `{ "ok": true }`。插件清理内存中的挑战数据，宿主随后丢弃事务。用户主动取消、超时、切换页面、宿主进入后台超过阈值都会调用它。

## 5. 宿主新增桥能力

以下能力都是通用的，不含任何平台知识。全部实现在 `AngelLiveCore` 的 `JSRuntime` 和一个新的 `LoginTransactionStore` 中。

### 5.1 登录事务与临时 Cookie Jar

```
beginLoginTransaction(pluginId) -> transactionId
promoteLoginTransaction(transactionId) -> cookieHeaderString
discardLoginTransaction(transactionId)
```

- 事务 Jar 是一个内存中的 `HTTPCookieStorage` 实例或等价结构，按 host、domain、path 存储，不落盘，不进入 `HTTPCookieStorage.shared`。
- 响应 Cookie 通过系统 Cookie 解析规则校验 Domain / 公共后缀，并额外执行 `Secure`、`__Secure-`、`__Host-` 前缀约束；非法跨域 Cookie 不进入事务。
- 每个事务有 10 分钟硬超时，到期自动销毁。同一 `pluginId` 同时只允许一个活动事务，新建会先丢弃旧的。
- `promote` 把 Jar 里所有 Cookie 序列化成 `name=value; name=value` 字符串返回给 `PlatformLoginChallengeService`，随即销毁 Jar。序列化时保留全部域的 Cookie，因为现有 `LiveParsePlatformSessionVault` 只认单一 Cookie 字符串。
- 若不同 domain/path 下存在同名但值不同的 Cookie，宿主拒绝提升并销毁事务；在现有扁平凭据模型下不能安全猜测应保留哪一个账号令牌。

### 5.2 Host.http.request 新增选项

```js
Host.http.request({
  url, method, headers, body,
  authMode: "login_transaction",
  transactionId: "...",
  followRedirects: false
})

// 可选：需要把某个事务 Cookie 改写到非 Cookie header 时使用
Host.http.request({
  url, authMode: "login_transaction", transactionId: "...",
  cookieInject: [{
    cookieName: "anonymous_device",
    target: "header",
    headerName: "X-Device-Token"
  }]
})
```

- `authMode: "login_transaction"`：宿主在发送前从事务 Jar 生成 `Cookie` 头。普通目标遵循 Cookie 的 RFC domain/path/secure 作用域；目标属于 manifest 的 `loginFlow.cookieDomains`/`loginURL` 时，宿主还会自动扁平携带事务内没有同名冲突的 Cookie，保证注册域建立的匿名身份在登录域的 create/poll 请求中保持一致，无需插件逐请求声明 `cookieInject`。插件显式传入的非用户 Cookie 仍拥有最高优先级。
- `login_transaction + cookieInject`：保留给需要把指定事务 Cookie 改写到其他 header 的高级场景，不再是跨域 Cookie 连续性的前置条件。事务本身可以先访问 manifest 登录域之外的 HTTPS 匿名注册端点；此时请求正常执行并吸收响应 Cookie，但宿主跳过所有 `cookieInject`。只有目标属于 manifest 登录域白名单时才解析并应用注入值。值始终留在 Swift，既不读取正式账号 vault，也不返回 JavaScript。该模式只允许 header 注入，跨源重定向会移除插件声明的注入 header，随后由宿主按新目标重新计算事务 Cookie。
- 响应中的所有 `Set-Cookie` 都只在 Swift 侧吸收进 Jar；返回给插件的 `headers` 会移除 `Set-Cookie`，`setCookies` 固定为空数组。插件应根据响应状态码和业务响应体判断流程状态。
- 重定向处理：在 `login_transaction` 模式下宿主用 `URLSessionTaskDelegate` 接管重定向，每一跳的 `Set-Cookie` 都先吸收再继续，这样冷启动导航链上的中间 Cookie 不会丢。`followRedirects: false` 则直接把 3xx 和 `Location` 返回给插件，两种方式插件按需选择。
- 普通 `authMode: "none"` 请求仍可按既有协议看到服务端响应头；任何 `login_transaction`、`platform_cookie` 或 `cookieInject` 请求都不向 JS 返回 `Set-Cookie` 值，其响应 `url` 也会移除 userinfo、query 与 fragment，防止 query 注入的凭据通过最终 URL 反射回插件。
- 所有宿主管理凭据的初始请求及每个重定向目标只允许 HTTPS（loopback 调试 HTTP 除外），并按当前响应跳拒绝 HTTPS→HTTP 降级，不能从 loopback HTTP 跳到远端明文 HTTP。跨源跳转会移除插件提供及宿主注入的全部请求头；若 Cookie 被注入 query/body，则直接停止跨源跳转。

### 5.3 事务 Cookie 写入

```js
await Host.session.seedTransactionCookies(
  transactionId,
  { name: value, ... },
  { domain, path, secure }
)
```

- 写入接口用于插件本地生成的匿名设备字段。这类值不是秘密，但也必须进入 Jar 才能在后续请求里稳定复用。
- 插件已经持有本地生成的匿名设备字段时，可以直接 seed 到对应父域；如果值来自被宿主吸收且对 JS 隐藏的 `Set-Cookie`，宿主会在 manifest 登录域之间自动保持该事务身份，插件不应再通过正式账号的 `getCookieHeader` 读取事务值，也不应把 seed 失败静默吞掉。
- 写入接口返回 Promise，只对当前插件拥有的活动事务有效；事务销毁、超时或所有权不匹配时会 reject。
- `Host.session.getCookieHeader(platformId)` 保留为同步接口，供 `createLoginChallenge`/旧 `getQRCode` 等必须在插件内自行签名的登录实现读取当前插件自己的完整 Cookie header；省略 `platformId` 时默认当前插件。请求其他插件只返回空字符串。隔离凭据校验 runtime 返回候选 Cookie，不会误读并发业务 runtime 的已提交凭据。
- 事务 Jar 仍不提供读取接口：`Host.session.getTransactionCookieHeader` 返回 `UNSUPPORTED`。事务响应吸收的 Cookie 由 `login_transaction` 在 manifest 登录域之间自动携带；只有改写到其他 header 时才需要 `cookieInject`。

### 5.4 单飞与缓存

`login_transaction`、`platform_cookie` 和 `cookieInject` 路径强制绕过 URLCache；凭据型请求不会加入插件响应缓存，避免轮询被去重、旧认证响应复用，或敏感响应从匿名调用的日志路径输出。

## 6. 宿主状态机

新增 `@MainActor @Observable PlatformLoginChallengeService`（`AngelLiveCore/Services`），三端 UI 只订阅它的单一枚举状态，不直接调插件。

```
idle
  └─ start(pluginId)
       ├─ beginLoginTransaction
       ├─ call createLoginChallenge
       └─ presenting(qrContent, expiresAt)
            └─ 定时 poll
                 ├─ waiting  → presenting
                 ├─ scanned  → scanned（UI 文案变化，继续 poll）
                 ├─ verification_required
                 │    ├─ awaitingVerification（暂停 poll）
                 │    ├─ rejected → 清空输入并允许重填/重发
                 │    └─ accepted → 恢复同一 challenge 的 poll
                 ├─ expired  → refreshes < max ? 重新 create : failed(expired)
                 ├─ failed   → failed(message)
                 └─ confirmed
                      ├─ promoteLoginTransaction → cookie
                      ├─ PlatformSessionManager.loginWithCookie(validateBeforeSave: true, source: .local)
                      ├─ .valid   → succeeded(CredentialStatus)
                      └─ 其他     → failed(validation)
cancel / timeout / background 超时
  ├─ call cancelLoginChallenge
  └─ discardLoginTransaction → idle
```

实现要点：

- 轮询用单个可取消 `Task`，间隔取 create 响应的 `pollIntervalMs`，缺省取 manifest 值，最小 1000 毫秒。
- 等待用户输入短信验证码也计入同一个 manifest 总 deadline；等待期间不再调用 poll，避免重复触发发送短信或风控接口。提交成功后立即重新 poll，不新建 transaction/challenge。
- 验证码不进入 Core service 的可观察状态、session、Keychain、UserDefaults、缓存或错误文本；它只在三端输入视图的短生命周期本地绑定与一次 submit 调用中存在，视图在调用 service 前立即清空绑定。submit/resend 调用统一标记为 sensitive；开发者控制台只记录宿主生成的白名单状态摘要，不记录验证码、原始入参/返回值或错误正文。
- 视图消失、宿主进入后台超过 60 秒、用户取消都走同一条 cancel 路径。tvOS 上焦点离开登录页视为取消。
- `loginWithCookie` 只有在插件明确返回 `state = valid` 且 Keychain/metadata 持久化成功后才返回成功；旧会话在取消、网络失败、无效响应或存储失败时恢复。`.valid` 是不可逆提交点，昵称补全或 iCloud 失败不会反转成功状态。
- 未确认的候选 Cookie 只进入一次性隔离校验 runtime；它可由该 runtime 的 `Host.session.getCookieHeader` 读取，也可在发往 manifest 允许域名的 `platform_cookie` / `cookieInject` 请求构造时使用，但不会写入共享 vault、JS payload 或 HTTP 返回对象。首页、收藏、播放等缓存 runtime 在校验完成前始终只使用已提交 vault。
- 从事务创建到候选凭据校验共用 manifest 的总 deadline；进入校验时最多再给 30 秒，且等待同插件凭据操作锁的时间也计入该剩余预算。
- 一次挑战从 begin 起租用同一份有效插件版本，create、poll、submit/resend verification、cancel 与 validate 不会在插件更新、pin 切换或 reload 后混入另一版本。租约存续期间缓存清理不会删除对应版本目录，事务终结及清理完成后释放。
- 状态机会刷新 `PlatformCredentialSyncService`，仅在用户已启用 iCloud 同步时调用 `syncAllToICloud()`；Bonjour 仍保留为用户主动触发的局域网同步，不会在扫码成功后自动广播。
- `succeeded` 会先用 poll 返回的 uid 展示；`fetchCredentialStatus` 只做最多 5 秒的 best-effort 昵称补全。
- 自动刷新前必须在短超时内完成旧 challenge 的 cancel；无法确认 cancel 时销毁整笔事务并要求用户重试，避免旧请求迟到污染新二维码。
- `challengeId` 最多 4096 UTF-8 字节；三端扫码页面显式使用 Core Image M 级纠错，`qrContent` 最多 2331 UTF-8 字节，超限会在进入展示状态前拒绝。

## 7. 三端 UI

- **tvOS**：`AccountManagementView` 中，当 `LoginPlatformEntry.loginChallenge` 存在且宿主版本满足时，把"扫码登录"放在手动输入和同步之前。二维码由页面内的原生 M 级生成器渲染；需要短信验证时用 tvOS 系统文本输入收集验证码。过期自动刷新，失败时保留原有手动输入和同步入口。
- **macOS**：新增 `MacPlatformLoginQRSheet`，与 `MacPlatformLoginWebSheet` 并列。`preferOn` 包含 macos 时默认打开扫码，sheet 内提供"改用网页登录"按钮回退。
- **iOS**：`PlatformAccountLoginView` 的 sheet 根据 entry 选择 QR 或 WebView。iPad 遵循 `preferOn`；iPhone 因同机展示二维码不便，默认仍打开 WebView，但显式提供“扫码登录”切换入口。
- 三端共用 `AngelLiveCore` 的挑战状态和状态机；二维码图片生成、布局、焦点与平台生命周期处理留在各宿主的 FullUI，未修改 ShellUI。

## 8. 安全与日志

- 核心不变量：事务 Jar 的 `Set-Cookie` 不通过插件函数入参、HTTP 响应字段或 runtime 通知回传 JavaScript；插件只持有不透明 `transactionId` / `challengeId` 并请求宿主执行 HTTP。唯一显式读取口是受 runtime 插件身份约束的 `Host.session.getCookieHeader`，用于必须由插件自行完成的签名；它不能读取其他插件凭据。二维码登录与 WebView/手动 Cookie 登录遵守同一作用域边界。
- 短信验证码不是 Cookie，必须在用户点击提交后短暂传给插件才能调用平台校验接口；它只允许出现在 sensitive 的 submitVerification 调用内。插件不得保存、打印或把验证码拼进错误信息，宿主提交后立即清空 UI 内存副本。
- 正式、隔离候选及事务 Cookie 的跨域原生注入目标由有效插件 manifest 的 `loginFlow.cookieDomains` 与 `loginURL` host 固定；插件在单次 HTTP 调用中不能临时扩大允许域名。事务 Cookie 对其他目标仍按 RFC domain/path/secure 逐条限制；进入 manifest 登录域时，宿主仅扁平携带值无冲突的当前事务 Cookie。
- 既有弹幕驱动也不再把 Cookie 放进 `createDanmakuSession` payload，只传 `credentialAvailable`。需要认证握手的插件使用 `Host.ws.open({ authMode: "platform_cookie", platformId, ... })`，宿主按同一 manifest 域名白名单把 Cookie 注入 WebSocket 握手；能力由 `Host.capabilities.webSocketPlatformCookie` 标识。
- `LiveParsePluginManager` 对 manifest 自定义的 create/poll/submit/resend/cancel 均显式标记敏感调用；控制台通过函数类型生成白名单摘要，可显示 `state`、`rawStatus`、协议类型、轮询/重发间隔和布尔状态。Debug 构建额外向系统控制台输出脱敏后的完整 HTTP JSON 结构、状态码、URL query 键名、事务短标识，以及最终原生 `URLRequest` 中 Cookie 的名称、长度和不可逆短指纹，用来核对 create/poll 是否实际携带同一份事务 Cookie；Cookie 值、token、认证 header、二维码内容、手机号、uid、验证码及各类 challenge/transaction 标识仍会替换为 `<redacted>`，`Set-Cookie` 也只显示长度和指纹。Release 构建和应用内插件控制台继续使用受限白名单摘要，不记录原始凭据。
- 插件 Promise 超时或取消时，Swift continuation 会一次性释放，JS 全局桥接项会清理；遗留 runtime 永久静默并从 manager 缓存逐实例驱逐，后续调用使用新 runtime，防止迟到 `console.log` 泄密或旧状态干扰重试。
- 插件提供的 HTTP timeout 仅接受有限正数，并被宿主限制为 0.1 至 120 秒；敏感 runtime 被取消或淘汰时，其未完成的登录事务 HTTP 任务也会取消并释放 JS 回调。
- 事务 Jar 不写日志、不进入崩溃上报、不参与 `PluginHomeFeedCacheStore` 等任何缓存。
- 插件侧禁止把挑战数据写入 `console.log`，Authoring Guide 增加对应条款。
- `promote` 之后 Jar 立即销毁，Cookie 字符串只经 `loginWithCookie` 进入 `SessionStore`，路径与 WebView 登录完全一致，不引入第二份持久化副本。
- 自动重定向时，每一跳先吸收作用域匹配的 Cookie；插件显式传入的 Cookie 和其他插件请求头只在同源跳转继续携带，跨源时不会转发。请求与响应均不写 URLCache。

## 9. 兼容矩阵

| 宿主 | 插件 | 行为 |
| --- | --- | --- |
| 旧宿主 | 新插件（含 `loginChallenge`） | 忽略未知字段，走 WebView，tvOS 走手动输入 |
| 新宿主 | 旧插件或未实现扫码的登录插件（无 `loginChallenge`） | 与现在完全一致，只展示原有 WebView/手动输入方式 |
| 新宿主 | 新插件 | 按 `preferOn` 首选扫码，失败可回退 WebView |
| 新宿主 | 插件声明了未知 `kind` 或更高协议版本 | 不展示该入口；保留 WebView/手动输入方式 |

插件在 `createLoginChallenge` 里应先检查 `Host.http` 是否接受 `login_transaction`，宿主通过 `Host.capabilities.loginTransaction === true` 暴露该能力，并通过 `Host.capabilities.loginChallengeProtocol === 2` 暴露当前挑战协议版本。缺失时插件抛 `unsupported` 标准化错误，宿主回退 WebView。

## 10. 插件实现模板

按第 4 节契约，一个平台插件在其 login 脚本中通常按下面的方式落地。具体接口、字段名和安全态步骤由各平台研究文档决定，这里只给结构。

1. `createLoginChallenge`：在事务内完成平台网页端的匿名冷启动。典型步骤包括导航首页吸收 host-scoped Cookie、本地生成匿名设备标识并 seed 进事务 Jar、执行平台要求的安全脚本或风控初始化、激活访客会话、调用创建二维码接口、必要时做一次预轮询或设备画像上报。返回 `qrContent` 和 `challengeId`。
2. `pollLoginChallenge`：调用轮询接口，把上游状态码映射到协议状态。若手机确认后需要短信二次验证，插件先发送验证码，再返回 `verification_required`；否则完成会话兑换后返回 `confirmed`。未知状态码一律映射为 `waiting` 并保留 `rawStatus`。
3. `submitLoginChallengeVerification`：用用户输入的 code 调校验接口，把返回 ticket 保存在 challenge 内存，再返回 `accepted`。下次 poll 带 ticket/`std_verify_*` 继续上游流程。
4. `resendLoginChallengeVerification`：可选重发短信并返回更新后的脱敏提示与倒计时。
5. `cancelLoginChallenge`：清空挑战标识及关联的二次验证临时字段。
6. `validateCredential` 需采用宿主管理凭据语义：入参只读取 `credentialAvailable`，再通过 `authMode: "platform_cookie"`（隔离校验时由同一模式自动使用候选凭据）调用平台校验接口。需要插件内签名时可读取当前 runtime 的 `Host.session.getCookieHeader(pluginId)`；不得期待 `input.credential.cookie` 或 `setCredential` JS 通知。

插件仓库中已有的探测脚本验证了"扫码到手机确认"以及短信验证这一段，缺失的正是把这些步骤收敛进插件函数。插件实现完成后，探测脚本应改为直接调用插件挑战函数，用一个模拟事务 Jar 替代宿主，从而与宿主实现共享同一份状态机测试。

## 11. 实施状态

1. **已完成（宿主 Core）**：manifest 显式能力、事务 Cookie Jar、`login_transaction`、manifest 登录域间自动保持事务 Cookie、重定向接管、事务 seed 接口、仅限当前插件的正式 Cookie getter、事务 Cookie 不可见边界、状态机、最终校验和控制台脱敏。
2. **已完成（宿主 FullUI）**：tvOS、macOS、iOS 扫码入口与现有网页登录/手动 Cookie 回退；ShellUI 不在本次范围内。
3. **已完成（自动化）**：覆盖多 `Set-Cookie`、中间跳、停止/跨源重定向、所有权、超时、提升销毁、缓存绕过、日志脱敏、基础轮询状态、短信验证暂停/拒绝重试/恢复轮询、刷新上限和取消迟到回写。
4. **待插件仓库完成**：Authoring Guide 增加本协议；首个平台插件发布新版本，实现基础函数及所需的短信验证函数并真机验收，不覆盖旧版本；探测脚本改为直接调用插件函数。
5. **后续平台插件**：先完成各自协议研究，确认扫码创建、轮询与兑换接口，再按同一契约实现；宿主无需增加平台专属代码。

## 12. 未决问题

- `LiveParsePlatformSessionVault` 只支持单一 Cookie 字符串，跨域但不同名的 Cookie 在提升后仍会全部带到每个请求上；同名不同值的多 scope Cookie 已明确拒绝提升。首个平台插件验收时必须确认其正式 Cookie 集合适合现有扁平模型，后续如出现必须保留 scope 的平台，应把持久化凭据升级为带 domain/path/secure 的结构化 Jar。
- HTTP/2 连接身份。部分平台的兑换接口对传输层身份一致性敏感。宿主 `URLSession` 在同一进程内会复用连接，预期满足；如果真机验收出现兑换被拒，下一步是为每个事务分配独立 `URLSession` 实例。
- 安全态计算可能需要执行服务端下发的脚本。插件应在受限的 `Function` 作用域内执行，不暴露 `Host` 对象；是否需要宿主提供隔离子 `JSContext`，待首个插件实现时评估。
