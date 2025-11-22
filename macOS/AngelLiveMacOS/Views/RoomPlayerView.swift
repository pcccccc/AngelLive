//
//  RoomPlayerView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import Observation
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
        @Bindable var viewModel = viewModel
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

                danmuOverlay(for: geometry.size)
                    .zIndex(2)

                // 控制层
                PlayerControlView(room: room, viewModel: viewModel, coordinator: coordinator)
                    .zIndex(3)
            }
        }
        .navigationTitle(viewModel.currentRoom.roomTitle)
        .ignoresSafeArea()
        .focusable()
        .onKeyPress(.space) {
            if viewModel.isPlaying {
                coordinator.playerLayer?.pause()
            } else {
                coordinator.playerLayer?.play()
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
            return .handled
        }
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

private extension RoomPlayerView {
    @ViewBuilder
    func danmuOverlay(for containerSize: CGSize) -> some View {
        let settings = viewModel.danmuSettings
        if settings.showDanmu, viewModel.currentPlayURL != nil {
            let config = danmuConfig(for: containerSize.height, index: settings.danmuAreaIndex)
            VStack(spacing: 0) {
                if config.position == .bottom {
                    Spacer()
                }

                DanmuView(
                    coordinator: viewModel.danmuCoordinator,
                    size: CGSize(width: containerSize.width, height: config.height),
                    fontSize: CGFloat(settings.danmuFontSize),
                    speed: CGFloat(settings.danmuSpeed),
                    paddingTop: CGFloat(settings.danmuTopMargin),
                    paddingBottom: CGFloat(settings.danmuBottomMargin)
                )
                .frame(width: containerSize.width, height: config.height)
                .opacity(settings.showDanmu ? 1 : 0)

                if config.position == .top {
                    Spacer()
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuAreaIndex)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuFontSize)
            .animation(.easeInOut(duration: 0.25), value: settings.danmuSpeed)
        } else {
            EmptyView()
        }
    }

    func danmuConfig(for containerHeight: CGFloat, index: Int) -> (height: CGFloat, position: DanmuPosition) {
        let ratios: [CGFloat] = [0.25, 0.5, 1.0, 0.5, 0.25]
        let clampedIndex = max(0, min(index, ratios.count - 1))
        let heightRatio = ratios[clampedIndex]
        let height = max(containerHeight * heightRatio, 1)

        if clampedIndex == 2 {
            return (height, .full)
        } else if clampedIndex >= 3 {
            return (height, .bottom)
        } else {
            return (height, .top)
        }
    }

    enum DanmuPosition {
        case top
        case bottom
        case full
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
