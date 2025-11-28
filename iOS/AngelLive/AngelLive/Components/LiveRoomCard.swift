//
//  LiveRoomCard.swift
//  AngelLive
//
//  Created by pangchong on 10/20/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct LiveRoomCard: View {
    let room: LiveModel
    let skipLiveCheck: Bool
    @State private var isPressed = false
    @State private var showPlayer = false
    @Namespace private var namespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast

    private var coverURL: URL? {
        guard !room.roomCover.isEmpty, let url = URL(string: room.roomCover) else { return nil }
        return url
    }

    private var avatarURL: URL? {
        guard !room.userHeadImg.isEmpty, let url = URL(string: room.userHeadImg) else { return nil }
        return url
    }

    init(room: LiveModel, width: CGFloat? = nil, skipLiveCheck: Bool = false) {
        self.room = room
        self.skipLiveCheck = skipLiveCheck
    }

    // 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    // 判断是否正在直播
    private var isLive: Bool {
        guard let liveState = room.liveState else { return true }
        return LiveState(rawValue: liveState) == .live
    }

    var body: some View {
        Group {
            if AppConstants.Device.isIPad {
                // iPad: 使用 fullScreenCover
                Button {
                    if skipLiveCheck || isLive {
                        showPlayer = true
                    } else {
                        let toast = ToastValue(
                            icon: Image(systemName: "tv.slash"),
                            message: "主播已下播"
                        )
                        presentToast(toast)
                    }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteContextMenu
                }
                .fullScreenCover(isPresented: $showPlayer) {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                        .navigationTransition(.zoom(sourceID: room.roomId, in: namespace))
                        .toolbar(.hidden, for: .tabBar)
                }
            } else {
                // iPhone: 使用 NavigationLink
                Button {
                    if skipLiveCheck || isLive {
                        showPlayer = true
                    } else {
                        let toast = ToastValue(
                            icon: Image(systemName: "tv.slash"),
                            message: "主播已下播"
                        )
                        presentToast(toast)
                    }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteContextMenu
                }
                .navigationDestination(isPresented: $showPlayer) {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                        .navigationTransition(.zoom(sourceID: room.roomId, in: namespace))
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
    }

    private var cardContent: some View {
        VStack {
            // 封面图（带可靠的兜底占位）
            coverView
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                .matchedTransitionSource(id: room.roomId, in: namespace)

            // 主播信息
            HStack(spacing: 8) {
                avatarView
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    Text(room.userName)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(.clear)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - 子视图

    /// 封面图容器：有 URL 时双层 KFImage（模糊背景 + 清晰前景，不变形），失败或无 URL 时用本地占位
    private var coverView: some View {
        Group {
            if let url = coverURL {
                // 背景模糊层：填充整个容器，不设置 aspectRatio
                KFImage(url)
                    .placeholder {
                        Rectangle()
                            .fill(AppConstants.Colors.placeholderGradient())
                    }
                    .resizable()
                    .blur(radius: 20)
                    .overlay(
                        // 前景清晰层：保持原比例居中显示，不变形
                        KFImage(url)
                            .placeholder {
                                placeholderCover()
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
            } else {
                placeholderCover()
            }
        }
    }

    /// 头像：无效 URL 时展示占位
    private var avatarView: some View {
        Group {
            if let url = avatarURL {
                KFImage(url)
                    .placeholder { avatarPlaceholder }
                    .resizable()
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    private func placeholderCover() -> some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.placeholderGradient())
            Image("placeholder")
                .resizable()
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .opacity(0.7)
        }
        .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
    }

    @ViewBuilder
    private var favoriteContextMenu: some View {
        if isFavorited {
            Button(role: .destructive) {
                Task {
                    await removeFavorite()
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash.fill")
            }
        } else {
            Button {
                Task {
                    await addFavorite()
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }
        }
    }

    @MainActor
    private func addFavorite() async {
        do {
            try await favoriteModel.addFavorite(room: room)

            // 显示成功提示
            let toast = ToastValue(
                icon: Image(systemName: "heart.fill"),
                message: "收藏成功"
            )
            presentToast(toast)
        } catch {
            // 显示失败提示
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "收藏失败"
            )
            presentToast(toast)
            print("收藏失败: \(error)")
        }
    }

    @MainActor
    private func removeFavorite() async {
        do {
            try await favoriteModel.removeFavoriteRoom(room: room)

            // 显示成功提示
            let toast = ToastValue(
                icon: Image(systemName: "heart.slash.fill"),
                message: "已取消收藏"
            )
            presentToast(toast)
        } catch {
            // 显示失败提示
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "取消收藏失败"
            )
            presentToast(toast)
            print("取消收藏失败: \(error)")
        }
    }
}
