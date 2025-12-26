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
    var douyuFirstLoad = true
    var yyFirstLoad = true

    // 弹幕相关属性
    var socketConnection: WebSocketConnection?
    var danmuMessages: [ChatMessage] = []
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    var danmuCoordinator = DanmuView.Coordinator() // 屏幕弹幕协调器
    var danmuSettings = DanmuSettingModel() // 弹幕设置模型

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
            var playArgs: [LiveQualityModel] = []
            switch currentRoom.liveType {
            case .bilibili:
                playArgs = try await Bilibili.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
            case .huya:
                playArgs = try await Huya.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
            case .douyin:
                playArgs = try await Douyin.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
            case .douyu:
                playArgs = try await Douyu.getPlayArgs(roomId: currentRoom.roomId, userId: nil)
            case .cc:
                playArgs = try await NeteaseCC.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
            case .ks:
                playArgs = try await KuaiShou.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
            case .yy:
                playArgs = try await YY.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
            case .youtube:
                playArgs = try await YoutubeParse.getPlayArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
            }
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

        // 启动弹幕连接
        if danmuSettings.showDanmu {
            getDanmuInfo()
        }
    }

    // 切换清晰度
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
        currentCdnIndex = cdnIndex


        // 虎牙特殊处理
        if currentRoom.liveType == .huya {
            self.playerOption.userAgent = "HYSDK(Windows,30000002)_APP(pc_exe&7030003&official)_SDK(trans&2.29.0.5493)"
            self.playerOption.appendHeader([
                "user-agent": "HYSDK(Windows,30000002)_APP(pc_exe&7030003&official)_SDK(trans&2.29.0.5493)"
            ])
        } else {
            self.playerOption.userAgent = "libmpv"
        }

        // B站优先使用 HLS
        if currentRoom.liveType == .bilibili && cdnIndex == 0 && urlIndex == 0 {
            for item in currentRoomPlayArgs! {
                for liveQuality in item.qualitys {
                    if liveQuality.liveCodeType == .hls {
                        KSOptions.firstPlayerType = KSAVPlayer.self
                        KSOptions.secondPlayerType = KSMEPlayer.self
                        DispatchQueue.main.async {
                            self.currentPlayURL = URL(string: liveQuality.url)!
                            self.currentPlayQualityString = liveQuality.title
                            self.isLoading = false
                        }
                        return
                    }
                }
            }
            if self.currentPlayURL == nil {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }
        }
        // 抖音优先使用 HLS
        else if currentRoom.liveType == .douyin {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
            if cdnIndex == 0 && urlIndex == 0 {
                for item in currentRoomPlayArgs! {
                    for liveQuality in item.qualitys {
                        if liveQuality.liveCodeType == .hls {
                            KSOptions.firstPlayerType = KSAVPlayer.self
                            KSOptions.secondPlayerType = KSMEPlayer.self
                            DispatchQueue.main.async {
                                self.currentPlayURL = URL(string: liveQuality.url)!
                                self.currentPlayQualityString = liveQuality.title
                                self.isLoading = false
                            }
                            return
                        } else {
                            KSOptions.firstPlayerType = KSMEPlayer.self
                            KSOptions.secondPlayerType = KSMEPlayer.self
                            DispatchQueue.main.async {
                                self.currentPlayURL = URL(string: liveQuality.url)!
                                self.currentPlayQualityString = liveQuality.title
                                self.isLoading = false
                            }
                            return
                        }
                    }
                }
            }
        }
        // 其他平台
        else {
            if currentQuality.liveCodeType == .hls && currentRoom.liveType == .huya && LiveState(rawValue: currentRoom.liveState ?? "unknow") == .video {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            } else if currentQuality.liveCodeType == .hls {
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            } else {
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
            }
        }

        // 快手特殊处理
        if currentRoom.liveType == .ks {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }

        // 斗鱼特殊处理
        if currentRoom.liveType == .douyu && douyuFirstLoad == false {
            // 斗鱼平台每次切换清晰度都需要重新请求流地址
            isLoading = true
            Task {
                do {
                    let currentCdn = currentRoomPlayArgs![cdnIndex]
                    let currentQuality = currentCdn.qualitys[urlIndex]
                    let playArgs = try await Douyu.getRealPlayArgs(roomId: currentRoom.roomId, rate: currentQuality.qn, cdn: currentCdn.douyuCdnName)
                    await MainActor.run {
                        if let newQuality = playArgs.first?.qualitys.first,
                           let url = URL(string: newQuality.url) {
                            self.currentPlayURL = url
                            self.isLoading = false
                        } else {
                            // 如果获取失败，保持当前播放地址
                            print("⚠️ 斗鱼切换清晰度失败：无法获取新的播放地址")
                            self.isLoading = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("❌ 斗鱼切换清晰度失败: \(error.localizedDescription)")
                        self.isLoading = false
                        // 保持当前播放地址，不中断播放
                    }
                }
            }
        } else {
            douyuFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                DispatchQueue.main.async {
                    self.currentPlayURL = url
                }
            }
        }

        // YY 特殊处理
        if currentRoom.liveType == .yy && yyFirstLoad == false {
            // YY 平台每次切换清晰度都需要重新请求流地址
            isLoading = true
            Task {
                do {
                    guard var playArgs = currentRoomPlayArgs,
                          cdnIndex < playArgs.count else {
                        await MainActor.run {
                            self.isLoading = false
                        }
                        return
                    }
                    let currentCdn = playArgs[cdnIndex]
                    let currentQuality = currentCdn.qualitys[urlIndex]
                    playArgs = try await YY.getRealPlayArgs(roomId: currentRoom.roomId, lineSeq: Int(currentCdn.yyLineSeq ?? "-1") ?? -1, gear: currentQuality.qn)
                    await MainActor.run {
                        if let newQuality = playArgs.first?.qualitys.first,
                           let url = URL(string: newQuality.url) {
                            self.currentPlayURL = url
                        }
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        print("❌ YY 切换清晰度失败: \(error.localizedDescription)")
                        self.isLoading = false
                    }
                }
            }
        } else {
            yyFirstLoad = false
            if let url = URL(string: currentQuality.url) {
                DispatchQueue.main.async {
                    self.currentPlayURL = url
                }
            }
        }

        // 只有非异步请求的平台才在这里设置 isLoading = false
        // 斗鱼和YY平台会在各自的异步任务中管理 isLoading
        if currentRoom.liveType != .douyu && currentRoom.liveType != .yy {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        } else if currentRoom.liveType == .douyu && douyuFirstLoad {
            // 斗鱼首次加载时也需要设置
            DispatchQueue.main.async {
                self.isLoading = false
            }
        } else if currentRoom.liveType == .yy && yyFirstLoad {
            // YY 首次加载时也需要设置
            DispatchQueue.main.async {
                self.isLoading = false
            }
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
        case .bilibili, .huya, .douyin, .douyu:
            return true
        case .cc, .ks, .yy, .youtube:
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
        danmuMessages.append(systemMsg)

        // 限制消息数量
        if danmuMessages.count > 100 {
            danmuMessages.removeFirst(danmuMessages.count - 100)
        }
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
                case .bilibili:
                    danmuArgs = try await Bilibili.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                case .huya:
                    danmuArgs = try await Huya.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                case .douyin:
                    danmuArgs = try await Douyin.getDanmukuArgs(roomId: currentRoom.roomId, userId: currentRoom.userId)
                case .douyu:
                    danmuArgs = try await Douyu.getDanmukuArgs(roomId: currentRoom.roomId, userId: nil)
                default:
                    await MainActor.run {
                        danmuServerIsLoading = false
                    }
                    return
                }

                await MainActor.run {
                    socketConnection = WebSocketConnection(
                        parameters: danmuArgs.0,
                        headers: danmuArgs.1,
                        liveType: currentRoom.liveType
                    )
                    socketConnection?.delegate = self
                    socketConnection?.connect()
                }
            } catch {
                print("获取弹幕连接失败: \(error)")
                await MainActor.run {
                    danmuServerIsLoading = false
                    addSystemMessage("连接弹幕服务器失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 断开弹幕连接
    func disconnectSocket() {
        socketConnection?.disconnect()
        socketConnection?.delegate = nil
        socketConnection = nil
        danmuServerIsConnected = false
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

    /// 设置弹幕显示状态
    @MainActor
    func setDanmuDisplay(_ enabled: Bool) {
        guard enabled != danmuSettings.showDanmu else { return }
        danmuSettings.showDanmu = enabled
        if enabled {
            danmuCoordinator.play()
            getDanmuInfo()
        } else {
            danmuCoordinator.clear()
            disconnectSocket()
        }
    }

    /// 添加弹幕消息到聊天列表
    @MainActor
    func addDanmuMessage(text: String, userName: String = "观众") {
        let message = ChatMessage(
            userName: userName,
            message: text
        )
        danmuMessages.append(message)

        // 限制消息数量，避免内存占用过大
        if danmuMessages.count > 100 {
            danmuMessages.removeFirst(danmuMessages.count - 100)
        }
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
            print("✅ 弹幕服务已连接")
        }
    }

    func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            danmuServerIsConnected = false
            danmuServerIsLoading = false
            if let error = error {
                addSystemMessage("弹幕服务器已断开：\(error.localizedDescription)")
                print("❌ 弹幕服务断开: \(error.localizedDescription)")
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
