//
//  RoomInfoStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/2.
//

import Foundation
import Observation
import CoreMedia
import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

public class PlayerOptions: KSOptions, @unchecked Sendable {
  public var syncSystemRate: Bool = false

//  override public func sei(string: String) {
//      
//  }
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
    var currentPlayQualityQn = 0 //当前清晰度，虎牙用来存放回放时间
    var showControlView: Bool = true
    var isPlaying = false
    var userPaused = false  // 跟踪用户是否手动暂停
    weak var playerCoordinator: KSVideoPlayer.Coordinator?
    var douyuFirstLoad = true
    var yyFirstLoad = true

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
    
    @MainActor
    init(currentRoom: LiveModel, appViewModel: AppState, enterFromLive: Bool, roomType: LiveRoomListType) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        KSOptions.firstPlayerType = KSAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        let option = PlayerOptions()
        option.userAgent = "libmpv"
        option.syncSystemRate = settingModel.syncSystemRate
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
        guard currentRoomPlayArgs != nil else {
            isLoading = false
            return
        }
        
        if cdnIndex >= currentRoomPlayArgs?.count ?? 0 {
            return
        }

        guard let currentCdn = currentRoomPlayArgs?[cdnIndex] else {
            return
        }
        
        if urlIndex >= currentCdn.qualitys.count {
            return
        }
        
        let currentQuality = currentCdn.qualitys[urlIndex]
        currentPlayQualityString = currentQuality.title
        currentPlayQualityQn = currentQuality.qn
        
        if currentRoom.liveType == .huya {
            self.playerOption.userAgent = "HYSDK(Windows,30000002)_APP(pc_exe&7060000&officia)_SDK(trans&2.32.3.5646)"
            self.playerOption.appendHeader([
                "user-agent": "HYSDK(Windows,30000002)_APP(pc_exe&7060000&officia)_SDK(trans&2.32.3.5646)"
            ])
        }else {
            self.playerOption.userAgent = "libmpv"
            self.playerOption.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = nil
            self.playerOption.formatContextOptions["headers"] = nil
        }
        
        
        if currentRoom.liveType == .bilibili && cdnIndex == 0 && urlIndex == 0 { // bilibili 优先 HLS 播放
            for item in currentRoomPlayArgs! {
                for liveQuality in item.qualitys {
                    let urlString = liveQuality.url.lowercased()
                    let isHls = liveQuality.liveCodeType == .hls || urlString.contains(".m3u8")
                    if isHls {
                        applyPlayerTypes(first: KSAVPlayer.self, second: nil)
                        if let url = URL(string: liveQuality.url) {
                            setPlayURL(url)
                        }
                        currentPlayQualityString = liveQuality.title
                        return
                    }
                }
            } 
            if self.currentPlayURL == nil {
                applyPlayerTypes(first: KSMEPlayer.self, second: nil)
            }
        }else if (currentRoom.liveType == .douyin) { //douyin 优先HLS播放
            applyPlayerTypes(first: KSMEPlayer.self, second: nil)
            if cdnIndex == 0 && urlIndex == 0 {
                for item in currentRoomPlayArgs! {
                    for liveQuality in item.qualitys {
                        let urlString = liveQuality.url.lowercased()
                        let isHls = liveQuality.liveCodeType == .hls || urlString.contains(".m3u8")
                        if isHls {
                            applyPlayerTypes(first: KSAVPlayer.self, second: nil)
                            if let url = URL(string: liveQuality.url) {
                                setPlayURL(url)
                            }
                            currentPlayQualityString = liveQuality.title
                            return
                        }else {
                            applyPlayerTypes(first: KSMEPlayer.self, second: nil)
                            if let url = URL(string: liveQuality.url) {
                                setPlayURL(url)
                            }
                            currentPlayQualityString = liveQuality.title
                            return
                        }
                    }
                }
            }
        } else {
            let urlString = currentQuality.url.lowercased()
            let isHls = currentQuality.liveCodeType == .hls || urlString.contains(".m3u8")
            if isHls && currentRoom.liveType == .huya && LiveState(rawValue: currentRoom.liveState ?? "unknow") == .video {
                applyPlayerTypes(first: KSMEPlayer.self, second: nil)
            }else if isHls {
                applyPlayerTypes(first: KSAVPlayer.self, second: nil)
            }else {
                applyPlayerTypes(first: KSMEPlayer.self, second: nil)
            }
        }
        
        if currentRoom.liveType == .ks {
            applyPlayerTypes(first: KSMEPlayer.self, second: nil)
        }
        
