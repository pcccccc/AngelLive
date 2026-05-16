//
//  NowPlayingManager.swift
//  AngelLive
//
//  Created by Claude on 03/12/26.
//

import Foundation
import MediaPlayer
import AngelLiveCore

/// 管理系统媒体中心（Now Playing）的信息显示
/// 在播放直播时更新锁屏/控制中心的媒体信息
enum NowPlayingManager {

    /// 更新 Now Playing 信息
    /// - Parameters:
    ///   - room: 当前直播间信息
    ///   - isPlaying: 是否正在播放
    static func update(room: LiveModel, isPlaying: Bool) {
        var info = [String: Any]()

        // 标题：房间标题
        info[MPMediaItemPropertyTitle] = room.roomTitle
        // 艺术家：主播名称
        info[MPMediaItemPropertyArtist] = room.userName
        // 专辑名：平台名称
        info[MPMediaItemPropertyAlbumTitle] = room.liveType.platformName
        // 标记为直播流（没有总时长）
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        // 播放速率
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 异步加载封面图
        loadArtwork(from: room.displayRoomCover) { artwork in
            if let artwork {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
            }
        }
    }

    /// 清除 Now Playing 信息
    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 更新播放状态（不改变其他信息）
    static func updatePlaybackState(isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    // MARK: - Private

    private static func loadArtwork(from urlString: String, completion: @escaping @Sendable (MPMediaItemArtwork?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard let data, let image = UIImage(data: data) else {
                    completion(nil)
                    return
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                completion(artwork)
            }
        }.resume()
    }
}
