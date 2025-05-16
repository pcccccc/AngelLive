//
//  RoomInfoStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/2.
//

import Foundation
import KSPlayer
import LiveParse
import SimpleToast
import Observation
import CoreMedia

public class PlayerOptions: KSOptions {
  public var syncSystemRate: Bool = false

  override public func sei(string: String) {
      
  }
    override public func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
    guard syncSystemRate else { return }
      super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
  }
}

@Observable
final class RoomInfoViewModel {
    
    var appViewModel: SimpleLiveViewModel
    
    var roomList: [LiveModel] = []
    var currentRoom: LiveModel
    var currentRoomIsLiked = false
    var currentRoomLikeLoading = false
    
    @MainActor
    var playerCoordinator = KSVideoPlayer.Coordinator()
    let settingModel = SettingStore()
    var playerOption: PlayerOptions
    var currentRoomPlayArgs: [LiveQualityModel]?
    var currentPlayURL: URL?
    var currentPlayQualityString = "清晰度"
    var currentPlayQualityQn = 0 //当前清晰度，虎牙用来存放回放时间
    var showControlView: Bool = true
    var isPlaying = false
    var douyuFirstLoad = true
    var yyFirstLoad = true
    
    var isLoading = false
    var rotationAngle = 0.0

    var debugTimerIsActive = false
    var dynamicInfo: DynamicInfo?
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var socketConnection: WebSocketConnection?
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
    init(currentRoom: LiveModel, appViewModel: SimpleLiveViewModel, enterFromLive: Bool, roomType: LiveRoomListType) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        let option = PlayerOptions()
        option.userAgent = "libmpv"
        option.syncSystemRate = settingModel.syncSystemRate
        self.playerOption = option
        self.currentRoom = currentRoom
        self.appViewModel = appViewModel
        let list = appViewModel.favoriteModel?.roomList ?? []
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
            self.playerOption.userAgent = "HYSDK(Windows, \(20000308))"
            self.playerOption.appendHeader([
                "user-agent": "HYSDK(Windows, \(20000308))"
            ])
        }else {
            self.playerOption.userAgent = "libmpv"
        }
        
        
        if currentRoom.liveType == .bilibili && cdnIndex == 0 && urlIndex == 0 { //bilibili 优先HLS播放
            for item in currentRoomPlayArgs! {
                for liveQuality in item.qualitys {
                    if liveQuality.liveCodeType == .hls {
                        KSOptions.firstPlayerType = KSAVPlayer.self
                        KSOptions.secondPlayerType = KSMEPlayer.self
                        self.currentPlayURL = URL(string: liveQuality.url)!
                        currentPlayQualityString = liveQuality.title
                        return
                    }
                }
            } 
            if self.currentPlayURL == nil {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }
        }else if (currentRoom.liveType == .douyin) { //douyin 优先HLS播放
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
            if cdnIndex == 0 && urlIndex == 0 {
                for item in currentRoomPlayArgs! {
                    for liveQuality in item.qualitys {
                        if liveQuality.liveCodeType == .hls {
                            KSOptions.firstPlayerType = KSAVPlayer.self
                            KSOptions.secondPlayerType = KSMEPlayer.self
                            self.currentPlayURL = URL(string: liveQuality.url)!
                            currentPlayQualityString = liveQuality.title
                            return
                        }else {
                            KSOptions.firstPlayerType = KSMEPlayer.self
                            KSOptions.secondPlayerType = KSMEPlayer.self
                            self.currentPlayURL = URL(string: liveQuality.url)!
                            currentPlayQualityString = liveQuality.title
                            return
                        }
                    }
                }
            }
        } else {
            if currentQuality.liveCodeType == .hls && currentRoom.liveType == .huya && LiveState(rawValue: currentRoom.liveState ?? "unknow") == .video {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }else if currentQuality.liveCodeType == .hls {
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }else {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }
        }
        
        if currentRoom.liveType == .ks {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }
        
        if currentRoom.liveType == .douyu && douyuFirstLoad == false {
            Task {
                let currentCdn = currentRoomPlayArgs![cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                let playArgs = try await Douyu.getRealPlayArgs(roomId: currentRoom.roomId, rate: currentQuality.qn, cdn: currentCdn.douyuCdnName)
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    self.currentPlayURL = URL(string: currentQuality?.url ?? lastCurrentPlayURL?.absoluteString ?? "")!
                }
            }
        }else {
            douyuFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                self.currentPlayURL = url
            }            
        }
        
        if currentRoom.liveType == .yy && yyFirstLoad == false {
            Task {
                let currentCdn = currentRoomPlayArgs![cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                let playArgs = try await YY.getRealPlayArgs(roomId: currentRoom.roomId, lineSeq:Int(currentCdn.yyLineSeq ?? "-1") ?? -1, gear: currentQuality.qn)
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    self.currentPlayURL = URL(string: currentQuality?.url ?? "") ?? lastCurrentPlayURL
                }
            }
        }else {
            yyFirstLoad = false
            self.currentPlayURL = URL(string: currentQuality.url)!
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
                var playArgs: [LiveQualityModel] = []
                switch currentRoom.liveType {
                    case .bilibili:
                        playArgs = try await Bilibili.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
                    case .huya:
                        playArgs =  try await Huya.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
                    case .douyin:
                        playArgs =  try await Douyin.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                    case .douyu:
                        playArgs =  try await Douyu.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
                    case .cc:
                        playArgs = try await NeteaseCC.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                    case .ks:
                        playArgs = try await KuaiShou.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                    case .yy:
                        playArgs = try await YY.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                    case .youtube:
                        playArgs = try await YoutubeParse.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                }
                await updateCurrentRoomPlayArgs(playArgs)
            }catch {
                print(error)
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
        if appViewModel.playerSettingModel.openExitPlayerViewWhenLiveEnd == true {
            if currentRoom.liveType != .youtube && currentRoom.liveType != .ks {
                liveFlagTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(appViewModel.playerSettingModel.openExitPlayerViewWhenLiveEndSecond), repeats: true) { _ in
                    Task {
                        let state = try await ApiManager.getCurrentRoomLiveState(roomId: self.currentRoom.roomId, userId: self.currentRoom.userId, liveType: self.currentRoom.liveType)
                        if state == .close || state == .unknow {
                            NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil, userInfo: nil)
                            self.liveFlagTimer?.invalidate()
                            self.liveFlagTimer = nil
                        }
                    }
                }
            }
        }
        
        if appViewModel.danmuSettingModel.showDanmu {
            getDanmuInfo()
        }
    }
    
    @MainActor func setPlayerDelegate() {
        playerCoordinator.playerLayer?.delegate = nil
        playerCoordinator.playerLayer?.delegate = self
    }
    
    func getDanmuInfo() {
        if danmuServerIsConnected == true || danmuServerIsLoading == true {
            return
        }
        Task {
            danmuServerIsLoading = true
            var danmuArgs: ([String : String], [String : String]?) = ([:],[:])
            switch currentRoom.liveType {
                case .bilibili:
                    danmuArgs = try await Bilibili.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                case .huya:
                    danmuArgs =  try await Huya.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                case .douyin:
                    danmuArgs =  try await Douyin.getDanmukuArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                case .douyu:
                    danmuArgs =  try await Douyu.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                default: break
            }
            socketConnection = WebSocketConnection(parameters: danmuArgs.0, headers: danmuArgs.1, liveType: currentRoom.liveType)
            socketConnection?.delegate = self
            socketConnection?.connect()
        }
    }
    
    func disConnectSocket() {
        self.socketConnection?.disconnect()
        self.socketConnection = nil
        socketConnection?.delegate = nil
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
    func webSocketDidConnect() {
        danmuServerIsConnected = true
        danmuServerIsLoading = false
    }
    
    func webSocketDidDisconnect(error: Error?) {
        danmuServerIsConnected = false
        danmuServerIsLoading = false
    }
    
    func webSocketDidReceiveMessage(text: String, color: UInt32) {
        danmuCoordinator.shoot(text: text, showColorDanmu: appViewModel.danmuSettingModel.showColorDanmu, color: color, alpha: appViewModel.danmuSettingModel.danmuAlpha, font: CGFloat(appViewModel.danmuSettingModel.danmuFontSize))
    }
    
    @MainActor func reloadRoom(liveModel: LiveModel) {
        liveFlagTimer?.invalidate()
        liveFlagTimer = nil
        currentPlayURL = nil
        disConnectSocket()
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        self.currentRoom = liveModel
        douyuFirstLoad = true
        yyFirstLoad = true
        getPlayArgs()
    }
}

extension RoomInfoViewModel: KSPlayerLayerDelegate {
    
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        isPlaying = layer.player.isPlaying
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
        if error == nil {
            NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil, userInfo: nil)
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
