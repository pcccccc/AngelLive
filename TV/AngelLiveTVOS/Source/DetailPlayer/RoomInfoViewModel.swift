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

    // MARK: - 受控播放重建状态
    /// 1 分钟内最多自动重建 3 次,超过则停手交给 UI 错误页/下播判定
    private static let maxPlaybackRetries = 3
    private static let playbackRetryWindow: TimeInterval = 60
    private var playbackRetryAttempts = 0
    private var playbackRetryWindowStart: Date?
    private var playbackRetryTask: Task<Void, Never>?

    // MARK: - 零吞吐看门狗
    /// 连续 N 秒 bytesRead 和 currentPlaybackTime 都不推进才视为 stall。
    /// 两者并用是为了过滤 KSPlayer 的合法 IO 暂停:loadedTime > maxBufferDuration 时
    /// MEPlayerItem 会 send(.pause) → av_read_pause(),此时 bytesRead 不动但
    /// playhead 仍在消耗缓冲推进,不应误判。直播流缓冲打满也会触发,不限于点播。
    private static let stallThresholdSeconds = 8
    /// 1Hz 采样
    private static let stallWatchdogTick: UInt64 = 1_000_000_000
    /// playhead 推进容差(秒) —— 1Hz 采样下正常播放每秒至少推进 0.5s 才算"在播"
    private static let stallPlayheadProgressTolerance: TimeInterval = 0.5
    private weak var watchedPlayerLayer: KSPlayerLayer?
    private var stallWatchdogTask: Task<Void, Never>?
    private var stallLastBytesRead: Int64 = -1
    private var stallLastPlaybackTime: TimeInterval = -1
    private var stallNoChangeTicks = 0

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
    var supportsDanmu: Bool {
        PlatformCapability.supports(.danmaku, for: currentRoom.liveType)
    }
    
    @MainActor
    init(currentRoom: LiveModel, appViewModel: AppState, enterFromLive: Bool, roomType: LiveRoomListType) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
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
                        let state = try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
                        guard state == .close || state == .unknow else { return }
                        await MainActor.run {
                            NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil, userInfo: nil)
                        }
                        await timerHandle.invalidate()
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
        // URL 变化时上层 .onChange 会重新调到这里,正好用于重启 stall watchdog,
        // 保证 watchedPlayerLayer 始终指向当前活跃的 layer。
        watchedPlayerLayer = playerCoordinator.playerLayer
        restartStallWatchdog()
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
        danmuCoordinator.shoot(text: text, showColorDanmu: appViewModel.danmuSettingsViewModel.showColorDanmu, color: color, alpha: appViewModel.danmuSettingsViewModel.danmuAlpha, font: CGFloat(appViewModel.danmuSettingsViewModel.danmuFontSize))
    }
    
    func webSocketDidConnect() {
        danmuServerIsConnected = true
        danmuServerIsLoading = false
    }
    
    func webSocketDidDisconnect(error: Error?) {
        danmuServerIsConnected = false
        danmuServerIsLoading = false
    }
    
    @MainActor func reloadRoom(liveModel: LiveModel) {
        liveFlagTimer?.invalidate()
        liveFlagTimer = nil
        currentPlayURL = nil
        disConnectSocket()
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
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
        // 真正起播成功后清空重试预算
        if state == .bufferFinished || state == .readyToPlay {
            resetPlaybackRetryBudget()
        }
        // 终态时停掉 watchdog;finish/error 路径由现有 managed retry 接管。
        // .paused 不停,因为用户可能马上恢复,而 tick 内部已通过 shouldWatch 短路了。
        if state == .error || state == .playedToTheEnd {
            stopStallWatchdog()
        }
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {

    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        guard let error else { return }
        // 进入 finish 路径意味着 KSPlayer 已经决定终结当前 session,
        // watchdog 必须先停,避免与 managed retry 在同一窗口内重复触发动作。
        stopStallWatchdog()
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
        print("[KSPlayer] suppress finish error UI on tvOS: \(errorMsg)")
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

    // MARK: - 零吞吐看门狗

    /// 弱网/CDN 边缘"鬼连接"时,KSPlayer 不会冒泡 error,UI 表现为 networkSpeed=0
    /// 但 state 仍停在 .buffering/.readyToPlay。watchdog 每秒采样 bytesRead 和
    /// currentPlaybackTime,两者都不推进 stallThresholdSeconds 秒就触发恢复:
    /// 优先切下一条 CDN,无可切则刷新。
    @MainActor
    private func restartStallWatchdog() {
        stallWatchdogTask?.cancel()
        stallLastBytesRead = -1
        stallLastPlaybackTime = -1
        stallNoChangeTicks = 0
        stallWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.stallWatchdogTick)
                guard let self, !Task.isCancelled else { return }
                self.tickStallWatchdog()
            }
        }
    }

    @MainActor
    private func stopStallWatchdog() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        stallLastBytesRead = -1
        stallLastPlaybackTime = -1
        stallNoChangeTicks = 0
    }

    @MainActor
    private func tickStallWatchdog() {
        guard let layer = watchedPlayerLayer else { return }
        let state = layer.state
        // 不监控 .preparing —— FFmpeg avformat_open_input 期间 pbArray 还未填充,
        // bytesRead 恒为 0,会被误判。真正的 open 卡死由 KSOptions.rw_timeout(默认 9s)
        // 兜底 → 走 finish error → managed retry。
        let shouldWatch: Bool
        switch state {
        case .buffering, .readyToPlay, .bufferFinished:
            shouldWatch = true
        default:
            shouldWatch = false
        }
        let currentBytes = layer.player.dynamicInfo.bytesRead
        let currentTime = layer.player.currentPlaybackTime
        guard shouldWatch else {
            stallNoChangeTicks = 0
            stallLastBytesRead = currentBytes
            stallLastPlaybackTime = currentTime
            return
        }
        if stallLastBytesRead < 0 || stallLastPlaybackTime < 0 {
            // 首次采样,只记录基线
            stallLastBytesRead = currentBytes
            stallLastPlaybackTime = currentTime
            return
        }
        // 任一信号推进都视为"在播":bytes 在流(IO 没死) OR playhead 在跑(在消耗缓冲)。
        // 两者都死才算真 stall。
        let bytesAdvanced = currentBytes > stallLastBytesRead
        let playheadAdvanced = currentTime > stallLastPlaybackTime + Self.stallPlayheadProgressTolerance
        if bytesAdvanced || playheadAdvanced {
            stallNoChangeTicks = 0
            stallLastBytesRead = currentBytes
            stallLastPlaybackTime = currentTime
        } else {
            stallNoChangeTicks += 1
            if stallNoChangeTicks >= Self.stallThresholdSeconds {
                stallNoChangeTicks = 0
                attemptStallRecovery(state: state, bytesRead: currentBytes)
            }
            // 不更新基线,继续对照同一基准。避免被 1-byte 抖动重置计数。
        }
    }

    /// stall 时的恢复升级链:切 CDN → 重拉 playArgs → 错误页
    /// 与 attemptManagedPlaybackRetry 共享重试预算,避免同一窗口内双重重试。
    @MainActor
    private func attemptStallRecovery(state: KSPlayerState, bytesRead: Int64) {
        let now = Date()
        if let start = playbackRetryWindowStart,
           now.timeIntervalSince(start) > Self.playbackRetryWindow {
            playbackRetryAttempts = 0
            playbackRetryWindowStart = nil
        }
        guard playbackRetryAttempts < Self.maxPlaybackRetries else {
            logStallBudgetExhausted(state: state, bytesRead: bytesRead)
            let stallError = NSError(
                domain: "AngelLive.Player.Stall",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey: "零吞吐持续 \(Self.stallThresholdSeconds)s"]
            )
            checkLiveStatusOnError(error: stallError)
            stopStallWatchdog()
            return
        }
        if playbackRetryWindowStart == nil {
            playbackRetryWindowStart = now
        }
        playbackRetryAttempts += 1
        let attempt = playbackRetryAttempts

        // 取消可能已排队的 managed retry,避免叠加。
        playbackRetryTask?.cancel()
        playbackRetryTask = nil

        if let next = nextCdnIndex() {
            logStallRecovery(
                attempt: attempt,
                action: "cdnFailover \(currentCdnIndex)->\(next)",
                state: state,
                bytesRead: bytesRead
            )
            changePlayUrl(cdnIndex: next, urlIndex: 0)
        } else {
            logStallRecovery(
                attempt: attempt,
                action: "refreshPlayback",
                state: state,
                bytesRead: bytesRead
            )
            refreshPlayback()
        }
    }

    /// 选择下一条可用 CDN。仅有 1 条时返回 nil,让上层走 refresh 分支。
    private func nextCdnIndex() -> Int? {
        guard let args = currentRoomPlayArgs, args.count > 1 else { return nil }
        return (currentCdnIndex + 1) % args.count
    }

    @MainActor
    private func logStallRecovery(
        attempt: Int,
        action: String,
        state: KSPlayerState,
        bytesRead: Int64
    ) {
        let id = PluginConsoleService.shared.log(
            tag: "Player",
            method: "stallWatchdog#\(attempt)",
            status: .loading
        )
        let host = currentPlayURL?.host ?? "-"
        PluginConsoleService.shared.updateRequest(
            id: id,
            body: """
            roomId: \(currentRoom.roomId)
            cdnIndex: \(currentCdnIndex)
            host: \(host)
            state: \(state)
            bytesRead: \(bytesRead)
            stallSeconds: \(Self.stallThresholdSeconds)
            attempt: \(attempt) / \(Self.maxPlaybackRetries)
            """
        )
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: .success,
            responseBody: "action=\(action)"
        )
    }

    @MainActor
    private func logStallBudgetExhausted(state: KSPlayerState, bytesRead: Int64) {
        let id = PluginConsoleService.shared.log(
            tag: "Player",
            method: "stallWatchdog",
            status: .loading
        )
        PluginConsoleService.shared.updateRequest(
            id: id,
            body: """
            roomId: \(currentRoom.roomId)
            cdnIndex: \(currentCdnIndex)
            host: \(currentPlayURL?.host ?? "-")
            state: \(state)
            bytesRead: \(bytesRead)
            """
        )
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: .error,
            errorMessage: "stall watchdog 预算用尽:\(Self.maxPlaybackRetries) 次 / \(Int(Self.playbackRetryWindow))s 窗口"
        )
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
