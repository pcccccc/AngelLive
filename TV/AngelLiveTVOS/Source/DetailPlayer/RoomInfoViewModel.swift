//
//  RoomInfoStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/2.
//

import Foundation
import Observation
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 播放器显示状态
enum PlayerDisplayState {
    case loading
    case playing
    case error
    case streamerOffline  // 主播已下播
}

private final class LiveFlagTimerHandle: @unchecked Sendable {
    private weak var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    @MainActor
    func invalidate() {
        timer?.invalidate()
    }
}

@Observable
final class RoomInfoViewModel {

    var appViewModel: AppState

    var roomList: [LiveModel] = []
    var currentRoom: LiveModel
    var currentRoomIsLiked = false
    var currentRoomLikeLoading = false

    let settingModel = SettingStore()
    var playerOption: PlayerOptions
    var currentRoomPlayArgs: [LiveQualityModel]?
    var currentPlayURL: URL?
    var currentPlayQualityString = "清晰度"
    var currentPlayQualityQn = 0
    var currentCdnIndex = 0      // 当前选中的线路索引
    var currentQualityIndex = 0  // 当前选中的清晰度索引
    var showControlView: Bool = true
    var isPlaying = false
    var userPaused = false  // 跟踪用户是否手动暂停
    weak var playerCoordinator: KSVideoPlayer.Coordinator?
    private var qualitySwitchTask: Task<Void, Never>?

