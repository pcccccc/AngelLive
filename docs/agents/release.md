# 发布渠道、版本与上传规则

**触发条件：查询发布版本、维护发布规则或技能、上传或发布。** 按根 [AGENTS.md](../../AGENTS.md) 的顺序在相关操作前读取；本流程与根指南同等效力，不能绕过根文件红线。未特别说明的路径均相对仓库根目录。

本文件是 AngelLive 渠道矩阵、版本/Build、产物和签名约束的唯一来源；个人 `angellive-release` Skill 负责查询与执行流程，不能替代或另存一份矩阵。根指南始终约束授权、代码模式和验收。

2026-10-25 用户确认以下发布矩阵。名称以仓库中实际存在的 scheme 为准；TestFlight（TF）、App Store 和 macOS 独立分发分别准备产物，不把某一渠道的版本号直接覆盖到其他渠道。表中的 TF 版本是起始基线，后续发布按下述版本选择流程更新，不能永久锁定为该版本。

| 渠道 | 平台 | Scheme | Archive 配置 | 营销版本 | Build |
| --- | --- | --- | --- | --- | --- |
| TestFlight | iOS | `AngelLive` | `Release` | `3.0.0` | `1` |
| TestFlight | tvOS | `AngelLiveTVOS-SimpleLive` | `Release-SimpleLive` | `2.0.0` | `1` |
| App Store | iOS | `AngelLive` | `Release` | `2.x.x`，每次发布确定具体值 | `1` |
| App Store | macOS | `AngelLiveMacOS-AppStore` | `Release` | `2.x.x`，每次发布确定具体值 | 动态递增 |
| App Store | tvOS | `AngelLiveTVOS` | `Release` | `2.x.x`，每次发布确定具体值 | `1` |
| DMG / Sparkle | macOS | `AngelLiveMacOS` | `Release` | `2.x.x`，每次发布确定具体值 | 动态递增 |

- **必读与范围**：版本查询、规则维护及发布前必须读取 `$angellive-release`（未发现则读个人技能目录的 `angellive-release/SKILL.md`）；本文件保留项目约束，操作步骤按技能执行。维护规则不启动发布、不催要版本或凭据；仅查询不改版本、不构建上传。
- **版本与 Build**：实际发布先查各渠道线上状态及本地配置，再让用户选择具体主/次/补丁版本；已指定则直接核验，确认前不改版本或构建上传。各渠道独立，TF 表值仅为起始基线，`2.x.x` 须落实为具体版本；App Store/DMG 默认维持该系列，用户选择主版本升级时更新约定。固定 Build `1` 冲突先核对是否本轮同一产物，不重传或静默改号；macOS 按各渠道已上传/发布、待发布、本地及 Sparkle `sparkle:version` 取更大 Build，不重置或强行统一。
- **产物隔离**：TF 覆盖 iOS、tvOS SimpleLive；App Store 覆盖 iOS、macOS 商店版、tvOS 正式版。按矩阵分别归档到独立目录，核对实际产物的 Bundle ID、版本、Build 与 ASC 应用，不凭显示名选择；tvOS 宿主与 Top Shelf 版本/Build 一致。
- **渠道工具与签名**：ASC 查询/上传/发布统一用 `asc`，构建导出走根 workspace。macOS 商店包不得含 Sparkle；DMG 用 `AngelLiveMacOS`，按 `macOS/Distribution/DMG/README.md` 完成 Developer ID 签名、公证、staple 及版本/Build/架构/签名校验。认证与私钥仅存钥匙串或仓库外受限位置。
- **DMG / Sparkle**：用 `gh` 核对当前远端、tag、附件后上传 GitHub Release，不覆盖同名已发布附件。以匹配公钥的私钥签署最终 DMG，更新根 `appcast.xml` 的下载 URL、字节长度、签名、营销版本与 Build；附件可下载且 feed 已发布后才声明自动更新可用。
- **状态与证据**：上传、处理、TF 分发、提审、上架、feed 生效分别记录，按授权范围执行；仅上传不自动分发/提审/上架，结果不确定先查询再决定重试。日志、校验、本次回执及 Build ID 保存在忽略的 `build/` 或 `runs/`，逐渠道报告成功/失败/阻塞。本文件取代旧发布约定，FullUI/ShellUI、构建和验收门禁仍有效。
