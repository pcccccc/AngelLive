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