    // MARK: - 统一播放恢复协调器
    /// 卡顿检测 + 自动恢复的单一状态机,替换原 stall watchdog + managed retry(与 iOS/macOS 共用一份)。
    /// 状态机本体在 AngelLiveCore(可单测);胶水(采样/动作映射)在 AngelLiveDependencies。
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
        // tvOS:起播 12s。stall 监控开启(KSAVPlayer 路径由采样源内部豁免 → 返回 nil)。
        PlaybackRecoveryFactory.make(host: self, config: .desktopTV(stallMonitoringEnabled: true))
    }

    var isLoading = false
    var rotationAngle = 0.0
    var hasError = false
    var errorMessage = ""
    var currentError: Error? = nil
    var displayState: PlayerDisplayState = .loading  // 播放器显示状态

    var debugTimerIsActive = false
    var dynamicInfo: DynamicInfo?
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var socketConnection: WebSocketConnection?
    var httpPollingConnection: HTTPPollingDanmakuConnection?  // HTTP 轮询连接
    var danmuCoordinator = DanmuView.Coordinator()
    let danmuShootScheduler = DanmakuShootScheduler() // §6.2 去突发:把批量弹幕摊开逐条发射
    
    var roomType: LiveRoomListType
    var historyList: [LiveModel]?
    
    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    var lastOptionState: PlayControlFocusableField?
    var showTop = false
    var onceTips = false
    var showDanmuSettingView = false
    var showControl = false {
        didSet {
            if showControl == true {
                controlViewOptionSecond = 5  // 重置计时器
            }
        }
    }
    var showTips = false {
        didSet {
            if showTips == true {
                startTipsTimer()
                onceTips = true
            }
        }
    }
    var controlViewOptionSecond = 5 {
        didSet {
            if controlViewOptionSecond == 5 {
                startTimer()
            }
        }
    }
    var tipOptionSecond = 3
    var contolTimer: Timer? = nil
    var tipsTimer: Timer? = nil
    var liveFlagTimer: Timer? = nil
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    /// 弹幕状态气泡文案;非空即显示,几秒后自动清空
    var danmuStatusHint: String? = nil
    /// 自动隐藏气泡的延迟任务
    private var danmuHintHideTask: Task<Void, Never>? = nil
    /// 是否经历过断开(用于区分"首次连上"与"重连恢复",避免正常进房弹气泡)
    private var danmuHadDisconnected = false
    var supportsDanmu: Bool {
        PlatformCapability.supports(.danmaku, for: currentRoom.liveType)
    }
    
    @MainActor
    init(currentRoom: LiveModel, appViewModel: AppState, enterFromLive: Bool, roomType: LiveRoomListType) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        // 全局默认:HLS 优先 KSAVPlayer,KSMEPlayer 兜底。FLV 流由 RoomPlaybackResolver 在
        // resolvePlan 里覆盖 playerOption.playerTypes 走 KSMEPlayer,不受这里默认影响。
        KSOptions.firstPlayerType = KSAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        let option = PlayerOptions()
        option.userAgent = "libmpv"
        option.syncSystemRate = settingModel.syncSystemRate
        // 强制按 VOD 路径处理 IO 失败/EOF,绕过 KSPlayer 的 MEPlayerItem.reconnect() ——
        // 该路径在重开 AVFormatContext 时不会同步暂停解码线程,会导致解码线程拿到 NULL AVCodecContext
        // 调用 avcodec_send_packet 时崩溃(EXC_BAD_ACCESS at 0x28)。
        // isLive=false 后,所有 IO 异常都通过 .failed/.endOfStream 走到 finish 回调,由我们这层做受控重建。
        option.isLive = false
        self.playerOption = option
        self.currentRoom = currentRoom
        self.appViewModel = appViewModel
        let list = appViewModel.favoriteViewModel.roomList
        self.currentRoomIsLiked = list.contains { $0.roomId == currentRoom.roomId }
        self.roomType = roomType
        getPlayArgs()
    }
    
    /**
     切换清晰度
    */
    @MainActor
    func changePlayUrl(cdnIndex: Int, urlIndex: Int) {
        guard let playArgs = currentRoomPlayArgs, !playArgs.isEmpty,
              cdnIndex < playArgs.count else {
            isLoading = false
            return
        }

        let currentCdn = playArgs[cdnIndex]
        guard urlIndex < currentCdn.qualitys.count else { return }

        // 逻辑会话 = 本次进房(roomId)。同 key 时协调器内部早退,自身的 switchCDN/refresh
        // 不会重置熔断预算;仅首次进房真正复位。
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
            currentPlayQualityString = currentQuality.title
            currentPlayQualityQn = currentQuality.qn
            self.currentCdnIndex = cdnIndex
            self.currentQualityIndex = urlIndex

            // 在 applyPlayURL 之前先决定播放内核，避免首次起播沿用 PlayerOptions 默认 [KSAVPlayer]
            // 导致 FLV 流被 AVPlayer 收到后报 AVError -11850(serverIncorrectlyConfigured) 卡住。
            let resolved = resolvePlayerTypes(quality: currentQuality, cdnIndex: cdnIndex, urlIndex: urlIndex)
            applyPlaybackRequestOptions(for: currentQuality)
            applyResolvedPlayerTypes(resolved.playerTypes)

            applyPlayURL(quality: currentQuality, cdn: currentCdn, debugContext: debugContext)
            return
        }

        let resolved = resolvePlayerTypes(quality: currentQuality, cdnIndex: cdnIndex, urlIndex: urlIndex)
        let effectiveSelection = resolved.resolvedSelection ?? tappedSelection
        let effectiveQuality = effectiveSelection?.quality ?? currentQuality
        let debugContext = RoomPlaybackDebugContext(
            tappedSelection: tappedSelection,
            effectiveSelection: effectiveSelection
        )

        currentPlayQualityString = effectiveQuality.title
        currentPlayQualityQn = effectiveQuality.qn
        self.currentCdnIndex = effectiveSelection?.cdnIndex ?? cdnIndex
        self.currentQualityIndex = effectiveSelection?.qualityIndex ?? urlIndex

        applyPlaybackRequestOptions(for: effectiveQuality)

        applyResolvedPlayerTypes(resolved.playerTypes)

        if let resolvedURL = resolved.overrideURL {
            setPlayURL(resolvedURL, source: "resolved", debugContext: debugContext)
            currentPlayQualityString = resolved.overrideTitle ?? effectiveQuality.title
            isLoading = false
            return
        }

        let effectiveCdn = effectiveSelection.map { playArgs[$0.cdnIndex] } ?? currentCdn
        applyPlayURL(quality: effectiveQuality, cdn: effectiveCdn, debugContext: debugContext)
    }

    private struct PlayerTypeResult {
        let playerTypes: [MediaPlayerProtocol.Type]
        let overrideURL: URL?
        let overrideTitle: String?
        let resolvedSelection: RoomPlaybackSelection?
    }

    private func resolvePlayerTypes(quality: LiveQualityDetail, cdnIndex: Int, urlIndex: Int) -> PlayerTypeResult {
        let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: quality)

        return PlayerTypeResult(
            playerTypes: plan.playerKinds.map(playerType(for:)),
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
    private func applyResolvedPlayerTypes(_ playerTypes: [MediaPlayerProtocol.Type]) {
        guard let first = playerTypes.first else { return }
        let second = playerTypes.dropFirst().first
        applyPlayerTypes(first: first, second: second)
    }

    @MainActor
    private func setPlayURL(
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
                self.recoveryCoordinator.urlChanged(url)
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
        let tappedSummary = RoomPlaybackResolver.debugSelectionSummary(
            in: currentRoomPlayArgs,
            selection: debugContext?.tappedSelection
        )
        let effectiveSummary = RoomPlaybackResolver.debugSelectionSummary(
            in: currentRoomPlayArgs,
            selection: debugContext?.effectiveSelection
        )
        let message = "[PlayerDebug][tvOS][WillPlay] source=\(source), platform=\(currentRoom.liveType.rawValue), roomId=\(currentRoom.roomId), tapped=\(tappedSummary), effective=\(effectiveSummary), finalQuality=\(currentPlayQualityString)(qn=\(currentPlayQualityQn)), players=\(selectedPlayers), url=\(url.absoluteString)"
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

    @MainActor
    private func applyPlayURL(
        quality: LiveQualityDetail,
        cdn: LiveQualityModel,
        debugContext: RoomPlaybackDebugContext
    ) {
        if RoomPlaybackResolver.shouldRefreshPlaybackOnSelection(quality, currentPlayURL: currentPlayURL) {
            fetchRefreshedPlayURL(
                quality: quality,
                cdn: cdn,
                cdnIndex: currentCdnIndex,
                urlIndex: currentQualityIndex,
                debugContext: debugContext
            )
            return
        }

        if let url = RoomPlaybackResolver.playableURL(for: quality) {
            setPlayURL(url, source: "direct", debugContext: debugContext)
        }
        isLoading = false
    }

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
                // 忽略取消的切换任务
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

        currentPlayQualityString = resolved.overrideTitle ?? quality.title
        currentPlayQualityQn = quality.qn
        applyPlaybackRequestOptions(for: quality)
        applyResolvedPlayerTypes(resolved.playerTypes)

        if let resolvedURL = resolved.overrideURL {
            setPlayURL(resolvedURL, source: source, debugContext: debugContext)
        } else if let url = RoomPlaybackResolver.playableURL(for: quality) {
            setPlayURL(url, source: source, debugContext: debugContext)
        }
        isLoading = false
    }
    
    /**
     获取播放参数。
     
     - Returns: 播放清晰度、url等参数
    */
    func getPlayArgs() {
        isLoading = true
        Task {
            do {
                guard let platform = SandboxPluginCatalog.platform(for: currentRoom.liveType) else {
                    throw LiveParseError.liveParseError("不支持的平台", "\(currentRoom.liveType)")
                }
                let playArgs = try await LiveParseJSPlatformManager.getPlayArgs(platform: platform, roomId: currentRoom.roomId, userId: currentRoom.userId)
                await updateCurrentRoomPlayArgs(playArgs)
            }catch {
                await MainActor.run {
                    isLoading = false
                    hasError = true
                    currentError = error
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    @MainActor func updateCurrentRoomPlayArgs(_ playArgs: [LiveQualityModel]) {
        self.currentRoomPlayArgs = playArgs
        if playArgs.count == 0 {
            self.isLoading = false
            showToast(false, title: "获取直播间信息失败")
            return
        }
        self.changePlayUrl(cdnIndex: 0, urlIndex: 0)
        //开一个定时，检查主播是否已经下播
        if appViewModel.playerSettingsViewModel.openExitPlayerViewWhenLiveEnd == true {
            if PlatformHostBehavior.supportsLiveEndPolling(for: currentRoom.liveType) {
                let roomId = currentRoom.roomId
                let userId = currentRoom.userId
                let liveType = currentRoom.liveType
                liveFlagTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(appViewModel.playerSettingsViewModel.openExitPlayerViewWhenLiveEndSecond), repeats: true) { timer in
                    let timerHandle = LiveFlagTimerHandle(timer: timer)
                    Task {
                        do {
                            let state = try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
                            guard state == .close || state == .unknow else { return }
                            await MainActor.run {
                                NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil, userInfo: nil)
                            }
                            await timerHandle.invalidate()
                        } catch {
                            print("检查直播状态失败:\(error)")
                        }
                    }
                }
            }
        }
        
        if appViewModel.danmuSettingsViewModel.showDanmu {
            getDanmuInfo()
        }
    }
    
    @MainActor func setPlayerDelegate(playerCoordinator: KSVideoPlayer.Coordinator) {
        self.playerCoordinator = playerCoordinator
        playerCoordinator.playerLayer?.delegate = nil
        playerCoordinator.playerLayer?.delegate = self
        // 始终让 watchedPlayerLayer 指向当前活跃 layer,供协调器 sample provider 采样。
        watchedPlayerLayer = playerCoordinator.playerLayer
    }

    @MainActor func togglePlayPause() {
        if userPaused {
            playerCoordinator?.playerLayer?.play()
            userPaused = false
        } else {
            playerCoordinator?.playerLayer?.pause()
            userPaused = true
        }
    }

    @MainActor
    private func applyPlayerTypes(first: MediaPlayerProtocol.Type, second: MediaPlayerProtocol.Type?) {
        KSOptions.firstPlayerType = first
        KSOptions.secondPlayerType = second
        if let second {
            playerOption.playerTypes = [first, second]
        } else {
            playerOption.playerTypes = [first]
        }
    }

    /// 按插件返回的播放配置应用 UA / Headers，保证三端行为一致
    private func applyPlaybackRequestOptions(for quality: LiveQualityDetail) {
        let requestOptions = RoomPlaybackResolver.requestOptions(
            for: quality,
            fallbackUserAgent: "libmpv"
        )

        playerOption.userAgent = requestOptions.userAgent
        // 先清理上一次流的头，避免跨平台/跨线路残留
        playerOption.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = nil
        playerOption.formatContextOptions["headers"] = nil

        if !requestOptions.headers.isEmpty {
            playerOption.appendHeader(requestOptions.headers)
        }
    }

    
    func getDanmuInfo() {
        guard supportsDanmu else {
            danmuServerIsConnected = false
            danmuServerIsLoading = false
            return
        }
        if danmuServerIsConnected == true || danmuServerIsLoading == true {
            return
        }
        danmuServerIsLoading = true
        let roomId = currentRoom.roomId
        let userId = currentRoom.userId
        let liveType = currentRoom.liveType
        Task {
            do {
                let danmakuPlan: LiveParseDanmakuPlan
                guard let platform = SandboxPluginCatalog.platform(for: liveType) else {
                    throw NSError(
                        domain: "danmu.platform",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "未找到平台映射：\(liveType.rawValue)"]
                    )
                }
                danmakuPlan = try await LiveParseJSPlatformManager.getDanmakuPlan(
                    platform: platform,
                    roomId: roomId,
                    userId: userId
                )
                await MainActor.run {
                    let parameters = danmakuPlan.legacyParameters

                    if danmakuPlan.prefersHTTPPolling {
                        // 使用 HTTP 轮询连接
                        httpPollingConnection = HTTPPollingDanmakuConnection(
                            parameters: parameters,
                            headers: danmakuPlan.headers,
                            liveType: liveType,
                            pluginId: platform.pluginId,
                            roomId: roomId,
                            userId: userId,
                            danmakuPlan: danmakuPlan
                        )
                        httpPollingConnection?.delegate = self
                        httpPollingConnection?.connect()
                    } else {
                        // 使用 WebSocket 连接
                        socketConnection = WebSocketConnection(
                            parameters: parameters,
                            headers: danmakuPlan.headers,
                            liveType: liveType,
                            pluginId: platform.pluginId,
                            roomId: roomId,
                            userId: userId,
                            danmakuPlan: danmakuPlan
                        )
                        socketConnection?.delegate = self
                        socketConnection?.connect()
                    }
                }
            } catch {
                await MainActor.run {
                    danmuServerIsLoading = false
                }
            }
        }
    }
    
    func disConnectSocket() {
        // 断开 WebSocket
        socketConnection?.delegate = nil
        socketConnection?.disconnect()
        socketConnection = nil

        // 断开 HTTP 轮询
        httpPollingConnection?.delegate = nil
        httpPollingConnection?.disconnect()
        httpPollingConnection = nil

        // §6.2 清空去突发缓冲,避免陈旧弹幕在切房/断流后继续飞出
        Task { @MainActor in danmuShootScheduler.reset() }

        danmuServerIsConnected = false
        danmuServerIsLoading = false
    }

    @MainActor
    func refreshPlayback() {
        if appViewModel.danmuSettingsViewModel.showDanmu {
            disConnectSocket()
        }
        getPlayArgs()
    }

    func stopTimer() {
        timer.upstream.connect().cancel()
        debugTimerIsActive = false
    }
    
    func showToast(_ success: Bool, title: String, hideAfter: TimeInterval? = 1.5) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
        self.toastOptions = SimpleToastOptions(
            alignment: .topLeading, hideAfter: hideAfter
        )
    }
}

