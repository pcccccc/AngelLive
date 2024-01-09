//
//  RoomInfoStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/2.
//

import Foundation
import KSPlayer
import LiveParse

class RoomInfoStore: ObservableObject {
    
    @Published var roomList: [LiveModel] = []
    @Published var currentRoom: LiveModel
    @Published var playerCoordinator = KSVideoPlayer.Coordinator()
    @Published var currentRoomPlayArgs: [LiveQualityModel]?
    @Published var currentPlayURL: URL?
    @Published var danmuSettingModel = DanmuSettingStore()
    @Published var showControlView: Bool = true
    
    var socketConnection: WebSocketConnection?
    var danmuCoordinator = DanmuView.Coordinator()
    
    init(currentRoom: LiveModel) {
        self.currentRoom = currentRoom
        getPlayArgs()
    }
    
    /**
     切换清晰度
    */
    func changePlayUrl(cdnIndex: Int, urlIndex: Int) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        guard currentRoomPlayArgs != nil else {
            return
        }
        let currentCdn = currentRoomPlayArgs![cdnIndex]
        let currentQuality = currentCdn.qualitys[urlIndex]
        if currentQuality.liveCodeType == .flv {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSAVPlayer.self
        }else {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }
        if currentRoom.liveType == .bilibili {
            for item in currentRoomPlayArgs! {
                for liveQuality in item.qualitys {
                    if liveQuality.liveCodeType == .hls {
                        KSOptions.firstPlayerType = KSAVPlayer.self
                        KSOptions.secondPlayerType = KSMEPlayer.self
                        
                        self.currentPlayURL = URL(string: liveQuality.url)!
                        return
                    }
                }
            }
        }

        self.currentPlayURL = URL(string: currentQuality.url)!
    }
    
    /**
     获取播放参数。
     
     - Returns: 播放清晰度、url等参数
    */
    func getPlayArgs() {
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
                    default: break
                }
                DispatchQueue.main.async {
                    self.currentRoomPlayArgs = playArgs
                    self.changePlayUrl(cdnIndex: 0, urlIndex: 0)
                }
            }catch {
                
            }
        }
    }
    
    func setPlayerDelegate() {
        playerCoordinator.playerLayer?.delegate = self
    }
    
    func getDanmuInfo() {
        Task {
            var danmuArgs: ([String : String], [String : String]?) = ([:],[:])
            switch currentRoom.liveType {
                case .bilibili:
                    danmuArgs = try await Bilibili.getDanmukuArgs(roomId: currentRoom.roomId)
                case .huya:
                    danmuArgs =  try await Huya.getDanmukuArgs(roomId: currentRoom.roomId)
                case .douyin:
                    danmuArgs =  try await Douyin.getDanmukuArgs(roomId: currentRoom.roomId)
                case .douyu:
                    danmuArgs =  try await Douyu.getDanmukuArgs(roomId: currentRoom.roomId)
                default: break
            }
            socketConnection = WebSocketConnection(parameters: danmuArgs.0, headers: danmuArgs.1, liveType: currentRoom.liveType)
            socketConnection?.delegate = self
            socketConnection?.connect()
        }
    }
    
    func disConnectSocket() {
        self.socketConnection?.disconnect()
    }
}

extension RoomInfoStore: WebSocketConnectionDelegate {
    func webSocketDidConnect() {
        
    }
    
    func webSocketDidDisconnect(error: Error?) {
        
    }
    
    func webSocketDidReceiveMessage(text: String, color: UInt32) {
        danmuCoordinator.shoot(text: text, showColorDanmu: danmuSettingModel.showColorDanmu, color: color, alpha: danmuSettingModel.danmuAlpha, font: CGFloat(danmuSettingModel.danmuFontSize))
    }
}

extension RoomInfoStore: KSPlayerLayerDelegate {
    
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        if state == .paused {
            showControlView = true
        }
        if layer.player.isPlaying == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                self.showControlView = false
            })
        }
    }
    
    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        
    }
    
    func player(layer: KSPlayer.KSPlayerLayer, finish error: Error?) {
        
    }
    
    func player(layer: KSPlayer.KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        
    }
    
    
}
