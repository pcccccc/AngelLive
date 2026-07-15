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
///
/// 标为 @MainActor：所有调用点（DetailPlayerView 的 onAppear/onChange 与
/// RoomInfoViewModel 的 KSPlayerLayerDelegate 回调，后者本就是 @MainActor）都在主线程，
/// MPNowPlayingInfoCenter 也应在主线程写入；同时让下方静态缓存在 Swift 6 严格并发下天然安全。
@MainActor
enum NowPlayingManager {

    /// 当前正在展示的封面 URL。
    /// 作用：异步下载的封面回来时，比对它是否仍是当前房间，避免快速切台时把上一个房间的封面盖到新房间上。
    private static var currentCoverURL: String?

    /// 封面缓存（按 URL），避免弱网反复重连时对同一封面重复下载。有界，自动淘汰。
    private static let artworkCache: NSCache<NSString, MPMediaItemArtwork> = {
        let cache = NSCache<NSString, MPMediaItemArtwork>()
        cache.countLimit = 20
        return cache
    }()

    /// 更新 Now Playing 信息
    /// - Parameters:
    ///   - room: 当前直播间信息
    ///   - isPlaying: 是否正在播放
    static func update(room: LiveModel, isPlaying: Bool, surfaceID: PlaybackSurfaceID) {
        guard PlaybackSessionRegistry.shared.isOwner(surfaceID, of: .nowPlaying) else { return }
        let cover = room.roomCover
        currentCoverURL = cover

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: room.roomTitle,          // 标题：房间标题
            MPMediaItemPropertyArtist: room.userName,          // 艺术家：主播名称
            MPMediaItemPropertyAlbumTitle: room.liveType.platformName, // 专辑名：平台名称
            MPNowPlayingInfoPropertyIsLiveStream: true,        // 标记为直播流（没有总时长）
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0, // 播放速率
        ]
        // 缓存命中则直接带上封面，避免先无图再闪现
        if let cached = artworkCache.object(forKey: cover as NSString) {
            info[MPMediaItemPropertyArtwork] = cached
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 未命中缓存才发起下载
        guard artworkCache.object(forKey: cover as NSString) == nil else { return }
        loadArtwork(from: cover) { artwork in
            guard let artwork else { return }
            artworkCache.setObject(artwork, forKey: cover as NSString)
            // 下载期间房间可能已切换，仅当仍是当前封面才落地
            guard currentCoverURL == cover,
                  PlaybackSessionRegistry.shared.isOwner(surfaceID, of: .nowPlaying)
            else { return }
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }

    /// 清除 Now Playing 信息
    static func clear(surfaceID: PlaybackSurfaceID) {
        guard PlaybackSessionRegistry.shared.isOwner(surfaceID, of: .nowPlaying) else { return }
        currentCoverURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 更新播放状态（不改变其他信息）
    static func updatePlaybackState(isPlaying: Bool, surfaceID: PlaybackSurfaceID) {
        guard PlaybackSessionRegistry.shared.isOwner(surfaceID, of: .nowPlaying) else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    // MARK: - Private

    private static func loadArtwork(from urlString: String, completion: @escaping @MainActor (MPMediaItemArtwork?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            Task { @MainActor in
                guard let image else {
                    completion(nil)
                    return
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                completion(artwork)
            }
        }.resume()
    }
}
