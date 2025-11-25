//
//  LiveRoomCardButton.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/23/25.
//

import SwiftUI
import AngelLiveCore
import LiveParse

// MARK: - 直播间卡片按钮包装器
struct LiveRoomCardButton<Content: View>: View {
    let room: LiveModel
    let content: Content
    @Environment(\.openWindow) private var openWindow
    @Environment(ToastManager.self) private var toastManager

    // 判断是否正在直播
    private var isLive: Bool {
        guard let liveState = room.liveState else { return true }
        return LiveState(rawValue: liveState) == .live
    }

    init(room: LiveModel, @ViewBuilder content: () -> Content) {
        self.room = room
        self.content = content()
    }

    var body: some View {
        Button {
            if isLive {
                openWindow(value: room)
            } else {
                toastManager.show(icon: "tv.slash", message: "主播已下播")
            }
        } label: {
            content
        }
        .buttonStyle(.plain)
    }
}
