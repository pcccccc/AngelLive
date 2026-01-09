//
//  MoreActionsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import AVKit

/// 直播间功能按钮（清屏、主播详情等直播间相关功能）
struct MoreActionsButton: View {
    let room: LiveModel
    var onClearChat: () -> Void

    @State private var showActionSheet = false
    @State private var showStreamerInfo = false
    @State private var buttonPressed = false

    var body: some View {
        Button(action: {
            buttonPressed.toggle()
            showActionSheet = true
        }) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .shadow(
                    color: .black.opacity(0.2),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .conditionalEffect(.pushDown, condition: buttonPressed)
        .confirmationDialog("直播间", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("主播详情") {
                showStreamerInfo = true
            }

            Button("清屏") {
                onClearChat()
            }

            // 预留：相关直播间推荐
            // Button("相关推荐") { }

            Button("取消", role: .cancel) {
                showActionSheet = false
            }
        }
        .sheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(room: room)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .tint(.primary)
    }
}

#Preview {
    ZStack {
        Color.black
        MoreActionsButton(
            room: LiveModel(
                userName: "测试主播",
                roomTitle: "测试直播间",
                roomCover: "",
                userHeadImg: "",
                liveType: .bilibili,
                liveState: "1",
                userId: "123",
                roomId: "456",
                liveWatchedCount: "1000"
            ),
            onClearChat: {
                print("清屏")
            }
        )
    }
}