        if currentRoom.liveType == .douyu && douyuFirstLoad == false {
            Task {
                let currentCdn = currentRoomPlayArgs![cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                let playArgs = try await LiveParseJSPlatformManager.getPlayArgsWithQuality(platform: .douyu, roomId: currentRoom.roomId, userId: nil, quality: ["rate": currentQuality.qn, "cdn": currentCdn.douyuCdnName ?? ""])
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    if let urlString = currentQuality?.url ?? lastCurrentPlayURL?.absoluteString,
                       let url = URL(string: urlString) {
                        self.setPlayURL(url)
                    }
                }
            }
        }else {
            douyuFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                setPlayURL(url)
            }            
        }
        
        if currentRoom.liveType == .yy && yyFirstLoad == false {
            Task {
                guard var playArgs = currentRoomPlayArgs,
                      cdnIndex < playArgs.count else { return }
                let currentCdn = playArgs[cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                playArgs = try await LiveParseJSPlatformManager.getPlayArgsWithQuality(platform: .yy, roomId: currentRoom.roomId, userId: nil, quality: ["lineSeq": Int(currentCdn.yyLineSeq ?? "-1") ?? -1, "gear": currentQuality.qn])
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    if let urlString = currentQuality?.url ?? lastCurrentPlayURL?.absoluteString,
                       let url = URL(string: urlString) {
                        self.setPlayURL(url)
                    }
                }
            }
        }else {
            yyFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                setPlayURL(url)
            }
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
                guard let platform = LiveParseJSPlatformManager.platform(for: currentRoom.liveType) else {
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
            if currentRoom.liveType != .ks {
                let roomId = currentRoom.roomId
                let userId = currentRoom.userId
                let liveType = currentRoom.liveType
                liveFlagTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(appViewModel.playerSettingsViewModel.openExitPlayerViewWhenLiveEndSecond), repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let state = try await ApiManager.getCurrentRoomLiveState(roomId: roomId, userId: userId, liveType: liveType)
                        if state == .close || state == .unknow {
                            NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil, userInfo: nil)
                            self.liveFlagTimer?.invalidate()
                            self.liveFlagTimer = nil
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
    
    func getDanmuInfo() {
        if danmuServerIsConnected == true || danmuServerIsLoading == true {
            return
        }
        danmuServerIsLoading = true
        let roomId = currentRoom.roomId
        let userId = currentRoom.userId
        let liveType = currentRoom.liveType
        Task {
            do {
                let danmuArgs: ([String : String], [String : String]?)
                switch liveType {
                    case .bilibili, .huya, .douyin, .douyu, .soop:
                        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else { return }
                        danmuArgs = try await LiveParseJSPlatformManager.getDanmukuArgs(platform: platform, roomId: roomId, userId: userId)
                    case .ks:  // 快手平台弹幕
                        guard let platform = LiveParseJSPlatformManager.platform(for: liveType) else { return }
                        danmuArgs = try await LiveParseJSPlatformManager.getDanmukuArgs(platform: platform, roomId: roomId, userId: userId)
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
                            liveType: liveType
                        )
                        httpPollingConnection?.delegate = self
                        httpPollingConnection?.connect()
                    } else {
                        // 使用 WebSocket 连接
                        socketConnection = WebSocketConnection(
                            parameters: danmuArgs.0,
                            headers: danmuArgs.1,
                            liveType: liveType
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

    @MainActor
    private func setPlayURL(_ url: URL) {
        if currentPlayURL == url {
            // 强制刷新同一 URL，避免播放器忽略相同地址的更新
            currentPlayURL = nil
            Task { @MainActor in
                await Task.yield()
                self.currentPlayURL = url
            }
        } else {
            currentPlayURL = url
        }
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
        douyuFirstLoad = true
        yyFirstLoad = true
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
        
        if currentRoom.liveType == .huya && LiveState(rawValue: currentRoom.liveState ?? "0") == .video && state == .readyToPlay {
            layer.seek(time: TimeInterval(currentPlayQualityQn), autoPlay: true) { _ in
                
            }
        }
    }
    
    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        
    }
    
    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        if let error = error {
            let errorMsg = error.localizedDescription
            // 检测流断开相关错误，可能是主播下播
            if errorMsg.contains("avformat can't open input") || errorMsg.contains("timed out") || errorMsg.contains("Operation timed out") {
                checkLiveStatusOnError(error: error)
            } else {
                hasError = true
                currentError = error
                errorMessage = errorMsg
                displayState = .error
            }
        }
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
