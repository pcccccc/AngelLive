//
//  RoomInfoViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Foundation
import SwiftUI
import Observation
import CoreMedia
import AngelLiveCore
import AngelLiveDependencies

public class PlayerOptions: KSOptions, @unchecked Sendable {
    public var syncSystemRate: Bool = false

    override public func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
        guard syncSystemRate else { return }
        super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
    }
}

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
    /// 虎牙 User-Agent
    static let huyaUserAgent = "HYSDK(Windows,30000002)_APP(pc_exe&7060000&officia)_SDK(trans&2.32.3.5646)"
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
    var isPlaying = false
    var isHLSStream = false  // 当前是否为 HLS 流（支持 AirPlay 投屏）
    var douyuFirstLoad = true
    var yyFirstLoad = true
    
    /// 斗鱼/YY 清晰度切换任务，用于取消之前的请求
    private var qualitySwitchTask: Task<Void, Never>?

    // 弹幕相关属性
    var socketConnection: WebSocketConnection?
    var httpPollingConnection: HTTPPollingDanmakuConnection?  // HTTP 轮询连接
    var danmuMessages: [ChatMessage] = []
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    var danmuCoordinator = DanmuView.Coordinator() // 屏幕弹幕协调器
    var danmuSettings = DanmuSettingModel() // 弹幕设置模型
    private var shouldReconnectDanmuOnActive = false

    init(room: LiveModel) {
        self.currentRoom = room

        // 初始化播放器选项
        KSOptions.isAutoPlay = true
        // 关闭双路自动重开，避免在弱网/失败时频繁重连导致 stop 循环
        KSOptions.isSecondOpen = false
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        // 根据用户设置启用后台播放
        KSOptions.canBackgroundPlay = PlayerSettingModel().enableBackgroundAudio
        let option = PlayerOptions()
        option.userAgent = "libmpv"
//        option.allowsExternalPlayback = true  //启用 AirPlay 和外部播放
        // 根据用户设置控制自动画中画行为
        option.canStartPictureInPictureAutomaticallyFromInline = PlayerSettingModel().enableAutoPiPOnBackground
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
            guard let platform = LiveParseJSPlatformManager.platform(for: currentRoom.liveType) else {
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
        guard let playArgs = currentRoomPlayArgs else { return nil }
        for item in playArgs {
            for quality in item.qualitys where quality.liveCodeType == .hls {
                return quality
            }
        }
        return nil
    }
    
    /// 在播放参数中查找第一个可用的清晰度
    /// - Returns: 第一个可用的清晰度详情
    private func findFirstQuality() -> LiveQualityDetail? {
        currentRoomPlayArgs?.first?.qualitys.first
    }

    // 切换清晰度
    @MainActor
    func changePlayUrl(cdnIndex: Int, urlIndex: Int) {
        guard let playArgs = currentRoomPlayArgs, !playArgs.isEmpty else {
            isLoading = false
            return
        }

        guard cdnIndex < playArgs.count else {
            return
        }

        let currentCdn = playArgs[cdnIndex]
        
        guard urlIndex < currentCdn.qualitys.count else {
            return
        }

        let currentQuality = currentCdn.qualitys[urlIndex]
        currentPlayQualityString = currentQuality.title
        currentPlayQualityQn = currentQuality.qn
        self.currentCdnIndex = cdnIndex


        // 虎牙特殊处理
        if currentRoom.liveType == .huya {
            self.playerOption.userAgent = PlayerConstants.huyaUserAgent
            self.playerOption.appendHeader([
                "user-agent": PlayerConstants.huyaUserAgent
            ])
        } else {
            self.playerOption.userAgent = PlayerConstants.defaultUserAgent
        }

        // B站/抖音优先使用 HLS（首次加载时）
        if (currentRoom.liveType == .bilibili || currentRoom.liveType == .douyin) && cdnIndex == 0 && urlIndex == 0 {
            if let hlsQuality = findHLSQuality(), let url = URL(string: hlsQuality.url) {
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                self.currentPlayURL = url
                self.currentPlayQualityString = hlsQuality.title
                self.isLoading = false
                self.isHLSStream = true
                return
            } else if currentRoom.liveType == .douyin {
                // 抖音没有 HLS 时使用第一个可用流
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                if let firstQuality = findFirstQuality(), let url = URL(string: firstQuality.url) {
                    self.currentPlayURL = url
                    self.currentPlayQualityString = firstQuality.title
                    self.isLoading = false
                    self.isHLSStream = false
                    return
                }
            } else {
                // B站没有 HLS 时继续走下面的逻辑
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                self.isHLSStream = false
            }
        }
        // 其他平台
        else {
            if currentQuality.liveCodeType == .hls && currentRoom.liveType == .huya && LiveState(rawValue: currentRoom.liveState ?? "unknow") == .video {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                isHLSStream = false
            } else if currentQuality.liveCodeType == .hls {
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                isHLSStream = true
            } else {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                isHLSStream = false
            }
        }

        // 快手特殊处理
        if currentRoom.liveType == .ks {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
            isHLSStream = false
        }

        // 斗鱼特殊处理
        if currentRoom.liveType == .douyu && douyuFirstLoad == false {
            // 取消之前的请求，避免快速切换时产生多个并发请求
            qualitySwitchTask?.cancel()
            
            isLoading = true
            qualitySwitchTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    // 安全访问数组
                    guard let playArgs = await MainActor.run(body: { self.currentRoomPlayArgs }),
                          cdnIndex < playArgs.count else {
                        await MainActor.run { self.isLoading = false }
                        return
                    }
                    let cdn = playArgs[cdnIndex]
                    guard urlIndex < cdn.qualitys.count else {
                        await MainActor.run { self.isLoading = false }
                        return
                    }
                    let quality = cdn.qualitys[urlIndex]
                    
                    // 检查是否已取消
                    try Task.checkCancellation()
                    
                    let newPlayArgs = try await LiveParseJSPlatformManager.getPlayArgsWithQuality(platform: .douyu, roomId: currentRoom.roomId, userId: nil, quality: ["rate": quality.qn, "cdn": cdn.douyuCdnName ?? ""])
                    
                    // 再次检查是否已取消
                    try Task.checkCancellation()
                    
                    await MainActor.run {
                        if let newQuality = newPlayArgs.first?.qualitys.first,
                           let url = URL(string: newQuality.url) {
                            self.currentPlayURL = url
                        }
                        self.isLoading = false
                    }
                } catch is CancellationError {
                    // 任务被取消，不做处理
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        } else {
            douyuFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                self.currentPlayURL = url
            }
        }

        // YY 特殊处理
        if currentRoom.liveType == .yy && yyFirstLoad == false {
            // 取消之前的请求
            qualitySwitchTask?.cancel()
            
            isLoading = true
            qualitySwitchTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    // 安全访问数组
                    guard let playArgs = await MainActor.run(body: { self.currentRoomPlayArgs }),
                          cdnIndex < playArgs.count else {
                        await MainActor.run { self.isLoading = false }
                        return
                    }
                    let cdn = playArgs[cdnIndex]
                    guard urlIndex < cdn.qualitys.count else {
                        await MainActor.run { self.isLoading = false }
                        return
                    }
                    let quality = cdn.qualitys[urlIndex]
                    
                    // 检查是否已取消
                    try Task.checkCancellation()
                    
                    let newPlayArgs = try await LiveParseJSPlatformManager.getPlayArgsWithQuality(platform: .yy, roomId: currentRoom.roomId, userId: nil, quality: ["lineSeq": Int(cdn.yyLineSeq ?? "-1") ?? -1, "gear": quality.qn])
                    
                    // 再次检查是否已取消
                    try Task.checkCancellation()
                    
                    await MainActor.run {
                        if let newQuality = newPlayArgs.first?.qualitys.first,
                           let url = URL(string: newQuality.url) {
                            self.currentPlayURL = url
                        }
                        self.isLoading = false
                    }
                } catch is CancellationError {
                    // 任务被取消，不做处理
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        } else {
            yyFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                self.currentPlayURL = url
            }
        }

        // 只有非异步请求的平台才在这里设置 isLoading = false
        // 斗鱼和YY平台会在各自的异步任务中管理 isLoading
        if currentRoom.liveType != .douyu && currentRoom.liveType != .yy {
            self.isLoading = false
        } else if currentRoom.liveType == .douyu && douyuFirstLoad {
            self.isLoading = false
        } else if currentRoom.liveType == .yy && yyFirstLoad {
            self.isLoading = false
        }
    }

    @MainActor
    func setPlayerDelegate(playerCoordinator: KSVideoPlayer.Coordinator) {
        playerCoordinator.playerLayer?.delegate = nil
        playerCoordinator.playerLayer?.delegate = self
    }

    // MARK: - 弹幕相关方法

    /// 检查平台是否支持弹幕
    func platformSupportsDanmu() -> Bool {
        switch currentRoom.liveType {
        case .bilibili, .huya, .douyin, .douyu, .soop, .cc:
            return true
        case .ks, .yy:
            return false
        }
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

            var danmuArgs: ([String : String], [String : String]?) = ([:],[:])
            do {
                switch currentRoom.liveType {
                case .bilibili, .huya, .douyin, .douyu, .soop:
                    guard let platform = LiveParseJSPlatformManager.platform(for: currentRoom.liveType) else { return }
                    danmuArgs = try await LiveParseJSPlatformManager.getDanmukuArgs(platform: platform, roomId: currentRoom.roomId, userId: currentRoom.userId)
                case .ks, .cc:  // 快手、网易CC平台弹幕
                    guard let platform = LiveParseJSPlatformManager.platform(for: currentRoom.liveType) else { return }
                    danmuArgs = try await LiveParseJSPlatformManager.getDanmukuArgs(platform: platform, roomId: currentRoom.roomId, userId: currentRoom.userId)
                default:
                    await MainActor.run {
                        danmuServerIsLoading = false
                    }
                    return
                }

                await MainActor.run {
                    // 判断弹幕类型
                    let danmuType = danmuArgs.0["_danmu_type"] ?? "websocket"

                    if danmuType == "http_polling" {
                        // 使用 HTTP 轮询连接
                        httpPollingConnection = HTTPPollingDanmakuConnection(
                            parameters: danmuArgs.0,
                            headers: danmuArgs.1,
                            liveType: currentRoom.liveType
                        )
                        httpPollingConnection?.delegate = self
                        httpPollingConnection?.connect()
                    } else {
                        // 使用 WebSocket 连接
                        socketConnection = WebSocketConnection(
                            parameters: danmuArgs.0,
                            headers: danmuArgs.1,
                            liveType: currentRoom.liveType
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
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // 播放进度回调
    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        if let error = error {
            let errorMsg = error.localizedDescription
            // 检测流断开相关错误，可能是主播下播
            if errorMsg.contains("avformat can't open input") || errorMsg.contains("timed out") || errorMsg.contains("Operation timed out") {
                checkLiveStatusOnError(error: error)
            } else {
                playError = error
                playErrorMessage = errorMsg
                displayState = .error
            }
        }
    }

    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        // 缓冲回调
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
