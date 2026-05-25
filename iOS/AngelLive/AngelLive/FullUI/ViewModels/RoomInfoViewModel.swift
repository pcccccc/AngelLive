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
    var isHLSStream = false  // 当前是否为 HLS 流（支持 AirPlay 投屏）

    var selectedPlayerKernel: PlayerKernel {
        PlayerKernelSupport.resolvedKernel(for: PlayerSettingModel().playerKernel)
    }

    var usesVLCKernel: Bool {
        selectedPlayerKernel == .vlc4
    }
    
    /// 需要重新取流的清晰度切换任务，用于取消之前的请求
    private var qualitySwitchTask: Task<Void, Never>?

    // MARK: - 受控播放重建状态
    /// 1 分钟内最多自动重建 3 次,超过则停手交给 UI 错误页/下播判定
    private static let maxPlaybackRetries = 3
    private static let playbackRetryWindow: TimeInterval = 60
    private var playbackRetryAttempts = 0
    private var playbackRetryWindowStart: Date?
    private var playbackRetryTask: Task<Void, Never>?

    // 弹幕相关属性
    var socketConnection: WebSocketConnection?
    var httpPollingConnection: HTTPPollingDanmakuConnection?  // HTTP 轮询连接
    var danmuMessages: [ChatMessage] = []
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    var danmuCoordinator = DanmuView.Coordinator() // 屏幕弹幕协调器
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

    // 加载播放地址
    @MainActor
    func loadPlayURL(force: Bool = false) async {
        // 避免重复触发导致接口被频繁调用
        guard !isFetchingPlayURL else { return }
        // 已经加载过且不强制刷新时直接返回
        guard force || !hasLoadedPlayURL else { return }

        isFetchingPlayURL = true
        defer { isFetchingPlayURL = false }

        isLoading = true
        playError = nil
        playErrorMessage = nil
        await getPlayArgs()
    }

    // 获取播放参数
    func getPlayArgs() async {
        isLoading = true
        do {
            guard let platform = SandboxPluginCatalog.platform(for: currentRoom.liveType) else {
                throw LiveParseError.liveParseError("不支持的平台", "\(currentRoom.liveType)")
            }
            let playArgs = try await LiveParseJSPlatformManager.getPlayArgs(platform: platform, roomId: currentRoom.roomId, userId: currentRoom.userId)
            updateCurrentRoomPlayArgs(playArgs)
        } catch {
            await MainActor.run {
                self.isLoading = false
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
            self.playErrorMessage = "暂无可用的播放源"
            return
        }
        self.changePlayUrl(cdnIndex: 0, urlIndex: 0)

        // 已成功获取到播放参数，标记已加载
        hasLoadedPlayURL = true

        // 始终启动弹幕连接（聊天区域需要），showDanmu 仅控制浮动弹幕显示
        getDanmuInfo()
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
            
            // 发射到屏幕弹幕（飞过效果）
            if danmuSettings.showDanmu {
                danmuCoordinator.shoot(
                    text: text,
                    showColorDanmu: danmuSettings.showColorDanmu,
                    color: color,
                    alpha: danmuSettings.danmuAlpha,
                    font: CGFloat(danmuSettings.danmuFontSize)
                )
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

    func webSocketDidReceiveMessage(text: String, nickname: String, color: UInt32) { // 新版本
        Task { @MainActor in
            // 将弹幕消息添加到聊天列表（底部气泡）
            addDanmuMessage(text: text, userName: nickname)

            // 发射到屏幕弹幕（飞过效果）
            if danmuSettings.showDanmu {
                danmuCoordinator.shoot(
                    text: text,
                    showColorDanmu: danmuSettings.showColorDanmu,
                    color: color,
                    alpha: danmuSettings.danmuAlpha,
                    font: CGFloat(danmuSettings.danmuFontSize)
                )
            }
        }
    }
}

// MARK: - KSPlayerLayerDelegate
extension RoomInfoViewModel: KSPlayerLayerDelegate {
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        isPlaying = layer.player.isPlaying
        // 真正起播成功后清空重试预算
        if state == .bufferFinished || state == .readyToPlay {
            resetPlaybackRetryBudget()
        }
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // 播放进度回调
    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        guard let error else { return }
        let errorMsg = error.localizedDescription
        // 因 isLive=false,IO 失败/超时/EOF 都会从这里出来。先尝试受控重建播放器,
        // 而不是依赖 KSPlayer 内部 reconnect(那条路径有解码线程 race,会 EXC_BAD_ACCESS)。
        if isRetryablePlaybackError(errorMsg) {
            if attemptManagedPlaybackRetry(triggeredBy: error) {
                return
            }
            // 重试预算用尽,回落到原有的下播/错误判定
            checkLiveStatusOnError(error: error)
            return
        }
        print("[KSPlayer] suppress finish error UI on iOS: \(errorMsg)")
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

    /// 返回 true 表示已安排了一次重建;false 表示预算已用完。
    @MainActor
    private func attemptManagedPlaybackRetry(triggeredBy error: Error) -> Bool {
        let now = Date()
        if let start = playbackRetryWindowStart,
           now.timeIntervalSince(start) > Self.playbackRetryWindow {
            playbackRetryAttempts = 0
            playbackRetryWindowStart = nil
        }
        guard playbackRetryAttempts < Self.maxPlaybackRetries else {
            logPlaybackRetryBudgetExhausted(triggeredBy: error)
            return false
        }

        if playbackRetryWindowStart == nil {
            playbackRetryWindowStart = now
        }
        playbackRetryAttempts += 1
        let attempt = playbackRetryAttempts
        // 指数退避:1s / 2s / 4s
        let delay = pow(2.0, Double(attempt - 1))
        print("[KSPlayer] managed retry \(attempt)/\(Self.maxPlaybackRetries) in \(delay)s")
        logPlaybackRetryScheduled(attempt: attempt, delay: delay, triggeredBy: error)

        playbackRetryTask?.cancel()
        playbackRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.refreshPlayback()
        }
        return true
    }

    @MainActor
    private func logPlaybackRetryScheduled(attempt: Int, delay: TimeInterval, triggeredBy error: Error) {
        let id = PluginConsoleService.shared.log(tag: "Player", method: "managedRetry#\(attempt)", status: .loading)
        PluginConsoleService.shared.updateRequest(
            id: id,
            body: """
            triggeredBy: \(error.localizedDescription)
            currentURL: \(currentPlayURL?.absoluteString ?? "-")
            attempt: \(attempt) / \(Self.maxPlaybackRetries)
            backoff: \(String(format: "%.1f", delay))s
            """
        )
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: .success,
            responseBody: "已安排在 \(String(format: "%.1f", delay))s 后重建播放器"
        )
    }

    @MainActor
    private func logPlaybackRetryBudgetExhausted(triggeredBy error: Error) {
        let id = PluginConsoleService.shared.log(tag: "Player", method: "managedRetry", status: .loading)
        PluginConsoleService.shared.updateRequest(
            id: id,
            body: """
            triggeredBy: \(error.localizedDescription)
            currentURL: \(currentPlayURL?.absoluteString ?? "-")
            """
        )
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: .error,
            errorMessage: "重试预算已用尽:\(Self.maxPlaybackRetries) 次 / \(Int(Self.playbackRetryWindow))s 窗口"
        )
    }

    @MainActor
    private func resetPlaybackRetryBudget() {
        playbackRetryAttempts = 0
        playbackRetryWindowStart = nil
        playbackRetryTask?.cancel()
        playbackRetryTask = nil
    }

    /// 播放器错误时检查直播状态
    @MainActor
    func checkLiveStatusOnError(error: Error) {
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
}
