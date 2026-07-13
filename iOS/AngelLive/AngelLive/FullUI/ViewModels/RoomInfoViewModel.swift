//
//  RoomInfoViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

/// 播放器显示状态
enum PlayerDisplayState {
    case loading
    case playing
    case error
    case streamerOffline  // 主播已下播
}

// MARK: - 播放器常量配置
private enum PlayerConstants {
    /// 弹幕消息最大数量限制
    static let maxDanmuMessageCount = 100
    /// 默认 User-Agent
    static let defaultUserAgent = "libmpv"
}

@Observable
final class RoomInfoViewModel {
    var currentRoom: LiveModel
    var currentPlayURL: URL?
    var isLoading = false
    var playError: Error?
    var playErrorMessage: String?
    var displayState: PlayerDisplayState = .loading  // 播放器显示状态
    /// 防止并发/重复请求播放地址
    private var isFetchingPlayURL = false
    /// 是否已成功加载过当前房间的播放地址
    private var hasLoadedPlayURL = false

    // 播放器相关属性
    var playerOption: PlayerOptions
    var currentRoomPlayArgs: [LiveQualityModel]?
    var currentPlayQualityString = "清晰度"
    var currentPlayQualityQn = 0
    var currentCdnIndex = 0  // 当前选中的线路索引
    var currentQualityIndex = 0  // 当前选中的清晰度索引
    var isPlaying = false
    /// KSPlayer 真实播放状态(来自 VM 抢到的 delegate)。
    /// PlayerContainerView 的 `playerCoordinator.state` 因 delegate 被抢已冻结不可信,
    /// UI 的缓冲/加载判定应读这里。
    private(set) var engineState: PlaybackEngineState = .initialized
    var isHLSStream = false  // 当前是否为 HLS 流（支持 AirPlay 投屏）

    var selectedPlayerKernel: PlayerKernel {
        PlayerKernelSupport.resolvedKernel(for: PlayerSettingModel().playerKernel)
    }

    var usesVLCKernel: Bool {
        selectedPlayerKernel == .vlc4
    }
    
    /// 需要重新取流的清晰度切换任务，用于取消之前的请求
    private var qualitySwitchTask: Task<Void, Never>?

    // MARK: - 统一播放恢复协调器
    /// 卡顿检测 + 自动恢复的单一状态机,替换原 stall watchdog + managed retry(修 Bug A/B)。
    /// 状态机本体在 AngelLiveCore(可单测);这里只做事件发射、动作映射与采样。
    /// 当前监视的 playerLayer,供 sample provider 读取 KSPlayer dynamicInfo。
    weak var watchedPlayerLayer: KSPlayerLayer?
    @ObservationIgnored private var _recoveryCoordinator: PlaybackRecoveryCoordinator?

    /// 懒构造(协调器 init 为 @MainActor;@Observable 不支持 lazy 存储属性,故手写)。
    @MainActor
    var recoveryCoordinator: PlaybackRecoveryCoordinator {
        if let c = _recoveryCoordinator { return c }
        let c = makeRecoveryCoordinator()
        _recoveryCoordinator = c
        return c
    }

    @MainActor
    private func makeRecoveryCoordinator() -> PlaybackRecoveryCoordinator {
        // KSAVPlayer / VLC 路径有清晰 .failed 走 fallback,关 stall 监控避免误判;
        // 起播超时仍由协调器按会话记次。动作映射与采样统一在 AngelLiveDependencies 的共享工厂。
        let config = RecoveryConfig.phone(stallMonitoringEnabled: !usesVLCKernel)
        return PlaybackRecoveryFactory.make(host: self, config: config)
    }

    /// KSPlayerState(8 case)→ 协调器抽象状态(转发共享映射,保留旧调用点命名)。
    private func mapEngineState(_ state: KSPlayerState) -> PlaybackEngineState {
        mapKSPlayerEngineState(state)
    }

    // 弹幕相关属性
    var socketConnection: WebSocketConnection?
    var httpPollingConnection: HTTPPollingDanmakuConnection?  // HTTP 轮询连接
    var danmuMessages: [ChatMessage] = []
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    var danmuCoordinator = DanmuView.Coordinator() // 屏幕弹幕协调器
    let danmuShootScheduler = DanmakuShootScheduler() // §6.2 去突发:把批量弹幕摊开逐条发射
    var danmuSettings = DanmuSettingModel() // 弹幕设置模型
    private var shouldReconnectDanmuOnActive = false
    var supportsDanmu: Bool {
        PlatformCapability.supports(.danmaku, for: currentRoom.liveType)
    }

