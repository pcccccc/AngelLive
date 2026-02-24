//
//  LiveCardView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/9.
//

import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

struct LiveCardView: View {

    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(AppState.self) var appViewModel
    @State var index: Int
    var externalFocusState: FocusState<FocusableField?>.Binding?
    var onMoveCommand: ((MoveCommandDirection) -> Void)? = nil
    @State var currentLiveModel: LiveModel?
    @State private var isLive: Bool = false
    @FocusState private var internalFocusState: FocusableField?

    /// 卡片底部渐变，用于显示观看人数
    private let cardGradient = LinearGradient(stops: [
        .init(color: .black.opacity(0.6), location: 0.0),
        .init(color: .black.opacity(0.3), location: 0.5),
        .init(color: .clear, location: 1.0)
    ], startPoint: .bottom, endPoint: .top)
    private let cardWidth: CGFloat = 370
    private let coverHeight: CGFloat = 210

    /// 是否获得焦点
    private var isFocused: Bool {
        if let external = externalFocusState {
            return external.wrappedValue == .mainContent(index)
        }
        return internalFocusState == .mainContent(index)
    }

    /// 获取当前 focusState 的值
    private var currentFocusValue: FocusableField? {
        externalFocusState?.wrappedValue ?? internalFocusState
    }

    var body: some View {
        @Bindable var liveModel = liveViewModel
        @State var roomList = liveViewModel.roomList

        if index < roomList.count {
            let currentLiveModel = self.currentLiveModel == nil ? roomList[index] : self.currentLiveModel!
            VStack(alignment: .leading, spacing: 12) {
                // 封面区域
                coverSection(currentLiveModel: currentLiveModel, liveModel: $liveModel)

                // 主播信息区域
                streamerInfoSection(currentLiveModel: currentLiveModel)
            }
        }
    }

    // MARK: - 封面区域
    @ViewBuilder
    private func coverSection(currentLiveModel: LiveModel, liveModel: Bindable<LiveViewModel>) -> some View {
        Button {
            enterDetailRoom()
        } label: {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .bottom) {
                    // 背景模糊层
                    KFImage(URL(string: currentLiveModel.roomCover))
                        .placeholder {
                            placeholderImage
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: cardWidth, height: coverHeight)
                        .blur(radius: 15)
                        .clipped()

                    // 前景封面图
                    KFImage(URL(string: currentLiveModel.roomCover))
                        .onFailure { error in
                            print("Image loading failed: \(error)")
                        }
                        .placeholder {
                            placeholderImage
                        }
                        .resizable()
                        .scaledToFit()
                        .frame(width: cardWidth, height: coverHeight)

                    // 底部渐变遮罩
                    Rectangle()
                        .fill(cardGradient)
                        .frame(height: 50)

                    // 观看人数标签
                    if let watchedCount = currentLiveModel.liveWatchedCount {
                        HStack {
                            Spacer()
                            watchedCountBadge(count: watchedCount)
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                    }
                }
                .frame(width: cardWidth, height: coverHeight)

                // 平台和直播状态标签（非直播列表页面显示）
                if liveViewModel.roomListType != .live {
                    platformAndStatusOverlay(currentLiveModel: currentLiveModel)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .focused(externalFocusState ?? $internalFocusState, equals: .mainContent(index))
        .onMoveCommand { direction in
            print("LiveCardView onMoveCommand index=\(index) direction=\(direction)")
            onMoveCommand?(direction)
        }
        .onChange(of: currentFocusValue) { oldValue, newValue in
            handleFocusChange(newValue: newValue, liveModel: liveModel)
        }
        .alert("提示", isPresented: liveModel.showAlert) {
            alertButtons
        } message: {
            Text("确认取消收藏吗")
        }
        .contextMenu { contextMenuContent }
        .fullScreenCover(isPresented: $isLive) {
            playerFullScreenContent
        }
    }

    // MARK: - 主播信息区域
    @ViewBuilder
    private func streamerInfoSection(currentLiveModel: LiveModel) -> some View {
        HStack(spacing: 12) {
            // 主播头像
            KFImage(URL(string: currentLiveModel.userHeadImg))
                .placeholder {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 0.3 : 0), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(currentLiveModel.userName)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                Text(currentLiveModel.roomTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.top, isFocused ? 16 : 8)
        .scaleEffect(isFocused ? 1.05 : 1.0, anchor: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
    }

    // MARK: - 子视图组件

    /// 占位图
    private var placeholderImage: some View {
        Image("placeholder")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: cardWidth, height: coverHeight)
    }

    /// 观看人数标签
    private func watchedCountBadge(count: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 12))
            Text(count.formatWatchedCount())
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }

    /// 平台和直播状态覆盖层
    @ViewBuilder
    private func platformAndStatusOverlay(currentLiveModel: LiveModel) -> some View {
        HStack {
            // 平台图标
            Image(uiImage: .init(named: getImage())!)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .padding(.top, 8)
                .padding(.leading, 8)

            Spacer()

            // 直播状态标签
            liveStatusBadge(currentLiveModel: currentLiveModel)
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .task {
            do {
                try await refreshStateIfStateIsUnknow()
            } catch {
                // 静默处理错误
            }
        }
    }

    /// 直播状态标签
    private func liveStatusBadge(currentLiveModel: LiveModel) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(formatLiveStateColor())
                .frame(width: 8, height: 8)
            Text(currentLiveModel.liveStateFormat())
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
        )
    }

