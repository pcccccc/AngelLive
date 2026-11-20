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
import UIKit

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
    @Environment(\.portraitControlsMotion) private var controlsMotion
    @Environment(\.portraitRoomPageActions) private var portraitRoomPageActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFavoriteAnimating = false
    @State private var showStreamerInfo = false
    @State private var showQualityPanel = false
    @State private var moreActionSheetPresented = false
    @State private var railWidth = FullUIPlayerChrome.controlSize
    private let onOpenRoomSwitcher: (() -> Void)?

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { room in
            if !viewModel.currentRoom.userId.isEmpty, !room.userId.isEmpty {
                return room.liveType == viewModel.currentRoom.liveType && room.userId == viewModel.currentRoom.userId
            }
            return room.liveType == viewModel.currentRoom.liveType && room.roomId == viewModel.currentRoom.roomId
        })
    }

    init(model: KSVideoPlayerModel, onOpenRoomSwitcher: (() -> Void)? = nil) {
        self.model = model
        self.onOpenRoomSwitcher = onOpenRoomSwitcher
    }

    var body: some View {
        GeometryReader { geometry in
            let visible = controlsVisible.wrappedValue
            ZStack {
                ZStack {
                    topBar(availableWidth: geometry.size.width)

                    bottomLeftArea(maximumWidth: max(0, geometry.size.width
                        - 2 * FullUIPlayerChrome.inset - railWidth - 8))
                        .allowsHitTesting(false)

                    bottomRightArea
                }
                .modifier(PortraitControlsOffset(
                    motion: viewModel.isOnDemand ? nil : controlsMotion,
                    width: geometry.size.width,
                    visible: visible,
                    reduceMotion: reduceMotion
                ))
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)

                FullUIPlayerDanmakuStatus(status: viewModel.danmakuConnectionStatus, controlsVisible: visible)
                    .animation(FullUIPlayerChrome.visibilityAnimation(visible, reduceMotion: reduceMotion), value: visible)

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
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        .environment(\.colorScheme, .dark)
        .onChange(of: showQualityPanel || showStreamerInfo || moreActionSheetPresented, initial: true) { _, presented in
            controlPopupPresented.wrappedValue = presented
        }
        .onDisappear {
            controlPopupPresented.wrappedValue = false
        }
    }

    // MARK: - 顶部信息栏

    private func topBar(availableWidth: CGFloat) -> some View {
        let inset = FullUIPlayerChrome.inset
        let backWidth = inset + FullUIPlayerBackButton.visibleGlyphWidth + 12
        // Leave clear space at the trailing edge in addition to the standard inset.
        let trailingClearance: CGFloat = 60
        let maximumStreamerWidth = max(0, availableWidth - backWidth - inset - trailingClearance)
        return VStack {
            HStack(spacing: 0) {
                FullUIPlayerBackButton(width: backWidth, symbolLeadingInset: inset) {
                    dismiss()
                }

                FullUIPlayerGlassGroup {
                    streamerControls(maximumWidth: maximumStreamerWidth)
                }
                .sheet(isPresented: $showStreamerInfo) {
                    StreamerInfoSheet(room: viewModel.currentRoom)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, inset)
            .padding(.top, inset)
            Spacer()
        }
    }

    private static let avatarSize: CGFloat = 28

    private func streamerControls(maximumWidth: CGFloat) -> some View {
        let name = viewModel.currentRoom.userName.orDash
        let nameFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let nameWidth = (BracketSafeName(name).fullTitle as NSString)
            .size(withAttributes: [.font: nameFont]).width.rounded(.up)
        let spacing: CGFloat = 8
        let maximumTextWidth = max(0, maximumWidth - Self.avatarSize - 2 * spacing - FullUIPlayerChrome.controlSize)
        let preferredNameWidth = max(nameWidth, 6 * nameFont.pointSize)
        let popularity = PlaybackDisplay.popularityTitle(viewModel.currentRoom.liveWatchedCount)

        return HStack(spacing: 0) {
            Button {
                showStreamerInfo = true
            } label: {
                HStack(spacing: spacing) {
                    avatar
                    FullUIPlayerName(name, font: nameFont, maximumWidth: min(nameWidth, maximumTextWidth))

                    if let popularity,
                       preferredNameWidth + spacing + FullUIPlayerHeatLabelStyle.width(for: popularity) <= maximumTextWidth {
                        Label(popularity, systemImage: FullUIPlayerHeatLabelStyle.symbol)
                            .labelStyle(FullUIPlayerHeatLabelStyle())
                            .fixedSize()
                    }
                }
                .padding(.leading, spacing)
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
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 左下角区域：弹幕气泡

    private func bottomLeftArea(maximumWidth: CGFloat) -> some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                if scenePhase == .active {
                    ForEach(viewModel.danmuMessages.suffix(6)) { message in
                        ChatBubbleView(message: message)
                    }
                }
            }
            .frame(maxWidth: maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: Self.avatarSize, height: Self.avatarSize)
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

    // MARK: - 右下角区域

    private var bottomRightArea: some View {
        VStack(alignment: .trailing, spacing: 12) {
            qualityButton

            if let onOpenRoomSwitcher {
                Button(action: onOpenRoomSwitcher) {
                    Image(systemName: "rectangle.stack")
                        .font(FullUIPlayerChrome.symbolFont)
                        .foregroundStyle(.white)
                        .fullUIPlayerCircularControl()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("换台")
            } else {
                Color.clear
                    .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            moreActionsButton
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            railWidth = width
        }
        .padding(.trailing, FullUIPlayerChrome.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var qualityButton: some View {
        let quality = viewModel.currentPlayQualityString.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullTitle = quality.isEmpty ? String(localized: "清晰度") : quality
        let title = PlaybackDisplay.compactQualityTitle(fullTitle)
        let size = FullUIPlayerChrome.controlSize
        let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        let label = Text(verbatim: title)
            .font(Font(font))
            .foregroundStyle(.white)
            .lineLimit(1)

        return Button {
            showQualityPanel = true
        } label: {
            if titleWidth <= size {
                label
                    .fullUIPlayerCircularControl()
                    .contentShape(Circle())
            } else {
                let width = min(76, titleWidth + 12)
                label
                    .padding(.horizontal, min(6, max(4, (width - titleWidth) / 2)))
                    .frame(width: width, height: size)
                    .fullUIPlayerGlass(in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清晰度")
        .accessibilityValue(fullTitle)
    }

    private var moreActionsButton: MoreActionsButton {
        MoreActionsButton(
            room: viewModel.currentRoom,
            onClearChat: {
                if !viewModel.isOnDemand, let portraitRoomPageActions {
                    portraitRoomPageActions.setControlsVisible(false)
                } else {
                    controlsVisible.wrappedValue = false
                }
            },
            showQualityOption: false,
            onRefreshPlayback: refreshPlayback,
            supportsPictureInPicture: supportsPictureInPicture,
            onTogglePictureInPicture: togglePictureInPicture,
            showsDanmakuConnectionIssue: true,
            popupPresented: $moreActionSheetPresented
        )
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
    static let symbol = "flame.fill"
    private static let font = UIFont.systemFont(ofSize: 12)
    private static let spacing: CGFloat = 3
    private static let symbolWidth = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font))?
        .size.width.rounded(.up) ?? font.pointSize

    static func width(for title: String) -> CGFloat {
        symbolWidth + spacing + (title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Self.spacing) {
            configuration.icon.foregroundStyle(.orange)
                .frame(width: Self.symbolWidth)
            configuration.title
        }
        .font(Font(Self.font))
    }
}

#endif
