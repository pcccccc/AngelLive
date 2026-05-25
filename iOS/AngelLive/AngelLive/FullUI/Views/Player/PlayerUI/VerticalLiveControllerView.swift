#if canImport(KSPlayer)

//
//  VerticalLiveControllerView.swift
//  AngelLive
//
//  Created by pangchong on 10/31/25.
//

import SwiftUI
import KSPlayer
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
    @Environment(\.safeAreaInsetsCustom) private var safeAreaInsets
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentToast) private var presentToast
    @State private var backTapped = false
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

    /// iPadOS 26 窗口控制按钮的参考几何：x=20, y=20, width=38, height=20。
    private var windowControlsFrame: CGRect? {
        guard AppConstants.Device.isIPad else { return nil }
        guard #available(iOS 26.0, *) else { return nil }
        return CGRect(x: 20, y: 20, width: 38, height: 20)
    }

    private var windowControlsLeadingInset: CGFloat {
        guard let frame = windowControlsFrame else { return 0 }
        return frame.maxX + 12
    }

    /// 返回按钮当前布局尺寸为 40pt，按红绿灯中心线反推顶部 padding，再整体上移 5pt。
    private var topBarTopPadding: CGFloat {
        guard let frame = windowControlsFrame else { return safeAreaInsets.top }
        return frame.midY - 25
    }

    var body: some View {
        ZStack {
            // 顶部信息栏
            topBar
                .padding(.top, topBarTopPadding)

            // 左下角：弹幕气泡
            bottomLeftArea
                .padding(.bottom, safeAreaInsets.bottom)

            // 右下角：更多按钮
            bottomRightArea
                .padding(.bottom, safeAreaInsets.bottom)

            // 清晰度选择面板（右侧滑入）
            if showQualityPanel {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showQualityPanel = false }
                QualitySelectionPanel(isShowing: $showQualityPanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        .environment(\.colorScheme, .dark)
        .opacity(model.config.isMaskShow || showQualityPanel ? 1 : 0)
    }

    // MARK: - 顶部信息栏

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    backTapped.toggle()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(AppConstants.PlayerUI.Opacity.backplate), in: RoundedRectangle(cornerRadius: 20))
                        .adaptiveGlassEffect(in: .rect(cornerRadius: 20.0))
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .padding(-5)
                .padding(.leading, windowControlsLeadingInset)

                // 主播信息
                HStack(spacing: 10) {
                    Button {
                        showStreamerInfo = true
                    } label: {
                        Group {
                            if !viewModel.currentRoom.userHeadImg.isEmpty,
                               let avatarURL = URL(string: viewModel.currentRoom.userHeadImg) {
                                KFAnimatedImage(avatarURL)
                                    .configure { view in
                                        view.framePreloadCount = 2
                                    }
                                    .placeholder { verticalAvatarFallback }
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                verticalAvatarFallback
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(viewModel.currentRoom.userName.prefix(10)).orDash)
                            .foregroundStyle(.white)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        // 直播间热度
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(formatPopularity(viewModel.currentRoom.liveWatchedCount ?? "0"))
                                .foregroundStyle(.white)
                                .font(.caption)
                        }
                    }

                    // 收藏按钮
                    Button {
                        Task {
                            await toggleFavorite()
                        }
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(isFavorited ? .red : .white)
                            .frame(width: 28, height: 28)
                            .symbolEffect(.bounce, value: isFavoriteAnimating)
                    }
                    .ksBorderlessButton()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(AppConstants.PlayerUI.Opacity.backplate), in: Capsule())
                .adaptiveGlassEffect(in: .capsule)
                .clipShape(Capsule())
                .sheet(isPresented: $showStreamerInfo) {
                    StreamerInfoSheet(room: viewModel.currentRoom)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }

                Spacer()
            }
            .padding(.horizontal)
            Spacer()
        }
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
            .padding(.leading)
        }
    }

    // MARK: - Helper Methods

    /// 格式化热度数值
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

    private func formatHeat(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000.0)
        } else {
            return "\(value)"
        }
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
            // 成功后触发动画
            isFavoriteAnimating.toggle()
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            presentToast(ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: wasFavorited ? "取消收藏失败:\(errorMessage)" : "收藏失败:\(errorMessage)"
            ))
            print("收藏操作失败: \(error)")
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
                        withAnimation {
                            viewModel.danmuMessages.removeAll()
                        }
                    },
                    showQualityOption: true,
                    onShowQualityPanel: {
                        showQualityPanel = true
                    }
                )
            }
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect(in shape: GlassEffectShape) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .rect(let radius):
                self.glassEffect(in: .rect(cornerRadius: radius))
            case .circle:
                self.glassEffect()
            case .capsule:
                self.glassEffect(in: .capsule)
            }
        } else {
            switch shape {
            case .rect(let radius):
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            case .circle:
                self.background(.ultraThinMaterial, in: Circle())
            case .capsule:
                self.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

private enum GlassEffectShape {
    case rect(cornerRadius: CGFloat)
    case circle
    case capsule
}

#endif
