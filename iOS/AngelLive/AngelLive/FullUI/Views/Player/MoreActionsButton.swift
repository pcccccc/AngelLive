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
    var showQualityOption: Bool = false
    var onShowQualityPanel: (() -> Void)? = nil

    @Environment(RoomInfoViewModel.self) private var viewModel
    @State private var showStreamerInfo = false
    @State private var buttonPressed = false

    var body: some View {
        Menu {
            Button("主播详情") {
                showStreamerInfo = true
            }

            if showQualityOption {
                Button("清晰度 - \(viewModel.currentPlayQualityString)") {
                    onShowQualityPanel?()
                }
            }

            // MARK: - Legacy Quality Menu (commented out for rollback)
            /*
            if showQualityOption, let playArgs = viewModel.currentRoomPlayArgs {
                Menu("清晰度 - \(viewModel.currentPlayQualityString)") {
                    ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                        Menu(cdn.cdn.isEmpty ? "线路 \(cdnIndex + 1)" : cdn.cdn) {
                            ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                                Button {
                                    viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                                } label: {
                                    HStack {
                                        Text(quality.title)
                                        if viewModel.currentCdnIndex == cdnIndex && viewModel.currentQualityIndex == urlIndex {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            */

            Button("清屏") {
                onClearChat()
            }
        } label: {
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
        .menuIndicator(.hidden)
        .sheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(room: room)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .tint(.primary)
    }
}

#Preview {
    let room = LiveModel(
        userName: "测试主播",
        roomTitle: "测试直播间",
        roomCover: "",
        userHeadImg: "",
        liveType: .placeholder,
        liveState: "1",
        userId: "123",
        roomId: "456",
        liveWatchedCount: "1000"
    )
    ZStack {
        Color.black
        MoreActionsButton(
            room: room,
            onClearChat: {
                Logger.debug("清屏", category: .ui)
            }
        )
    }
    .environment(RoomInfoViewModel(room: room))
}