extension RoomInfoViewModel: WebSocketConnectionDelegate {
    func webSocketDidReceiveMessage(text: String, nickname: String, color: UInt32) {
        // §6.2 经去突发调度器摊开发射(调度器 @MainActor,故包一层 Task)
        Task { @MainActor in
            let settings = appViewModel.danmuSettingsViewModel
            let showColorDanmu = settings.showColorDanmu
            let alpha = settings.danmuAlpha
            let font = CGFloat(settings.danmuFontSize)
            danmuShootScheduler.enqueue { [danmuCoordinator] in
                danmuCoordinator.shoot(text: text, showColorDanmu: showColorDanmu, color: color, alpha: alpha, font: font)
            }
        }
    }
    
    func webSocketDidConnect() {
        Task { @MainActor in
            danmuServerIsConnected = true
            danmuServerIsLoading = false
            // 首次连上提示"已连接",重连成功提示"已恢复"
            showDanmuHint(danmuHadDisconnected ? "弹幕已恢复" : "弹幕已连接")
            danmuHadDisconnected = false
        }
    }

    func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            danmuServerIsConnected = false
            danmuServerIsLoading = false
            danmuHadDisconnected = true
            if let error {
                showDanmuHint("弹幕连接已断开:\(error.localizedDescription)")
            }
        }
    }

    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int) {
        Task { @MainActor in
            danmuHadDisconnected = true
            showDanmuHint("弹幕断开,正在重连… (\(attempt)/\(maxAttempts))")
        }
    }

    /// 显示左下角气泡并安排自动隐藏(默认 3 秒)。重复调用会重置计时。
    @MainActor
    private func showDanmuHint(_ text: String, autoHideAfter seconds: Double = 3.0) {
        danmuHintHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            danmuStatusHint = text
        }
        danmuHintHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                danmuStatusHint = nil
            }
        }
    }
    
    @MainActor func reloadRoom(liveModel: LiveModel) {
        liveFlagTimer?.invalidate()
        liveFlagTimer = nil
        currentPlayURL = nil
        disConnectSocket()
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        // 同 init:HLS 默认走 KSAVPlayer,ME 兜底;FLV 由 resolvePlan 覆盖。
        KSOptions.firstPlayerType = KSAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        self.currentRoom = liveModel
        getPlayArgs()
    }
}