    /// Alert 按钮
    private var alertButtons: some View {
        Group {
            Button("取消收藏", role: .destructive) {
                Task {
                    do {
                        try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                        liveViewModel.showToast(true, title: "取消收藏成功")
                        TopShelfManager.notifyContentChanged()
                    } catch {
                        liveViewModel.showToast(false, title: FavoriteService.formatErrorCode(error: error))
                    }
                }
            }
            Button("再想想", role: .cancel) {
                liveViewModel.showAlert = false
            }
        }
    }

    /// 上下文菜单内容
    @ViewBuilder
    private var contextMenuContent: some View {
        if liveViewModel.currentRoomIsFavorited {
            Button {
                Task {
                    do {
                        try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                        appViewModel.favoriteViewModel.roomList.removeAll(where: { $0.roomId == liveViewModel.currentRoom!.roomId })
                        liveViewModel.showToast(true, title: "取消收藏成功")
                        liveViewModel.currentRoomIsFavorited = false
                        TopShelfManager.notifyContentChanged()
                    } catch {
                        liveViewModel.showToast(false, title: FavoriteService.formatErrorCode(error: error))
                    }
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash.fill")
            }
        } else {
            Button {
                Task {
                    do {
                        if liveViewModel.currentRoom!.liveState == nil || (liveViewModel.currentRoom!.liveState ?? "").isEmpty {
                            liveViewModel.currentRoom!.liveState = try await ApiManager.getCurrentRoomLiveState(
                                roomId: liveViewModel.currentRoom!.roomId,
                                userId: liveViewModel.currentRoom!.userId,
                                liveType: liveViewModel.currentRoom!.liveType
                            ).rawValue
                        }
                        try await appViewModel.favoriteViewModel.addFavorite(room: liveViewModel.currentRoom!)
                        liveViewModel.showToast(true, title: "收藏成功")
                        appViewModel.favoriteViewModel.roomList.append(liveViewModel.currentRoom!)
                        liveViewModel.currentRoomIsFavorited = true
                        TopShelfManager.notifyContentChanged()
                    } catch {
                        liveViewModel.showToast(false, title: FavoriteService.formatErrorCode(error: error))
                    }
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }
        }

        if liveViewModel.roomListType == .history {
            Button(role: .destructive) {
                liveViewModel.deleteHistory(index: index)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 播放器全屏内容
    @ViewBuilder
    private var playerFullScreenContent: some View {
        if liveViewModel.roomInfoViewModel != nil {
            DetailPlayerView { isLive, hint in
                self.isLive = isLive
            }
            .environment(liveViewModel.roomInfoViewModel!)
            .environment(appViewModel)
            .edgesIgnoringSafeArea(.all)
            .frame(width: 1920, height: 1080)
        }
    }

    // MARK: - 事件处理

    private func handleFocusChange(newValue: FocusableField?, liveModel: Bindable<LiveViewModel>) {
        guard case .mainContent(let focusedIndex) = newValue, focusedIndex == index else { return }
        guard index < liveViewModel.roomList.count else { return }

        liveViewModel.currentRoom = liveViewModel.roomList[index]
        liveViewModel.selectedRoomListIndex = focusedIndex
        if liveViewModel.roomListType == .live || liveViewModel.roomListType == .search {
            if focusedIndex >= liveViewModel.roomList.count - 4 && liveModel.wrappedValue.roomListType != .favorite {
                liveViewModel.roomPage += 1
            }
        }
    }

    private func enterDetailRoom() {
        liveViewModel.currentRoom = currentLiveModel ?? liveViewModel.roomList[index]
        liveViewModel.selectedRoomListIndex = index

        let currentState = LiveState(rawValue: liveViewModel.currentRoom?.liveState ?? "unknow")
        let isLiveOrVideo = currentState == .live ||
            ((liveViewModel.currentRoom?.liveType == .huya || liveViewModel.currentRoom?.liveType == .douyu) && currentState == .video)

        if isLiveOrVideo || liveViewModel.roomListType == .live {
            if !appViewModel.historyViewModel.watchList.contains(where: { liveViewModel.currentRoom!.roomId == $0.roomId }) {
                appViewModel.historyViewModel.watchList.insert(liveViewModel.currentRoom!, at: 0)
            }
            let enterFromLive = liveViewModel.roomListType == .live
            liveViewModel.createCurrentRoomViewModel(enterFromLive: enterFromLive)
            DispatchQueue.main.async {
                isLive = true
            }
        } else {
            DispatchQueue.main.async {
                isLive = false
                liveViewModel.showToast(false, title: "主播已经下播")
            }
        }
    }

    func formatLiveStateColor() -> Color {
        let currentLiveModel = self.currentLiveModel == nil ? liveViewModel.roomList[index] : self.currentLiveModel!
        if LiveState(rawValue: currentLiveModel.liveState ?? "3") == .live || LiveState(rawValue:currentLiveModel.liveState ?? "3") == .video {
            return Color.green
        }else {
            return Color.gray
        }
    }

    func refreshStateIfStateIsUnknow() async throws {
        guard index < liveViewModel.roomList.count else { return }

        let currentLiveModel: LiveModel
        if let existingModel = self.currentLiveModel {
            currentLiveModel = existingModel
        } else {
            currentLiveModel = liveViewModel.roomList[index]
        }

        if currentLiveModel.liveState == "" {
            let newState = try await ApiManager.getCurrentRoomLiveState(roomId: currentLiveModel.roomId, userId: currentLiveModel.userId, liveType: currentLiveModel.liveType)
            await MainActor.run {
                self.currentLiveModel?.liveState = newState.rawValue
            }
        }
    }

    func getImage() -> String {
        guard index < liveViewModel.roomList.count else { return "live_card_bili" }

        let currentLiveModel: LiveModel
        if let existingModel = self.currentLiveModel {
            currentLiveModel = existingModel
        } else {
            currentLiveModel = liveViewModel.roomList[index]
        }

        switch currentLiveModel.liveType {
            case .bilibili:
                return "live_card_bili"
            case .douyu:
                return "live_card_douyu"
            case .huya:
                return "live_card_huya"
            case .douyin:
                return "live_card_douyin"
            case .yy:
                return "live_card_yy"
            case .cc:
                return "live_card_cc"
            case .ks:
                return "live_card_ks"
            case .soop:
                return "live_card_soop"
        }
    }
}
