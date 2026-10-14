# 分片字节还原管线

日期：2026-10-14。宿主实现位于 AngelLiveCore 与 AngelLiveDependencies，KSPlayer 源码及依赖版本保持不变。设备播放与实际插件接入仍需独立验收。

## 接入位置

原提案把 `KSOptions.resolveIO` 视为 HLS 分片入口；当前固定版本的这个入口只处理顶层输入，`FormatContext` 的子请求转发没有开放 options hook。因此宿主在 probe 前自行配置 FFmpeg `io_open/io_close2`，再通过公开的 `FormatContext(formatCtx:...)` 和 `KSMEPlayer(...formatContext:)` 注入。无须修改上游仓库。

- Core：严格解码与验证 `LivePlaybackHints.mediaTransform`、纯字节算法、播放路由、插件能力查询和日志脱敏。
- Dependencies：按 HLS 标签识别资源、复用 FFmpeg 原生网络 IO、执行还原、把已准备的上下文交给 KSMEPlayer；稳定的播放器包装对象处理取消、替换、恢复和 delegate 转发。
- 三端 FullUI：既有 session configurator 选择包装播放器；使用 `PlayerOptions` 保存当前资源规则。未声明规则的资源继续走原有播放器选择。

## 插件协议

插件必须在解析播放前确认 `Host.capabilities.mediaTransform >= 1`。Core 单独运行、未注册适配器或 VLC 构建返回 0；三端启动通过 Dependencies 注册 KSPlayer 适配器能力。能力 getter 实时读取，先创建的 JSRuntime 也会看到后续注册。

仅支持 `xorshift32` 和 `targets: ["segment"]`；省略 targets 时默认 segment。非法参数会拒绝本次播放 JSON，不能忽略规则后尝试播放扰码字节。未知的普通提示字段仍保持兼容。

以下是合成测试配置，seed 不对应任何线上资源：

```json
{
  "playbackHints": {
    "streamFormat": "hlsLive",
    "mediaTransform": {
      "targets": ["segment"],
      "scope": {
        "offsetInPeriod": 0,
        "lengthPerPeriod": 16,
        "periodBytes": 188,
        "periodCount": 0
      },
      "keygen": {
        "algorithm": "xorshift32",
        "seed": 305419896,
        "saltBias": 1,
        "saltMultiplier": 2654435769,
        "shiftLeftA": 13,
        "shiftRight": 17,
        "shiftLeftB": 5,
        "zeroState": 1831565813,
        "zeroKeyByte": 165,
        "resetPerPeriod": true
      }
    }
  }
}
```

偏移以每个分片的资源起点计数，周期编号从 0 开始。初始状态为 `seed ^ ((UInt32(periodIndex) &+ saltBias) &* saltMultiplier)`，为 0 时替换成 zeroState；每个目标字节先执行三次移位异或，再取低 8 位，为 0 时使用 zeroKeyByte。所有整数运算按 UInt32 模运算解释。

`periodCount = 0` 覆盖整段，正数只覆盖开头指定数量的周期。`resetPerPeriod = false` 时用第 0 周期初始状态建立连续序列，只有被还原的字节推进状态。随机读取使用跳跃计算定位状态，分块大小不改变结果。zeroState 和 zeroKeyByte 允许为 0。

## 当前支持范围

支持独立 MPEG-TS 分片的 HLS master/media playlist、相对 URI、HTTP 重定向、现有请求头、普通分片读取与 seek。资源角色来自 HLS 标签，不依赖 `.ts` 后缀。每个分片开头还原后检查 TS 同步结构；该检查用于识别容器错误，不是密码学完整性验证。

以下场景显式报错：fMP4/MAP、BYTERANGE、PART/PART-INF/PRELOAD-HINT/SKIP、I-FRAMES-ONLY、DEFINE，以及 METHOD=NONE 以外的标准 HLS 加密。清单最大 4 MiB，超过时拒绝而不截断。音频或字幕等独立非 TS 分片不在当前支持范围。

实时语音字幕目前仍通过具体 `KSMEPlayer` 类型判断能力；组合播放器不满足该条件，会沿既有路径显示“不支持实时字幕”。本次不扩展这条语音识别管线。容器内已有字幕轨继续通过播放器协议转发。

FFmpeg HTTP persistent/multiple 在此管线内关闭，确保后续请求仍经过公开 IO 回调。清单更新替换当前引用图，避免长时间直播累积所有历史分片 URL。取消信号贯穿打开和后续读取；停止及恢复会重建带规则的上下文。包装器禁用 KSMEPlayer 内部直接 URL 重连，保留宿主恢复状态机和原始直播语义。

## 验证与维护

`scripts/generate_media_transform_fixture.py` 使用 ffmpeg 生成合成图案视频，并以独立 Python 实现生成扰码分片。测试资源不含线上媒体、凭证或真实平台映射。

- Core 测试覆盖固定向量、分块、随机偏移、连续状态、整段及有限周期、非法 JSON、强制 ME 路由、日志脱敏和能力协商。
- IO 测试覆盖资源分类、拒绝不支持的标签、短读、SET/CUR/END seek、EOF 和关闭配对。
- FFmpeg 集成测试逐包比较明文与还原后的 24 个视频包，并对照 seek、HTTP 重定向和请求头。
- 包装器测试覆盖每资源配置、选项快照、取消后的旧结果、重开及 delegate 身份。

2026-10-14 使用 Xcode 27.0 RC（27A266a）运行 Core 全量 574 项／72 组、Dependencies 全量 37 项／8 组，测试汇总均通过。原有需要外部资源的 opt-in 测试仍跳过（Core 1 项，Dependencies 2 项），本次媒体还原测试全部执行。后者包含真实 KSMEPlayer 软件解码、播放时间推进和 160×96 解码帧验证，以及 probe 后分片损坏不会被正常 EOF 吞掉的回归测试。测试使用本机 Metal 环境和视频专用无声音频输出；这不代表 iOS/tvOS 设备或真实插件媒体已完成验收。

当前固定的 KSPlayer 会在 `performSeek(time: 0)` 时强制 flags=0；测试必须用明文同参数对照，不能假设 seek 到 0 一定返回第一个 GOP。升级 KSPlayer 时应重新核对注入构造器、opaque 转发、AVIO 关闭顺序及同步播放器协议。

本次不包含具体平台插件发布或外部服务退役。实际插件应自行解析参数并检查宿主能力，再单独完成真实流与设备回归。

### 本轮 workspace 验证状态

最后一次媒体管线源码编辑后的 MCP workspace 构建：`AngelLiveMacOS / My Mac`、`AngelLive / iPhone 17 Pro (27.0)` 与 `AngelLiveTVOS / Apple TV 4K (3rd generation) (27.0)` 均通过，构建错误数为 0。构建期间另一组加载样式改动短暂未完成；待组件落盘后 tvOS 重新构建通过，未覆盖或回滚其他修改。

全仓 tracked 与非忽略 untracked 文件扫描共 797 个文件，内容平台标识与测试数字映射实际命中为 0；同词误报已经人工核对。二进制仅检查可读标识，未做图片 OCR。`git diff --check` 通过。

本轮没有修改页面布局；iOS/tvOS 安装运行、遥控器、PiP 和真实插件媒体未验证，不能由构建或本机合成播放测试代替。