    init(room: LiveModel) {
        self.currentRoom = room

        // 初始化播放器选项
        KSOptions.isAutoPlay = true
        // 关闭双路自动重开，避免在弱网/失败时频繁重连导致 stop 循环
        KSOptions.isSecondOpen = false
        // 根据用户设置启用后台播放
        KSOptions.canBackgroundPlay = PlayerSettingModel().enableBackgroundAudio
        let option = PlayerOptions()
        option.userAgent = "libmpv"
//        option.allowsExternalPlayback = true  //启用 AirPlay 和外部播放
        // 根据用户设置控制自动画中画行为
        option.canStartPictureInPictureAutomaticallyFromInline = PlayerSettingModel().enableAutoPiPOnBackground
        // 强制按 VOD 路径处理 IO 失败/EOF,绕过 KSPlayer 的 MEPlayerItem.reconnect() ——
        // 该路径在重开 AVFormatContext 时不会同步暂停解码线程,会导致解码线程拿到 NULL AVCodecContext
        // 调用 avcodec_send_packet 时崩溃(EXC_BAD_ACCESS at 0x28)。
        // isLive=false 后,所有 IO 异常都通过 .failed/.endOfStream 走到 finish 回调,由我们这层做受控重建。
        option.isLive = false
        self.playerOption = option
    }

    /// 恢复协调器是否正在自动续播(重新取参/切源)。用于静默刷新,避免全屏错误页打断。
    @MainActor
    private var isPlaybackRecovering: Bool {
        if case .recovering = recoveryCoordinator.phase { return true }
        return false
    }

    // 加载播放地址
    @MainActor
    func loadPlayURL(force: Bool = false) async {
        // 避免重复触发导致接口被频繁调用
        guard !isFetchingPlayURL else { return }
        // 已经加载过且不强制刷新时直接返回
        guard force || !hasLoadedPlayURL else { return }

        isFetchingPlayURL = true
        defer { isFetchingPlayURL = false }

        // 已在播时的强制刷新(含恢复阶梯 reloadPlayArgs):静默取新 URL,不全屏 loading/清错误态抢 UI
        let silentRefresh = force && hasLoadedPlayURL && currentPlayURL != nil
        if !silentRefresh {
            isLoading = true
            playError = nil
            playErrorMessage = nil
        }
        await getPlayArgs(silent: silentRefresh)
    }

    // 获取播放参数
    func getPlayArgs(silent: Bool = false) async {
        if !silent {
            isLoading = true
        }
        do {
            guard let platform = SandboxPluginCatalog.platform(for: currentRoom.liveType) else {
                throw LiveParseError.liveParseError("不支持的平台", "\(currentRoom.liveType)")
            }
            let playArgs = try await LiveParseJSPlatformManager.getPlayArgs(platform: platform, roomId: currentRoom.roomId, userId: currentRoom.userId)
            await MainActor.run {
                self.updateCurrentRoomPlayArgs(playArgs)
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                // 恢复过程中取参失败:交给协调器继续阶梯,不立刻进错误页
                if silent || self.isPlaybackRecovering {
                    Logger.warning("[PlayerFlow] silent getPlayArgs failed: \(error.localizedDescription)", category: .player)
                    return
                }
                self.playError = error
                self.playErrorMessage = "获取播放地址失败"
            }
        }
    }

    @MainActor
    func updateCurrentRoomPlayArgs(_ playArgs: [LiveQualityModel]) {
        self.currentRoomPlayArgs = playArgs
        if playArgs.count == 0 {
            self.isLoading = false
            if !isPlaybackRecovering {
                self.playErrorMessage = "暂无可用的播放源"
            }
            return
        }

        // 重新取参后尽量保持当前线路/清晰度,避免无感续播跳回默认档
        let clamped = RoomPlaybackResolver.clampedSelection(
            in: playArgs,
            preferredCdnIndex: currentCdnIndex,
            preferredQualityIndex: currentQualityIndex
        )
        let firstLoad = !hasLoadedPlayURL
        self.changePlayUrl(cdnIndex: clamped.cdnIndex, urlIndex: clamped.qualityIndex)

        // 已成功获取到播放参数，标记已加载
        hasLoadedPlayURL = true

        // 仅首次进房拉弹幕;续播重取参数不重连弹幕,避免聊天区闪断
        if firstLoad {
            getDanmuInfo()
        }
    }
    
    // MARK: - HLS 流查找辅助方法
    
    /// 在播放参数中查找 HLS 流
    /// - Returns: 找到的 HLS 清晰度详情，如果没有则返回 nil
    private func findHLSQuality() -> LiveQualityDetail? {
        RoomPlaybackResolver.findHLSQuality(in: currentRoomPlayArgs)
    }
    
