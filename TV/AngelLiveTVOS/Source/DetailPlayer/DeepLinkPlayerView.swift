//
//  DeepLinkPlayerView.swift
//  AngelLiveTVOS
//
//  Created for Top Shelf Deep Link handling
//

import SwiftUI
import SharedAssets
import AngelLiveCore
import AngelLiveDependencies

/// 处理从 Top Shelf Deep Link 进入的播放器视图
struct DeepLinkPlayerView: View {

    var appViewModel: AppState
    @State private var roomInfoViewModel: RoomInfoViewModel?
    @State private var shortDramaRoom: LiveModel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if let room = shortDramaRoom {
                TVShortDramaPlayerView(room: room, onExit: cleanupAndDismiss)
                    .id(room.id)
            } else if let viewModel = roomInfoViewModel {
                DetailPlayerView { _, _ in
                    cleanupAndDismiss()
                }
                .environment(viewModel)
                .environment(appViewModel)
                .edgesIgnoringSafeArea(.all)
                .frame(width: 1920, height: 1080)
            }
        }
        .fullUIArcLoadingStyle(isEnabled: appViewModel.pluginAvailability.hasAvailablePlugins)
        .task {
            await loadRoomInfo()
        }
        .onExitCommand {
            // The short-drama page owns its panel → controls → exit Menu state.
            if shortDramaRoom == nil { cleanupAndDismiss() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .fullUIArcLoadingStyle(
                    isEnabled: appViewModel.pluginAvailability.hasAvailablePlugins,
                    size: 64, lineWidth: 2.5
                )
                .scaleEffect(appViewModel.pluginAvailability.hasAvailablePlugins ? 1 : 2)
                .tint(.white)
            Text("正在获取直播信息...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)

            Text("无法播放")
                .font(.title)
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("返回") {
                cleanupAndDismiss()
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @MainActor
    private func loadRoomInfo() async {
        guard let room = appViewModel.pendingDeepLinkRoom else {
            errorMessage = "无效的直播间信息"
            isLoading = false
            return
        }

        if TVShortDramaRoute.matches(room: room, appViewModel: appViewModel) {
            if !appViewModel.historyViewModel.watchList.contains(room) {
                appViewModel.historyViewModel.watchList.insert(room, at: 0)
            }
            shortDramaRoom = room
            isLoading = false
            return
        }

        do {
            // 获取最新的直播间信息
            let latestInfo = try await ApiManager.fetchLastestLiveInfo(liveModel: room)
            guard !Task.isCancelled else { return }

            // 检查是否正在直播
            guard latestInfo.liveState == "1" else {
                errorMessage = "主播已下播"
                isLoading = false
                return
            }

            // 添加到历史记录
            if !appViewModel.historyViewModel.watchList.contains(where: { latestInfo.roomId == $0.roomId }) {
                appViewModel.historyViewModel.watchList.insert(latestInfo, at: 0)
            }

            // 创建 RoomInfoViewModel
            roomInfoViewModel = RoomInfoViewModel(
                currentRoom: latestInfo,
                appViewModel: appViewModel,
                enterFromLive: false,
                roomType: .favorite
            )

            isLoading = false

        } catch {
            errorMessage = "获取直播信息失败：\(error.localizedDescription)"
            isLoading = false
        }
    }

    private func cleanupAndDismiss() {
        roomInfoViewModel?.disConnectSocket()
        appViewModel.pendingDeepLinkRoom = nil
        appViewModel.showDeepLinkPlayer = false
        dismiss()
    }
}
