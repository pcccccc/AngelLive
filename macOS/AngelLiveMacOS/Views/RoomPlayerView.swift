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

struct RoomPlayerView: View {
    let room: LiveModel
    @Environment(PlayerCoordinatorManager.self) private var playerManager
    @State private var viewModel: RoomInfoViewModel
    @State private var showQualitySelector = false

    init(room: LiveModel) {
        self.room = room
        self._viewModel = State(initialValue: RoomInfoViewModel(room: room))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 播放器
                if let url = viewModel.currentPlayURL {
                    KSVideoPlayerView(
                        coordinator: playerManager.coordinator,
                        url: url,
                        options: viewModel.playerOption
                    )
                    .onAppear {
                        viewModel.setPlayerDelegate(playerCoordinator: playerManager.coordinator)
                    }
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
                VStack {
                    // 顶部控制栏
                    HStack {
                        Text(room.roomTitle)
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        // 清晰度选择
                        if let playArgs = viewModel.currentRoomPlayArgs, !playArgs.isEmpty {
                            Menu {
                                ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                                    ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                                        Button(action: {
                                            Task { @MainActor in
                                                viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                                            }
                                        }) {
                                            HStack {
                                                Text(quality.title)
                                                if viewModel.currentPlayQualityString == quality.title {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(viewModel.currentPlayQualityString)
                                    Image(systemName: "chevron.down")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                            }
                            .menuStyle(.borderlessButton)
                        }

                        // 刷新按钮
                        Button(action: {
                            Task {
                                await viewModel.refreshPlayback()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Spacer()

                    // 底部信息
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.userName)
                                .font(.subheadline)
                                .foregroundColor(.white)

                            if let count = room.liveWatchedCount, !count.isEmpty {
                                Text("在线：\(count)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .navigationTitle(room.roomTitle)
        .task {
            await viewModel.loadPlayURL()
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
    .environment(PlayerCoordinatorManager())
}