    /// 在播放参数中查找第一个可用的清晰度
    /// - Returns: 第一个可用的清晰度详情
    private func findFirstQuality() -> LiveQualityDetail? {
        RoomPlaybackResolver.findFirstQuality(in: currentRoomPlayArgs)
    }

    /// 按插件返回的播放配置应用 UA / Headers，保证三端行为一致
    private func applyPlaybackRequestOptions(for quality: LiveQualityDetail) {
        let requestOptions = RoomPlaybackResolver.requestOptions(
            for: quality,
            fallbackUserAgent: PlayerConstants.defaultUserAgent
        )

        playerOption.userAgent = requestOptions.userAgent
        // 先清理上一次流的头，避免跨平台/跨线路残留
        playerOption.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = nil
        playerOption.formatContextOptions["headers"] = nil

        if !requestOptions.headers.isEmpty {
            playerOption.appendHeader(requestOptions.headers)
        }
    }

    // 切换清晰度
    @MainActor
    func changePlayUrl(cdnIndex: Int, urlIndex: Int) {
        guard let playArgs = currentRoomPlayArgs, !playArgs.isEmpty,
              cdnIndex < playArgs.count else {
            isLoading = false
            return
        }

        let currentCdn = playArgs[cdnIndex]
        guard urlIndex < currentCdn.qualitys.count else { return }

        // 逻辑会话 = 本次进房(roomId)。同 key 时 applyEpisode 早退,
        // 故协调器自身的 switchCDN/refreshSameURL/reloadPlayArgs 不会重置熔断预算;
        // 仅首次进房真正复位,重进房间为新 VM+新协调器。
        recoveryCoordinator.episodeChanged(streamKey: currentRoom.roomId)

        let tappedSelection = RoomPlaybackResolver.selection(
            in: playArgs,
            cdnIndex: cdnIndex,
            qualityIndex: urlIndex
        )
        let currentQuality = currentCdn.qualitys[urlIndex]
        if RoomPlaybackResolver.requiresRefreshOnSelect(currentQuality) {
            let debugContext = RoomPlaybackDebugContext(
                tappedSelection: tappedSelection,
                effectiveSelection: tappedSelection
            )
            currentPlayQualityString = RoomPlaybackResolver.qualityDisplayTitle(
                in: playArgs,
                selection: tappedSelection
            )
            currentPlayQualityQn = currentQuality.qn
            self.currentCdnIndex = cdnIndex
            self.currentQualityIndex = urlIndex

            // 在 applyPlayURL 之前先决定播放内核，避免首次起播沿用 PlayerOptions 默认 [KSAVPlayer]
            // 导致 FLV 流被 AVPlayer 收到后报 AVError -11850(serverIncorrectlyConfigured) 卡住。
            let resolved = resolvePlayerTypes(quality: currentQuality, cdnIndex: cdnIndex, urlIndex: urlIndex)
            applyPlaybackRequestOptions(for: currentQuality)
            playerOption.playerTypes = resolved.playerTypes
            isHLSStream = resolved.isHLS

            applyPlayURL(
                quality: currentQuality,
                cdn: currentCdn,
                cdnIndex: cdnIndex,
                urlIndex: urlIndex,
                debugContext: debugContext
            )
            return
        }

        let resolved = resolvePlayerTypes(quality: currentQuality, cdnIndex: cdnIndex, urlIndex: urlIndex)
        let effectiveSelection = resolved.resolvedSelection ?? tappedSelection
        let effectiveQuality = effectiveSelection?.quality ?? currentQuality
        let effectiveDisplayTitle = RoomPlaybackResolver.qualityDisplayTitle(
            in: playArgs,
            selection: effectiveSelection ?? tappedSelection
        )
        let debugContext = RoomPlaybackDebugContext(
            tappedSelection: tappedSelection,
            effectiveSelection: effectiveSelection
        )

        currentPlayQualityString = effectiveDisplayTitle
        currentPlayQualityQn = effectiveQuality.qn
        self.currentCdnIndex = effectiveSelection?.cdnIndex ?? cdnIndex
        self.currentQualityIndex = effectiveSelection?.qualityIndex ?? urlIndex

        applyPlaybackRequestOptions(for: effectiveQuality)

        // 1. 决定播放器类型
        playerOption.playerTypes = resolved.playerTypes
        isHLSStream = resolved.isHLS

        // 如果已经通过 HLS 查找确定了播放地址，直接返回
        if let resolvedURL = resolved.overrideURL {
            currentPlayQualityString = resolved.overrideTitle ?? effectiveDisplayTitle
            assignCurrentPlayURL(resolvedURL, source: "resolved", debugContext: debugContext)
            isLoading = false
            return
        }

        // 2. 设置播放地址（部分平台需要异步重新请求）
        let effectiveCdn = effectiveSelection.map { playArgs[$0.cdnIndex] } ?? currentCdn
        applyPlayURL(
            quality: effectiveQuality,
            cdn: effectiveCdn,
            cdnIndex: self.currentCdnIndex,
            urlIndex: self.currentQualityIndex,
            debugContext: debugContext
        )
    }

