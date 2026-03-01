//
//  PlayerControlBridge.swift
//  AngelLive
//

import Foundation

/// 播放控制兼容层：UI 只依赖这个桥接结构，不直接依赖具体播放器内核。
struct PlayerControlBridge {
    var isPlaying: Bool
    var isBuffering: Bool
    var supportsPictureInPicture: Bool
    var togglePlayPause: () -> Void
    var refreshPlayback: () -> Void
    var togglePictureInPicture: () -> Void
}
