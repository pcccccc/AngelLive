//
//  RoomInfoViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

@Observable
final class RoomInfoViewModel {
    var currentRoom: LiveModel
    var currentPlayURL: URL?
    var isLoading = false

    init(room: LiveModel) {
        self.currentRoom = room
    }

    // 加载播放地址
    @MainActor
    func loadPlayURL() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: 实现播放地址解析逻辑
        // 这里需要调用 LiveService 获取播放地址
    }
}
