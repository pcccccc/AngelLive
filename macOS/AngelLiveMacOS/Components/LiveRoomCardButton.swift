//
//  LiveRoomCardButton.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/23/25.
//

import SwiftUI
import AngelLiveCore

// MARK: - 直播间卡片按钮包装器
struct LiveRoomCardButton<Content: View>: View {
    let room: LiveModel
    let content: Content
    @Environment(\.openWindow) private var openWindow
    @Environment(ToastManager.self) private var toastManager
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager

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
                fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
            } else {
                toastManager.show(icon: "tv.slash", message: "主播已下播")
            }
        } label: {
            content
        }
        .buttonStyle(MacRoomCardButtonStyle())
        .macRoomCardHoverEffect()
    }
}

struct MacRoomCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct MacRoomCardHoverModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
            .zIndex(isHovered ? 1 : 0)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func macRoomCardHoverEffect() -> some View {
        modifier(MacRoomCardHoverModifier())
    }
}