    // MARK: - 播放器类型决策

    private struct PlayerTypeResult {
        let playerTypes: [MediaPlayerProtocol.Type]
        let isHLS: Bool
        /// 某些分支会直接确定播放地址（如 HLS 资源查找）
        var overrideURL: URL?
        var overrideTitle: String?
        var resolvedSelection: RoomPlaybackSelection?
    }

    private func resolvePlayerTypes(quality: LiveQualityDetail, cdnIndex: Int, urlIndex: Int) -> PlayerTypeResult {
        let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: quality)

        return PlayerTypeResult(
            playerTypes: plan.playerKinds.map(playerType(for:)),
            isHLS: plan.isHLS,
            overrideURL: plan.overrideURL,
            overrideTitle: plan.overrideTitle,
            resolvedSelection: plan.resolvedSelection
        )
    }

    private func playerType(for kind: RoomPlaybackPlayerKind) -> MediaPlayerProtocol.Type {
        switch kind {
        case .avPlayer:
            KSAVPlayer.self
        case .mePlayer:
            KSMEPlayer.self
        }
    }

    @MainActor
    private func assignCurrentPlayURL(
        _ url: URL,
        source: String,
        debugContext: RoomPlaybackDebugContext? = nil
    ) {
        logSelectedStreamBeforePlayback(url, source: source, debugContext: debugContext)
        if currentPlayURL == url {
            currentPlayURL = nil
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.currentPlayURL == nil else { return }
                self.currentPlayURL = url
            }
            return
        }

        currentPlayURL = url
        // token 滚动等 URL 变化:仅更新协调器记录,不重置起播计时/熔断(修 Bug A)。
        recoveryCoordinator.urlChanged(url)
    }

    @MainActor
    private func logSelectedStreamBeforePlayback(
        _ url: URL,
        source: String,
        debugContext: RoomPlaybackDebugContext?
    ) {
        let playerNames = playerOption.playerTypes.map { playerTypeName(for: $0) }
        let selectedPlayers = playerNames.isEmpty ? "未设置" : playerNames.joined(separator: ",")
        let fallbackSelection = RoomPlaybackResolver.selection(
            in: currentRoomPlayArgs,
            cdnIndex: currentCdnIndex,
            qualityIndex: currentQualityIndex
        )
        let tappedSummary = RoomPlaybackResolver.debugSelectionSummary(
            in: currentRoomPlayArgs,
            selection: debugContext?.tappedSelection
        )
        let effectiveSummary = RoomPlaybackResolver.debugSelectionSummary(
            in: currentRoomPlayArgs,
            selection: debugContext?.effectiveSelection ?? fallbackSelection
        )
        let message = "[PlayerDebug][iOS][WillPlay] source=\(source), platform=\(currentRoom.liveType.rawValue), roomId=\(currentRoom.roomId), tapped=\(tappedSummary), effective=\(effectiveSummary), finalQuality=\(currentPlayQualityString)(qn=\(currentPlayQualityQn)), players=\(selectedPlayers), url=\(url.absoluteString)"
        Logger.debug(message, category: .player)
        BugsnagBootstrap.setLiveContext(platform: currentRoom.liveType.rawValue, roomID: currentRoom.roomId)
        BugsnagBootstrap.setPlayerKernel(selectedPlayers)
    }

    private func playerTypeName(for playerType: MediaPlayerProtocol.Type) -> String {
        let name = String(describing: playerType)
        return name
            .replacingOccurrences(of: "AngelLiveDependencies.", with: "")
            .replacingOccurrences(of: "KSPlayer.", with: "")
    }

    // MARK: - 播放地址设置

    private func applyPlayURL(
        quality: LiveQualityDetail,
        cdn: LiveQualityModel,
        cdnIndex: Int,
        urlIndex: Int,
        debugContext: RoomPlaybackDebugContext
    ) {
        if RoomPlaybackResolver.shouldRefreshPlaybackOnSelection(quality, currentPlayURL: currentPlayURL) {
            fetchRefreshedPlayURL(
                quality: quality,
                cdn: cdn,
                cdnIndex: cdnIndex,
                urlIndex: urlIndex,
                debugContext: debugContext
            )
            return
        }

        // 通用：直接使用资源侧返回的 URL。
        if let url = RoomPlaybackResolver.playableURL(for: quality) {
            assignCurrentPlayURL(url, source: "direct", debugContext: debugContext)
        }
        isLoading = false
    }

    /// 异步请求新的播放地址（资源声明需要重新取流时使用）
    private func fetchRefreshedPlayURL(
        quality: LiveQualityDetail,
        cdn: LiveQualityModel,
        cdnIndex: Int,
        urlIndex: Int,
        debugContext: RoomPlaybackDebugContext
    ) {
        guard let parsePlatform = SandboxPluginCatalog.platform(for: currentRoom.liveType) else {
            isLoading = false
            return
        }
        qualitySwitchTask?.cancel()
        isLoading = true

        let roomId = currentRoom.roomId
        qualitySwitchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let preparedQuality = try await RoomPlaybackPreparer.prepare(
                    roomId: roomId,
                    cdn: cdn,
                    quality: quality,
                    plugin: parsePlatform
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.applyPreparedPlayURL(
                        preparedQuality,
                        cdnIndex: cdnIndex,
                        urlIndex: urlIndex,
                        source: "refreshPlayback",
                        debugContext: debugContext
                    )
                }
            } catch is CancellationError {
                // 任务被取消，不做处理
            } catch {
                await MainActor.run {
                    self.applyPreparedPlayURL(
                        quality,
                        cdnIndex: cdnIndex,
                        urlIndex: urlIndex,
                        source: "direct-fallback",
                        debugContext: debugContext
                    )
                }
            }
        }
    }

    @MainActor
    private func applyPreparedPlayURL(
        _ quality: LiveQualityDetail,
        cdnIndex: Int,
        urlIndex: Int,
        source: String,
        debugContext: RoomPlaybackDebugContext
    ) {
        let resolved = resolvePlayerTypes(quality: quality, cdnIndex: cdnIndex, urlIndex: urlIndex)
        let displayTitle = RoomPlaybackResolver.qualityDisplayTitle(quality, in: currentRoomPlayArgs)

        currentPlayQualityString = resolved.overrideTitle ?? displayTitle
        currentPlayQualityQn = quality.qn
        applyPlaybackRequestOptions(for: quality)
        playerOption.playerTypes = resolved.playerTypes
        isHLSStream = resolved.isHLS

        if let resolvedURL = resolved.overrideURL {
            assignCurrentPlayURL(resolvedURL, source: source, debugContext: debugContext)
        } else if let url = RoomPlaybackResolver.playableURL(for: quality) {
            assignCurrentPlayURL(url, source: source, debugContext: debugContext)
        }
        isLoading = false
    }

    @MainActor
    func setPlayerDelegate(playerCoordinator: KSVideoPlayer.Coordinator) {
        guard !usesVLCKernel else { return }
        playerCoordinator.playerLayer?.delegate = nil
        playerCoordinator.playerLayer?.delegate = self
        // 始终让 watchedPlayerLayer 指向当前活跃 layer,供协调器 sample provider 采样。
        // VLC 内核时 dynamicInfo 不归 KSPlayer 管,上面 guard 已跳过。
        watchedPlayerLayer = playerCoordinator.playerLayer
    }

    // MARK: - 弹幕相关方法

    /// 检查平台是否支持弹幕
    func platformSupportsDanmu() -> Bool {
        supportsDanmu
    }

    /// 添加系统消息到聊天列表
    @MainActor
    func addSystemMessage(_ message: String) {
        let systemMsg = ChatMessage(
            userName: "系统",
            message: message,
            isSystemMessage: true
        )
        appendDanmuMessage(systemMsg)
    }

    /// 获取弹幕连接信息并连接
    func getDanmuInfo() {
        // 检查平台是否支持弹幕
        if !platformSupportsDanmu() {
            Task { @MainActor in
                addSystemMessage("当前平台不支持查看弹幕/评论")
            }
            return
        }

        if danmuServerIsConnected == true || danmuServerIsLoading == true {
            return
        }

        Task {
            danmuServerIsLoading = true

            // 添加连接中消息
            await MainActor.run {
                addSystemMessage("正在连接弹幕服务器...")
            }

            var danmakuPlan = LiveParseDanmakuPlan(args: [:], headers: [:])
            do {
                guard let platform = SandboxPluginCatalog.platform(for: currentRoom.liveType) else {
                    throw NSError(
                        domain: "danmu.platform",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "未找到平台映射：\(currentRoom.liveType.rawValue)"]
                    )
                }
                danmakuPlan = try await LiveParseJSPlatformManager.getDanmakuPlan(
                    platform: platform,
                    roomId: currentRoom.roomId,
                    userId: currentRoom.userId
                )

                await MainActor.run {
                    let parameters = danmakuPlan.legacyParameters

                    if danmakuPlan.prefersHTTPPolling {
                        // 使用 HTTP 轮询连接
                        httpPollingConnection = HTTPPollingDanmakuConnection(
                            parameters: parameters,
                            headers: danmakuPlan.headers,
                            liveType: currentRoom.liveType,
                            pluginId: platform.pluginId,
                            roomId: currentRoom.roomId,
                            userId: currentRoom.userId,
                            danmakuPlan: danmakuPlan
                        )
                        httpPollingConnection?.delegate = self
                        httpPollingConnection?.connect()
                    } else {
                        // 使用 WebSocket 连接
                        socketConnection = WebSocketConnection(
                            parameters: parameters,
                            headers: danmakuPlan.headers,
                            liveType: currentRoom.liveType,
                            pluginId: platform.pluginId,
                            roomId: currentRoom.roomId,
                            userId: currentRoom.userId,
                            danmakuPlan: danmakuPlan
                        )
                        socketConnection?.delegate = self
                        socketConnection?.connect()
                    }
                }
            } catch {
                Logger.error(error, message: "获取弹幕连接失败", category: .danmu)
                await MainActor.run {
                    danmuServerIsLoading = false
                    addSystemMessage("连接弹幕服务器失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 断开弹幕连接
    @MainActor
    func disconnectSocket() {
        // 断开 WebSocket
        socketConnection?.delegate = nil
        socketConnection?.disconnect()
        socketConnection = nil

        // 断开 HTTP 轮询
        httpPollingConnection?.delegate = nil
        httpPollingConnection?.disconnect()
        httpPollingConnection = nil

        // §6.2 清空去突发缓冲,避免陈旧弹幕在切房/断流后继续飞出
        danmuShootScheduler.reset()

        danmuServerIsConnected = false
        danmuServerIsLoading = false
    }

    /// 进入后台时暂停弹幕更新，避免后台 UI 更新触发崩溃
    @MainActor
    func pauseDanmuUpdatesForBackground() {
        // 只在首次进入后台时记录状态，避免 inactive → background 两次调用覆盖
        if !shouldReconnectDanmuOnActive {
            shouldReconnectDanmuOnActive = danmuServerIsConnected || danmuServerIsLoading
        }
        Logger.debug("进入后台，断开弹幕连接，shouldReconnect: \(shouldReconnectDanmuOnActive)", category: .danmu)
        disconnectSocket()
    }

    /// 回到前台时恢复弹幕连接（如果之前连接过）
    @MainActor
    func resumeDanmuUpdatesIfNeeded() {
        Logger.debug("回到前台，shouldReconnect: \(shouldReconnectDanmuOnActive)", category: .danmu)
        guard shouldReconnectDanmuOnActive else { return }
        shouldReconnectDanmuOnActive = false
        getDanmuInfo()
    }

    /// 刷新当前播放流
    @MainActor
    func refreshPlayback() {
        Task {
            await loadPlayURL(force: true)
        }
    }

    /// 「自动画中画」开关切换时,同步武装/拆除 PiP 控制器。
    ///
    /// 根因:`KSComplexPlayerLayer` 只在 `readyToPlay` 且当时选项已 true 时预建 `pipController`。
    /// 在播放中(readyToPlay 已过)才打开开关 → `pipController` 仍为 nil → 首次进后台 `pipStart()` 走
    /// else 分支:新建控制器后**延迟 0.3s 再 start**,而此刻 App 已进后台、start 失败;控制器虽建好,
    /// 要等第二次进后台才走即时 start 分支 →「推出进来推出进来才生效」。
    ///
    /// 开:提前把控制器建好(与 readyToPlay 完全一致的 configPIP + delegate),首次进后台即即时 start。
    /// 关:若 PiP 未在进行,拆掉控制器,避免残留武装态(防「关不掉」)。幂等。
    @MainActor
    func setAutoPiPArmed(_ armed: Bool) {
        #if canImport(KSPlayer)
        guard let layer = watchedPlayerLayer as? KSComplexPlayerLayer else {
            Logger.debug("[PlayerFlow] PiP arm skip: no KSComplexPlayerLayer (armed=\(armed))", category: .player)
            return
        }
        if armed {
            guard layer.player.pipController == nil else { return }   // 已就绪,幂等
            layer.player.configPIP()
            // delegate 便捷属性跨模块不可见,用公开的 setValue(等价 KSPlayer 内部 `delegate = self`)。
            layer.player.pipController?.setValue(layer, forKey: "delegate")
            Logger.debug("[PlayerFlow] PiP controller armed (toggle on)", category: .player)
        } else {
            guard !layer.isPictureInPictureActive else { return }     // 正在 PiP 不拆,交给 enterForeground
            layer.player.pipController = nil
            Logger.debug("[PlayerFlow] PiP controller torn down (toggle off)", category: .player)
        }
        #endif
    }

    /// 切换弹幕显示状态
    @MainActor
    func toggleDanmuDisplay() {
        guard supportsDanmu else { return }
        setDanmuDisplay(!danmuSettings.showDanmu)
    }

    /// 设置弹幕显示状态（仅控制浮动弹幕，不影响聊天区域）
    @MainActor
    func setDanmuDisplay(_ enabled: Bool) {
        guard enabled != danmuSettings.showDanmu else { return }
        danmuSettings.showDanmu = enabled
        if enabled {
            danmuCoordinator.play()
        } else {
            danmuCoordinator.clear()
        }
        // 注意：不断开 WebSocket，让底部聊天区域继续接收消息
    }

    /// 添加弹幕消息到聊天列表
    @MainActor
    func addDanmuMessage(text: String, userName: String = "观众") {
        let message = ChatMessage(
            userName: userName,
            message: text
        )
        appendDanmuMessage(message)
    }
    
    /// 统一的消息追加方法，自动管理消息数量
    /// 优化：在追加前检查容量，避免数组频繁扩容和移除操作
    @MainActor
    private func appendDanmuMessage(_ message: ChatMessage) {
        // 如果已满，先移除最旧的消息
        if danmuMessages.count >= PlayerConstants.maxDanmuMessageCount {
            danmuMessages.removeFirst()
        }
        danmuMessages.append(message)
    }
}

// MARK: - WebSocketConnectionDelegate
extension RoomInfoViewModel: WebSocketConnectionDelegate {
    func webSocketDidReceiveMessage(text: String, color: UInt32) { //旧版本
        Task { @MainActor in
            // 将弹幕消息添加到聊天列表（底部气泡）
            addDanmuMessage(text: text, userName: "")
            
            // 发射到屏幕弹幕（飞过效果）— §6.2 经去突发调度器摊开发射
            if danmuSettings.showDanmu {
                let showColorDanmu = danmuSettings.showColorDanmu
                let alpha = danmuSettings.danmuAlpha
                let font = CGFloat(danmuSettings.danmuFontSize)
                danmuShootScheduler.enqueue { [danmuCoordinator] in
                    danmuCoordinator.shoot(text: text, showColorDanmu: showColorDanmu, color: color, alpha: alpha, font: font)
                }
            }
        }
    }

    func webSocketDidConnect() {
        Task { @MainActor in
            danmuServerIsConnected = true
            danmuServerIsLoading = false
            addSystemMessage("弹幕服务器连接成功")
            Logger.info("弹幕服务已连接", category: .danmu)
        }
    }

    func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            danmuServerIsConnected = false
            danmuServerIsLoading = false
            if let error = error {
                addSystemMessage("弹幕服务器已断开：\(error.localizedDescription)")
                Logger.error(error, message: "弹幕服务断开", category: .danmu)
            }
        }
    }

    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int) {
        Task { @MainActor in
            // 仅首次重连提示一次，避免聊天区被多次重试刷屏
            guard attempt == 1 else { return }
            addSystemMessage("弹幕连接断开，正在尝试重连…")
        }
    }

    func webSocketDidReceiveMessage(text: String, nickname: String, color: UInt32) { // 新版本
        Task { @MainActor in
            // 将弹幕消息添加到聊天列表（底部气泡）
            addDanmuMessage(text: text, userName: nickname)

            // 发射到屏幕弹幕（飞过效果）— §6.2 经去突发调度器摊开发射
            if danmuSettings.showDanmu {
                let showColorDanmu = danmuSettings.showColorDanmu
                let alpha = danmuSettings.danmuAlpha
                let font = CGFloat(danmuSettings.danmuFontSize)
                danmuShootScheduler.enqueue { [danmuCoordinator] in
                    danmuCoordinator.shoot(text: text, showColorDanmu: showColorDanmu, color: color, alpha: alpha, font: font)
                }
            }
        }
    }
}

