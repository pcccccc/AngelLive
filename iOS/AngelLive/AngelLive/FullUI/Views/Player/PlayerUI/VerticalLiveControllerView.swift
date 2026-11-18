#if canImport(KSPlayer)

//
//  VerticalLiveControllerView.swift
//  AngelLive
//
//  Created by pangchong on 10/31/25.
//

import SwiftUI
import KSPlayer
import KSPlayerUI
import AngelLiveCore
import AngelLiveDependencies

/// 竖屏直播专用控制层
/// 设计参考沉浸式竖屏直播布局
struct VerticalLiveControllerView: View {
    @ObservedObject private var model: KSVideoPlayerModel
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentToast) private var presentToast
    @Environment(\.verticalLiveControlsVisible) private var controlsVisible
    @Environment(\.verticalLiveControlPopupPresented) private var controlPopupPresented
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFavoriteAnimating = false
    @State private var showStreamerInfo = false
    @State private var showQualityPanel = false

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { room in
            if !viewModel.currentRoom.userId.isEmpty, !room.userId.isEmpty {
                return room.liveType == viewModel.currentRoom.liveType && room.userId == viewModel.currentRoom.userId
            }
            return room.liveType == viewModel.currentRoom.liveType && room.roomId == viewModel.currentRoom.roomId
        })
    }

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    var body: some View {
        GeometryReader { geometry in
            let visible = controlsVisible.wrappedValue
            ZStack {
                ZStack {
                    topBar(maximumStreamerWidth: max(0, geometry.size.width - 2 * FullUIPlayerChrome.inset) * 0.46)

                    bottomLeftArea
                        .allowsHitTesting(false)

                    bottomRightArea
                }
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)

                FullUIPlayerDanmakuStatus(status: viewModel.danmakuConnectionStatus, controlsVisible: visible)

                // 面板独立于清屏动画；展开时不接收底层清屏手势。
                if showQualityPanel {
                    Color.black.opacity(0.001)
                        .onTapGesture { showQualityPanel = false }
                    QualitySelectionPanel(isShowing: $showQualityPanel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .fullUIPlayerContrast(while: controlsVisible.wrappedValue) { model.config.playerLayer?.player }
        .animation(
            FullUIPlayerChrome.visibilityAnimation(controlsVisible.wrappedValue, reduceMotion: reduceMotion),
            value: controlsVisible.wrappedValue
        )
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        .environment(\.colorScheme, .dark)
        .onChange(of: showQualityPanel || showStreamerInfo, initial: true) { _, presented in
            controlPopupPresented.wrappedValue = presented
        }
        .onDisappear {
            controlPopupPresented.wrappedValue = false
        }
    }

    // MARK: - 顶部信息栏

    private func topBar(maximumStreamerWidth: CGFloat) -> some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(FullUIPlayerChrome.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                        .fullUIPlayerGlass(in: Circle())
                        .fullUIPlayerShadow(in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                FullUIPlayerGlassGroup {
                    streamerControls(maximumWidth: maximumStreamerWidth)
                }
                .sheet(isPresented: $showStreamerInfo) {
                    StreamerInfoSheet(room: viewModel.currentRoom)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }

                Spacer()
            }
            .padding(.horizontal, FullUIPlayerChrome.inset)
            .padding(.top, FullUIPlayerChrome.inset)
            Spacer()
        }
    }

    private func streamerControls(maximumWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button {
                showStreamerInfo = true
            } label: {
                HStack(spacing: 8) {
                    avatar
                    FullUIPlayerName(viewModel.currentRoom.userName.orDash, font: .systemFont(ofSize: 13, weight: .semibold))
                        .layoutPriority(1)

                    if let popularity = FullUIPlayerDisplay.popularityTitle(viewModel.currentRoom.liveWatchedCount) {
                        Label(popularity, systemImage: "flame.fill")
                            .labelStyle(FullUIPlayerHeatLabelStyle())
                            .fixedSize()
                    }
                }
                .padding(.leading, 8)
                .frame(minHeight: FullUIPlayerChrome.controlSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(FullUIPlayerChrome.symbolFont)
                    .foregroundStyle(isFavorited ? .red : .white)
                    .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                    .contentShape(Rectangle())
                    .symbolEffect(.bounce, value: isFavoriteAnimating)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorited ? "取消收藏" : "收藏")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: maximumWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 左下角区域：弹幕气泡

    private var bottomLeftArea: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if scenePhase == .active {
                        // 弹幕气泡（显示最近6条）- 使用 ChatBubbleView
                        ForEach(viewModel.danmuMessages.suffix(6)) { message in
                            ChatBubbleView(message: message)
                        }
                    }
                }

                Spacer()
            }
            .padding(.leading, FullUIPlayerChrome.inset)
        }
    }

    // MARK: - Helper Methods

    private var avatar: some View {
        Group {
            if !viewModel.currentRoom.userHeadImg.isEmpty,
               let avatarURL = URL(string: viewModel.currentRoom.userHeadImg) {
                KFAnimatedImage(avatarURL)
                    .configure { view in view.framePreloadCount = 2 }
                    .placeholder { verticalAvatarFallback }
                    .aspectRatio(contentMode: .fill)
            } else {
                verticalAvatarFallback
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// 头像兜底（URL 空 / 加载失败）
    private var verticalAvatarFallback: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(5)
            )
    }

    @MainActor
    private func toggleFavorite() async {
        let wasFavorited = isFavorited
        do {
            if wasFavorited {
                try await favoriteModel.removeFavoriteRoom(room: viewModel.currentRoom)
            } else {
                try await favoriteModel.addFavorite(room: viewModel.currentRoom)
            }
            // 成功后触发动画 + Toast(跟列表入口对齐)
            isFavoriteAnimating.toggle()
            presentToast(ToastValue(
                icon: Image(systemName: wasFavorited ? "heart.slash.fill" : "heart.fill"),
                message: wasFavorited ? "已取消收藏" : "收藏成功"
            ))
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            presentToast(ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: wasFavorited ? "取消收藏失败:\(errorMessage)" : "收藏失败:\(errorMessage)"
            ))
            Logger.warning("收藏操作失败: \(error)", category: .favorite)
        }
    }

    // MARK: - 右下角区域：更多按钮

    private var bottomRightArea: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                MoreActionsButton(
                    room: viewModel.currentRoom,
                    onClearChat: {
                        controlsVisible.wrappedValue = false
                    },
                    showQualityOption: true,
                    onShowQualityPanel: {
                        showQualityPanel = true
                    },
                    onRefreshPlayback: refreshPlayback,
                    supportsPictureInPicture: supportsPictureInPicture,
                    onTogglePictureInPicture: togglePictureInPicture,
                    showsDanmakuConnectionIssue: true
                )
            }
            .padding(.trailing, FullUIPlayerChrome.inset)
        }
    }

    private var supportsPictureInPicture: Bool {
        model.config.playerLayer is KSComplexPlayerLayer
    }

    private func refreshPlayback() {
        guard activatePlaybackSurface() else { return }
        viewModel.refreshPlayback()
    }

    private func togglePictureInPicture() {
        guard activatePlaybackSurface(),
              let playerLayer = model.config.playerLayer as? KSComplexPlayerLayer else {
            return
        }

        if playerLayer.isPictureInPictureActive {
            playerLayer.pipStop(restoreUserInterface: true)
        } else {
            playerLayer.pipStart()
        }
    }

    private func activatePlaybackSurface() -> Bool {
        guard let surfaceID = viewModel.playbackSurfaceID else { return false }
        return PlaybackSessionRegistry.shared.activate(surfaceID)
    }
}

private struct FullUIPlayerHeatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.foregroundStyle(.orange)
            configuration.title
        }
        .font(.system(size: 12))
    }
}

#endif
