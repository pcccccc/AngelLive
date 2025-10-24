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

@Observable
final class RoomInfoViewModel {
    var currentRoom: LiveModel
    var currentPlayURL: URL?
    var isLoading = false

    // 播放器相关属性
    var playerOption: PlayerOptions
    var currentRoomPlayArgs: [LiveQualityModel]?
    var currentPlayQualityString = "清晰度"
    var currentPlayQualityQn = 0
    var isPlaying = false
    var douyuFirstLoad = true
    var yyFirstLoad = true

    // 弹幕相关属性
    var socketConnection: WebSocketConnection?
    var danmuMessages: [ChatMessage] = []
    var danmuServerIsConnected = false
    var danmuServerIsLoading = false
    var showDanmu = true // 是否显示弹幕
    var danmuCoordinator = DanmuView.Coordinator() // 屏幕弹幕协调器

    init(room: LiveModel) {
        self.currentRoom = room

        // 初始化播放器选项
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self

        let option = PlayerOptions()
        option.userAgent = "libmpv"
        self.playerOption = option
    }

    // 加载播放地址
    @MainActor
    func loadPlayURL() async {
        isLoading = true
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
            await updateCurrentRoomPlayArgs(playArgs)
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    @MainActor
    func updateCurrentRoomPlayArgs(_ playArgs: [LiveQualityModel]) {
        self.currentRoomPlayArgs = playArgs
        if playArgs.count == 0 {
            self.isLoading = false
            return
        }
        self.changePlayUrl(cdnIndex: 0, urlIndex: 0)

        // 启动弹幕连接
        if showDanmu {
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


        // 虎牙特殊处理
        if currentRoom.liveType == .huya {
            self.playerOption.userAgent = "HYSDK(Windows, \(20000308))"
            self.playerOption.appendHeader([
                "user-agent": "HYSDK(Windows, \(20000308))"
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
            Task {
                let currentCdn = currentRoomPlayArgs![cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                let playArgs = try await Douyu.getRealPlayArgs(roomId: currentRoom.roomId, rate: currentQuality.qn, cdn: currentCdn.douyuCdnName)
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    if let urlString = currentQuality?.url ?? lastCurrentPlayURL?.absoluteString,
                       let url = URL(string: urlString) {
                        self.currentPlayURL = url
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
            Task {
                guard var playArgs = currentRoomPlayArgs,
                      cdnIndex < playArgs.count else { return }
                let currentCdn = playArgs[cdnIndex]
                let currentQuality = currentCdn.qualitys[urlIndex]
                playArgs = try await YY.getRealPlayArgs(roomId: currentRoom.roomId, lineSeq: Int(currentCdn.yyLineSeq ?? "-1") ?? -1, gear: currentQuality.qn)
                DispatchQueue.main.async {
                    let currentQuality = playArgs.first?.qualitys[urlIndex]
                    let lastCurrentPlayURL = self.currentPlayURL
                    self.currentPlayURL = URL(string: currentQuality?.url ?? "") ?? lastCurrentPlayURL
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

        DispatchQueue.main.async {
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
            await loadPlayURL()
        }
    }

    /// 切换弹幕显示状态
    @MainActor
    func toggleDanmuDisplay() {
        setDanmuDisplay(!showDanmu)
    }

    /// 设置弹幕显示状态
    @MainActor
    func setDanmuDisplay(_ enabled: Bool) {
        guard enabled != showDanmu else { return }
        showDanmu = enabled
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

    func webSocketDidReceiveMessage(text: String, color: UInt32) {
        Task { @MainActor in
            // 将弹幕消息添加到聊天列表（底部气泡）
            addDanmuMessage(text: text)

            // 发射到屏幕弹幕（飞过效果）
            if showDanmu {
                danmuCoordinator.shoot(
                    text: text,
                    showColorDanmu: true,
                    color: color,
                    alpha: 1.0,
                    font: 16
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
        // 播放完成回调
    }

    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        // 缓冲回调
    }
}