// MARK: - KSPlayerLayerDelegate
extension RoomInfoViewModel: KSPlayerLayerDelegate {
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        isPlaying = layer.player.isPlaying
        let engine = mapEngineState(state)
        engineState = engine   // 发布真实状态供 UI 判缓冲/加载(取代冻结的 playerCoordinator.state)
        // 状态变化喂给协调器:起播成功/抖动/终态的判定与熔断预算全在状态机内。
        recoveryCoordinator.stateChanged(engine)

        // 播放器就绪后重设一次系统媒体中心(Now Playing)信息。
        // NowPlayingManager.update 是媒体中心内容的唯一来源(房间标题/主播/平台/封面);
        // 而 KSComplexPlayerLayer 只会清空它:set(resource) 置 nil(VideoPlayerView:80)、
        // .initialized 置 nil(KSPlayerLayer:656)。这些清空与 DetailPlayerView.onAppear 里同步执行的
        // update 抢同一个全局字典,而清空多发生在异步起播链路(loadPlayURL→resource→init)之后,
        // 会把 onAppear 写的信息抹掉 → 媒体中心有概率变空。
        // readyToPlay 是所有清空动作之后的稳定时点(此后至下次重建不再清空),在此补写一次即可确保
        // 我们的信息最后落地;恢复协调器每次重建也会重新走到 readyToPlay,自动补回被清空的信息。
        if state == .readyToPlay {
            NowPlayingManager.update(room: currentRoom, isPlaying: layer.player.isPlaying)
        }
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // 播放进度回调
    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        // isLive=false 时直播 CDN 会话结束常走 endOfStream → finish(nil)/playedToTheEnd。
        // 直播没有「播完」语义,已起播后的结束一律交给协调器判定恢复(见 Coordinator startedPlaying)。
        guard let error else {
            Logger.warning("========== 🔴 [EOF-RECOVER] 检测到直播流结束(EOF)→ 无感续签重取地址续播 · host=\(currentPlayURL?.host ?? "-") ==========", category: .player)
            recoveryCoordinator.finished(error: nil)
            return
        }
        let errorMsg = error.localizedDescription
        // 可重试错误交给协调器阶梯受控重建,而不是依赖 KSPlayer 内部 reconnect(那条路径有解码线程
        // race,会 EXC_BAD_ACCESS)。预算用尽时协调器会经 reportFailed 回落到下播/错误判定。
        if isRetryablePlaybackError(errorMsg) {
            Logger.warning("========== 🔴 [EOF-RECOVER] 播放中断(可重试)→ 无感续签重取地址续播 · reason=\(errorMsg) ==========", category: .player)
            recoveryCoordinator.finished(error: error)
            return
        }
        Logger.warning("[KSPlayer] suppress finish error UI on iOS: \(errorMsg)", category: .player)
    }

    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        // 缓冲回调
    }

    // MARK: - 受控播放重建

    private func isRetryablePlaybackError(_ message: String) -> Bool {
        message.contains("avformat can't open input")
            || message.contains("timed out")
            || message.contains("Operation timed out")
            || message.contains("End of file")
            || message.contains("readFrame")
            || message.contains("I/O error")
    }

    /// 播放器错误时检查直播状态
    @MainActor
    func checkLiveStatusOnError(error: Error) {
        // 恢复阶梯未结束时不进错误页,避免无感续播被打断
        if isPlaybackRecovering { return }
        Task {
            do {
                let state = try await ApiManager.getCurrentRoomLiveState(
                    roomId: currentRoom.roomId,
                    userId: currentRoom.userId,
                    liveType: currentRoom.liveType
                )
                if state == .close || state == .unknow {
                    // 主播已下播
                    displayState = .streamerOffline
                } else {
                    // 仍在直播但连接失败，显示错误
                    playError = error
                    playErrorMessage = error.localizedDescription
                    displayState = .error
                }
            } catch {
                // 检查状态失败，显示原始错误
                playError = error
                playErrorMessage = error.localizedDescription
                displayState = .error
            }
        }
    }

    /// 选择下一条可用 CDN。仅有 1 条时返回 nil,让上层走 refresh 分支。
    func nextCdnIndex() -> Int? {
        guard let args = currentRoomPlayArgs, args.count > 1 else { return nil }
        return (currentCdnIndex + 1) % args.count
    }

}

// MARK: - PlaybackRecoveryHost
// watchedPlayerLayer / currentCdnIndex / currentQualityIndex / changePlayUrl /
// refreshPlayback / nextCdnIndex / checkLiveStatusOnError 均已具备,直接 conform。
extension RoomInfoViewModel: PlaybackRecoveryHost {}