extension RoomInfoViewModel: KSPlayerLayerDelegate {
    
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        isPlaying = layer.player.isPlaying
        userPaused = !layer.player.isPlaying
        self.dynamicInfo = layer.player.dynamicInfo
        if state == .paused {
            showControlView = true
        }
        if layer.player.isPlaying == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                self.showControlView = false
            })
        }
        
        let currentSelection = RoomPlaybackResolver.selection(
            in: currentRoomPlayArgs,
            cdnIndex: currentCdnIndex,
            qualityIndex: currentQualityIndex
        )
        if let startPosition = currentSelection?.quality.playbackHints?.startPositionSeconds,
           startPosition > 0,
           state == .readyToPlay {
            layer.seek(time: TimeInterval(startPosition), autoPlay: true) { _ in }
        }
        // 状态变化喂给协调器:起播成功/抖动/终态的判定与熔断预算全在状态机内。
        recoveryCoordinator.stateChanged(mapKSPlayerEngineState(state))
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {

    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        guard let error else {
            // 正常结束:通知协调器停止监控。
            recoveryCoordinator.finished(error: nil)
            return
        }
        let errorMsg = error.localizedDescription
        // 因 isLive=false,IO 失败/超时/EOF 都会从这里出来。可重试错误交给协调器阶梯
        // 受控重建;预算用尽时协调器经 reportFailed 回落到下播/错误判定。
        if isRetryablePlaybackError(errorMsg) {
            recoveryCoordinator.finished(error: error)
            return
        }
        Logger.warning("[KSPlayer] suppress finish error UI on tvOS: \(errorMsg)", category: .player)
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
                    hasError = true
                    currentError = error
                    errorMessage = error.localizedDescription
                    displayState = .error
                }
            } catch {
                // 检查状态失败，显示原始错误
                hasError = true
                currentError = error
                errorMessage = error.localizedDescription
                displayState = .error
            }
        }
    }

    /// 选择下一条可用 CDN。仅有 1 条时返回 nil,让上层走 refresh 分支。
    func nextCdnIndex() -> Int? {
        guard let args = currentRoomPlayArgs, args.count > 1 else { return nil }
        return (currentCdnIndex + 1) % args.count
    }

    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {

    }
    
    //控制层timer和顶部提示timer
    func startTimer() {
        contolTimer?.invalidate() // 停止之前的计时器
        contolTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.controlViewOptionSecond > 0 {
                self.controlViewOptionSecond -= 1
            } else {
                self.showControl = false
                if self.onceTips == false {
                    self.showTips = true
                }
                self.contolTimer?.invalidate() // 计时器停止
            }
        }
    }
    
    func startTipsTimer() {
        if onceTips {
            return
        }
        tipsTimer?.invalidate() // 停止之前的计时器
        tipOptionSecond = 3 // 重置计时器

        tipsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.tipOptionSecond > 0 {
                self.tipOptionSecond -= 1
            } else {
                self.showTips = false
                self.tipsTimer?.invalidate() // 计时器停止
            }
        }
    }

}

// MARK: - PlaybackRecoveryHost
extension RoomInfoViewModel: PlaybackRecoveryHost {}
