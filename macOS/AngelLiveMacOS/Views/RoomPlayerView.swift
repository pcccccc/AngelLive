//
//  RoomPlayerView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import AppKit

struct RoomPlayerView: View {
    let room: LiveModel
    @State private var viewModel: RoomInfoViewModel
    @ObservedObject private var coordinator = KSVideoPlayer.Coordinator()

    init(room: LiveModel) {
        self.room = room
        self._viewModel = State(initialValue: RoomInfoViewModel(room: room))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 播放器
                if let url = viewModel.currentPlayURL {
                    KSVideoPlayer(coordinator: _coordinator, url: url, options: viewModel.playerOption)
                        .onAppear {
                            viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                            hideWindowButtons()
                        }
                        .ignoresSafeArea()
                } else {
                    // 加载中
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在加载...")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                // 控制层
                PlayerControlView(room: room, viewModel: viewModel, coordinator: coordinator)
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.loadPlayURL()
        }
        .onDisappear {
            viewModel.disconnectSocket()
        }
    }

    private func hideWindowButtons() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }
}

#Preview {
    RoomPlayerView(room: LiveModel(
        userName: "测试主播",
        roomTitle: "测试直播间",
        roomCover: "",
        userHeadImg: "",
        liveType: .bilibili,
        liveState: "live",
        userId: "",
        roomId: "12345",
        liveWatchedCount: "1.2万"
    ))
    .frame(width: 800, height: 600)
}
